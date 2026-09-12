#!/usr/bin/env node
/**
 * Split ONE catalog row into per-program-day variants.
 *
 * THE INVERSE OF `merge-exercise.mjs`, and it exists for the opposite failure.
 * Merging fixes one movement wearing two names, where the second name starts
 * with no history and every set is a fresh record. This fixes two movements
 * wearing ONE name, where the harder variant's history sets a bar the other can
 * never clear — a record that is silently never awarded, which leaves no trace
 * anywhere and is therefore the worse of the two.
 *
 * The concrete case (2026-08-06): `Seated Cable Row` was a V-grip pull on Upper
 * A (Sunday, 42.5 kg from its first session) and a wide-bar pull on Upper B
 * (Thursday, climbing 35 → 42.5). Sunday's 42.5 × 13 put the per-set volume bar
 * at 552.5 kg and the e1RM bar at 60.9, so Thursday's 42.5 × 11 — 467.5 kg and
 * 58.1, a best against every wide-bar set ever logged — lost both axes.
 *
 *   node scripts/split-exercise-by-day.mjs "<name>" <dayKey>=<variant> [...] --dry-run
 *   node scripts/split-exercise-by-day.mjs "<name>" <dayKey>=<variant> [...]
 *
 *   node scripts/split-exercise-by-day.mjs "Seated Cable Row" \
 *     cb_a="Seated Cable Row (V-Grip)" cb_b="Seated Cable Row (Wide Grip)"
 *
 * Creates each variant row (copying muscle tags and the compound flag from the
 * parent) and re-points every `workout_sets` row onto it, chosen by the PARENT
 * SESSION'S `day_key` — the workout's own identity, so a swapped day migrates
 * to what was actually performed rather than to what the weekday implies.
 *
 * The parent row is KEPT. Sessions whose day_key matches no mapping stay on it,
 * and a legacy plan may still reference it; an emptied row is harmless while a
 * deleted one breaks whatever still points at it.
 *
 * IDEMPOTENT. Re-running moves nothing once every set is on a variant.
 *
 * ALWAYS, in the same change: give each variant its own `exercises.slug` and
 * alias (the native catalogue is `exercises` + `ExerciseIndex`; a routine
 * template naming the parent slug must be repointed), then re-run
 * `scripts/reconcile-pr-counts.mjs` — the PR ledger is rebuilt on the phone
 * by the rescore cascade the next time each affected session is opened.
 *
 * Requires NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env.local.
 * Service-role: bypasses RLS, so it must never run in the browser bundle.
 */
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const DRY = process.argv.includes('--dry-run')
const args = process.argv.slice(2).filter((a) => a !== '--dry-run')
const [PARENT, ...pairs] = args

const MAP = new Map()
for (const p of pairs) {
  const i = p.indexOf('=')
  if (i < 0) { console.error(`Bad mapping "${p}" — expected <dayKey>=<variant name>`); process.exit(1) }
  MAP.set(p.slice(0, i).trim(), p.slice(i + 1).trim())
}
if (!PARENT || !MAP.size) {
  console.error('Usage: node scripts/split-exercise-by-day.mjs "<name>" <dayKey>=<variant> [...] [--dry-run]')
  process.exit(1)
}

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

// ── resolve the parent ───────────────────────────────────────────────────────
// `split_day` and `name_he` come along too: `split_day` is NOT NULL, and a
// variant of an upper-body pull is still an upper-body pull.
const { data: parentRows, error: exErr } = await db.from('exercises')
  .select('id, name, name_he, split_day, muscle_groups, is_compound, user_id').eq('name', PARENT)
if (exErr) { console.error('exercises read failed:', exErr.message); process.exit(1) }
const parent = parentRows?.[0]
if (!parent) { console.error(`No exercises row named "${PARENT}".`); process.exit(1) }

// ── the sets to move, with their session's day_key ───────────────────────────
const { data: sets, error: setErr } = await db.from('workout_sets')
  .select('id, weight_kg, reps, workout_sessions!inner(started_at, day_key)')
  .eq('exercise_id', parent.id)
if (setErr) { console.error('workout_sets read failed:', setErr.message); process.exit(1) }

const buckets = new Map()   // variant name → set rows
const unmapped = []
for (const s of sets ?? []) {
  const dayKey = s.workout_sessions?.day_key ?? null
  const variant = dayKey ? MAP.get(dayKey) : undefined
  if (!variant) { unmapped.push({ ...s, dayKey }); continue }
  const b = buckets.get(variant) ?? []
  b.push(s)
  buckets.set(variant, b)
}

console.log(`"${parent.name}" · ${sets?.length ?? 0} sets\n`)
for (const [variant, rows] of buckets) {
  const dates = [...new Set(rows.map((r) => r.workout_sessions.started_at.slice(0, 10)))].sort()
  console.log(`  → ${variant}: ${rows.length} sets across ${dates.length} sessions (${dates.join(', ')})`)
}
if (unmapped.length) {
  const keys = [...new Set(unmapped.map((r) => r.dayKey ?? 'null'))]
  console.log(`  · staying on "${parent.name}": ${unmapped.length} sets (day_key ${keys.join(', ')})`)
}
console.log()

if (DRY) { console.log('Dry run — nothing written.'); process.exit(0) }
if (!buckets.size) { console.log('Nothing to move.'); process.exit(0) }

// ── create each variant, then re-point its sets ──────────────────────────────
for (const [variant, rows] of buckets) {
  const { data: existing } = await db.from('exercises').select('id').eq('name', variant).maybeSingle()
  let id = existing?.id
  if (!id) {
    // Muscle tags and the compound flag are inherited: a grip changes emphasis,
    // not which muscles the movement trains, and re-deriving them here would
    // let the catalog drift from the parent it was cut out of.
    const { data: made, error } = await db.from('exercises').insert({
      user_id: parent.user_id,
      name: variant,
      name_he: parent.name_he,
      split_day: parent.split_day,
      muscle_groups: parent.muscle_groups,
      is_compound: parent.is_compound,
    }).select('id').single()
    if (error) { console.error(`insert "${variant}" failed:`, error.message); process.exit(1) }
    id = made.id
    console.log(`created "${variant}"`)
  }
  // Individual updates rather than an upsert: an upsert on workout_sets would
  // need every NOT NULL column echoed back, and one typo there rewrites history.
  let moved = 0
  for (const s of rows) {
    const { error } = await db.from('workout_sets').update({ exercise_id: id }).eq('id', s.id)
    if (error) { console.error(`move set ${s.id} failed:`, error.message); process.exit(1) }
    moved += 1
  }
  console.log(`moved ${moved} sets → "${variant}"`)
}

console.log('\nDone. Now re-run: node scripts/backfill-prs.mjs --dry-run')
