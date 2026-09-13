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
 * Three shapes, and they are distinguished by their KEYS, not by their order in
 * the file:
 *
 *   · BASE_SHAPES   — bare string literals, one per line
 *   · MUSCLE_PATHS  — `{ muscle: …, view: …, d: … }`
 *   · DETAIL_SHAPES — `{ view: …, d: … }`, no muscle
 *
 * The detail regex cannot match a muscle path (a muscle path opens with
 * `muscle:`), and the base regex cannot match either object form (both open
 * with `{`). That is what keeps the face out of the silhouette: swept into
 * `base`, the eyes and the linea alba would be FILLED as body mass on the
 * widget, which is a body with a hole in it rather than a body with a face.
 */
export function readAtlas(ts) {
  const base = [...ts.matchAll(/^\s*'(M[^']+)',\s*$/gm)].map((m) => m[1])
  const paths = [...ts.matchAll(/\{\s*muscle:\s*'([^']+)',\s*view:\s*'(front|back)',\s*d:\s*'([^']+)'\s*\}/g)]
    .map((m) => ({ muscle: m[1], view: m[2], d: m[3] }))
  const detail = [...ts.matchAll(/\{\s*view:\s*'(front|back)',\s*d:\s*'([^']+)'\s*\}/g)]
    .map((m) => ({ view: m[1], d: m[2] }))
  if (!paths.length) throw new Error('atlas.ts: no MUSCLE_PATHS found — did the shape change?')
  if (!detail.length) throw new Error('atlas.ts: no DETAIL_SHAPES found — did the shape change?')
  // BASE_SHAPES are the bare string literals; the muscle paths are matched
  // above and must not be counted twice.
  const muscleDs = new Set(paths.map((p) => p.d))
  return { base: base.filter((d) => !muscleDs.has(d)), paths, detail }
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
  const { base, paths, detail } = readAtlas(ts)
  const entry = (p) => [
    '  OnyxAtlasPath(muscle: "' + p.muscle + '", view: .' + p.view + ') { rect, p in',
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

public enum OnyxAtlasView: String, Sendable {
  case front, back
}

/// A definition line — stroked, never filled, never tinted, never a hit target.
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
/// every line into a wedge. \`OnyxAtlasFigure\` strokes it and only strokes it.
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
  public let build: @Sendable (CGRect, inout Path) -> Void

  public var id: String { "\\(muscle)-\\(view.rawValue)-\\(String(describing: build))" }

  public init(muscle: String, view: OnyxAtlasView, _ build: @escaping @Sendable (CGRect, inout Path) -> Void) {
    self.muscle = muscle
    self.view = view
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
