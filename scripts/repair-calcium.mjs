#!/usr/bin/env node
/**
 * Neutralise the contaminated calcium readings in `nutrition_entries.micros`.
 *
 * WHY THIS EXISTS
 * Calcium on this account is bimodal. Most days sit between about 155 and 290 mg;
 * seventeen days sit between about 3,070 and 3,383 mg. Calories, sodium and
 * potassium are entirely normal on the high days, so it is not a duplicated day
 * — it is one contributor worth roughly 3,100 mg of calcium appearing and
 * disappearing. Both populations are written by the same path (the HealthKit
 * daily ingest: `hk_uuid` null, `logged_at` 00:00), and the ingest
 * stores calcium raw with no conversion, so nothing in this codebase is doing
 * arithmetic to it. The duplicate is upstream, in the Health source.
 *
 * ── WHY NOT JUST SUBTRACT 3,100 ──────────────────────────────────────────────
 * Because it does not work. 2026-08-27 stores 3,074, and subtracting a flat
 * 3,100 gives a negative milligram figure. The contaminant is not a constant —
 * it rides on top of a real intake that varies day to day, and the two cannot be
 * separated from an aggregate that has no item breakdown.
 *
 * ── WHAT IT DOES INSTEAD ─────────────────────────────────────────────────────
 * Replaces each flagged value with the MEDIAN of the unflagged days within ±7
 * days, and records what it did on the row itself:
 *
 *     micros.calcium           <- the local median (an estimate)
 *     micros.calcium_raw       <- the original stored value, untouched
 *     micros.calcium_repaired  <- true
 *
 * The raw value is preserved, so this is reversible and a second run is a no-op.
 * The estimate is labelled in the data rather than laundered into it: the
 * `calcium_repaired` flag is what any future reader needs to know it is looking
 * at a substitution and not a measurement.
 *
 * ── THE GATE ─────────────────────────────────────────────────────────────────
 * Every replacement must land inside the observed clean band (120–600 mg). If
 * any does not, nothing is written at all — a repair that produces its own
 * outliers is worse than the contamination, because it looks correct.
 *
 *   node scripts/repair-calcium.mjs --dry-run   # print the diff, write nothing
 *   node scripts/repair-calcium.mjs             # apply
 *
 * Requires NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env.local.
 */
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const DRY = process.argv.includes('--dry-run')

/** Above this many times the 1,000 mg target, a food-side reading is not real. */
const FLAG_ABOVE = 2500
/** The band every repaired value has to land in, from the clean population. */
const CLEAN_MIN = 120
const CLEAN_MAX = 600
/** How far either side to look for clean neighbours. */
const WINDOW_DAYS = 7

const env = Object.fromEntries(
  readFileSync(new URL('../.env.local', import.meta.url), 'utf8')
    .split('\n')
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
)
const url = env.NEXT_PUBLIC_SUPABASE_URL
const key = env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !key) {
  console.error('Missing NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in .env.local')
  process.exit(1)
}
const db = createClient(url, key, { auth: { persistSession: false } })

const { data: rows, error } = await db
  .from('nutrition_entries')
  .select('id, user_id, date, micros')
  .eq('meal_type', 'daily')
  .order('date', { ascending: true })
if (error) throw error
if (!rows?.length) { console.error('Empty read — refusing to run.'); process.exit(1) }

const PGRST_CAP = 1000
if (rows.length % PGRST_CAP === 0) {
  console.error(`nutrition_entries came back at exactly ${rows.length} — the PostgREST page cap. The read is truncated; refusing to run.`)
  process.exit(1)
}

const dayMs = 86_400_000
const asNum = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const median = (xs) => {
  const a = [...xs].sort((x, y) => x - y)
  if (!a.length) return null
  const mid = a.length >> 1
  return a.length % 2 ? a[mid] : Math.round((a[mid - 1] + a[mid]) / 2)
}

// A row is "clean" if it was never flagged AND was never repaired — a previously
// repaired value is an estimate and must not become the source of another one.
const clean = rows.filter((r) => {
  const m = r.micros ?? {}
  if (m.calcium_repaired) return false
  const c = asNum(m.calcium)
  return c != null && c <= FLAG_ABOVE
})

const flagged = rows.filter((r) => {
  const m = r.micros ?? {}
  if (m.calcium_repaired) return false          // idempotence
  const c = asNum(m.calcium)
  return c != null && c > FLAG_ABOVE
})

console.log(`${rows.length} daily rows · ${clean.length} clean · ${flagged.length} flagged${DRY ? ' · DRY RUN' : ''}\n`)
if (!flagged.length) { console.log('Nothing to repair.'); process.exit(0) }

const updates = []
const problems = []

for (const r of flagged) {
  const t = Date.parse(`${r.date}T00:00:00Z`)
  const neighbours = clean
    .filter((c) => c.user_id === r.user_id && Math.abs(Date.parse(`${c.date}T00:00:00Z`) - t) <= WINDOW_DAYS * dayMs)
    .map((c) => asNum(c.micros?.calcium))
    .filter((v) => v != null)

  const est = median(neighbours)
  const raw = asNum(r.micros?.calcium)
  if (est == null) { problems.push(`${r.date}: no clean day within ±${WINDOW_DAYS} days`); continue }
  if (est < CLEAN_MIN || est > CLEAN_MAX) { problems.push(`${r.date}: estimate ${est} mg is outside the clean band`); continue }

  console.log(`  ${r.date}  ${raw} → ${est} mg   (from ${neighbours.length} clean neighbour${neighbours.length === 1 ? '' : 's'})`)
  updates.push({
    id: r.id,
    micros: { ...(r.micros ?? {}), calcium: est, calcium_raw: raw, calcium_repaired: true },
  })
}

if (problems.length) {
  console.error(`\nRefusing to write — ${problems.length} row(s) could not be repaired safely:`)
  for (const p of problems) console.error(`  ${p}`)
  process.exit(1)
}

console.log(`\n${updates.length} row${updates.length === 1 ? '' : 's'} to update`)
if (DRY) process.exit(0)

for (const u of updates) {
  const { error: uErr } = await db.from('nutrition_entries').update({ micros: u.micros }).eq('id', u.id)
  if (uErr) throw uErr
}
console.log('Done.')
