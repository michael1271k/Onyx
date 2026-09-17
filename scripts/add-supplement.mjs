#!/usr/bin/env node
//
// Put one row in `custom_supplements`, idempotently.
//
// ── WHY A SCRIPT AND NOT THE APP ────────────────────────────────────────────
// The Stack editor owns name, form, dose, time and days. It does NOT own
// `micros` — the per-dose nutrient payload — because that is a fact about a
// PRODUCT LABEL rather than about a protocol, and a numeric keypad for eleven
// nutrients is a form nobody would fill in twice. So a row that carries a
// payload is seeded, and the app edits everything else about it afterwards.
//
// ── AND WHY IT IS IDEMPOTENT ON `schedule.key` ──────────────────────────────
// `schedule.key` is the join to every `supplement_log` row the item ever wrote
// (`SupplementStack.swift`). Re-running this must therefore UPDATE the row that
// already holds the key rather than insert a second one beside it — two rows
// with one key credit the day twice and neither can be un-ticked.
//
//   node scripts/add-supplement.mjs psyllium              # seed / update
//   node scripts/add-supplement.mjs psyllium --dry-run    # print, write nothing
//   node scripts/add-supplement.mjs psyllium --user <uuid>
//
import { readFileSync } from "node:fs";

// ── The catalogue ───────────────────────────────────────────────────────────
//
// A label is stated as the SERVING the tub prints, and the dose actually taken
// beside it. The payload stored on the row is per dose, because
// `SupplementNutrients` multiplies only COUNT units ("2 caps") and a mass dose
// is already the total — so a 9 g serving row on a 5 g dose would credit 80 %
// more of everything, silently, on the Nutrition tab.
const CATALOGUE = {
  psyllium: {
    name: "Psyllium Husk Powder",
    brand: "Now Foods",
    form: "powder",
    colour: "#8E9AAC",
    slot: "Evening",
    time: "18:30",
    servingG: 9,
    doseG: 5,
    // Per SERVING, exactly as the tub prints it.
    label: {
      kcal: 30,
      fat: 0,
      sodium: 10,
      carbs: 8,
      fiber: 7,
      protein: 0,
      iron: 1.5,
      potassium: 90,
    },
  },
};

// ── Arguments ───────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const key = argv.find((a) => !a.startsWith("--"));
const dryRun = argv.includes("--dry-run");
const userFlag = argv.indexOf("--user");
const userArg = userFlag >= 0 ? argv[userFlag + 1] : null;

if (!key || !CATALOGUE[key]) {
  console.error(`Usage: node scripts/add-supplement.mjs <${Object.keys(CATALOGUE).join("|")}> [--dry-run] [--user <uuid>]`);
  process.exit(1);
}
const item = CATALOGUE[key];

// ── Credentials ─────────────────────────────────────────────────────────────
// `.env.local`, never a flag: a service-role key on a command line lands in the
// shell history of whoever ran it.
function env() {
  const out = {};
  let raw;
  try {
    raw = readFileSync(new URL("../.env.local", import.meta.url), "utf8");
  } catch {
    console.error("No .env.local. This script needs NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.");
    process.exit(1);
  }
  for (const line of raw.split("\n")) {
    const match = /^\s*(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*)$/.exec(line);
    if (match) out[match[1]] = match[2].trim().replace(/^["']|["']$/g, "");
  }
  return out;
}

const { NEXT_PUBLIC_SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: serviceKey } = env();
if (!url || !serviceKey) {
  console.error("NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing from .env.local.");
  process.exit(1);
}

const headers = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
  "Content-Type": "application/json",
};

async function rest(path, init = {}) {
  const response = await fetch(`${url}/rest/v1/${path}`, { ...init, headers: { ...headers, ...init.headers } });
  const text = await response.text();
  if (!response.ok) throw new Error(`${response.status} ${path} — ${text}`);
  return text ? JSON.parse(text) : null;
}

// ── The payload ─────────────────────────────────────────────────────────────
// Derived here rather than typed in, so the arithmetic is visible in the diff
// and a different dose is one number away. One decimal: the label is stated to
// one, and a total carried to four would claim a precision the tub does not.
const ratio = item.doseG / item.servingG;
const round = (n) => Math.round(n * 10) / 10;
const micros = Object.fromEntries(
  Object.entries(item.label).map(([nutrient, perServing]) => [
    nutrient,
    nutrient === "iron" ? Math.round(perServing * ratio * 100) / 100 : round(perServing * ratio),
  ]),
);

const row = {
  user_id: null, // resolved below
  name: item.name,
  dose: `${item.doseG} g`,
  dose_amount: item.doseG,
  dose_unit: "g",
  color: item.colour,
  form: item.form,
  time: item.time,
  schedule: { key, slot: item.slot, notes: `${item.brand} · ${item.doseG} g of a ${item.servingG} g serving` },
  micros,
};

// ── Run ─────────────────────────────────────────────────────────────────────
const main = async () => {
  // The owner: the flag, or whoever already owns a stack. Never hardcoded —
  // a user id in a tracked file is the wrong kind of durable.
  let userId = userArg;
  if (!userId) {
    const owners = await rest("custom_supplements?select=user_id&order=created_at.desc&limit=1");
    userId = owners?.[0]?.user_id;
  }
  if (!userId) {
    console.error("Could not resolve a user_id. Pass --user <uuid>.");
    process.exit(1);
  }
  row.user_id = userId;

  const existing = await rest(
    `custom_supplements?select=id,name&user_id=eq.${userId}&schedule->>key=eq.${encodeURIComponent(key)}`,
  );

  console.log(`${item.name} — ${item.doseG} g of a ${item.servingG} g serving (×${ratio.toFixed(4)})`);
  console.table(micros);

  if (dryRun) {
    console.log(existing?.length ? `Would UPDATE ${existing[0].id}.` : "Would INSERT a new row.");
    return;
  }

  // ── THE SAME GATE THE HOOK ASKS FOR, SAID IN THE SCRIPT ───────────────────
  // `.claude/settings.json` blocks an ungated `node scripts/*.mjs`, but that
  // file is machine-local and is not what makes this safe — there is no staging
  // Supabase, so the default for anything here has to be "print, write
  // nothing", in a fresh clone as much as in this one.
  if (process.env.ONYX_APPLY !== "1") {
    console.error("\nRefusing to write. This is the production database — re-run with ONYX_APPLY=1 in front.");
    process.exit(1);
  }

  if (existing?.length) {
    const id = existing[0].id;
    await rest(`custom_supplements?id=eq.${id}`, { method: "PATCH", body: JSON.stringify(row) });
    console.log(`Updated ${id}.`);
  } else {
    const [created] = await rest("custom_supplements", {
      method: "POST",
      body: JSON.stringify(row),
      headers: { Prefer: "return=representation" },
    });
    console.log(`Inserted ${created.id}.`);
  }
};

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
