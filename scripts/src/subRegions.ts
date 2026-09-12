import { DOMS_MUSCLES, type DomsMuscle } from './soreness'

/**
 * Soreness sub-regions, sides and joints — the three vocabularies v2 adds.
 *
 * ── WHY THIS IS A SUB-KEY AND NOT AN ELEVENTH MUSCLE ─────────────────────────
 * Onyx already speaks three muscle languages that fold ONE way (raw program
 * tokens → 16 LANDMARK muscles → 10 DOMS muscles; see `atlas.ts`). The obvious
 * way to say "erectors, not traps" is to add members to one of those sets. It
 * is also the expensive way, and the expense is invisible until it has already
 * shipped:
 *
 *   · `muscleHue.ts` builds a family ramp by luminance — a new member with no
 *     distinct hex silently collapses two steps to one colour.
 *   · `OnyxTokens.swift`'s `muscleFamily` returns `members[count / 2]`, so
 *     adding a member CHANGES that family's colour on every native surface.
 *   · `useWeeklyLoop` casts a database string with `as LandmarkMuscle`,
 *     unchecked, and indexes the targets with it.
 *   · `AccountSeed` seeds `allCases` for NEW accounts only, so an added muscle
 *     is split-brain: seeded for new users, target 0 forever for everyone else.
 *   · Eight tests pin one of the two sets exhaustively, including one that pins
 *     the exact ordered list of sixteen hexes in a Swift file.
 *
 * The evidence that this drift is real rather than theoretical: `Inner thighs`
 * became the tenth DOMS muscle on 2026-09-08, and four days later the tracker's
 * own docstring still said nine.
 *
 * So a sub-region lives BELOW a DOMS muscle. `subRegionParent` folds it in one
 * step, the fold is total, and nothing upstream learns a new word: scoring,
 * volume, hues, the atlas and the seed all keep seeing the same ten.
 *
 * ── AND IT IS PLAIN DATA ─────────────────────────────────────────────────────
 * No React, no colour, no Supabase. `gen-doms-swift.mjs` mirrors these three
 * lists into `DomsMap.swift`, and `check:doms` fails if the two drift.
 */

/** Which side a rating is about. `both` is the default and the pre-v2 meaning. */
export const SORENESS_SIDES = ['both', 'left', 'right'] as const
export type SorenessSide = (typeof SORENESS_SIDES)[number]

/** Short marker used in the weekly export. `both` carries none. */
export const SIDE_MARK: Record<SorenessSide, string> = { both: '', left: 'L', right: 'R' }

/**
 * The sub-regions of the four DOMS muscles that have them.
 *
 * A parent absent from this map has none, and is always rated whole. A parent
 * present here may STILL be rated whole — "Back: 2" stays a complete answer, and
 * `''` is that answer's stored sub-region.
 *
 * `Abductors` is the reason this file can be small. The brief asks for abductor
 * soreness; `LANDMARK_MUSCLES` has `Adductors` and no abductors, and there is no
 * volume target, no exercise mapping and no scoring path for one. As a landmark
 * it would drag in the whole list above. As a sub-region it is one string.
 *
 * `Traps` / `Rhomboids` / `Erectors` likewise: the landmark set already splits
 * `Upper back` from `Lower back`, but soreness is reported in DOMS vocabulary
 * where both fold into `Back`, so the distinction the brief wants is expressible
 * here with no taxonomy change at all.
 */
export const SUB_REGIONS = {
  Back: ['Traps', 'Rhomboids', 'Lats', 'Erectors'],
  Shoulders: ['Front delts', 'Side delts', 'Rear delts'],
  Arms: ['Biceps', 'Triceps', 'Forearms'],
  'Inner thighs': ['Adductors', 'Abductors'],
} as const satisfies Partial<Record<DomsMuscle, readonly string[]>>

export type SubRegionParent = keyof typeof SUB_REGIONS
export type SubRegion = (typeof SUB_REGIONS)[SubRegionParent][number]

/** Every sub-region, flat, in parent-then-declaration order. */
export const ALL_SUB_REGIONS: readonly SubRegion[] =
  DOMS_MUSCLES.flatMap((m) => (m in SUB_REGIONS ? SUB_REGIONS[m as SubRegionParent] : []))

/** Does this muscle divide? */
export function hasSubRegions(muscle: DomsMuscle): muscle is SubRegionParent {
  return muscle in SUB_REGIONS
}

/** The sub-regions of a muscle, or empty. Never null — a caller maps over it. */
export function subRegionsOf(muscle: DomsMuscle): readonly SubRegion[] {
  return hasSubRegions(muscle) ? SUB_REGIONS[muscle] : []
}

/**
 * The DOMS muscle a sub-region belongs to, or null if it is not one.
 *
 * This is the fold that keeps every consumer upstream unchanged, and it is
 * total over `ALL_SUB_REGIONS` — asserted by a test, because a sub-region that
 * folded nowhere would be a rating the scoring engine could never see.
 */
export function subRegionParent(sub: string): DomsMuscle | null {
  for (const parent of Object.keys(SUB_REGIONS) as SubRegionParent[]) {
    if ((SUB_REGIONS[parent] as readonly string[]).includes(sub)) return parent
  }
  return null
}

/**
 * The joints and connective-tissue points a complaint can be filed against.
 *
 * NOT muscles, and deliberately not in any muscle vocabulary: a knee is not
 * something you can train, and giving it a landmark to hang on would be
 * inventing anatomy to satisfy a key. These are their own table, their own
 * layer on the figure, and they never reach the scoring engine.
 */
export const JOINTS = [
  'Knee', 'Hip', 'Ankle', 'Wrist', 'Elbow', 'AC joint', 'Lumbar junction', 'Neck',
] as const
export type Joint = (typeof JOINTS)[number]

/**
 * Which group sheet a joint is offered in — so a joint is reachable from the
 * same tap that reaches the muscles around it, and no joint is orphaned.
 *
 * Keyed on the four `SorenessGroup`s in `SorenessMap.tsx`, spelled here as
 * strings so this module stays free of component imports.
 */
export const JOINTS_BY_GROUP: Record<'torso' | 'back' | 'arms' | 'legs', readonly Joint[]> = {
  torso: ['Neck'],
  back: ['Lumbar junction'],
  arms: ['AC joint', 'Elbow', 'Wrist'],
  legs: ['Hip', 'Knee', 'Ankle'],
}
