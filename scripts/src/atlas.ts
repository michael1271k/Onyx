import type { DomsMuscle } from './soreness'

/**
 * The sixteen landmark muscles, in display order. The Swift twin is
 * `OnyxCore/Training/Landmarks.swift`; the two lists must agree by hand.
 */
export const LANDMARK_MUSCLES = [
  'Chest', 'Lats', 'Upper back', 'Lower back',
  'Front delts', 'Side delts', 'Rear delts',
  'Biceps', 'Triceps', 'Forearms',
  'Quads', 'Hamstrings', 'Glutes', 'Adductors', 'Calves', 'Abs/core',
] as const
export type LandmarkMuscle = (typeof LANDMARK_MUSCLES)[number]

/**
 * The muscle atlas — ONE anatomy, for every surface that draws a body.
 *
 * ── THREE TAXONOMIES MET HERE ────────────────────────────────────────────────
 * Onyx speaks three muscle languages and none of them was anatomical:
 *
 *   · raw program tokens   (`muscleMap.ts` — 'lats', 'inner_thigh', 'pecs')
 *   · 13 LANDMARK MUSCLES  (`landmarks.ts` — what volume is targeted against)
 *   · 10 DOMS muscles      (`useRecovery.ts` — what soreness is reported in)
 *
 * The atlas is keyed on the LANDMARK muscles, because those are the ones the
 * program actually prescribes and the only set that distinguishes the things a
 * lifter cares about (side delts from rear delts, quads from hamstrings). The
 * other two fold INTO it — never the reverse, because both are coarser and
 * folding the other way would have to invent detail.
 *
 * ── ONE VIEWBOX, FOREVER ─────────────────────────────────────────────────────
 * 120 × 260, with a shared skeleton: head at cy 22, shoulders at y 50, waist at
 * y 126, hips at y 140, knees at y 192, ankles at y 238. Front and back
 * therefore line up when the view flips, and every consumer's layout — and the
 * widget's rect — is unaffected by what is drawn inside it.
 *
 * ── THREE LAYERS, AND WHY ────────────────────────────────────────────────────
 * It used to be two: four `BASE_SHAPES` (head, neck, two feet) and the muscle
 * bellies. That is why the figure read as an anatomy chart rather than a
 * person — there was no torso, no arm and no leg, only the bellies floating in
 * the space where a body should have been, so the whole thing was outline and
 * no mass.
 *
 *   1. `BASE_SHAPES`   — the silhouette. Head, hair, neck, torso, arms, fists,
 *                        legs, feet. Drawn under every view, never tinted: this
 *                        is the body, not the data.
 *   2. `MUSCLE_PATHS`  — the 16 landmarks, per view. The only interactive layer,
 *                        and the only one that carries intensity.
 *   3. `DETAIL_SHAPES` — definition. The face, the knuckles, the linea alba and
 *                        the three tendinous intersections that make a six-pack,
 *                        the erector groove, the scapulae, the kneecaps, the
 *                        heels. Stroked hairlines over the top, never filled,
 *                        never a hit target, never tinted.
 *
 * Layer 3 is what makes the figure read as sculpted rather than as a set of
 * regions, and it is deliberately NOT part of layer 2: a kneecap is not a
 * muscle you can train, and putting it in `MUSCLE_PATHS` would mean inventing a
 * landmark to key it on.
 *
 * ── AND TWO MORE FOR THE ÉCORCHÉ (Precision F1) ──────────────────────────────
 * The flesh material (`OnyxUI/Atlas/AtlasMaterial.swift`) draws a flayed
 * figure: muscle over a dark silhouette, with the cords and the bone that
 * show through. `TENDON_SHAPES` and `BONE_SHAPES` are those — FILLED, closed,
 * never tinted, never a hit target, and drawn only by that material (the flat
 * one ignores them). Each muscle path also carries its `fibre` axis, which the
 * material shades along. Still geometry only; the colours are tokens.
 *
 * ── AND IT IS PLAIN DATA ─────────────────────────────────────────────────────
 * No React, no colour, no severity, no shading. `MuscleAtlas.tsx` decides how a
 * body is LIT — that is a rendering decision, and it differs between a 24px
 * thumbnail and a 220px sheet. `scripts/gen-atlas-swift.mjs` turns the same
 * strings into SwiftUI `Path` builders for the widget, because SwiftUI cannot
 * parse an SVG `d` attribute. A parity test asserts the two can never drift.
 */

export const ATLAS_VIEWBOX = { width: 120, height: 260 } as const

/**
 * The midline band, in viewBox x — how a path learns which SIDE of the body it
 * is on.
 *
 * ── THE GEOMETRY ALREADY KNEW ────────────────────────────────────────────────
 * Every bilateral muscle below is TWO entries, one mirrored about x = 60, and
 * that has been true since the atlas was first drawn. Nothing read it: the hit
 * test found which path contained the tap and then returned only the muscle,
 * so "the right glute" and "the left glute" were the same answer. Adding a
 * `side` to the emitted Swift is therefore not new anatomy — it is the fact the
 * coordinates have carried all along, finally written down.
 *
 * A path's side is its vertex centroid's x against this band: left of `left`
 * is the body's left, right of `right` is its right, and anything inside the
 * band is AXIAL and has no side. The band is ±2 rather than a bare `x < 60`
 * test because three shapes straddle the spine on purpose — the trapezius
 * diamond, the erector column and the rectus abdominis — and a hard midline
 * would assign each of them a side on the accident of a control point.
 *
 * `gen-atlas-swift.mjs` parses these two numbers out of this file rather than
 * carrying its own copy, so the rule and the anatomy cannot drift apart.
 */
export const ATLAS_MIDLINE_BAND = { left: 58, right: 62 } as const

export type AtlasView = 'front' | 'back'

export interface AtlasPath {
  muscle: LandmarkMuscle
  view: AtlasView
  /** Path data on the 120 × 260 viewBox. `M`, `L`, `C` and `Z` only — the
   *  Swift generator implements exactly those four commands. */
  d: string
  /**
   * The fibre direction, in viewBox units (x right, y down; length is
   * irrelevant, and so is the sign — it is an AXIS).
   *
   * ── WHY THE ANATOMY CARRIES A DIRECTION (Precision F1) ──────────────────
   * The écorché material lights each belly with a gradient ALONG its fibres
   * and a specular band beside them, the way a flayed muscle catches light:
   * a biceps shades down its length, a pec across the chest toward the arm, a
   * glute on the diagonal from sacrum to femur. That axis is anatomy, not
   * styling — it is the same for every renderer and every size — so it lives
   * here beside the shape, and `gen-atlas-swift.mjs` refuses a path without
   * one. Which END of the axis is lit is the renderer's call (the light is
   * upper-left on every figure), which is why the sign carries nothing.
   */
  fibre: readonly [number, number]
}

/** A definition line or feature. Same command vocabulary, but stroked, not filled. */
export interface AtlasDetail {
  view: AtlasView
  d: string
}

/**
 * The silhouette — the body itself, and never data.
 *
 * Athletic proportions on the standing skeleton above: shoulders about 2.9 head
 * widths across, waist narrowing to y 126, arms hanging to mid-thigh and ending
 * in closed fists. Drawn under both views and never tinted; a glowing head
 * would read as a muscle nobody can train.
 */
export const BASE_SHAPES: readonly string[] = [
  // Head
  'M60,10 C67,10 72,16 72,24 C72,31 68,37 63,39 C62,40 61,40 60,40 C59,40 58,40 57,39 C52,37 48,31 48,24 C48,16 53,10 60,10 Z',
  // Hair — a short crop, sitting on the skull rather than replacing it.
  'M48,24 C48,14 53,8 60,8 C67,8 72,14 72,24 C72,20 71,17 69,15 C65,11 55,11 51,15 C49,17 48,20 48,24 Z',
  // Neck, resting on the jaw above it
  'M56,37 C56,41 55,44 53,47 L67,47 C65,44 64,41 64,37 C63,39 62,40 60,40 C58,40 57,39 56,37 Z',
  // Torso: trapezius slope, ribcage, the taper into the waist, then the hips
  'M43,52 C48,46 53,44 60,44 C67,44 72,46 77,52 C83,58 85,71 84,84 C83,98 79,110 77,122 C78,132 80,142 81,150 L39,150 C40,142 42,132 43,122 C41,110 37,98 36,84 C35,71 37,58 43,52 Z',
  // Left arm, hanging clear of the ribcage
  'M41,51 C33,54 27,63 26,75 C25,87 25,100 27,112 C28,126 31,139 34,150 L42,148 C39,137 37,125 36,112 C35,100 35,88 37,77 C38,66 40,56 43,52 Z',
  // Right arm
  'M79,51 C87,54 93,63 94,75 C95,87 95,100 93,112 C92,126 89,139 86,150 L78,148 C81,137 83,125 84,112 C85,100 85,88 83,77 C82,66 80,56 77,52 Z',
  // Left fist — closed, not a taper into nothing
  'M34,149 C30,152 28,158 31,163 C34,168 41,168 44,163 C46,159 45,153 43,148 Z',
  // Right fist
  'M86,149 C90,152 92,158 89,163 C86,168 79,168 76,163 C74,159 75,153 77,148 Z',
  // Left leg: thigh, knee, calf belly, ankle
  'M39,150 C36,160 35,168 35,178 C35,186 36,190 38,194 C36,200 35,206 36,214 C37,224 39,233 43,240 L52,240 C53,232 53,223 52,214 C52,206 52,200 51,194 C53,190 55,186 56,178 C57,168 57,160 58,150 Z',
  // Right leg
  'M81,150 C84,160 85,168 85,178 C85,186 84,190 82,194 C84,200 85,206 84,214 C83,224 81,233 77,240 L68,240 C67,232 67,223 68,214 C68,206 68,200 69,194 C67,190 65,186 64,178 C63,168 63,160 62,150 Z',
  // Left foot
  'M43,239 C40,243 38,248 39,252 C41,254 48,254 52,253 C54,251 53,245 52,239 Z',
  // Right foot
  'M77,239 C80,243 82,248 81,252 C79,254 72,254 68,253 C66,251 67,245 68,239 Z',
]

/**
 * Every muscle belly, per view.
 *
 * ── WHY SOME MUSCLES APPEAR ON ONE VIEW ONLY ─────────────────────────────────
 * Chest, quads and abs are front; back, glutes, hamstrings and rear delts are
 * back. Calves and forearms appear on BOTH, because they genuinely are visible
 * from both and a figure whose forearms vanish when you flip it reads as a
 * rendering bug. A muscle drawn on both views carries the same intensity in
 * both — it is one muscle, seen twice.
 *
 * The arm is split at the elbow (y ≈ 108): above it is biceps on the front and
 * triceps on the back, below it is forearm on either.
 *
 * ── AND WHY SOME MUSCLES ARE SEVERAL PATHS ───────────────────────────────────
 * The chest is two pecs with a sternum between them, and the back is traps plus
 * two lats plus the lower column. Drawn as one blob each they read as a bib and
 * a shield; drawn as the shapes they are, the figure gains its whole midline.
 * The key is what matters — every path keyed `Chest` lights together, because
 * the program prescribes a chest, not a left pec.
 *
 * The back's four shapes carry THREE keys, because the program does prescribe
 * lats separately from traps: this is the split that turned one `Back` landmark
 * into `Lats` / `Upper back` / `Lower back`, and it needed no redraw — the
 * shapes were already apart, they had simply been sharing a name.
 */
export const MUSCLE_PATHS: readonly AtlasPath[] = [
  // ── FRONT ──
  // ── THE DELTOID CAP IS TWO MUSCLES, AND THE SEAM WAS ALREADY DRAWN ────────
  // Front view used to be one `Side delts` shape per shoulder, so the anterior
  // head — which every press in the program trains, and which the weekly
  // counter now credits nine sets a week — had no way to light. The split
  // follows the definition hairline that was already stroked over this exact
  // cap (see the deltoid seam in DETAIL_SHAPES), so the fill boundary and the
  // drawn line agree instead of crossing each other.
  //
  // Anterior takes the MEDIAL wedge (toward the sternum), lateral keeps the
  // outer sweep. Both still close on the original outline, so the silhouette is
  // byte-for-byte the shape it was — only the interior boundary is new.
  //
  // NOTE for anyone editing these: the two ORIGINAL cap strings are reused
  // verbatim as the back view's `Rear delts`. A find-and-replace on the old
  // path data hits four entries, not two.
  { muscle: 'Front delts', view: 'front', d: 'M43,50 C41,52 40,53 39,55 C34,60 31,67 30,75 L38,76 C38,69 40,60 44,54 Z', fibre: [-0.3, 1] },
  { muscle: 'Front delts', view: 'front', d: 'M77,50 C79,52 80,53 81,55 C86,60 89,67 90,75 L82,76 C82,69 80,60 76,54 Z', fibre: [0.3, 1] },
  { muscle: 'Side delts', view: 'front', d: 'M43,50 C35,53 29,61 27,71 C26,74 26,77 27,79 L30,75 C31,67 34,60 39,55 C40,53 41,52 43,50 Z', fibre: [-0.45, 1] },
  { muscle: 'Side delts', view: 'front', d: 'M77,50 C85,53 91,61 93,71 C94,74 94,77 93,79 L90,75 C89,67 86,60 81,55 C80,53 79,52 77,50 Z', fibre: [0.45, 1] },
  { muscle: 'Chest', view: 'front', d: 'M58,59 L45,60 C41,63 39,69 40,76 C41,84 47,89 54,90 C57,90 58,87 58,84 C58,76 58,67 58,59 Z', fibre: [-1, -0.35] },
  { muscle: 'Chest', view: 'front', d: 'M62,59 L75,60 C79,63 81,69 80,76 C79,84 73,89 66,90 C63,90 62,87 62,84 C62,76 62,67 62,59 Z', fibre: [1, -0.35] },
  { muscle: 'Abs/core', view: 'front', d: 'M50,93 C47,93 46,95 46,99 C46,110 48,123 51,133 L69,133 C72,123 74,110 74,99 C74,95 73,93 70,93 Z', fibre: [0, 1] },
  // The oblique flanks. Same landmark as the rectus — the program prescribes a
  // core, not a serratus — but drawn apart, because the taper from ribcage to
  // waist is most of what makes a midsection read as a midsection.
  { muscle: 'Abs/core', view: 'front', d: 'M45,99 C42,101 41,107 42,114 C43,121 45,127 48,132 L49,132 C47,122 45,110 45,99 Z', fibre: [0.35, 1] },
  { muscle: 'Abs/core', view: 'front', d: 'M75,99 C78,101 79,107 78,114 C77,121 75,127 72,132 L71,132 C73,122 75,110 75,99 Z', fibre: [-0.35, 1] },
  { muscle: 'Biceps', view: 'front', d: 'M39,62 C34,66 31,73 30,82 C29,91 29,100 30,108 L37,106 C36,98 36,90 38,81 C39,73 40,67 41,62 Z', fibre: [-0.12, 1] },
  { muscle: 'Biceps', view: 'front', d: 'M81,62 C86,66 89,73 90,82 C91,91 91,100 90,108 L83,106 C84,98 84,90 82,81 C81,73 80,67 79,62 Z', fibre: [0.12, 1] },
  { muscle: 'Forearms', view: 'front', d: 'M30,112 C30,121 31,131 33,140 C34,144 35,146 36,148 L42,146 C40,139 39,131 38,123 C38,118 38,115 38,111 Z', fibre: [0.15, 1] },
  { muscle: 'Forearms', view: 'front', d: 'M90,112 C90,121 89,131 87,140 C86,144 85,146 84,148 L78,146 C80,139 81,131 82,123 C82,118 82,115 82,111 Z', fibre: [-0.15, 1] },
  { muscle: 'Quads', view: 'front', d: 'M41,153 C37,164 36,178 39,192 L50,192 C51,178 52,164 52,153 Z', fibre: [0.05, 1] },
  { muscle: 'Quads', view: 'front', d: 'M79,153 C83,164 84,178 81,192 L70,192 C69,178 68,164 68,153 Z', fibre: [-0.05, 1] },
  // ── THE ADDUCTORS TOOK THE MEDIAL THIRD BACK (2026-09-08) ─────────────────
  // They used to be a two-unit sliver, drawn small "on purpose" and sitting
  // OUTSIDE the leg silhouette by about a unit at the hip. At a 24 px thumbnail
  // that is not a small muscle, it is no muscle: it could not be seen, could not
  // be tapped, and its colour could not be read — so the Inner thighs rating
  // would have had nothing to light. The quad's inner edge is pulled in by four
  // units at the hip and two at the knee, and the adductor takes the strip it
  // vacates, which is where the adductor group actually lies.
  { muscle: 'Adductors', view: 'front', d: 'M52,153 C52,164 51,178 50,192 L54,192 C55,178 56,164 58,153 Z', fibre: [-0.2, 1] },
  { muscle: 'Adductors', view: 'front', d: 'M68,153 C68,164 69,178 70,192 L66,192 C65,178 64,164 62,153 Z', fibre: [0.2, 1] },
  { muscle: 'Calves', view: 'front', d: 'M37,200 C36,210 36,222 38,232 C39,236 40,238 42,239 L51,239 C52,228 52,214 51,200 Z', fibre: [0.05, 1] },
  { muscle: 'Calves', view: 'front', d: 'M83,200 C84,210 84,222 82,232 C81,236 80,238 78,239 L69,239 C68,228 68,214 69,200 Z', fibre: [-0.05, 1] },

  // ── BACK ──
  { muscle: 'Rear delts', view: 'back', d: 'M43,50 C35,53 29,61 27,71 C26,74 26,77 27,79 L38,76 C38,69 40,60 44,54 Z', fibre: [-0.6, 1] },
  { muscle: 'Rear delts', view: 'back', d: 'M77,50 C85,53 91,61 93,71 C94,74 94,77 93,79 L82,76 C82,69 80,60 76,54 Z', fibre: [0.6, 1] },
  // Trapezius — the diamond from the neck out to both shoulders.
  { muscle: 'Upper back', view: 'back', d: 'M60,45 C66,45 72,47 77,52 C75,60 70,66 63,70 L60,71 L57,70 C50,66 45,60 43,52 C48,47 54,45 60,45 Z', fibre: [0, 1] },
  // Lats: wide at the armpit, sweeping IN to the waist. Drawn as their own
  // shapes with the spine between them rather than as one slab across the back,
  // because the V is the whole silhouette of a trained back.
  { muscle: 'Lats', view: 'back', d: 'M42,62 C39,70 38,80 39,90 C41,100 45,108 51,113 L57,113 C57,100 56,86 55,70 C50,69 45,66 42,62 Z', fibre: [-0.35, -1] },
  { muscle: 'Lats', view: 'back', d: 'M78,62 C81,70 82,80 81,90 C79,100 75,108 69,113 L63,113 C63,100 64,86 65,70 C70,69 75,66 78,62 Z', fibre: [0.35, -1] },
  // The erector column between the lats and the pelvis.
  { muscle: 'Lower back', view: 'back', d: 'M56,115 C58,116 62,116 64,115 C64,124 65,131 66,137 L54,137 C55,131 56,124 56,115 Z', fibre: [0, 1] },
  { muscle: 'Triceps', view: 'back', d: 'M39,62 C34,66 31,73 30,82 C29,91 29,100 30,108 L37,106 C36,98 36,90 38,81 C39,73 40,67 41,62 Z', fibre: [-0.12, 1] },
  { muscle: 'Triceps', view: 'back', d: 'M81,62 C86,66 89,73 90,82 C91,91 91,100 90,108 L83,106 C84,98 84,90 82,81 C81,73 80,67 79,62 Z', fibre: [0.12, 1] },
  { muscle: 'Forearms', view: 'back', d: 'M30,112 C30,121 31,131 33,140 C34,144 35,146 36,148 L42,146 C40,139 39,131 38,123 C38,118 38,115 38,111 Z', fibre: [0.15, 1] },
  { muscle: 'Forearms', view: 'back', d: 'M90,112 C90,121 89,131 87,140 C86,144 85,146 84,148 L78,146 C80,139 81,131 82,123 C82,118 82,115 82,111 Z', fibre: [-0.15, 1] },
  { muscle: 'Glutes', view: 'back', d: 'M43,132 C40,137 39,145 41,152 C44,156 49,157 54,154 C57,152 59,148 59,143 L59,132 Z', fibre: [-1, 0.9] },
  { muscle: 'Glutes', view: 'back', d: 'M77,132 C80,137 81,145 79,152 C76,156 71,157 66,154 C63,152 61,148 61,143 L61,132 Z', fibre: [1, 0.9] },
  { muscle: 'Hamstrings', view: 'back', d: 'M40,157 C37,168 36,180 39,192 L52,192 C53,180 54,168 56,157 Z', fibre: [0.05, 1] },
  { muscle: 'Hamstrings', view: 'back', d: 'M80,157 C83,168 84,180 81,192 L68,192 C67,180 66,168 64,157 Z', fibre: [-0.05, 1] },
  { muscle: 'Calves', view: 'back', d: 'M37,199 C36,208 36,220 38,230 C39,234 40,236 42,237 L51,237 C52,226 52,212 51,199 Z', fibre: [0.05, 1] },
  { muscle: 'Calves', view: 'back', d: 'M83,199 C84,208 84,220 82,230 C81,234 80,236 78,237 L69,237 C68,226 68,212 69,199 Z', fibre: [-0.05, 1] },
]

/**
 * Definition — stroked, never filled, never tinted, never tappable.
 *
 * Everything here is a line the light would catch: a tendon, a groove, a seam
 * between two heads of one muscle, or a feature of a face. None of it is a
 * landmark, which is exactly why it is a separate array — a kneecap has no
 * volume target and inventing a `LandmarkMuscle` to key it on would corrupt the
 * one vocabulary the program is written in.
 *
 * View-scoped, because most of it only exists on one side: there is no face on
 * the back and no erector groove on the front.
 */
export const DETAIL_SHAPES: readonly AtlasDetail[] = [
  // ── FRONT: the face ──
  { view: 'front', d: 'M52,21 C54,20 56,20 57,21' },                                   // left brow
  { view: 'front', d: 'M63,21 C64,20 66,20 68,21' },                                   // right brow
  { view: 'front', d: 'M53,25 C54,24 56,24 57,25 C56,26 54,26 53,25 Z' },              // left eye
  { view: 'front', d: 'M63,25 C64,24 66,24 67,25 C66,26 64,26 63,25 Z' },              // right eye
  { view: 'front', d: 'M60,27 L59,32 L61,32' },                                        // nose
  { view: 'front', d: 'M56,36 C58,37 62,37 64,36' },                                   // mouth
  // ── FRONT: the torso ──
  { view: 'front', d: 'M48,55 C52,51 57,50 59,50' },                                   // left clavicle
  { view: 'front', d: 'M72,55 C68,51 63,50 61,50' },                                   // right clavicle
  { view: 'front', d: 'M39,55 C34,60 31,67 30,75' },                                   // left deltoid cap seam
  { view: 'front', d: 'M81,55 C86,60 89,67 90,75' },                                   // right deltoid cap seam
  { view: 'front', d: 'M60,60 L60,90' },                                               // sternum
  { view: 'front', d: 'M60,93 L60,132' },                                              // linea alba
  { view: 'front', d: 'M49,103 L71,103' },                                             // tendinous intersection 1
  { view: 'front', d: 'M48,113 L72,113' },                                             // tendinous intersection 2
  { view: 'front', d: 'M49,123 L71,123' },                                             // tendinous intersection 3
  { view: 'front', d: 'M43,82 L47,86' },                                               // left serratus
  { view: 'front', d: 'M43,88 L48,91' },
  { view: 'front', d: 'M77,82 L73,86' },                                               // right serratus
  { view: 'front', d: 'M77,88 L72,91' },
  // ── FRONT: the fists ──
  { view: 'front', d: 'M31,155 L42,153' },                                             // left knuckles
  { view: 'front', d: 'M32,159 L43,157' },
  { view: 'front', d: 'M89,155 L78,153' },                                             // right knuckles
  { view: 'front', d: 'M88,159 L77,157' },
  // ── FRONT: the legs ──
  { view: 'front', d: 'M47,157 C45,169 44,180 44,190' },                               // left vastus sweep
  { view: 'front', d: 'M73,157 C75,169 76,180 76,190' },                               // right vastus sweep
  { view: 'front', d: 'M41,193 C39,197 39,202 42,204 C46,206 50,205 52,202 C53,198 52,194 50,192 Z' },  // left kneecap
  { view: 'front', d: 'M79,193 C81,197 81,202 78,204 C74,206 70,205 68,202 C67,198 68,194 70,192 Z' },  // right kneecap
  // ── FRONT: tendon and fibre, added for v2 ──
  // The brief wanted a lifelike figure. This is the layer where that is free:
  // stroked, never filled, never tinted, never a hit target — so it cannot
  // disturb the severity colour, the sixteen muscle hues, or a single tap.
  { view: 'front', d: 'M48,62 C53,65 57,67 59,68' },                                   // left pec clavicular seam
  { view: 'front', d: 'M72,62 C67,65 63,67 61,68' },                                   // right pec clavicular seam
  { view: 'front', d: 'M34,104 C36,107 38,109 40,110' },                               // left biceps tendon into the elbow
  { view: 'front', d: 'M86,104 C84,107 82,109 80,110' },                               // right biceps tendon
  { view: 'front', d: 'M31,120 C33,128 35,136 37,144' },                               // left forearm flexor line
  { view: 'front', d: 'M89,120 C87,128 85,136 83,144' },                               // right forearm flexor line
  { view: 'front', d: 'M46,186 C47,189 48,191 49,192' },                               // left quadriceps tendon
  { view: 'front', d: 'M74,186 C73,189 72,191 71,192' },                               // right quadriceps tendon
  { view: 'front', d: 'M38,160 C37,172 37,183 38,191' },                               // left iliotibial line
  { view: 'front', d: 'M82,160 C83,172 83,183 82,191' },                               // right iliotibial line
  { view: 'front', d: 'M44,204 C43,214 44,224 46,233' },                               // left tibia line
  { view: 'front', d: 'M76,204 C77,214 76,224 74,233' },                               // right tibia line

  // ── BACK: the spine ──
  { view: 'back', d: 'M60,45 L60,71' },                                                // trapezius groove
  { view: 'back', d: 'M60,71 L60,137' },                                               // erector spinae groove
  { view: 'back', d: 'M56,116 C56,125 56,131 57,137' },                                // left erector column
  { view: 'back', d: 'M64,116 C64,125 64,131 63,137' },                                // right erector column
  { view: 'back', d: 'M47,66 C51,74 53,81 53,89' },                                    // left scapula
  { view: 'back', d: 'M73,66 C69,74 67,81 67,89' },                                    // right scapula
  { view: 'back', d: 'M42,64 C40,76 41,90 47,102' },                                   // left lat border
  { view: 'back', d: 'M78,64 C80,76 79,90 73,102' },                                   // right lat border
  { view: 'back', d: 'M39,55 C34,60 31,67 30,75' },                                    // left deltoid cap seam
  { view: 'back', d: 'M81,55 C86,60 89,67 90,75' },                                    // right deltoid cap seam
  // ── BACK: the glutes and legs ──
  { view: 'back', d: 'M60,133 L60,155' },                                              // gluteal cleft
  { view: 'back', d: 'M41,152 C46,156 52,157 57,154' },                                // left glute fold
  { view: 'back', d: 'M79,152 C74,156 68,157 63,154' },                                // right glute fold
  { view: 'back', d: 'M47,159 C45,170 45,181 45,191' },                                // left hamstring split
  { view: 'back', d: 'M73,159 C75,170 75,181 75,191' },                                // right hamstring split
  { view: 'back', d: 'M39,194 L52,194' },                                              // left knee crease
  { view: 'back', d: 'M81,194 L68,194' },                                              // right knee crease
  // ── BACK: tendon and fibre, added for v2 ──
  { view: 'back', d: 'M52,63 C56,66 58,68 60,69' },                                    // left rhomboid seam
  { view: 'back', d: 'M68,63 C64,66 62,68 60,69' },                                    // right rhomboid seam
  { view: 'back', d: 'M33,86 C34,94 35,101 36,107' },                                  // left triceps long-head seam
  { view: 'back', d: 'M87,86 C86,94 85,101 84,107' },                                  // right triceps long-head seam
  { view: 'back', d: 'M43,228 C43,233 43,237 43,239' },                                // left achilles
  { view: 'back', d: 'M77,228 C77,233 77,237 77,239' },                                // right achilles
  { view: 'back', d: 'M44,201 C43,212 44,222 46,231' },                                // left gastrocnemius split
  { view: 'back', d: 'M76,201 C77,212 76,222 74,231' },                                // right gastrocnemius split
  { view: 'back', d: 'M41,237 C39,242 38,247 40,251 L49,251 C50,245 50,241 50,237 Z' },  // left heel
  { view: 'back', d: 'M79,237 C81,242 82,247 80,251 L71,251 C70,245 70,241 70,237 Z' },  // right heel
  // ── BACK: the fists ──
  { view: 'back', d: 'M30,156 L44,155' },
  { view: 'back', d: 'M90,156 L76,155' },
]

/**
 * Tendon — the ivory where a muscle becomes a cord (Precision F1, écorché).
 *
 * ── A FIFTH LAYER, AND WHY IT IS NOT DETAIL ──────────────────────────────────
 * `DETAIL_SHAPES` is stroked hairline and never filled; these are FILLED, so
 * every one is a CLOSED shape (`gen-atlas-swift.mjs` refuses an open one — a
 * filled open path closes itself into a wedge). They are drawn over the muscle
 * layer and are never a hit target and never tinted: an Achilles is not a
 * muscle you can train, exactly the argument that kept the kneecap out of
 * `MUSCLE_PATHS`.
 *
 * Each sits where the anatomy puts the cord and where the figure already drew
 * a hint of it: the patellar and quadriceps tendons either side of the
 * kneecap, the Achilles under the calf, the distal biceps into the elbow
 * crease, the triceps aponeurosis over the back of the elbow, the
 * deltopectoral seam, the teres/lat seam under the armpit, the wrist tendons, the hamstring tendons behind the knee,
 * and the linea alba with its three tendinous intersections — the six-pack is
 * tendon, not muscle, which is why it reads ivory here.
 *
 * Bilateral entries are mirrored about x = 60 (x′ = 120 − x) and listed left
 * first, like the muscles.
 */
export const TENDON_SHAPES: readonly AtlasDetail[] = [
  // ── FRONT ──
  { view: 'front', d: 'M44.8,202.8 L47.2,202.8 L46.8,210 L45.2,210 Z' },                                           // left patellar tendon
  { view: 'front', d: 'M75.2,202.8 L72.8,202.8 L73.2,210 L74.8,210 Z' },                                           // right patellar tendon
  { view: 'front', d: 'M43,188 C45,187 47,187 49,188 L48.5,192.5 L43.5,192.5 Z' },                        // left quadriceps tendon
  { view: 'front', d: 'M77,188 C75,187 73,187 71,188 L71.5,192.5 L76.5,192.5 Z' },                        // right quadriceps tendon
  { view: 'front', d: 'M32.5,103.5 L35,103 C35.3,105.5 35.6,108 35.8,111 L33.8,111.2 C33.5,108.5 33,106 32.5,103.5 Z' }, // left distal biceps
  { view: 'front', d: 'M87.5,103.5 L85,103 C84.7,105.5 84.4,108 84.2,111 L86.2,111.2 C86.5,108.5 87,106 87.5,103.5 Z' }, // right distal biceps
  { view: 'front', d: 'M44,56 L45.5,57 C43,61 41,66 40,71 L38.5,71 C39,66 41,60 44,56 Z' },               // left deltopectoral seam
  { view: 'front', d: 'M76,56 L74.5,57 C77,61 79,66 80,71 L81.5,71 C81,66 79,60 76,56 Z' },               // right deltopectoral seam
  { view: 'front', d: 'M36.6,140.6 L38.2,140.2 L40,146.2 L38.4,146.6 Z' },                                               // left wrist flexor tendons
  { view: 'front', d: 'M83.4,140.6 L81.8,140.2 L80,146.2 L81.6,146.6 Z' },                                               // right wrist flexor tendons
  { view: 'front', d: 'M59.4,94 L60.6,94 L60.6,132 L59.4,132 Z' },                                         // linea alba
  { view: 'front', d: 'M49,102.5 L71,102.5 L71,103.5 L49,103.5 Z' },                                       // tendinous intersection 1
  { view: 'front', d: 'M48,112.5 L72,112.5 L72,113.5 L48,113.5 Z' },                                       // tendinous intersection 2
  { view: 'front', d: 'M49,122.5 L71,122.5 L71,123.5 L49,123.5 Z' },                                       // tendinous intersection 3
  // ── BACK ──
  { view: 'back', d: 'M45,226 L48,226 L47.6,239 L45.6,239 Z' },                                            // left Achilles
  { view: 'back', d: 'M75,226 L72,226 L72.4,239 L74.4,239 Z' },                                            // right Achilles
  { view: 'back', d: 'M31.5,99 C33,98.5 34.5,98.5 35.8,99 L35.8,106 C34,106.5 32.5,107 30.5,107.5 Z' },          // left triceps aponeurosis
  { view: 'back', d: 'M88.5,99 C87,98.5 85.5,98.5 84.2,99 L84.2,106 C86,106.5 87.5,107 89.5,107.5 Z' },          // right triceps aponeurosis
  { view: 'back', d: 'M38.5,62 C41,63 44,64.5 47.5,66 L47,67.5 C43.5,66 40.5,65 38,64 Z' },               // left teres/lat seam
  { view: 'back', d: 'M81.5,62 C79,63 76,64.5 72.5,66 L73,67.5 C76.5,66 79.5,65 82,64 Z' },               // right teres/lat seam
  { view: 'back', d: 'M35.6,140.8 L37.2,140.5 L39,146.3 L37.4,146.7 Z' },                                              // left wrist extensor tendons
  { view: 'back', d: 'M84.4,140.8 L82.8,140.5 L81,146.3 L82.6,146.7 Z' },                                              // right wrist extensor tendons
  { view: 'back', d: 'M40,185 L42.5,185 L42,193.5 L40.5,193.5 Z' },                                        // left biceps femoris tendon
  { view: 'back', d: 'M80,185 L77.5,185 L78,193.5 L79.5,193.5 Z' },                                        // right biceps femoris tendon
  { view: 'back', d: 'M48.5,185 L51,185 L50.5,193.5 L49,193.5 Z' },                                        // left semitendinosus tendon
  { view: 'back', d: 'M71.5,185 L69,185 L69.5,193.5 L71,193.5 Z' },                                        // right semitendinosus tendon
]

/**
 * Bone — the landmarks that sit under skin and no muscle (Precision F1).
 *
 * The clavicles, the sternum between the pecs, the kneecaps, the tibial crests
 * down the shins and the iliac crests at the hip on the front; the ulnae, the
 * scapular spines and the posterior iliac crests on the back. Every one is a
 * place a lifter can actually feel bone through skin, which is what earns it a
 * fill on a figure that is otherwise all muscle. Closed, filled, drawn over
 * the muscles, never a hit target, never tinted — the same contract as
 * `TENDON_SHAPES`.
 */
export const BONE_SHAPES: readonly AtlasDetail[] = [
  // ── FRONT ──
  { view: 'front', d: 'M43,53.5 C48,51.5 54,49.8 59,49.6 L59,51.2 C54,51.4 48.5,53 43.5,55 Z' },          // left clavicle
  { view: 'front', d: 'M77,53.5 C72,51.5 66,49.8 61,49.6 L61,51.2 C66,51.4 71.5,53 76.5,55 Z' },          // right clavicle
  { view: 'front', d: 'M59.5,57 L60.5,57 L60.4,88 L60,90 L59.6,88 Z' },                                        // sternum
  { view: 'front', d: 'M46,193.5 C48.4,193.5 49.6,195.6 49.6,198 C49.6,200.8 48,202.6 46,202.6 C44,202.6 42.4,200.8 42.4,198 C42.4,195.6 43.6,193.5 46,193.5 Z' },  // left patella
  { view: 'front', d: 'M74,193.5 C71.6,193.5 70.4,195.6 70.4,198 C70.4,200.8 72,202.6 74,202.6 C76,202.6 77.6,200.8 77.6,198 C77.6,195.6 76.4,193.5 74,193.5 Z' },  // right patella
  { view: 'front', d: 'M44.2,211 C43.4,219 44,226 45.6,233 L46.6,232.6 C45.2,226 44.8,219 45.4,211 Z' },   // left tibial crest
  { view: 'front', d: 'M75.8,211 C76.6,219 76,226 74.4,233 L73.4,232.6 C74.8,226 75.2,219 74.6,211 Z' },   // right tibial crest
  { view: 'front', d: 'M43,129 C44.5,131.5 46.5,133.5 49,134.5 L48.6,135.6 C46,134.6 43.8,132.4 42.2,129.8 Z' }, // left iliac crest (ASIS)
  { view: 'front', d: 'M77,129 C75.5,131.5 73.5,133.5 71,134.5 L71.4,135.6 C74,134.6 76.2,132.4 77.8,129.8 Z' }, // right iliac crest (ASIS)
  // ── BACK ──
  { view: 'back', d: 'M34,111 C34.5,122 35.8,134 37.8,145 L38.8,144.6 C36.9,134 35.7,122 35.3,111 Z' },    // left ulna
  { view: 'back', d: 'M86,111 C85.5,122 84.2,134 82.2,145 L81.2,144.6 C83.1,134 84.3,122 84.7,111 Z' },    // right ulna
  { view: 'back', d: 'M52.5,60.5 C49.5,58.3 45.5,55.8 41.5,53.5 L42,52.2 C46,54.4 50,56.9 53,59.2 Z' },           // left scapular spine
  { view: 'back', d: 'M67.5,60.5 C70.5,58.3 74.5,55.8 78.5,53.5 L78,52.2 C74,54.4 70,56.9 67,59.2 Z' },           // right scapular spine
  { view: 'back', d: 'M42,131 C46,127 51,126 55.5,127 L55.5,128 C51,127.1 46.5,128 42.8,131.6 Z' },        // left posterior iliac crest
  { view: 'back', d: 'M78,131 C74,127 69,126 64.5,127 L64.5,128 C69,127.1 73.5,128 77.2,131.6 Z' },        // right posterior iliac crest
]

/** Every landmark muscle drawn on a view, in the canonical display order. */
export function musclesOnView(view: AtlasView): LandmarkMuscle[] {
  const present = new Set(MUSCLE_PATHS.filter((p) => p.view === view).map((p) => p.muscle))
  return LANDMARK_MUSCLES.filter((m) => present.has(m))
}

/** The view a muscle is drawn on, preferring front when it is on both. */
export function primaryViewOf(muscle: LandmarkMuscle): AtlasView | null {
  if (MUSCLE_PATHS.some((p) => p.muscle === muscle && p.view === 'front')) return 'front'
  if (MUSCLE_PATHS.some((p) => p.muscle === muscle && p.view === 'back')) return 'back'
  return null
}

/**
 * DOMS → landmark. One reported muscle can cover several landmarks: "Arms" is
 * biceps, triceps and forearms, and a sore arm is all three as far as a person
 * tapping a body map is concerned.
 */
export const DOMS_TO_LANDMARK: Record<DomsMuscle, readonly LandmarkMuscle[]> = {
  Chest: ['Chest'],
  Back: ['Lats', 'Upper back', 'Lower back'],
  Arms: ['Biceps', 'Triceps', 'Forearms'],
  // A sore shoulder is a sore shoulder — all three heads light. (This entry
  // was written before the anterior head had geometry; it does now.)
  Shoulders: ['Front delts', 'Side delts', 'Rear delts'],
  Abs: ['Abs/core'],
  Glutes: ['Glutes'],
  Quads: ['Quads'],
  Hamstrings: ['Hamstrings'],
  // The adductors, which until 2026-09-08 were the only landmark the atlas
  // drew that no reported soreness could ever light.
  'Inner thighs': ['Adductors'],
  Calves: ['Calves'],
}

/** landmark → DOMS. The inverse of the fold above, and necessarily lossy. */
export function landmarkToDoms(muscle: LandmarkMuscle): DomsMuscle | null {
  for (const [doms, landmarks] of Object.entries(DOMS_TO_LANDMARK) as Array<[DomsMuscle, readonly LandmarkMuscle[]]>) {
    if (landmarks.includes(muscle)) return doms
  }
  return null
}

/**
 * Spread a DOMS severity map across the landmarks it covers.
 *
 * Severity is 0–3 in the tracker and 0–1 here, because the atlas draws
 * INTENSITY and does not know what the number means. Keeping the tracker's
 * scale would make the atlas an opinion about soreness rather than a renderer.
 */
export function domsToWorked(
  doms: Partial<Record<DomsMuscle, number>> | undefined,
  maxSeverity = 3,
): Partial<Record<LandmarkMuscle, number>> {
  const out: Partial<Record<LandmarkMuscle, number>> = {}
  if (!doms) return out
  for (const [muscle, severity] of Object.entries(doms) as Array<[DomsMuscle, number]>) {
    if (!severity) continue
    const intensity = Math.max(0, Math.min(1, severity / maxSeverity))
    for (const landmark of DOMS_TO_LANDMARK[muscle] ?? []) {
      out[landmark] = Math.max(out[landmark] ?? 0, intensity)
    }
  }
  return out
}

/** A joint marker: a ring on the figure, in viewBox units. */
export interface AtlasJoint {
  /** The name in `JOINTS` (`lib/body/subRegions.ts`). Two entries share it when
   *  the joint is paired, and `side` tells them apart. */
  joint: string
  side: 'left' | 'right' | 'both'
  view: AtlasView
  cx: number
  cy: number
}

/**
 * Where the joints sit on the body.
 *
 * ── A FOURTH LAYER, WITH NO HIT PLANE ────────────────────────────────────────
 * Drawn above the definition layer as open rings, and — like that layer —
 * `pointer-events: none`. A ring over the quad must never eat the quad's own
 * tap, and on a figure rendered 110 px wide there is no room for a second set
 * of targets: the smallest muscle path is already under 3 px across. Joints are
 * chosen in the sheet, where a row is 44 px tall, so the rings only ever have to
 * be legible, never tappable.
 *
 * Anchored to geometry that already exists (kneecaps, the deltoid cap seam, the
 * fist/forearm junction, the erector groove terminus) so they read as landmarks
 * on the body rather than stickers on top of it.
 */
export const JOINT_POINTS: readonly AtlasJoint[] = [
  // Front
  { joint: 'Neck', side: 'both', view: 'front', cx: 60, cy: 44 },
  { joint: 'AC joint', side: 'left', view: 'front', cx: 40, cy: 56 },
  { joint: 'AC joint', side: 'right', view: 'front', cx: 80, cy: 56 },
  { joint: 'Elbow', side: 'left', view: 'front', cx: 33, cy: 108 },
  { joint: 'Elbow', side: 'right', view: 'front', cx: 87, cy: 108 },
  { joint: 'Wrist', side: 'left', view: 'front', cx: 36, cy: 147 },
  { joint: 'Wrist', side: 'right', view: 'front', cx: 84, cy: 147 },
  { joint: 'Hip', side: 'left', view: 'front', cx: 45, cy: 147 },
  { joint: 'Hip', side: 'right', view: 'front', cx: 75, cy: 147 },
  { joint: 'Knee', side: 'left', view: 'front', cx: 46, cy: 198 },
  { joint: 'Knee', side: 'right', view: 'front', cx: 74, cy: 198 },
  { joint: 'Ankle', side: 'left', view: 'front', cx: 43, cy: 236 },
  { joint: 'Ankle', side: 'right', view: 'front', cx: 77, cy: 236 },
  // Back. The lumbar junction only exists here, and it sits at the terminus of
  // the erector groove rather than in the middle of the Lower back path — that
  // path is 12 units wide, and a ring in its centre would read as a target.
  { joint: 'Neck', side: 'both', view: 'back', cx: 60, cy: 44 },
  { joint: 'Lumbar junction', side: 'both', view: 'back', cx: 60, cy: 137 },
  { joint: 'AC joint', side: 'left', view: 'back', cx: 40, cy: 56 },
  { joint: 'AC joint', side: 'right', view: 'back', cx: 80, cy: 56 },
  { joint: 'Elbow', side: 'left', view: 'back', cx: 33, cy: 108 },
  { joint: 'Elbow', side: 'right', view: 'back', cx: 87, cy: 108 },
  { joint: 'Wrist', side: 'left', view: 'back', cx: 36, cy: 147 },
  { joint: 'Wrist', side: 'right', view: 'back', cx: 84, cy: 147 },
  { joint: 'Hip', side: 'left', view: 'back', cx: 45, cy: 147 },
  { joint: 'Hip', side: 'right', view: 'back', cx: 75, cy: 147 },
  { joint: 'Knee', side: 'left', view: 'back', cx: 46, cy: 195 },
  { joint: 'Knee', side: 'right', view: 'back', cx: 74, cy: 195 },
  { joint: 'Ankle', side: 'left', view: 'back', cx: 43, cy: 234 },
  { joint: 'Ankle', side: 'right', view: 'back', cx: 77, cy: 234 },
]

/** The rings to draw on one view. */
export function jointsOnView(view: AtlasView): readonly AtlasJoint[] {
  return JOINT_POINTS.filter((j) => j.view === view)
}

/**
 * Normalise a set-count map into 0–1 intensities.
 *
 * Relative to the session's OWN hardest-worked muscle, not to a weekly target:
 * the atlas beside a finished session answers "where did this go", and grading
 * one session against a week's target would paint every session mostly empty.
 */
export function setsToWorked(
  sets: Partial<Record<LandmarkMuscle, number>>,
): Partial<Record<LandmarkMuscle, number>> {
  const values = Object.values(sets).filter((v): v is number => typeof v === 'number' && v > 0)
  if (!values.length) return {}
  const max = Math.max(...values)
  const out: Partial<Record<LandmarkMuscle, number>> = {}
  for (const [muscle, count] of Object.entries(sets) as Array<[LandmarkMuscle, number]>) {
    if (!count || count <= 0) continue
    // A floor of 0.25: a muscle that got one set out of twelve still HAPPENED,
    // and fading it to invisible would report it as untrained.
    out[muscle] = Math.max(0.25, Math.min(1, count / max))
  }
  return out
}
