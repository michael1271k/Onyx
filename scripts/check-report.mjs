#!/usr/bin/env node
/**
 * The report parsers' self-check.
 *
 * ── WHY THIS FILE EXISTS AT ALL ────────────────────────────────────────────
 * `fmtV2.ts`'s header claimed "every branch is exercised by
 * `src/tests/fmt-v2.test.ts`" — a file that went with the web app. So the 945
 * lines of parsing rules that feed the in-app report renderer had no runnable
 * check of any kind, and W1 changed one of them (the title rule) with nothing
 * to catch a regression.
 *
 * ── AND WHY IT IS `assert`, NOT A TEST FRAMEWORK ───────────────────────────
 * Cross-wave law 10: no new dependency for what a few lines do. There is no
 * test runner in `devDependencies` and adding one to assert eight facts would
 * be the wrong trade. Node 24 strips TypeScript types on import natively, so a
 * plain `.mjs` can import the real parser and assert against it — no build
 * step, no config, no new package.
 *
 *   node scripts/check-report.mjs        # or: npm run check:report
 */
import assert from 'node:assert/strict'
import { parseFmtV2 } from './src/report/fmtV2.ts'

let checked = 0
const check = (name, fn) => { fn(); checked++; process.stdout.write(`  ✔ ${name}\n`) }

const BOX_TOP = '╔══════════════════════════════════╗'
const BANNER = '║ W01 · 2026-07-19 → 07-25 · CUT / RE-ENTRY · SENTINEL-7 · FMT v2 ║'
const BOX_BOTTOM = '╚══════════════════════════════════╝'
const BODY = '▓ PART 1 — WEIGHT & METABOLIC VERIFICATION\nWeight: 82.1 kg\n'

const report = (...preamble) => {
  const r = parseFmtV2([...preamble, BOX_TOP, BANNER, BOX_BOTTOM, BODY].join('\n'))
  assert.ok(r, 'parseFmtV2 returned null for a report it should recognise')
  return r
}

// ── The title is a POSITION, not a brand ──────────────────────────────────
// W1 removed the predecessor's name from the repository, so the title can no
// longer be found by matching a brand. It is the first non-empty line ABOVE
// the box. These four cases are the ones that rule has to get right.

check('the masthead above the box is the title', () => {
  assert.equal(report('# ⬢ ONYX OS · WEEKLY TELEMETRY & PERFORMANCE AUDIT').header.title,
    '# ⬢ ONYX OS · WEEKLY TELEMETRY & PERFORMANCE AUDIT')
})

check('a masthead under the RETIRED brand still yields a title', () => {
  // The seven stored reports opened this way. Parsing them must not depend on
  // a word this repository no longer contains.
  assert.equal(report('# ⬢ VITAL OS · WEEKLY TELEMETRY & PERFORMANCE AUDIT').header.title,
    '# ⬢ VITAL OS · WEEKLY TELEMETRY & PERFORMANCE AUDIT')
})

check('no masthead yields null, NOT the framed banner line', () => {
  // The regression this file was written for. `BOX` matches only lines made
  // entirely of frame characters, so the banner — which has letters — is not a
  // box line, and a plain "first non-box line" search returns it with its
  // pipes attached. Ten of the seventeen stored reports have no masthead.
  const h = report().header
  assert.equal(h.title, null, `expected null, got ${JSON.stringify(h.title)}`)
})

check('leading blank lines are skipped', () => {
  assert.equal(report('', '   ', '# ⬢ ONYX OS · AUDIT').header.title, '# ⬢ ONYX OS · AUDIT')
})

// ── And the fields the banner still carries, so the slice did not cost them ─

check('the banner still yields week, range, phase and version', () => {
  const h = report('# ⬢ ONYX OS · AUDIT').header
  assert.equal(h.weekLabel, 'W01')
  assert.equal(h.rangeLabel, '2026-07-19 → 07-25')
  assert.equal(h.version, 'v2')
  assert.ok(h.phase, 'phase should be read off the banner')
})

check('a report with no box at all still finds its title', () => {
  const r = parseFmtV2(['Plain heading', '', BODY].join('\n'))
  assert.ok(r, 'parseFmtV2 returned null')
  const h = r.header
  assert.equal(h.title, 'Plain heading')
})

process.stdout.write(`\nreport parsers: ${checked} checks passed\n`)
