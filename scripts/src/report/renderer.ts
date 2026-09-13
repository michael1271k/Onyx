/**
 * The report renderer, as it runs inside the native app's `WKWebView`.
 *
 * ── WHY THE PARSERS ARE IMPORTED AND NOT REWRITTEN ──────────────────────────
 * `fmtV2.ts` and `smartBlocks.ts` are 945 lines of parsing that was bought one
 * rule at a time: tables with no separator row, `⚑` and `◆` not being
 * Extended_Pictographic, a bar run needing three glyphs so `▓ PART 1` is not an
 * empty progress bar, an anchor line's trailing parenthetical that turns 65.6
 * into the last numeric token. Both are explicitly pure — no React, no network,
 * no clock — so the native bundle imports them and inherits every one of those
 * rules. A second implementation would be a second set of them, drifting.
 *
 * ── AND WHY `micromark` RATHER THAN `react-markdown` ────────────────────────
 * The web page renders markdown through react-markdown + remark-gfm; both sit on
 * micromark, which is already in this repo's tree. Using it directly drops React
 * from the bundle and keeps the markdown semantics identical — including the one
 * that matters most: **raw HTML in a report body is escaped, never executed.**
 * A report is arbitrary text pasted from a model, and the web renderer refuses
 * to run HTML in it because `rehype-raw` was deliberately never added. This
 * keeps that refusal (`allowDangerousHtml` is off by default).
 *
 * The bundle is built by `scripts/gen-report-bundle.mjs` and committed into the
 * app. It has no network access at runtime and needs none.
 */
import { micromark } from 'micromark'
import { gfm, gfmHtml } from 'micromark-extension-gfm'
import { isFmtV2, parseFmtV2, type FmtV2Section } from './fmtV2'
import {
  splitSmartBlocks,
  parseStatusLead,
  type SmartBlock,
  type TextBar,
} from './smartBlocks'

// ── The document ───────────────────────────────────────────────────────────

function el(tag: string, className?: string, text?: string): HTMLElement {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

/** Markdown → HTML, GFM, with HTML in the source escaped rather than run. */
function markdown(md: string): string {
  return micromark(md, {
    extensions: [gfm()],
    htmlExtensions: [gfmHtml()],
  })
}

/**
 * A markdown block, with one exception applied first.
 *
 * A paragraph that OPENS with a known status glyph and a shouted label is drawn
 * as a badge plus the rest of the sentence. The web version finds those by
 * walking React children after parsing; doing it on the source line before
 * parsing is simpler and lands in the same place — including the quirk that a
 * bolded lead (`**🟢 VERDICT** — …`) is not a badge, because the glyph is no
 * longer the first character of the text.
 */
function renderMarkdown(md: string): HTMLElement {
  const host = el('div', 'md')
  const paragraphs = md.split(/\n{2,}/)

  for (const para of paragraphs) {
    const lead = parseStatusLead(para)
    if (lead) {
      const wrap = el('p', 'lead')
      const badge = el('span', `badge ${lead.tone}`)
      badge.textContent = `${lead.emoji} ${lead.label}`
      wrap.appendChild(badge)
      if (lead.rest) {
        const rest = el('span', 'lead-rest')
        rest.innerHTML = markdown(lead.rest).replace(/^<p>|<\/p>\n?$/g, '')
        wrap.appendChild(rest)
      }
      host.appendChild(wrap)
      continue
    }
    const block = el('div')
    block.innerHTML = markdown(para)
    host.appendChild(block)
  }
  return host
}

function renderBars(bars: TextBar[]): HTMLElement {
  const host = el('div', 'bars')
  for (const bar of bars) {
    const row = el('div', 'bar-row')
    row.appendChild(el('span', 'bar-label', bar.label))

    const track = el('span', 'bar-track')
    const fill = el('span', 'bar-fill')
    // The AUTHOR's percentage wins over the glyph ratio: a bar drawn at 16
    // characters can only express 6.25 % steps, so re-deriving would print 75 %
    // under a line that says 78 %.
    const pct = bar.pct ?? bar.ratio * 100
    fill.style.width = `${Math.max(0, Math.min(120, pct))}%`
    fill.dataset.tone = pct > 100 ? 'over' : pct >= 66 ? 'good' : pct >= 33 ? 'mid' : 'low'
    track.appendChild(fill)
    row.appendChild(track)

    row.appendChild(el('span', 'bar-value', bar.pct != null ? `${bar.pct}%` : ''))
    host.appendChild(row)
  }
  return host
}

function renderHero(headline: string, chips: string[], lines: string[]): HTMLElement {
  const host = el('section', 'hero')
  host.appendChild(el('h2', 'hero-headline', headline))
  if (chips.length) {
    const row = el('div', 'hero-chips')
    for (const chip of chips) row.appendChild(el('span', 'chip', chip))
    host.appendChild(row)
  }
  for (const line of lines) host.appendChild(el('p', 'hero-line', line))
  return host
}

function renderBlocks(blocks: SmartBlock[]): DocumentFragment {
  const frag = document.createDocumentFragment()
  for (const block of blocks) {
    switch (block.kind) {
      case 'hero':
        frag.appendChild(renderHero(block.headline, block.chips, block.lines))
        break
      case 'bars':
        frag.appendChild(renderBars(block.bars))
        break
      case 'code': {
        // Box art and column-aligned ledgers. `white-space: pre` and no
        // ligatures, so `─` and `═` cannot fuse into one glyph.
        const pre = el('pre', 'report-pre')
        pre.appendChild(el('code', undefined, block.text))
        frag.appendChild(pre)
        break
      }
      case 'md':
        frag.appendChild(renderMarkdown(block.text))
        break
    }
  }
  return frag
}

/**
 * A section's prose, with the lines its chart already drew removed.
 *
 * Mirrors `proseLines` on the web: a TDEE section drops its `ANCHOR` lines and a
 * table-backed section drops the table rows, so nothing is printed twice. Every
 * other line survives — the renderer must never be the reason a section
 * disappears.
 */
function proseOf(section: FmtV2Section): string {
  const lines = section.lines.filter((line) => {
    if (section.kind === 'tdee' && /^\s*ANCHOR\s+\S/i.test(line)) return false
    if ((section.kind === 'bodyComp' || section.kind === 'asymmetry')
        && (line.match(/\|/g)?.length ?? 0) >= 2) return false
    return true
  })
  return lines.join('\n').trim()
}

/** A table the parser already read, drawn as a table. */
function renderTable(columns: string[], rows: string[][]): HTMLElement {
  const wrap = el('div', 'table-wrap')
  const table = el('table')
  const thead = el('thead')
  const hr = el('tr')
  for (const c of columns) hr.appendChild(el('th', undefined, c))
  thead.appendChild(hr)
  table.appendChild(thead)

  const tbody = el('tbody')
  for (const row of rows) {
    const tr = el('tr')
    for (const cell of row) tr.appendChild(el('td', 'num', cell))
    tbody.appendChild(tr)
  }
  table.appendChild(tbody)
  wrap.appendChild(table)
  return wrap
}

/** The TDEE ladder: bars from the LOWEST anchor, not from zero. */
function renderTdee(anchors: Array<{ key: string; label: string; value: number; adopted: boolean }>): HTMLElement {
  const host = el('div', 'ladder')
  const values = anchors.map((a) => a.value)
  const lo = Math.min(...values)
  const span = Math.max(1, Math.max(...values) - lo)

  for (const anchor of anchors) {
    const row = el('div', 'ladder-row')
    row.appendChild(el('span', 'ladder-label', `${anchor.key} · ${anchor.label}`))
    const track = el('span', 'bar-track')
    const fill = el('span', 'bar-fill')
    // Zero-based bars for four anchors inside 300 kcal of each other are four
    // identical bars; anchored at the lowest, the differences are the drawing.
    fill.style.width = `${12 + ((anchor.value - lo) / span) * 88}%`
    fill.dataset.tone = anchor.adopted ? 'over' : 'mid'
    track.appendChild(fill)
    row.appendChild(track)
    // Value and chip in ONE cell: a fourth child in a three-column grid wraps
    // onto its own row and reads as another anchor.
    const value = el('span', 'ladder-value')
    value.appendChild(el('span', 'bar-value num', anchor.value.toLocaleString()))
    if (anchor.adopted) value.appendChild(el('span', 'chip', 'adopted'))
    row.appendChild(value)
    host.appendChild(row)
  }
  return host
}

// ── The entry point ────────────────────────────────────────────────────────

/**
 * Render one report body into `#root`.
 *
 * Called by the native side through `window.onyxRender(markdown)`. Never
 * throws: a report that cannot be parsed is printed verbatim, because a saved
 * report the reader can no longer read is the one unacceptable outcome.
 */
export function render(md: string): void {
  const root = document.getElementById('root')
  if (!root) return
  root.textContent = ''

  try {
    if (!isFmtV2(md)) {
      root.appendChild(renderBlocks(splitSmartBlocks(md)))
      return
    }

    const report = parseFmtV2(md)
    if (!report || report.parts.length === 0) {
      root.appendChild(renderBlocks(splitSmartBlocks(md)))
      return
    }

    if (report.preamble.length) {
      root.appendChild(renderBlocks(splitSmartBlocks(report.preamble.join('\n'))))
    }

    for (const part of report.parts) {
      root.appendChild(el('h2', 'part', part.title))

      for (const section of part.sections) {
        const heading = el('h3', 'section')
        if (section.emoji) {
          const glyph = el('span', 'section-glyph', section.emoji)
          glyph.setAttribute('aria-hidden', 'true')
          heading.appendChild(glyph)
        }
        heading.appendChild(document.createTextNode(section.title))
        root.appendChild(heading)

        if (section.kind === 'tdee' && report.tdee.length) {
          root.appendChild(renderTdee(report.tdee))
        }
        if (section.kind === 'bodyComp' && section.table) {
          root.appendChild(renderTable(section.table.columns, section.table.rows))
        }
        if (section.kind === 'asymmetry' && section.table) {
          root.appendChild(renderTable(section.table.columns, section.table.rows))
        }

        const prose = proseOf(section)
        if (prose) root.appendChild(renderBlocks(splitSmartBlocks(prose)))
      }
    }
  } catch (error) {
    // The parser is not supposed to throw and its own tests say so. If it ever
    // does, the report still has to be readable.
    root.textContent = ''
    const pre = el('pre', 'report-pre')
    pre.appendChild(el('code', undefined, md))
    root.appendChild(pre)
    console.error(error)
  }
}

declare global {
  interface Window {
    onyxRender: (md: string) => void
  }
}

window.onyxRender = render
