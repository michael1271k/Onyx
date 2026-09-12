/**
 * The pure half of `useRecovery.ts` — the soreness vocabulary and the fold the
 * score reads — in a module with no 'use client' header, so the scorer
 * (`computeForDate`) can reach it without pulling react-query and a Supabase
 * client into its bundle. `recovery/fatigue.ts` is the same split, one file over.
 *
 * ── THE FOLD IS THE POINT OF THIS FILE ───────────────────────────────────────
 * `domsSeverity` used to be the mean severity over ROWS PRESENT, with no
 * vocabulary check at any layer — not in the client (`useLogDoms` takes
 * `muscle: string`), not in the types, and not in the database (the CHECK
 * constraint on `muscle_group` was dropped in `dashboard-polish.sql` on the
 * premise that the app only ever writes from a closed set).
 *
 * Two things follow from that, and one of them was already live:
 *
 *   · `scripts/seed-demo-account.mjs` writes `'Quadriceps'` and `'Lats'`.
 *     Neither is a DOMS muscle, so neither can ever be read back as a rating —
 *     and both were counted in the denominator anyway.
 *   · Laterality doubles the row count per complaint. Under a row-count mean,
 *     rating both biceps instead of one would have silently re-based every
 *     battery number, retroactively, because scoring recomputes history.
 *
 * So the denominator becomes DISTINCT RECOGNISED MUSCLE, and the numerator the
 * MAX severity across that muscle's sides and sub-regions. Sub-regions and
 * sides are then free: a muscle contributes exactly one number however many
 * ways it was described, which is what keeps this wave's history invariant.
 *
 * Max rather than mean within a muscle, deliberately. "Left quad severe, right
 * quad fine" is a severe quad — averaging it to moderate reports a day nobody
 * had.
 */

/**
 * The ten tracked muscles, in display order: upper (Chest → Shoulders), trunk
 * (Abs), then lower (Glutes → Calves).
 *
 * `Inner thighs` is the tenth, added 2026-09-08. The adductors were the one
 * muscle the atlas DREW and soreness could never report: hip adduction is on the
 * deck, it gets sore like anything else, and a rating had nowhere to land. It
 * sits between Hamstrings and Calves so the lower-body block still reads top to
 * bottom.
 */
export const DOMS_MUSCLES = ['Chest', 'Back', 'Arms', 'Shoulders', 'Abs', 'Glutes', 'Quads', 'Hamstrings', 'Inner thighs', 'Calves'] as const
export type DomsMuscle = (typeof DOMS_MUSCLES)[number]

export const DOMS_LEVELS = [
  { v: 0, label: 'None' },
  { v: 1, label: 'Mild' },
  { v: 2, label: 'Moderate' },
  { v: 3, label: 'Severe' },
] as const

const RECOGNISED: ReadonlySet<string> = new Set(DOMS_MUSCLES)

/** Is this a muscle the scorer will count? Anything else is unreadable data. */
export function isDomsMuscle(muscle: string): muscle is DomsMuscle {
  return RECOGNISED.has(muscle)
}

/** The shape every caller of the fold already has in hand. */
export interface SorenessRow {
  muscle_group: string
  severity: number
}

/**
 * Mean severity of a day's soreness, 0..3 — one number per muscle, however many
 * rows describe it. `null` when the day has no recognised rating at all, which
 * is "no answer" and not "no soreness".
 *
 * Zeros are kept: a muscle rated "not sore" IS an answer, and dropping it would
 * make a careful rating pass look like a lazy one.
 */
export function foldDomsSeverity(rows: readonly SorenessRow[]): number | null {
  const peak = new Map<string, number>()
  for (const r of rows) {
    if (!isDomsMuscle(r.muscle_group)) continue
    if (!Number.isFinite(r.severity)) continue
    peak.set(r.muscle_group, Math.max(peak.get(r.muscle_group) ?? 0, r.severity))
  }
  if (peak.size === 0) return null
  let total = 0
  for (const v of peak.values()) total += v
  return total / peak.size
}
