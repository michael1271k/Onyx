/**
 * FMT v2 — a reader for the pasted weekly audit, not a contract for it.
 *
 * WHAT THIS IS NOT. Onyx defines no report format; the whole point of the paste
 * loop is that the format lives outside the app and can change without a
 * release. So nothing here validates, rejects, or requires. `parseFmtV2` returns
 * what it recognised and says nothing about the rest, and every consumer is
 * expected to render unrecognised text verbatim. A parser that can fail is a
 * parser that can stop you saving your own notes.
 *
 * WHAT IT IS FOR. FMT v2 carries three things that are genuinely data and read
 * badly as text on a phone: a TDEE anchor ladder (five candidate numbers, one of
 * them adopted), a body-composition table (ten columns across five days), and a
 * left/right asymmetry block. Those get charts. Everything else stays prose.
 *
 * The layout it reads, from a real report:
 *
 *   ⬢ ONYX OS · WEEKLY TELEMETRY & PERFORMANCE AUDIT
 *   ╔══════════════════════════════════════════════╗
 *   ║ W01 · 2026-07-19 → 07-25 · CUT / RE-ENTRY · SENTINEL-7 · FMT v2 ║
 *   ▓ PART 1 — WEIGHT & METABOLIC VERIFICATION
 *   🧮 THE MATH & TDEE CHECK
 *   ANCHOR A · DIARY (blueprint primary)     2,400   ← ADOPTED
 *   📉 WEIGHT & BODY COMP TRAJECTORY
 *   Date | Wt | BF% | Fat kg | Musc% | Musc kg | FFM kg | H₂O% | Visc | BMR
 *
 * Note the pipe tables carry NO markdown separator row, which is why remark-gfm
 * renders them as one long paragraph and why they are parsed here instead.
 *
 * Pure: no React, no network, no clock. The header rules are exercised by
 * `scripts/check-report.mjs` (`npm run check:report`), which imports THIS file
 */

export interface FmtV2Header {
  /** "W01", when the banner carries one. */
  weekLabel: string | null
  /** "2026-07-19 → 07-25" as written. */
  rangeLabel: string | null
  /** "CUT / RE-ENTRY". */
  phase: string | null
  /** The literal version token, e.g. "v2". */
  version: string
  /** The banner line above the box, if present. */
  title: string | null
}

/** One candidate daily-energy figure from the TDEE ladder. */
export interface TdeeAnchor {
  /** "A", "B", … or whatever labels the line. */
  key: string
  label: string
  value: number
  /** The one marked `← ADOPTED`. */
  adopted: boolean
}

export interface ParsedTable {
  columns: string[]
  rows: string[][]
}

export interface AsymmetryRow {
  exercise: string
  left: number | null
  right: number | null
  /** (right − left) / left, as a percentage. Null when either side is missing. */
  gapPct: number | null
}

/**
 * One movement the report asked for by name and load.
 *
 * `loadKg` is what to put on the bar; the rep window is kept SEPARATELY from it
 * because a prescription is frequently one without the other ("Leg Press → hold
 * 120 kg, chase reps"), and a chip that needs both to render would show nothing
 * for exactly the weeks the instruction mattered most.
 */
export interface TargetExercise {
  /** As written in the report, then run through the catalog's alias table. */
  name: string
  loadKg: number | null
  repsLow: number | null
  repsHigh: number | null
}

/** What the last report asked for, in the shapes the app can act on. */
export interface ReportTargets {
  exercises: TargetExercise[]
  water: { minL: number; maxL: number } | null
  steps: number | null
  macros: { kcal: number | null; proteinG: number | null; carbsG: number | null; fatG: number | null } | null
  /** Instruction sentences from the same sections, for the dashboard. */
  notes: string[]
}

/** Sections the renderer draws instead of printing. Everything else is `null`. */
export type FmtV2SectionKind = 'tdee' | 'bodyComp' | 'asymmetry' | 'targets'

export interface FmtV2Section {
  /** Leading emoji, when the heading had one. */
  emoji: string | null
  title: string
  /** Body lines with the heading removed, trailing blanks trimmed. */
  lines: string[]
  /** First pipe table in the section, if any. */
  table: ParsedTable | null
  /**
   * Set only when the section's DATA was successfully extracted — a section
   * titled "ASYMMETRY WATCH" whose rows didn't parse stays `null` and renders as
   * text, rather than showing an empty chart where the numbers used to be.
   */
  kind: FmtV2SectionKind | null
}

export interface FmtV2Part {
  title: string
  sections: FmtV2Section[]
}

export interface FmtV2Report {
  header: FmtV2Header
  parts: FmtV2Part[]
  /** Lines before the first `▓ PART` heading (the banner box and preamble). */
  preamble: string[]
  tdee: TdeeAnchor[]
  bodyComp: ParsedTable | null
  asymmetry: AsymmetryRow[]
  /** Null when the report prescribed nothing this reader recognised. */
  targets: ReportTargets | null
}

/** Box-drawing and rule characters that carry no content of their own. */
const BOX = /^[\s╔╗╚╝║═╠╣╦╩╬┌┐└┘│─├┤┬┴┼▁▔_=~-]+$/

/**
 * Parts and sections are written as MARKDOWN HEADINGS, not as bare lines:
 * `# ▓ PART 1 — …` and `## 🟢 QUICK VERDICT`. Anchoring on `▓`/emoji alone made
 * every real report parse as one 246-line preamble, so `parts` came back empty
 * and the TDEE, body-comp and asymmetry charts never drew a single pixel — the
 * reader silently degraded to plain text on the exact document it was written
 * for. The `#{0,6}` prefix is what makes it fire.
 */
const PART = /^\s*#{0,6}\s*▓+\s*(.+?)\s*$/
const ATX = /^\s*#{1,6}\s+(\S.*?)\s*$/
/**
 * A heading's leading glyph. Extended_Pictographic covers 🟢🧮📉⏱🎯, but NOT the
 * geometric marks the same report uses for its other sections (⚑ DB LADDER,
 * ◆ WEEK 2 PROJECTION), so those are named explicitly.
 */
const EMOJI_LEAD = /^(\p{Extended_Pictographic}️?|[◆◇■□▶◀▸●○★☆⚑⚐✦✧⬢⬡])\s+(\S.*)$/u

/** A heading is SHOUTED — that is what separates it from a sentence. */
function isShouted(text: string): boolean {
  const letters = text.replace(/[^A-Za-z]/g, '')
  if (letters.length < 3) return false
  const upper = text.replace(/[^A-Z]/g, '').length
  return upper / letters.length >= 0.7
}

/**
 * A number, or null.
 *
 * The explicit digit test is load-bearing: `Number('')` is 0, not NaN, so a
 * stripped-out prose cell ("felt heavy" → "") would otherwise arrive as a
 * perfectly plausible zero and get plotted.
 */
const numOf = (raw: string): number | null => {
  const cleaned = raw.replace(/[,\s]/g, '')
  if (!/\d/.test(cleaned)) return null
  const n = Number(cleaned)
  return Number.isFinite(n) ? n : null
}

/** Does this text look like an FMT v2 audit? Cheap enough to call during render. */
export function isFmtV2(md: string | null | undefined): boolean {
  return !!md && /\bFMT\s*v?2\b/i.test(md)
}

/** `a | b | c` → `['a','b','c']`, or null when the line is not a pipe row. */
function pipeCells(line: string): string[] | null {
  if ((line.match(/\|/g)?.length ?? 0) < 2) return null
  const cells = line.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split('|').map((c) => c.trim())
  return cells.length >= 3 ? cells : null
}

/** The first pipe table in a run of lines. Separator rows are dropped. */
export function parseTable(lines: string[]): ParsedTable | null {
  let columns: string[] | null = null
  const rows: string[][] = []
  for (const line of lines) {
    const cells = pipeCells(line)
    if (!cells) {
      // A blank line ends the table; prose between rows does not.
      if (columns && !line.trim()) break
      continue
    }
    if (cells.every((c) => /^:?-{2,}:?$/.test(c))) continue   // markdown separator
    if (!columns) { columns = cells; continue }
    rows.push(cells)
  }
  return columns && rows.length ? { columns, rows } : null
}

/**
 * The TDEE ladder.
 *
 * `ANCHOR A · DIARY (blueprint primary)     2,400   ← ADOPTED`
 *
 * The label and the number are separated by run-on whitespace in the original
 * (it is column-aligned ASCII), so the number is taken as the LAST numeric token
 * on the line and everything before it is the label. That survives a label
 * containing its own digits ("ANCHOR C · TDEE ×1.15").
 *
 * A TRAILING PARENTHETICAL IS DROPPED FIRST, and it has to be — real anchors
 * annotate their own working:
 *
 *   ANCHOR B · HISTORICAL CUT @1,925   2,430   (−0.46 kg/wk @ 65.6 kg)
 *   ANCHOR C · BOTTOM-UP THIS WEEK     2,290   (range 2,163–2,420)
 *
 * and "last numeric token" reads those as 65.6 and 2,420 — a daily-energy ladder
 * with a 65-kcal rung in it, drawn to scale, next to a bar it invented.
 */
export function parseTdeeAnchors(lines: string[]): TdeeAnchor[] {
  const out: TdeeAnchor[] = []
  for (const line of lines) {
    const m = /^\s*ANCHOR\s+(\S+)\s*(?:·|-|—)?\s*(.*)$/i.exec(line)
    if (!m) continue
    const rest = m[2]
    const adopted = /←\s*ADOPTED|\bADOPTED\b/i.test(rest)
    const body = rest
      .replace(/←\s*ADOPTED/i, '').replace(/\bADOPTED\b/i, '')
      .replace(/\s*[([][^)\]]*[)\]]\s*$/, '')
    const nums = [...body.matchAll(/(\d[\d,]*(?:\.\d+)?)/g)]
    if (!nums.length) continue
    const last = nums[nums.length - 1]
    const value = numOf(last[1])
    if (value == null) continue
    out.push({
      key: m[1].replace(/[·:.]$/, ''),
      label: body.slice(0, last.index).replace(/[\s·—-]+$/, '').trim(),
      value,
      adopted,
    })
  }
  return out
}

/**
 * The asymmetry block, from either shape it plausibly takes.
 *
 * A pipe table with left/right columns is preferred; failing that, inline
 * `L 20 … R 18` on one line per movement. The exact layout was not available
 * when this was written, so both are attempted and neither is required — an
 * unrecognised block simply renders as text.
 */
export function parseAsymmetry(lines: string[]): AsymmetryRow[] {
  const gap = (l: number | null, r: number | null) =>
    l != null && r != null && l !== 0 ? Math.round(((r - l) / l) * 1000) / 10 : null

  const table = parseTable(lines)
  if (table) {
    const li = table.columns.findIndex((c) => /^(l|left)\b/i.test(c))
    const ri = table.columns.findIndex((c) => /^(r|right)\b/i.test(c))
    if (li >= 0 && ri >= 0) {
      return table.rows.map((cells) => {
        const l = numOf(cells[li] ?? '')
        const r = numOf(cells[ri] ?? '')
        return { exercise: cells[0] ?? '', left: l, right: r, gapPct: gap(l, r) }
      }).filter((row) => row.exercise && (row.left != null || row.right != null))
    }
  }

  const out: AsymmetryRow[] = []
  for (const line of lines) {
    const m = /^(.*?)\bL\s*[:=]?\s*(\d[\d.]*)\b.*?\bR\s*[:=]?\s*(\d[\d.]*)\b/i.exec(line)
    if (!m) continue
    const name = m[1].replace(/[\s·|—-]+$/, '').trim()
    if (!name) continue
    const l = numOf(m[2])
    const r = numOf(m[3])
    out.push({ exercise: name, left: l, right: r, gapPct: gap(l, r) })
  }
  return out
}

/**
 * A line of the report reduced to the sentence a human would read out, or null
 * if it is decoration, a table row, or a heading the parser did not claim.
 *
 * Lives here rather than in `directive.ts` because the targets reader needs the
 * identical judgement, and two copies of "what counts as an instruction" would
 * drift the moment either was tuned.
 */
export function cleanInstruction(raw: string, maxLen = 140): string | null {
  let line = raw.trim()
  if (!line || DECORATION.test(line)) return null
  if (line.includes('|')) return null                 // a table row is data
  line = line.replace(BULLET, '')
  if (/^#{1,6}\s/.test(line)) return null             // a nested heading
  line = line.replace(/\*\*/g, '').replace(/`/g, '').trim()
  if (line.length < 12) return null
  // Shouted lines are headings the section split missed — a real instruction is
  // written as a sentence.
  if (line === line.toUpperCase() && /[A-Z]{4}/.test(line)) return null
  return line.length > maxLen ? `${line.slice(0, maxLen - 1).trimEnd()}…` : line
}

/** Leading bullet glyphs the reports use, stripped before display. */
const BULLET = /^\s*(?:[-*•▸▪◆◇→⚑>]|\d+[.)])\s+/
/** Box-drawing, rules, and other pure decoration — never an instruction. */
const DECORATION = /^[\s─━═╔╚║╠▓▒░#|+=_.·—–-]*$/

/** `8-10`, `8–10`, `× 12`, `x8` — a rep window or a single number. */
function repsIn(text: string): { low: number | null; high: number | null } {
  const m = /(?:[×x]\s*|\breps?\s*[:=]?\s*)(\d{1,3})\s*(?:[-–—]|to)\s*(\d{1,3})/i.exec(text)
    ?? /(\d{1,3})\s*(?:[-–—]|to)\s*(\d{1,3})\s*reps?\b/i.exec(text)
  if (m) return { low: numOf(m[1]), high: numOf(m[2]) }
  const one = /(?:[×x]\s*(\d{1,3})\b)|(?:\b(\d{1,3})\s*reps?\b)/i.exec(text)
  if (one) {
    const n = numOf(one[1] ?? one[2] ?? '')
    return { low: n, high: n }
  }
  return { low: null, high: null }
}

/**
 * What the report told you to do next week, in the shapes the app can act on.
 *
 * ── EVERY FIELD IS OPTIONAL, INDEPENDENTLY ───────────────────────────────────
 * Same discipline as the rest of this reader: a report with a hydration line and
 * no load ladder yields a hydration target and nothing else, never an error and
 * never a zero. A consumer that receives `null` for a field renders nothing for
 * it, because a prescription nobody wrote is not a prescription of zero.
 *
 * The exercise ladder is read from a pipe table when there is one and from
 * inline `Name → 49.5 kg × 8-10` lines when there is not, because reports have
 * been written both ways and neither shape is the contract.
 */
export function parseTargets(lines: string[]): ReportTargets {
  const exercises: TargetExercise[] = []
  const seen = new Set<string>()
  const push = (name: string, loadKg: number | null, reps: { low: number | null; high: number | null }) => {
    const clean = name.replace(/^[\s·—–>-]+|[\s·—–:>-]+$/g, '').replace(/\*\*/g, '').trim()
    if (clean.length < 3 || !/[a-z]/i.test(clean)) return
    const key = clean.toLowerCase()
    if (seen.has(key)) return
    seen.add(key)
    exercises.push({ name: clean, loadKg, repsLow: reps.low, repsHigh: reps.high })
  }

  const table = parseTable(lines)
  if (table) {
    const li = table.columns.findIndex((c) => /\b(kg|load|weight|target)\b/i.test(c))
    const ri = table.columns.findIndex((c) => /\breps?\b|\brange\b|\bwindow\b/i.test(c))
    if (li > 0) {
      for (const cells of table.rows) {
        const load = numOf((cells[li] ?? '').replace(/[^\d.,]/g, ''))
        push(cells[0] ?? '', load, repsIn(ri >= 0 ? (cells[ri] ?? '') : ''))
      }
    }
  }

  // Lines already read as a NUMBER are not also read as prose. Without this the
  // notes fill up with the load ladder restated in words, and the one sentence
  // the report actually wrote to you falls off the end of the list.
  const consumed = new Set<number>()

  for (const [i, raw] of lines.entries()) {
    if (raw.includes('|')) continue
    const line = raw.replace(BULLET, '').trim()
    // A load line needs a NAME and a kg figure. Requiring the separator is what
    // stops "Volume dropped to 24 kg per set on Tuesday" being read as a
    // prescription for an exercise called "Volume dropped to".
    const m = /^(.{2,64}?)\s*(?:[→⇒:·•]|[—–-]{1,2}|\bat\b|\bto\b|\bhold\b)\s*(\d[\d.,]*)\s*kg\b(.*)$/i.exec(line)
    if (!m) continue
    const load = numOf(m[2])
    if (load == null || load <= 0) continue
    push(m[1], load, repsIn(m[3]))
    consumed.add(i)
  }

  let water: ReportTargets['water'] = null
  let steps: number | null = null
  let macros: ReportTargets['macros'] = null
  const notes: string[] = []

  for (const [i, raw] of lines.entries()) {
    const line = raw.replace(BULLET, '').trim()

    if (!water && /water|hydrat|h₂o|h2o|fluid/i.test(line)) {
      const range = /(\d[\d.]*)\s*(?:[-–—]|to)\s*(\d[\d.]*)\s*(?:L\b|litre|liter)/i.exec(line)
      const single = /(\d[\d.]*)\s*(?:L\b|litre|liter)/i.exec(line)
      const lo = range ? numOf(range[1]) : single ? numOf(single[1]) : null
      const hi = range ? numOf(range[2]) : lo
      // A "3.2 L" that is really "3200 ml" written oddly, or a stray year, is
      // not a hydration target. Bounds, not trust.
      if (lo != null && hi != null && lo >= 0.5 && hi <= 12) { water = { minL: lo, maxL: hi }; consumed.add(i) }
    }

    if (steps == null && /\bsteps?\b/i.test(line)) {
      const k = /(\d[\d.]*)\s*k\b/i.exec(line)
      const plain = /(\d[\d,]{2,})/.exec(line)
      const n = k ? (numOf(k[1]) ?? 0) * 1000 : plain ? numOf(plain[1]) : null
      if (n != null && n >= 1000 && n <= 60000) { steps = Math.round(n); consumed.add(i) }
    }

    if (!macros && /kcal|calorie/i.test(line)) {
      const kcal = /(\d[\d,]{2,})\s*(?:kcal|cal)/i.exec(line)
      const grams = (letter: string) =>
        numOf(new RegExp(`(\\d{1,3})\\s*(?:g\\s*)?${letter}\\b`, 'i').exec(line)?.[1] ?? '')
        ?? numOf(new RegExp(`${letter}[a-z]*\\s*[:=]?\\s*(\\d{1,3})\\s*g?\\b`, 'i').exec(line)?.[1] ?? '')
      const value = {
        kcal: kcal ? numOf(kcal[1]) : null,
        proteinG: grams('P'), carbsG: grams('C'), fatG: grams('F'),
      }
      if (value.kcal != null) { macros = value; consumed.add(i) }
    }

    if (notes.length < 4 && !consumed.has(i)) {
      const note = cleanInstruction(raw)
      if (note) notes.push(note)
    }
  }

  return { exercises, water, steps, macros, notes }
}

/**
 * Fold several sections' targets into one. First non-null wins per field, so a
 * later section repeating last week's hydration line cannot overwrite this
 * week's; exercises accumulate, deduplicated by name.
 */
function mergeTargets(all: ReportTargets[]): ReportTargets {
  const out: ReportTargets = { exercises: [], water: null, steps: null, macros: null, notes: [] }
  const seen = new Set<string>()
  for (const t of all) {
    for (const ex of t.exercises) {
      const key = ex.name.toLowerCase()
      if (seen.has(key)) continue
      seen.add(key)
      out.exercises.push(ex)
    }
    out.water ??= t.water
    out.steps ??= t.steps
    out.macros ??= t.macros
    for (const n of t.notes) if (out.notes.length < 4 && !out.notes.includes(n)) out.notes.push(n)
  }
  return out
}

/** Is there anything here worth showing? An all-empty result is treated as none. */
export function hasTargets(t: ReportTargets | null | undefined): t is ReportTargets {
  return !!t && (t.exercises.length > 0 || !!t.water || t.steps != null || !!t.macros || t.notes.length > 0)
}

function parseHeader(preamble: string[], md: string): FmtV2Header {
  const version = (/\bFMT\s*(v?\d+)\b/i.exec(md)?.[1] ?? 'v2').toLowerCase()

  // The banner line is inside the box: strip the frame, then split on the
  // middle dot the format uses as a field separator.
  const banner = preamble
    .map((l) => l.replace(/[║╔╗╚╝═]/g, '').trim())
    .find((l) => /·/.test(l) && /FMT\s*v?\d/i.test(l))
  const fields = banner ? banner.split('·').map((f) => f.trim()).filter(Boolean) : []

  const weekLabel = fields.find((f) => /^W\d+$/i.test(f)) ?? null
  const rangeLabel = fields.find((f) => /\d{4}-\d{2}-\d{2}/.test(f)) ?? null
  const phase = fields.find((f) => /^[A-Z][A-Z\s/&-]+$/.test(f) && !/FMT|SENTINEL/i.test(f)) ?? null

  // ── THE TITLE IS A POSITION, NOT A BRAND (Expansion W1) ───────────────────
  // This matched the brand name, and carried the predecessor's too, because
  // the seven reports already stored open with that app's banner. W1 removed
  // that name from the repository, so the test became structural instead: the
  // title is the first line of the preamble that is not box-drawing and not
  // the banner itself. That matches both eras of report without naming either,
  // and it is strictly more permissive — a report whose masthead says neither
  // word now gets a title where it used to get null.
  //
  // ── "ABOVE THE BOX", NOT "NOT A BOX LINE" ────────────────────────────────
  // `preamble` is everything before the first `▓ PART`, so it holds the
  // masthead, the box rules, AND the banner line between them. `BOX` matches
  // only lines made ENTIRELY of frame characters, so the banner —
  // `║ W01 · … · FMT v2 ║` — is not a box line and a plain `find` picks it up
  // the moment a report has no masthead. Ten of the seventeen stored reports
  // are exactly that shape, and they would have been titled with the framed
  // banner, pipes included. The masthead is defined by POSITION: it is above
  // the box, so only the lines above the first box rule can be one.
  // `BOX` includes `\s`, so a BLANK line matches it — meaning a report that
  // opens with an empty line would otherwise cut the search at line 0 and find
  // no title at all. A rule is a line that is box-drawing AND has something on
  // it; a blank line is just a blank line.
  const boxAt = preamble.findIndex((l) => l.trim() !== '' && BOX.test(l))
  const aboveBox = boxAt === -1 ? preamble : preamble.slice(0, boxAt)
  const title = aboveBox.find((l) => l.trim() !== '')?.trim() ?? null

  return { weekLabel, rangeLabel, phase, version, title }
}

/**
 * A section heading, or null.
 *
 * Two shapes, because reports are written both ways: a markdown heading
 * (`## 🟢 QUICK VERDICT`), and a bare emoji-led line for pastes that use no
 * markdown at all. The leading glyph is lifted out either way so the renderer
 * can show it beside the title instead of inside it.
 */
export function headingOf(line: string): { emoji: string | null; title: string } | null {
  const atx = ATX.exec(line)
  const text = atx ? atx[1] : line.trim()
  const em = EMOJI_LEAD.exec(text)
  if (em) return { emoji: em[1], title: em[2].trim() }
  return atx ? { emoji: null, title: text } : null
}

/**
 * Split a pasted report into parts and sections.
 *
 * Returns null only when the text is empty — an unrecognised layout still comes
 * back with everything in `preamble`, which renders as the original text.
 */
export function parseFmtV2(md: string | null | undefined): FmtV2Report | null {
  if (!md || !md.trim()) return null
  const lines = md.replace(/\r\n?/g, '\n').split('\n')

  const preamble: string[] = []
  const parts: FmtV2Part[] = []

  let part: FmtV2Part | null = null
  let section: FmtV2Section | null = null

  const pushSection = () => {
    if (!part || !section) return
    while (section.lines.length && !section.lines[section.lines.length - 1].trim()) section.lines.pop()
    // The blank line between a part heading and its first section is not a
    // section. Anonymous ones only survive if they actually carry text.
    if (section.title || section.lines.length) {
      section.table = parseTable(section.lines)
      part.sections.push(section)
    }
    section = null
  }

  for (const line of lines) {
    const pm = PART.exec(line)
    if (pm && isShouted(pm[1])) {
      pushSection()
      part = { title: pm[1].replace(/^PART\s*/i, '').replace(/^\d+\s*[—–-]\s*/, '').trim() || pm[1], sections: [] }
      parts.push(part)
      continue
    }

    const head = headingOf(line)
    if (head && part && isShouted(head.title)) {
      pushSection()
      section = { emoji: head.emoji, title: head.title, lines: [], table: null, kind: null }
      continue
    }

    if (!part) { preamble.push(line); continue }
    if (!section) { section = { emoji: null, title: '', lines: [], table: null, kind: null } }
    section.lines.push(line)
  }
  pushSection()

  // Cross-part lookups. Deliberately searched by MEANING, not position: a report
  // that moves the TDEE block to Part 3 must not lose its chart.
  const allSections = parts.flatMap((p) => p.sections)
  const find = (re: RegExp) => allSections.find((s) => re.test(s.title))

  const tdeeSection = find(/TDEE|MATH|METABOLIC|ENERGY/i)
  const tdee = tdeeSection ? parseTdeeAnchors(tdeeSection.lines) : []
  if (tdeeSection && tdee.length) tdeeSection.kind = 'tdee'

  const bodySection = find(/BODY\s*COMP|COMPOSITION|TRAJECTORY/i)
  const bodyComp = bodySection?.table && /date/i.test(bodySection.table.columns[0] ?? '')
    ? bodySection.table
    : null
  if (bodySection && bodyComp) bodySection.kind = 'bodyComp'

  const asymSection = find(/ASYMMETR|IMBALANCE|L\/R|LEFT.*RIGHT/i)
  const asymmetry = asymSection ? parseAsymmetry(asymSection.lines) : []
  if (asymSection && asymmetry.length) asymSection.kind = 'asymmetry'

  // Prescriptions are spread across whatever the week's report called them, so
  // EVERY matching section contributes rather than the first one winning. A
  // hydration line under "PROTOCOL" and a load ladder under "DB LADDER" are one
  // set of instructions to the person reading them.
  const targetSections = allSections.filter((s) =>
    /DIRECTIVE|ACTION|NEXT\s*WEEK|PROTOCOL|PRESCRIPTION|ADJUST|DO\s*THIS|LADDER|LOAD|TARGET|PROJECTION/i.test(s.title))
  const targets = targetSections.length
    ? mergeTargets(targetSections.map((s) => parseTargets(s.lines)))
    : null
  if (targets && hasTargets(targets)) {
    for (const s of targetSections) {
      if (!s.kind && hasTargets(parseTargets(s.lines))) s.kind = 'targets'
    }
  }

  return {
    header: parseHeader(preamble, md),
    parts,
    preamble: preamble.filter((l) => l.trim()),
    tdee,
    bodyComp,
    asymmetry,
    targets: hasTargets(targets) ? targets : null,
  }
}

/**
 * Numeric columns of a body-comp table, ready to plot.
 *
 * Column 0 is the date; every other column is kept only if MOST of its cells
 * parse as numbers, so a stray "—" or a trailing note column doesn't produce a
 * chart of nothing.
 */
export function bodyCompSeries(table: ParsedTable): Array<{ label: string; points: Array<{ date: string; value: number | null }> }> {
  const out: Array<{ label: string; points: Array<{ date: string; value: number | null }> }> = []
  for (let c = 1; c < table.columns.length; c++) {
    const points = table.rows.map((r) => ({
      date: r[0] ?? '',
      value: numOf((r[c] ?? '').replace(/[^\d.,-]/g, '')),
    }))
    const real = points.filter((p) => p.value != null).length
    if (real >= Math.max(2, Math.ceil(points.length / 2))) {
      out.push({ label: table.columns[c], points })
    }
  }
  return out
}
