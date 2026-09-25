#!/usr/bin/env node
/**
 * Generate `OnyxAtlas.swift` from `scripts/src/atlas.ts`.
 *
 * ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
 * SwiftUI has no SVG parser. `Path(svg:)` is not a thing, and shipping a
 * rasterised body would give up the one property the atlas has: a muscle can be
 * filled independently of every other muscle. So the same path data is emitted
 * as explicit `Path` builders — `move(to:)`, `addLine(to:)`,
 * `addCurve(to:control1:control2:)`, `closeSubpath()`.
 *
 * ── THE RULE THIS ENFORCES ───────────────────────────────────────────────────
 * There is ONE anatomy. A body drawn twice by hand drifts the first time either
 * copy is nudged, and nobody notices until the app and the widget disagree
 * about where the glutes are. `npm run check:atlas` re-runs this generator and
 * fails if the checked-in Swift differs, so the two cannot separate silently.
 *
 * ── WHAT IT PARSES ───────────────────────────────────────────────────────────
 * M, L, C and Z, absolute, comma-or-space separated — which is exactly what the
 * atlas contains, asserted by a test. Anything else throws rather than emitting
 * a path that is subtly wrong: a body missing one curve segment still LOOKS
 * like a body, which is the worst possible failure mode here.
 *
 * Usage: node scripts/gen-atlas-swift.mjs [--check]
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SOURCE = join(ROOT, 'scripts/src/atlas.ts')

/**
 * Every Swift copy of the atlas. Byte-identical, all of them — the generator
 * emits one string and writes it to each.
 *
 * ONE copy: `OnyxUI` is a package the app AND the widget extension both
 * import, so the atlas is public API there and neither host carries its own.
 * A second hand-drawn body is exactly what this generator exists to prevent,
 * so a new consumer imports OnyxUI rather than joining this list.
 */
export const TARGETS = [
  join(ROOT, 'native/Packages/OnyxUI/Sources/OnyxUI/Atlas/OnyxAtlas.swift'),
]

/**
 * Pull the literal arrays out of the TypeScript without importing it.
 *
 * Five arrays, and each regex runs over ITS OWN array only:
 *
 *   · BASE_SHAPES   — bare string literals, one per line
 *   · MUSCLE_PATHS  — `{ muscle: …, view: …, d: …, fibre: [dx, dy] }`
 *   · DETAIL_SHAPES — `{ view: …, d: … }`, stroked
 *   · TENDON_SHAPES — `{ view: …, d: … }`, filled, closed (Precision F1)
 *   · BONE_SHAPES   — `{ view: …, d: … }`, filled, closed (Precision F1)
 *
 * ── WHY BY ARRAY AND NOT BY KEY (Precision F1) ──────────────────────────────
 * This used to tell the arrays apart by their keys over the whole file, which
 * held while `{ view, d }` meant only DETAIL. Three arrays share that shape
 * now, and a whole-file match would stroke every tendon as a hairline and fill
 * none — or, worse, fill the linea alba's open DETAIL line as a wedge. Scoping
 * is also what keeps the face out of the silhouette: swept into `base`, the
 * eyes would be FILLED as body mass.
 *
 * Every array must parse ENTIRELY: an entry the regex skips (a typo, a missing
 * `fibre`) throws rather than emitting a body with a hole in it.
 */
export function readAtlas(ts) {
  const baseSrc = section(ts, 'BASE_SHAPES')
  const base = [...baseSrc.matchAll(/^\s*'(M[^']+)',\s*$/gm)].map((m) => m[1])
  if (base.length !== (baseSrc.match(/^\s*'/gm) ?? []).length) {
    throw new Error('atlas.ts: a BASE_SHAPES entry did not parse')
  }
  const musclesSrc = section(ts, 'MUSCLE_PATHS')
  const paths = [...musclesSrc.matchAll(
    /\{\s*muscle:\s*'([^']+)',\s*view:\s*'(front|back)',\s*d:\s*'([^']+)',\s*fibre:\s*\[\s*(-?\d*\.?\d+)\s*,\s*(-?\d*\.?\d+)\s*\]\s*\}/g,
  )].map((m) => ({ muscle: m[1], view: m[2], d: m[3], fibre: [Number(m[4]), Number(m[5])] }))
  if (!paths.length) throw new Error('atlas.ts: no MUSCLE_PATHS found — did the shape change?')
  const declared = (musclesSrc.match(/\{\s*muscle:/g) ?? []).length
  if (paths.length !== declared) {
    throw new Error(`atlas.ts: ${declared - paths.length} MUSCLE_PATHS entr(ies) did not parse — every path needs a fibre: [dx, dy]`)
  }
  for (const p of paths) {
    if (p.fibre[0] === 0 && p.fibre[1] === 0) throw new Error(`atlas.ts: ${p.muscle} (${p.view}) has a zero fibre`)
  }
  const tendons = shapes(ts, 'TENDON_SHAPES', { closed: true })
  const bones = shapes(ts, 'BONE_SHAPES', { closed: true })
  return {
    base,
    paths: withSides(paths, readMidline(ts)),
    detail: shapes(ts, 'DETAIL_SHAPES', { closed: false }),
    tendons,
    bones,
  }
}

/**
 * The source of one exported array literal: from the `[` after
 * `export const NAME … =` to the `]` that closes it at column 0.
 */
export function section(ts, name) {
  const start = ts.indexOf(`export const ${name}`)
  if (start < 0) throw new Error(`atlas.ts: no ${name} found — did the shape change?`)
  const open = ts.indexOf('[', ts.indexOf('=', start))
  const close = ts.indexOf('\n]', open)
  if (open < 0 || close < 0) throw new Error(`atlas.ts: ${name} is not an array literal`)
  return ts.slice(open, close)
}

/**
 * A `{ view, d }` array. `closed` shapes are FILLED by the renderer, so each
 * must end in `Z`: SwiftUI closes an open path when it fills one, and an
 * unclosed tendon would come out as a wedge across the muscle under it.
 */
export function shapes(ts, name, { closed }) {
  const src = section(ts, name)
  const out = [...src.matchAll(/\{\s*view:\s*'(front|back)',\s*d:\s*'([^']+)'\s*\}/g)]
    .map((m) => ({ view: m[1], d: m[2] }))
  if (!out.length) throw new Error(`atlas.ts: no ${name} found — did the shape change?`)
  const declared = (src.match(/\{\s*view:/g) ?? []).length
  if (out.length !== declared) throw new Error(`atlas.ts: ${declared - out.length} ${name} entr(ies) did not parse`)
  if (closed) {
    for (const s of out) {
      if (!/Z\s*$/.test(s.d)) throw new Error(`atlas.ts: ${name} entry "${s.d}" is not closed — a filled shape must end in Z`)
    }
  }
  return out
}

/**
 * `ATLAS_MIDLINE_BAND`, read out of the source rather than restated here.
 *
 * The rule that turns a coordinate into a side is anatomy, so it belongs beside
 * the anatomy; this generator is the only thing that applies it, so it is the
 * only thing that reads it. Two copies of the band would drift the first time
 * either was nudged — the same argument that made this file exist at all.
 */
export function readMidline(ts) {
  const m = ts.match(/ATLAS_MIDLINE_BAND\s*=\s*\{\s*left:\s*(-?\d*\.?\d+)\s*,\s*right:\s*(-?\d*\.?\d+)\s*\}/)
  if (!m) throw new Error('atlas.ts: no ATLAS_MIDLINE_BAND found — did the shape change?')
  return { left: Number(m[1]), right: Number(m[2]) }
}

/**
 * The mean x of every point a path names — on-curve and control alike.
 *
 * Not the area centroid, and deliberately: these are 4–12 segment bellies drawn
 * symmetrically about their own long axis, so the two agree to well inside the
 * ±2 band, and a polygon-area centroid would need the curves flattened first.
 * A control point pulls the mean the same way it pulls the shape.
 */
export function centroidX(d) {
  const xs = []
  for (const { args } of tokenize(d)) {
    for (let i = 0; i < args.length; i += 2) xs.push(args[i])
  }
  if (!xs.length) throw new Error(`no points in "${d}"`)
  return xs.reduce((a, b) => a + b, 0) / xs.length
}

/**
 * Each path's side, and the one rule that keeps an axial muscle axial.
 *
 * Pass one is the band: centroid left of the band is `left`, right of it is
 * `right`, inside it is `both`.
 *
 * Pass two is the reason `Abs/core` does not come out lateralised. The rectus
 * straddles the spine and lands in the band, but the two oblique flanks sit at
 * x ≈ 45 and x ≈ 75 and would each take a side of their own — so tapping the
 * middle of a midsection would offer "both" and tapping an inch to the left
 * would offer "left", for one muscle the athlete rates as one thing. A muscle
 * is lateral only when a view draws it as EXACTLY one left and one right; any
 * other shape (one path, three paths, two on the same side) is axial and every
 * path of it answers `both`.
 *
 * Derived, not listed. A hand-written set of axial muscles would be a fourth
 * copy of the anatomy, and `npm run check:atlas` would not be able to tell when
 * it went stale.
 */
export function withSides(paths, band) {
  const raw = paths.map((p) => {
    const cx = centroidX(p.d)
    return { ...p, side: cx < band.left ? 'left' : cx > band.right ? 'right' : 'both' }
  })
  const groups = new Map()
  for (const p of raw) {
    const key = `${p.muscle}\u001F${p.view}`
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(p)
  }
  for (const group of groups.values()) {
    const lefts = group.filter((p) => p.side === 'left').length
    const rights = group.filter((p) => p.side === 'right').length
    if (lefts === 1 && rights === 1 && group.length === 2) continue
    for (const p of group) p.side = 'both'
  }
  return raw
}

const NUM = /-?\d*\.?\d+/g

/** `d` → a list of {cmd, args}. Absolute M/L/C/Z only. */
export function tokenize(d) {
  const out = []
  const re = /([MLCZmlcz])([^MLCZmlcz]*)/g
  let m
  while ((m = re.exec(d)) !== null) {
    const cmd = m[1]
    if (cmd !== cmd.toUpperCase()) {
      throw new Error(`relative command '${cmd}' in "${d}" — the atlas is absolute-only`)
    }
    const args = (m[2].match(NUM) ?? []).map(Number)
    out.push({ cmd, args })
  }
  return out
}

/** Swift body for one path. */
export function swiftPath(d) {
  const lines = []
  for (const { cmd, args } of tokenize(d)) {
    if (cmd === 'M') {
      if (args.length !== 2) throw new Error(`M takes 2 numbers, got ${args.length} in "${d}"`)
      lines.push(`  p.move(to: pt(${args[0]}, ${args[1]}, in: rect))`)
    } else if (cmd === 'L') {
      for (let i = 0; i < args.length; i += 2) {
        lines.push(`  p.addLine(to: pt(${args[i]}, ${args[i + 1]}, in: rect))`)
      }
    } else if (cmd === 'C') {
      if (args.length % 6 !== 0) throw new Error(`C takes multiples of 6, got ${args.length} in "${d}"`)
      for (let i = 0; i < args.length; i += 6) {
        lines.push(`  p.addCurve(to: pt(${args[i + 4]}, ${args[i + 5]}, in: rect), ` +
          `control1: pt(${args[i]}, ${args[i + 1]}, in: rect), ` +
          `control2: pt(${args[i + 2]}, ${args[i + 3]}, in: rect))`)
      }
    } else if (cmd === 'Z') {
      lines.push('  p.closeSubpath()')
    } else {
      throw new Error(`unsupported command '${cmd}' in "${d}"`)
    }
  }
  return lines.join('\n')
}

export function generate(ts) {
  const { base, paths, detail, tendons, bones } = readAtlas(ts)
  const entry = (p) => [
    '  OnyxAtlasPath(muscle: "' + p.muscle + '", view: .' + p.view + ', side: .' + p.side +
      ', fibre: CGVector(dx: ' + p.fibre[0] + ', dy: ' + p.fibre[1] + ')) { rect, p in',
    swiftPath(p.d).split('\n').map((l) => '  ' + l).join('\n'),
    '  },',
  ].join('\n')
  const detailEntry = (p) => [
    '  OnyxAtlasDetail(view: .' + p.view + ') { rect, p in',
    swiftPath(p.d).split('\n').map((l) => '  ' + l).join('\n'),
    '  },',
  ].join('\n')

  return `// GENERATED by scripts/gen-atlas-swift.mjs — DO NOT EDIT.
//
// The anatomy lives in scripts/src/atlas.ts and is emitted here because
// SwiftUI cannot parse an SVG path. \`npm run check:atlas\` re-runs the
// generator and fails when this file differs, so the app and the widget can
// never disagree about where a muscle is.
//
// Coordinates are on the atlas's 120 x 260 viewBox and are scaled into
// whatever rect the shape is given, preserving aspect ratio and centring.
//
// Public: this lives in OnyxUI and is drawn by the app's \`AtlasFigure\` and
// the tiles' \`OnyxAtlasFigure\` alike. Geometry only — how a body is TINTED
// is each figure's own decision.
import SwiftUI
import OnyxCore

public enum OnyxAtlasView: String, Sendable {
  case front, back
}

/// A shape outside the muscle layer — never tinted, never a hit target.
///
/// Three lists carry it: \`detail\` (definition lines, STROKED only) and, for
/// the écorché material (Precision F1), \`tendons\` and \`bones\` (closed,
/// FILLED — the generator refuses an open one).
///
/// Sendable, and so are the closures. These are pure geometry: they capture
/// nothing and mutate nothing outside the Path handed to them. The native app
/// builds with SWIFT_STRICT_CONCURRENCY = complete, where a global let of a
/// non-Sendable function type is an error rather than a warning — and saying
/// Sendable here is the truthful annotation, where nonisolated(unsafe) would
/// be a suppression of a question that has a real answer.
///
/// Several of these are OPEN paths (a brow, the linea alba). SwiftUI closes an
/// open path implicitly when it fills one, so filling this layer would turn
/// every line into a wedge. The painters stroke \`detail\` and only stroke it.
public struct OnyxAtlasDetail: Sendable {
  public let view: OnyxAtlasView
  public let build: @Sendable (CGRect, inout Path) -> Void

  public init(view: OnyxAtlasView, _ build: @escaping @Sendable (CGRect, inout Path) -> Void) {
    self.view = view
    self.build = build
  }
}

public struct OnyxAtlasPath: Identifiable, Sendable {
  public let muscle: String
  public let view: OnyxAtlasView
  /// Which side of the body this ONE path is — derived from its centroid
  /// against \`ATLAS_MIDLINE_BAND\`, never hand-written.
  ///
  /// A bilateral muscle is two entries per view and always has been; this is
  /// the field that finally says so, and it is what lets a tap answer "the
  /// right glute" rather than "the glutes". \`both\` is an AXIAL path — the
  /// trapezius diamond, the erector column, a midsection — and also every path
  /// of a muscle a view does not draw as a mirrored pair, so a muscle is never
  /// half lateralised.
  public let side: BodySide
  /// The fibre AXIS in viewBox units (x right, y down) — \`fibre\` in
  /// atlas.ts. The écorché material shades along it; the sign carries
  /// nothing, the painter lights whichever end faces its light. Defaulted so
  /// a path built by hand (a test's) needs none.
  public let fibre: CGVector
  public let build: @Sendable (CGRect, inout Path) -> Void

  public var id: String { "\\(muscle)-\\(view.rawValue)-\\(String(describing: build))" }

  public init(muscle: String, view: OnyxAtlasView, side: BodySide = .both, fibre: CGVector = CGVector(dx: 0, dy: 1), _ build: @escaping @Sendable (CGRect, inout Path) -> Void) {
    self.muscle = muscle
    self.view = view
    self.side = side
    self.fibre = fibre
    self.build = build
  }
}

public enum OnyxAtlas {
  public static let viewBox = CGSize(width: 120, height: 260)

  /// The silhouette — head, hair, neck, torso, arms, fists, legs, feet.
  /// Anatomy, never data, never tinted.
  public static let base: [@Sendable (CGRect, inout Path) -> Void] = [
${base.map((d) => '  { rect, p in\n' + swiftPath(d).split('\n').map((l) => '  ' + l).join('\n') + '\n  },').join('\n')}
  ]

  public static let muscles: [OnyxAtlasPath] = [
${paths.map(entry).join('\n')}
  ]

  /// Definition: the face, the six-pack seams, the erector groove, the kneecaps.
  public static let detail: [OnyxAtlasDetail] = [
${detail.map(detailEntry).join('\n')}
  ]

  /// Tendon — the ivory cords of the écorché (Precision F1). Closed, filled.
  public static let tendons: [OnyxAtlasDetail] = [
${tendons.map(detailEntry).join('\n')}
  ]

  /// Bone — the subcutaneous landmarks of the écorché (Precision F1). Closed, filled.
  public static let bones: [OnyxAtlasDetail] = [
${bones.map(detailEntry).join('\n')}
  ]

  /// One viewBox point, scaled into \`rect\` with the aspect ratio preserved.
  ///
  /// Fitting WITHOUT preserving it is what turns a body into a puddle in a wide
  /// widget cell — and every muscle would still be in the right place relative
  /// to the others, so it would look deliberate.
  public static func pt(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
    let dx = rect.minX + (rect.width - viewBox.width * scale) / 2
    let dy = rect.minY + (rect.height - viewBox.height * scale) / 2
    return CGPoint(x: dx + x * scale, y: dy + y * scale)
  }
}

private func pt(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
  OnyxAtlas.pt(x, y, in: rect)
}
`
}

// ── CLI ──
if (process.argv[1] && process.argv[1].endsWith('gen-atlas-swift.mjs')) {
  const ts = readFileSync(SOURCE, 'utf8')
  const out = generate(ts)
  if (process.argv.includes('--check')) {
    for (const target of TARGETS) {
      if (readFileSync(target, 'utf8') !== out) {
        console.error(`${target} is stale — re-run this generator`)
        process.exit(1)
      }
    }
    console.log(`✔ OnyxAtlas.swift matches atlas.ts`)
  } else {
    for (const target of TARGETS) {
      writeFileSync(target, out)
      console.log(`✔ wrote ${target}`)
    }
  }
}
