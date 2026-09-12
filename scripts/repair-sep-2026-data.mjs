#!/usr/bin/env node
/**
 * Reconcile two September 2026 sessions against what was actually performed.
 *
 * ── § 1 · 2026-09-08 "Delts & Arms" ─────────────────────────────────────────
 * Compared set by set against the Hevy record of the same workout. Three things
 * disagreed, and only one of them moves a number:
 *
 *   · Seated Incline DB Curl set 2 stored 16 kg × 13; it was 16 kg × 12. That
 *     one rep is the whole of the tonnage gap — 3,696.75 against 3,680.75.
 *   · The treadmill stored 0.370 km; the bout was 0.4 km. It carries no load,
 *     so this changes the bout and not the tonnage.
 *   · `exercise_order` was scrambled: Seated Incline DB Curl had rows under
 *     BOTH 1 and 2, and Single Arm Lateral Raise under both 2 and 4. So the
 *     summary drew two of each movement — one card with three sets and one
 *     with a single stray. Every reader that groups a session
 *     (`SessionAnalysis.grouped`, `useSessionDetail`) sorts on this column, so
 *     the damage is visible on both clients and in the weekly export.
 *
 * The Single Arm Lateral Raise rows are NOT flattened. Hevy lists four sets;
 * this database holds seven rows — one unsided and three L/R pairs — and those
 * are the same four sets under `SessionVolume`'s weaker-side rule, which is
 * exactly why that rule exists (see `SessionVolume` in OnyxCore). Collapsing
 * them to four rows would destroy the per-side asymmetry (L 15 / R 16) without
 * changing a single number.
 *
 * ── § 2 · 2026-09-03 "Upper B" ──────────────────────────────────────────────
 * Twelve sets and 3,108.5 kg, stored as `duration_min = 2` with `ended_at`
 * 120 seconds after `started_at`. Both halves are corrupt together, so the
 * timestamps cannot repair the duration and the duration cannot repair the
 * timestamps. Backfilled to 60 minutes, and `ended_at` moved with it so a later
 * `closeSession` or pull cannot re-derive the 2 from a stale clock.
 *
 * WHY 60: the founder named it. For the record, this session's own neighbours —
 * 12-to-14-set sessions in the same fortnight — ran 46 to 48 minutes, so 60 is
 * generous rather than typical. It is one constant below if that matters later.
 *
 * ── WHAT IS RECOMPUTED, AND WHAT IS NOT ─────────────────────────────────────
 * `total_volume_kg` and `set_count` are recomputed FROM THE ROWS under the same
 * two rules the app writes them with, rather than being set to a literal:
 * a literal is correct once, and a recomputation is correct after the next
 * repair too. `session_score` is deliberately left null — `save.ts` writes null
 * there and the day's score lives in `daily_scores`, which
 * `scripts/recompute-scores.mjs` owns.
 *
 * `effort` (rpe), `quality`, `is_pr` and `est_1rm_kg` are NOT touched on any
 * row. The ratings are the athlete's own record of how the set went and no
 * comparison against another app's export has anything to say about them.
 *
 * IDEMPOTENT. Every write is an absolute value, never a delta, and the second
 * run reports zero changes.
 *
 *   node scripts/repair-sep-2026-data.mjs --dry-run   # print the diff, write nothing
 *   HELIX_APPLY=1 node scripts/repair-sep-2026-data.mjs
 *
 * Requires NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env.local.
 */
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const DRY = process.argv.includes('--dry-run')

const USER_ID = 'f405d57b-d09f-4a2e-8a33-0c112f2ec34c'

/** The 2026-09-08 session, as Hevy recorded it. */
const ARMS_DATE = '2026-09-08'
const ARMS_DAY_KEY = 'arms'
/** The tonnage this session must come to once the rows are right. */
const ARMS_EXPECTED_KG = 3680.75

/** The 2026-09-03 session whose clock was written after it had stopped. */
const UPPER_B_DATE = '2026-09-03'
const UPPER_B_DAY_KEY = 'cb_b'
/** Minutes to backfill it to. See the header. */
const UPPER_B_DURATION_MIN = 60

/**
 * The movement order the workout was performed in. `exercise_order` is dense
 * from 0 and one movement occupies exactly one position — a movement with rows
 * under two different orders is the defect this repairs.
 */
const ARMS_ORDER = [
  'Treadmill',
  'Shoulder Press',
  'Seated Incline DB Curl',
  'Overhead Triceps Extension',
  'Single Arm Lateral Raise',
  'Rope Triceps Pushdown',
  'Hammer Curl',
  'Reverse EZ-Bar Curl',
]

/**
 * Every set, keyed by movement, in performed order — the Hevy record.
 *
 * Matched to rows POSITIONALLY within a movement, by `set_number`, which is why
 * a unilateral pair is one entry here and two rows in the database: both sides
 * of a pair share a set number and are corrected together only when they
 * disagree with it, which they do not on this day.
 */
const ARMS_TRUTH = {
  Treadmill: [{ distanceKm: 0.4, durationSec: 300 }],
  'Shoulder Press': [{ kg: 35, reps: 10 }, { kg: 35, reps: 9 }, { kg: 35, reps: 8 }],
  'Seated Incline DB Curl': [{ kg: 16, reps: 12 }, { kg: 16, reps: 12 }, { kg: 16, reps: 8 }],
  'Overhead Triceps Extension': [{ kg: 11.25, reps: 15 }, { kg: 12.5, reps: 12 }, { kg: 12.5, reps: 11 }],
  'Rope Triceps Pushdown': [{ kg: 13.75, reps: 15 }, { kg: 13.75, reps: 13 }],
  'Hammer Curl': [{ kg: 20, reps: 12 }, { kg: 20, reps: 12 }, { kg: 20, reps: 10 }],
  'Reverse EZ-Bar Curl': [{ kg: 15, reps: 15 }, { kg: 15, reps: 13 }],
  // Single Arm Lateral Raise is deliberately absent: its seven rows are three
  // L/R pairs plus one unsided set, and under the weaker-side rule they already
  // come to Hevy's four sets (5×16, 5×15, 3.75×19, 3.75×15). Asserting the
  // four flat numbers against seven rows would be comparing two spellings of
  // the same fact — and "fixing" it would delete the recorded asymmetry.
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

/**
 * `SessionVolume.tonnage` from OnyxCore, over DB rows.
 *
 * A COPY, not an import: the rule lives in Swift and this script is plain ESM.
 * It is eight lines and it is pinned by the golden fixtures on the Swift side —
 * re-check it against `OnyxCore/Sessions/Volume.swift` before any
 * re-run; if the two ever disagree, the Swift is the rule and this is the copy
 * that is wrong.
 */
function sessionVolumeKg(rows) {
  const pairs = new Map()
  let total = 0
  for (const s of rows) {
    if ((s.set_type ?? 'normal') === 'ghost') continue
    const w = Number(s.weight_kg) || 0
    const r = Number(s.reps) || 0
    if (s.pair_id && (s.side === 'L' || s.side === 'R')) {
      const bucket = pairs.get(s.pair_id) ?? []
      bucket.push({ w, r, side: s.side })
      pairs.set(s.pair_id, bucket)
      continue
    }
    total += w * r
  }
  for (const bucket of pairs.values()) {
    const left = bucket.find((x) => x.side === 'L')
    const right = bucket.find((x) => x.side === 'R')
    if (left && right) total += Math.min(left.w, right.w) * Math.min(left.r, right.r)
    else for (const x of bucket) total += x.w * x.r
  }
  return Math.round(total * 100) / 100
}

/** `countCommittedSets`: each `pair_id` once, every unpaired row once, ghosts out. */
function countCommittedSets(rows) {
  const paired = new Set()
  let solo = 0
  for (const s of rows) {
    if ((s.set_type ?? 'normal') === 'ghost') continue
    if (s.pair_id) paired.add(s.pair_id)
    else solo++
  }
  return solo + paired.size
}

/** The session logged on `date` under `dayKey`, in the athlete's own zone. */
async function sessionOn(date, dayKey) {
  const { data, error } = await db
    .from('workout_sessions')
    .select('id, started_at, ended_at, duration_min, total_volume_kg, set_count, day_key')
    .eq('user_id', USER_ID)
    .eq('day_key', dayKey)
    .gte('started_at', `${date}T00:00:00+03:00`)
    .lt('started_at', `${date}T23:59:59+03:00`)
    .order('started_at', { ascending: true })
  if (error) throw error
  if (data?.length !== 1) {
    console.error(`Expected exactly one ${dayKey} session on ${date}, found ${data?.length ?? 0}. Refusing to run.`)
    process.exit(1)
  }
  return data[0]
}

const changes = []
const note = (table, id, what, from, to) => {
  if (String(from) === String(to)) return
  changes.push({ table, id, what, from, to })
}

// ── § 1 · the 2026-09-08 sets ───────────────────────────────────────────────

const arms = await sessionOn(ARMS_DATE, ARMS_DAY_KEY)
const { data: rows, error: rowsError } = await db
  .from('workout_sets')
  .select('id, exercise_id, set_number, exercise_order, weight_kg, reps, side, pair_id, set_type, duration_sec, distance_km, incline, exercises(name)')
  .eq('session_id', arms.id)
  .order('set_number', { ascending: true })
if (rowsError) throw rowsError
if (!rows?.length) { console.error('No sets on the 2026-09-08 session — refusing to run.'); process.exit(1) }

console.log(`\n2026-09-08 "Delts & Arms" — ${arms.id}`)
console.log(`  before: ${rows.length} rows · ${arms.total_volume_kg} kg · set_count ${arms.set_count}`)

const byName = new Map()
for (const r of rows) {
  const name = r.exercises?.name ?? r.exercise_id
  byName.set(name, [...(byName.get(name) ?? []), r])
}

const unknown = [...byName.keys()].filter((n) => !ARMS_ORDER.includes(n))
if (unknown.length) {
  console.error(`Movements this repair does not know about: ${unknown.join(', ')}. Refusing to run.`)
  process.exit(1)
}

/** Row id → the columns to write. Built first, applied once, so a row that
 *  needs two corrections is one request and the dry run reads as one row. */
const patch = new Map()
const stage = (row, column, value) => {
  patch.set(row.id, { ...(patch.get(row.id) ?? {}), [column]: value })
}

for (const [name, group] of byName) {
  // The movement's one position in the session.
  const order = ARMS_ORDER.indexOf(name)
  for (const row of group) {
    if (row.exercise_order !== order) {
      note('workout_sets', `${name} #${row.set_number}`, 'exercise_order', row.exercise_order, order)
      stage(row, 'exercise_order', order)
    }
  }

  const truth = ARMS_TRUTH[name]
  if (!truth) continue

  // Positional within the movement, by set number — a pair's two rows share
  // one, so they take the same entry and are corrected together.
  const numbers = [...new Set(group.map((r) => r.set_number))].sort((a, b) => a - b)
  if (numbers.length !== truth.length) {
    console.error(`${name}: ${numbers.length} sets stored, ${truth.length} in the record. Refusing to run.`)
    process.exit(1)
  }
  for (const [index, setNumber] of numbers.entries()) {
    const want = truth[index]
    for (const row of group.filter((r) => r.set_number === setNumber)) {
      for (const [column, value] of [
        ['weight_kg', want.kg], ['reps', want.reps],
        ['distance_km', want.distanceKm], ['duration_sec', want.durationSec],
      ]) {
        if (value == null) continue
        if (Number(row[column]) === Number(value)) continue
        note('workout_sets', `${name} #${setNumber}`, column, row[column], value)
        stage(row, column, value)
      }
    }
  }
}

// The session's own aggregates, over the rows AS THEY WILL BE.
const repaired = rows.map((r) => ({ ...r, ...(patch.get(r.id) ?? {}) }))
const volumeKg = sessionVolumeKg(repaired)
const setCount = countCommittedSets(repaired)

if (volumeKg !== ARMS_EXPECTED_KG) {
  console.error(
    `\nThe repaired rows come to ${volumeKg} kg, not the ${ARMS_EXPECTED_KG} kg this session is asserted to be.\n` +
    `Nothing has been written. Either the record above is wrong or a row this script does not know about changed.`,
  )
  process.exit(1)
}
note('workout_sessions', arms.id, 'total_volume_kg', arms.total_volume_kg, volumeKg)
note('workout_sessions', arms.id, 'set_count', arms.set_count, setCount)
console.log(`  after:  ${rows.length} rows · ${volumeKg} kg · set_count ${setCount}`)

// ── § 2 · the 2026-09-03 clock ──────────────────────────────────────────────

const upperB = await sessionOn(UPPER_B_DATE, UPPER_B_DAY_KEY)
const endedAt = new Date(
  new Date(upperB.started_at).getTime() + UPPER_B_DURATION_MIN * 60_000,
).toISOString()
console.log(`\n2026-09-03 "Upper B" — ${upperB.id}`)
console.log(`  before: duration_min ${upperB.duration_min} · ended_at ${upperB.ended_at}`)
console.log(`  after:  duration_min ${UPPER_B_DURATION_MIN} · ended_at ${endedAt}`)
note('workout_sessions', upperB.id, 'duration_min', upperB.duration_min, UPPER_B_DURATION_MIN)
if (new Date(upperB.ended_at).getTime() !== new Date(endedAt).getTime()) {
  note('workout_sessions', upperB.id, 'ended_at', upperB.ended_at, endedAt)
}

// ── The diff ────────────────────────────────────────────────────────────────

console.log(`\n${changes.length} change${changes.length === 1 ? '' : 's'}:`)
for (const c of changes) console.log(`  ${c.table}  ${c.id}  ${c.what}: ${c.from} → ${c.to}`)

if (DRY) {
  console.log('\nDRY RUN — nothing written.')
  process.exit(0)
}
if (!changes.length) {
  console.log('\nNothing to do.')
  process.exit(0)
}

// ── Apply ───────────────────────────────────────────────────────────────────

for (const [id, columns] of patch) {
  const { error } = await db.from('workout_sets').update(columns).eq('id', id)
  if (error) throw error
}

const { error: armsError } = await db
  .from('workout_sessions')
  .update({ total_volume_kg: volumeKg, set_count: setCount, updated_at: new Date().toISOString() })
  .eq('id', arms.id)
if (armsError) throw armsError

const { error: upperBError } = await db
  .from('workout_sessions')
  .update({ duration_min: UPPER_B_DURATION_MIN, ended_at: endedAt, updated_at: new Date().toISOString() })
  .eq('id', upperB.id)
if (upperBError) throw upperBError

console.log(`\nApplied. ${patch.size} set row${patch.size === 1 ? '' : 's'} and 2 session rows written.`)
console.log('Now re-run the daily scores: node scripts/recompute-scores.mjs --from 2026-09-03 --to 2026-09-10')
