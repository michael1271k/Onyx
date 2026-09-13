/**
 * A reader for the ASCII a report is written in — box banners, text progress
 * bars, status leads — so the renderer can draw them instead of dumping them.
 *
 * WHY THIS IS A SPLITTER AND NOT A FORMAT. Onyx defines no report format, so
 * nothing here may require, reject, or reorder. `splitSmartBlocks` walks the
 * text once and labels each run as one of four things; the ONLY block that
 * changes what you see is one whose shape was recognised beyond doubt. Anything
 * else falls through to `md` (rendered as markdown) or `code` (rendered
 * preformatted, exactly as pasted). A paste that this module fails to
 * understand looks precisely as it did before this module existed.
 *
 * The three shapes it knows, all from real Sentinel-7 output:
 *
 *   ╔══════════════════════════════════╗
 *   ║ W01 · 2026-07-19 → 07-25 · CUT   ║     → hero
 *   ╚══════════════════════════════════╝
 *
 *   Protein   ████████████░░░░  78%           → bars
 *   🟢 QUICK VERDICT — the cut is on rails    → status lead (per paragraph)
 *
 * Pure: no React, no network, no clock.
 */

// ── shapes ───────────────────────────────────────────────────────────────────

export interface TextBar {
  label: string
  /** Filled fraction, 0…1, derived from the glyphs. */
  ratio: number
  /** The author's OWN percentage, when the line carried one. Never invented. */
  pct: number | null
  /** Whatever followed the bar ("78%", "2,140 / 2,300 kcal"). */
  trailing: string
}

export interface HeroBlock { kind: 'hero'; headline: string; chips: string[]; lines: string[] }
export interface BarsBlock { kind: 'bars'; bars: TextBar[] }
export interface CodeBlock { kind: 'code'; text: string; lang: string | null }
export interface MdBlock { kind: 'md'; text: string }
export type SmartBlock = HeroBlock | BarsBlock | CodeBlock | MdBlock

export type StatusTone = 'good' | 'warn' | 'bad' | 'info'

export interface StatusLead {
  emoji: string
  label: string
  tone: StatusTone
  /** The sentence after the separator, if there was one. */
  rest: string
}

// ── character classes ────────────────────────────────────────────────────────

/** Shading glyphs a text progress bar is drawn from. */
const BAR_RUN = /[█▓▒░]{3,}/
/** Box-drawing that means "this line is a picture, not a sentence". */
const BOX_CHAR = /[╔╗╚╝║═╠╣╦╩╬┌┐└┘│─├┤┬┴┼]/
const BOX_ONLY = /^[\s╔╗╚╝║═╠╣╦╩╬┌┐└┘│─├┤┬┴┼]+$/
const HERO_OPEN = /^\s*[╔┌][═─╌]/
const HERO_CLOSE = /^\s*[╚└][═─╌]/
/**
 * Column joints. A box that has them is a GRID — an ASCII table — and squashing
 * one into a hero card would delete its columns. A banner is a box with nothing
 * inside it but a line of text.
 */
const GRID_CHAR = /[┬┴┼╦╩╬┳┻╋]/
/** Column alignment: three or more spaces holding two columns apart. */
const ALIGNED = /\S {3,}\S/
/** Longest a banner may run before we stop believing it is one. */
const HERO_MAX_LINES = 14

const TONE_BY_EMOJI: Record<string, StatusTone> = {
  '🟢': 'good', '✅': 'good', '✔': 'good', '☑': 'good', '🎯': 'good', '💚': 'good',
  '🟡': 'warn', '🟠': 'warn', '⚠': 'warn', '🔶': 'warn', '⏳': 'warn', '🟧': 'warn',
  '🔴': 'bad', '❌': 'bad', '🛑': 'bad', '‼': 'bad', '🚨': 'bad',
  '🔵': 'info', 'ℹ': 'info', '📌': 'info', '📋': 'info', '🧭': 'info', '🔷': 'info',
}

/** A label is SHOUTED — that is what separates a status tag from a sentence. */
function isShouted(text: string): boolean {
  const letters = text.replace(/[^A-Za-z]/g, '')
  if (letters.length < 3) return false
  return text.replace(/[^A-Z]/g, '').length / letters.length >= 0.7
}

// ── line readers ─────────────────────────────────────────────────────────────

/**
 * A text progress bar, or null.
 *
 * The author's own percentage wins when the line states one — the glyph ratio is
 * a rounding of it at whatever resolution they drew, and reporting 76% under a
 * line that says 78% is the renderer contradicting the report.
 */
export function parseTextBar(line: string): TextBar | null {
  const m = BAR_RUN.exec(line)
  if (!m) return null
  const glyphs = m[0]
  const filled = (glyphs.match(/[█▓]/g) ?? []).length
  const half = (glyphs.match(/▒/g) ?? []).length
  const total = glyphs.length
  const trailing = line.slice(m.index + glyphs.length).trim()
  const label = line.slice(0, m.index).replace(/[\s:|·]+$/, '').trim()
  const pctMatch = /(-?\d+(?:[.,]\d+)?)\s*%/.exec(trailing) ?? /(-?\d+(?:[.,]\d+)?)\s*%/.exec(label)
  const pct = pctMatch ? Number(pctMatch[1].replace(',', '.')) : null
  return {
    label,
    ratio: total ? (filled + half * 0.5) / total : 0,
    pct: pct != null && Number.isFinite(pct) ? pct : null,
    trailing,
  }
}

/**
 * A leading status tag ("🟢 QUICK VERDICT — …"), or null.
 *
 * Requires all three of a known emoji, a SHOUTED label and a plausible length.
 * Two out of three is a sentence that happens to start with an emoji, and
 * badging those would put a chip around half the report.
 */
export function parseStatusLead(text: string): StatusLead | null {
  const m = /^\s*(\p{Extended_Pictographic}️?)\s+(\S.*)$/u.exec(text)
  if (!m) return null
  const emoji = m[1]
  const tone = TONE_BY_EMOJI[emoji] ?? TONE_BY_EMOJI[emoji.replace(/️/g, '')]
  if (!tone) return null

  const body = m[2]
  const sep = body.search(/[—–:]|\s[|·]\s/)
  const label = (sep > 0 ? body.slice(0, sep) : body).trim()
  const rest = sep > 0 ? body.slice(sep).replace(/^[\s—–:|·]+/, '').trim() : ''
  if (label.length < 2 || label.length > 40 || !isShouted(label)) return null
  return { emoji, label, tone, rest }
}

// ── block splitting ──────────────────────────────────────────────────────────

/** Strip a box banner's side borders and padding from one line. */
const unbox = (l: string) => l.replace(/^\s*[║│]?\s?/, '').replace(/\s*[║│]\s*$/, '').trim()

/** The separators a banner uses between facts on one line. */
const SEGMENT = /\s+[·|│]\s+|\s{2,}[·|│]\s{2,}/

/**
 * Read the inner lines of a banner into a headline plus chips.
 *
 * The banner's own separator is ` · ` (or ` │ `), so the first segment of the
 * first line is the headline and everything else is a fact about the week —
 * exactly what a row of chips is for. A real banner runs to four lines:
 *
 *   W01 · 2026-07-19 → 07-25 · CUT / RE-ENTRY · SENTINEL-7 · FMT v2
 *   T4WM 64.85 kg │ BF 17.5% │ 92 sets │ 35,372 kg │ 5 PRs
 *   DATA: 5 valid readings · 2 protocol skips · INTEGRITY FLAGS: 0 ✅
 *   🟢 STATUS: ON-BLUEPRINT — DEFICIT IN BAND, STEPS AT LOWER EDGE
 *
 * so EVERY line is segmented, not just the first. A line that doesn't split is
 * a sentence and stays one.
 */
function heroOf(inner: string[]): HeroBlock {
  const content = inner.map(unbox).filter((l) => l && !BOX_ONLY.test(l))
  const first = content[0] ?? ''
  const segments = first.split(SEGMENT).map((s) => s.trim()).filter(Boolean)
  const chips = segments.slice(1)
  const lines: string[] = []
  for (const l of content.slice(1)) {
    const parts = l.split(SEGMENT).map((s) => s.trim()).filter(Boolean)
    if (parts.length > 1) chips.push(...parts)
    else lines.push(l)
  }
  return { kind: 'hero', headline: segments[0] ?? first, chips, lines }
}

// ── pipe tables ──────────────────────────────────────────────────────────────

const PIPES = (l: string) => (l.match(/\|/g) ?? []).length
/** A GFM alignment row: pipes, dashes, colons and space — nothing else. */
const SEPARATOR = /^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/

/** A table row's cells, with the optional leading/trailing pipes dropped. */
function cellsOf(line: string): string[] {
  const parts = line.split('|')
  if (parts[0].trim() === '') parts.shift()
  if (parts.length > 1 && parts[parts.length - 1].trim() === '') parts.pop()
  return parts
}

/** Longest a table cell may be before it is more plausibly a sentence. */
const MAX_CELL = 40

/**
 * A run of two or more rows that all carry the same number of columns.
 *
 * Two pipes is unambiguous. ONE pipe ("Metric | Value") is a real two-column
 * table but also the shape of an ordinary sentence containing a pipe, so that
 * case additionally requires every cell to be short — a table cell is a label or
 * a number, and a 40-character one is prose.
 */
function pipeTableAt(lines: string[], i: number): string[] | null {
  const width = PIPES(lines[i])
  if (width < 1) return null
  const run: string[] = []
  let j = i
  while (j < lines.length && lines[j].trim() && PIPES(lines[j]) === width) { run.push(lines[j]); j += 1 }
  if (run.length < 2) return null
  if (width < 2 && run.some((l) => cellsOf(l).some((c) => c.trim().length > MAX_CELL))) return null
  return run
}

/**
 * Give a bare pipe table the alignment row GFM requires.
 *
 * Sentinel-7 writes its tables without one, which is why remark-gfm renders them
 * as a single run-on paragraph — ten columns of body composition collapsed into
 * a sentence. Synthesising the row the author omitted turns them into real
 * tables everywhere, not just inside the FMT v2 reader.
 */
export function withSeparator(run: string[]): string {
  if (run.length >= 2 && SEPARATOR.test(run[1])) return run.join('\n')
  const cols = cellsOf(run[0]).length
  const bounded = run[0].trim().startsWith('|')
  const sep = bounded ? `|${' --- |'.repeat(cols)}` : Array(cols).fill('---').join(' | ')
  return [run[0], sep, ...run.slice(1)].join('\n')
}

/** Classify a block of preformatted text: a banner, a bar chart, or as-is. */
/** A box with no column joints in it — i.e. a banner rather than a table. */
const isBanner = (lines: string[]) => HERO_OPEN.test(lines[0] ?? '') && !GRID_CHAR.test(lines.join(''))

function classify(lines: string[], lang: string | null): SmartBlock {
  const solid = lines.filter((l) => l.trim())
  if (isBanner(solid)) return heroOf(lines)
  const bars = solid.map(parseTextBar)
  if (bars.length && bars.every((b) => b != null)) return { kind: 'bars', bars: bars as TextBar[] }
  return { kind: 'code', text: lines.join('\n').replace(/\s+$/, ''), lang }
}

/**
 * Split markdown into renderable blocks.
 *
 * Order matters: banners are claimed before bars, and bars before the generic
 * "this is a picture" fallback, because a banner's rule lines would otherwise
 * read as an empty bar.
 */
export function splitSmartBlocks(md: string): SmartBlock[] {
  const lines = (md ?? '').split('\n')
  const out: SmartBlock[] = []
  let buf: string[] = []

  const flushMd = () => {
    const text = buf.join('\n').trim()
    if (text) out.push({ kind: 'md', text })
    buf = []
  }

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i]

    // ── fenced block: take it whole, then read what is inside it ──
    const fence = /^\s*```+\s*(\S*)\s*$/.exec(line)
    if (fence) {
      flushMd()
      const lang = fence[1] || null
      const body: string[] = []
      i += 1
      while (i < lines.length && !/^\s*```+\s*$/.test(lines[i])) { body.push(lines[i]); i += 1 }
      if (body.length) out.push(classify(body, lang))
      continue
    }

    // ── banner box ──
    if (HERO_OPEN.test(line)) {
      const body: string[] = [line]
      let j = i + 1
      while (j < lines.length && j - i < HERO_MAX_LINES) {
        body.push(lines[j])
        if (HERO_CLOSE.test(lines[j])) break
        j += 1
      }
      // An unterminated box is not a box, and a box with column joints is a
      // table; both are left to the preformatted path, which prints them intact.
      if (HERO_CLOSE.test(body[body.length - 1] ?? '') && isBanner(body)) {
        flushMd()
        out.push(heroOf(body))
        i = j
        continue
      }
    }

    // ── a run of progress bars ──
    if (parseTextBar(line)) {
      const bars: TextBar[] = []
      let j = i
      while (j < lines.length) {
        const b = lines[j].trim() ? parseTextBar(lines[j]) : null
        if (!b) break
        bars.push(b)
        j += 1
      }
      flushMd()
      out.push({ kind: 'bars', bars })
      i = j - 1
      continue
    }

    // ── pipe table ──
    // Claimed BEFORE the preformatted path: a padded table ("| Date      | Wt |")
    // is column-aligned by construction, and letting that win would ship every
    // table as monospace text.
    const table = pipeTableAt(lines, i)
    if (table) {
      flushMd()
      out.push({ kind: 'md', text: withSeparator(table) })
      i += table.length - 1
      continue
    }

    // ── preformatted: box art, or a run of column-aligned lines ──
    const picture = BOX_CHAR.test(line)
    const aligned = ALIGNED.test(line) && ALIGNED.test(lines[i + 1] ?? '')
    if (line.trim() && (picture || aligned)) {
      const body: string[] = []
      let j = i
      while (j < lines.length && lines[j].trim() && (BOX_CHAR.test(lines[j]) || ALIGNED.test(lines[j]))) {
        body.push(lines[j])
        j += 1
      }
      flushMd()
      out.push({ kind: 'code', text: body.join('\n'), lang: null })
      i = j - 1
      continue
    }

    buf.push(line)
  }

  flushMd()
  return out
}
