#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// backfill-precision.mjs — the founder's AUDIT of `precision-c-backfill-sets.sql`
//
// WHY: Precision Lane C (founder decisions Q10/Q11) redefines
// `workout_sessions.set_count` as every set performed (warm-ups and cardio
// bouts included, a unilateral pair once, ghosts never) and adds
// `working_set_count` (the same minus warm-ups). The server is repaired by the
// SQL the founder pastes; this script recomputes the SAME rule in JavaScript
// over PostgREST, prints per-user before/after counts, and — only with
// ONYX_APPLY=1 — PATCHes the sessions that differ. It exists so the paste can
// be checked from outside Postgres, and so a later drift can be measured.
//
// WRITES: `workout_sessions.set_count`, `workout_sessions.working_set_count`,
// finished sessions with rows only. Nothing else. `total_volume_kg` is left
// alone on purpose: the Hevy basis needs the weigh-in and the bodyweight flag
// the phone has (`onyx.recount.sets.v1` pushes it).
//
// IDEMPOTENT: a second run reports 0 sessions to change.
//
// USAGE (service role from .env.local; `--dry-run` is the default):
//     node scripts/backfill-precision.mjs --dry-run
//     ONYX_APPLY=1 node scripts/backfill-precision.mjs --apply
//
// PAGING: `workout_sets` is read by keyset on `id`, stopping on an EMPTY page —
// `length < PAGE` would silently truncate under `db-max-rows` (memory
// `hotfix-ui-data-sep11`).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const apply = process.argv.includes("--apply") && process.env.ONYX_APPLY === "1";
if (process.argv.includes("--apply") && !apply) {
  console.error("refusing to write: --apply needs ONYX_APPLY=1 in the environment");
  process.exit(2);
}

const env = Object.fromEntries(
  readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
    .split("\n")
    .filter((l) => l.includes("=") && !l.trim().startsWith("#"))
    .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^["']|["']$/g, "")]; })
);
const url = env.NEXT_PUBLIC_SUPABASE_URL;
const key = env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error("NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from .env.local"); process.exit(2); }
const headers = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };

async function get(path) {
  const r = await fetch(`${url}/rest/v1/${path}`, { headers });
  if (!r.ok) throw new Error(`${path}: ${r.status} ${await r.text()}`);
  return r.json();
}

// ── 1 · every set, keyset-paged ─────────────────────────────────────────────
const PAGE = 1000;
const sets = [];
let after = "";
for (;;) {
  const page = await get(
    `workout_sets?select=id,session_id,set_type,pair_id&order=id.asc&limit=${PAGE}` + (after ? `&id=gt.${after}` : "")
  );
  if (page.length === 0) break;
  sets.push(...page);
  after = page[page.length - 1].id;
}

// ── 2 · the rule — `SessionCounts.total` / `.working`, verbatim ─────────────
const bySession = new Map();
for (const s of sets) {
  const b = bySession.get(s.session_id) ?? { total: new Set(), working: new Set() };
  if (s.set_type === "ghost") { bySession.set(s.session_id, b); continue; }
  const unit = s.pair_id && s.pair_id !== "" ? `p:${s.pair_id}` : `s:${s.id}`;
  b.total.add(unit);
  if (s.set_type !== "warmup") b.working.add(unit);
  bySession.set(s.session_id, b);
}

// ── 3 · compare with the stored figures, finished sessions only ─────────────
const sessions = await get("workout_sessions?select=id,user_id,started_at,day_key,set_count,working_set_count,ended_at&ended_at=not.is.null");
const perUser = new Map();
const changes = [];
for (const ws of sessions) {
  const b = bySession.get(ws.id);
  if (!b) continue; // no rows on the server: not ours to restate
  const want = { set_count: b.total.size, working_set_count: b.working.size };
  const u = perUser.get(ws.user_id) ?? { finished_with_rows: 0, to_change: 0 };
  u.finished_with_rows += 1;
  if (ws.set_count !== want.set_count || ws.working_set_count !== want.working_set_count) {
    u.to_change += 1;
    changes.push({ id: ws.id, user_id: ws.user_id, day: (ws.started_at ?? "").slice(0, 10), day_key: ws.day_key,
      before: { set_count: ws.set_count, working_set_count: ws.working_set_count }, after: want });
  }
  perUser.set(ws.user_id, u);
}

console.log(`sets read: ${sets.length}   finished sessions: ${sessions.length}   with rows: ${[...perUser.values()].reduce((n, u) => n + u.finished_with_rows, 0)}`);
console.log("per user (before):");
for (const [uid, u] of perUser) console.log(`  ${uid}  finished_with_rows=${u.finished_with_rows}  to_change=${u.to_change}`);
for (const c of changes) {
  console.log(`  ${c.day} ${c.day_key ?? "-"} ${c.id.slice(0, 8)}  set_count ${c.before.set_count} → ${c.after.set_count}  working ${c.before.working_set_count ?? "null"} → ${c.after.working_set_count}`);
}
console.log(`${changes.length} session(s) to change`);

if (!apply) { console.log("dry run — nothing written (ONYX_APPLY=1 … --apply to write)"); process.exit(0); }

// ── 4 · apply, one PATCH per session ────────────────────────────────────────
let written = 0;
for (const c of changes) {
  const r = await fetch(`${url}/rest/v1/workout_sessions?id=eq.${c.id}`, {
    method: "PATCH", headers: { ...headers, Prefer: "return=minimal" }, body: JSON.stringify(c.after),
  });
  if (!r.ok) throw new Error(`PATCH ${c.id}: ${r.status} ${await r.text()}`);
  written += 1;
}
const afterUsers = new Map();
for (const c of changes) afterUsers.set(c.user_id, (afterUsers.get(c.user_id) ?? 0) + 1);
console.log(`written: ${written}`);
console.log("per user (after): sessions changed");
for (const [uid, n] of afterUsers) console.log(`  ${uid}  changed=${n}`);
console.log("re-run with --dry-run: it must report 0 session(s) to change");
