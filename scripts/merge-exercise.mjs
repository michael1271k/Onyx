#!/usr/bin/env node
/**
 * Merge two catalog rows that are the same movement under different names.
 *
 * WHY THIS EXISTS
 * The day templates named some stations differently on their A and B days, so
 * one machine ended up with TWO `exercises` rows and therefore two independent
 * PR baselines. The failure is silent and always in the same direction: a lift
 * already performed under name A counts as a fresh record the first time it is
 * logged under name B. It has now happened three times (the machine merges on
 * 2026-08-01, and Cable Lateral Raise vs Single Arm Lateral Raise (Cable) on
 * 2026-08-02), so it gets a tool rather than another hand-run one-off.
 *
 *   node scripts/merge-exercise.mjs "<absorbed>" "<survivor>" --dry-run
 *   node scripts/merge-exercise.mjs "<absorbed>" "<survivor>"
 *
 * Re-points every workout_set off the absorbed row onto the survivor, then
 * deletes the absorbed row. Both names are matched exactly against
 * `exercises.name`. ALWAYS add the absorbed name as an alias on the survivor
 * row (`exercises.aliases`) — otherwise the next phone-logged set under the
 * old name recreates the row this just deleted.
 *
 * Requires NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env.local.
 * Service-role: bypasses RLS, so it must never run in the browser bundle.
 */
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const args = process.argv.slice(2).filter((a) => a !== '--dry-run')
const DRY = process.argv.includes('--dry-run')
const [FROM_NAME, TO_NAME] = args
if (!FROM_NAME || !TO_NAME) {
  console.error('Usage: node scripts/merge-exercise.mjs "<absorbed>" "<survivor>" [--dry-run]')
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

// ── resolve both rows ────────────────────────────────────────────────────────
const { data: rows, error } = await db.from('exercises')
  .select('id, name').in('name', [FROM_NAME, TO_NAME])
if (error) { console.error('exercises read failed:', error.message); process.exit(1) }

const from = rows.find((r) => r.name === FROM_NAME)
const to = rows.find((r) => r.name === TO_NAME)
if (!from) { console.error(`No exercises row named "${FROM_NAME}" — nothing to merge.`); process.exit(1) }
if (!to) { console.error(`No exercises row named "${TO_NAME}" — the survivor must already exist.`); process.exit(1) }

const { data: moving } = await db.from('workout_sets')
  .select('id, set_number, weight_kg, reps, workout_sessions(started_at)')
  .eq('exercise_id', from.id)
const { data: existing } = await db.from('workout_sets').select('id').eq('exercise_id', to.id)

console.log(`"${FROM_NAME}" (${from.id})`)
console.log(`  → "${TO_NAME}" (${to.id})\n`)
for (const s of (moving ?? []).sort((a, b) =>
  String(a.workout_sessions?.started_at).localeCompare(String(b.workout_sessions?.started_at)))) {
  console.log(`  ${String(s.workout_sessions?.started_at ?? '').slice(0, 10)}  set ${s.set_number}  ${s.weight_kg}×${s.reps}`)
}
console.log(`\n${moving?.length ?? 0} sets to re-point · survivor currently holds ${existing?.length ?? 0}`)

if (DRY) {
  console.log('\n--dry-run: nothing written.')
  process.exit(0)
}

// ── apply ────────────────────────────────────────────────────────────────────
// Sets move FIRST. If the delete failed afterwards the catalog would carry a
// harmless empty row; deleting first could orphan real training history.
const { error: e1 } = await db.from('workout_sets')
  .update({ exercise_id: to.id }).eq('exercise_id', from.id)
if (e1) { console.error('re-point failed:', e1.message); process.exit(1) }

const { error: e2 } = await db.from('exercises').delete().eq('id', from.id)
if (e2) { console.error('delete failed (sets were moved):', e2.message); process.exit(1) }

const { data: after } = await db.from('workout_sets').select('id').eq('exercise_id', to.id)
console.log(`\nMerged. "${TO_NAME}" now holds ${after?.length ?? 0} sets; "${FROM_NAME}" is gone.`)
console.log('Add the absorbed name to the survivor row\'s aliases so it cannot respawn.')
