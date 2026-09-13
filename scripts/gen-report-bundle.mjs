#!/usr/bin/env node
/**
 * Build the offline report renderer the native app ships inside its bundle.
 *
 * ── WHY THERE IS A GENERATOR AND NOT A HAND-WRITTEN HTML FILE ───────────────
 * The two parsers this bundle needs — `fmtV2.ts` and `smartBlocks.ts` — are 945
 * lines of rules bought one bug at a time, and they live in `scripts/src/report/`.
 * A hand-written copy inside an HTML file would be a second implementation of
 * them, and the two would drift the first time a report used a shape only one
 * of them knew. `scripts/gen-atlas-swift.mjs` exists for exactly
 * this reason and this follows it: the checked-in artefact is generated, and the
 * generator is the thing that is reviewed.
 *
 * Output: `native/Onyx/Resources/report/index.html`, one self-contained
 * file — inlined script, inlined CSS, no external request of any kind. A
 * `WKWebView` loads it from the app bundle with no network available.
 *
 *   node scripts/gen-report-bundle.mjs
 */
import { build } from 'vite'
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT_DIR = join(ROOT, 'native/Onyx/Resources')
const TMP = join(ROOT, '.report-bundle-tmp')

/**
 * The stylesheet.
 *
 * Dark-only, and deliberately NOT the app's SwiftUI tokens: this is a document
 * inside a web view, and the two type stacks cannot share a source. What it does
 * share is the palette's INTENT — a near-black ground, one accent, and numerals
 * that hold their column.
 *
 * The rules that are load-bearing rather than decorative are commented; the rest
 * is ordinary document styling.
 */
const CSS = `
:root {
  color-scheme: dark;
  --bg: #000000;
  --text: rgba(255,255,255,0.92);
  --muted: rgba(255,255,255,0.62);
  --faint: rgba(255,255,255,0.38);
  --line: rgba(255,255,255,0.08);
  --accent: #7C5CFF;
  --accent-2: #38E1FF;
  --good: #3DFFB0;
  --warn: #FFB13D;
  --bad: #FF453A;
  --info: #38E1FF;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--text); }
body {
  font: 16px/1.55 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  /* The web view is edge-to-edge under the navigation bar; the native side
     sets the top inset, this owns the sides and the bottom. */
  padding: 8px 16px 48px;
  -webkit-text-size-adjust: 100%;
}
/* ── THE DOCUMENT'S OWN H1 IS NOT A PAGE TITLE ─────────────────────────
   A report opens with its full name as an \`# H1\`, and at browser-default
   sizing that is three lines of 2rem type before any content. The native
   navigation bar already says which report this is, so the H1 is a
   masthead: small, muted, and out of the way. */
h1 {
  margin: 0 0 12px;
  font-size: 0.95rem; font-weight: 600; letter-spacing: 0.01em;
  color: var(--muted);
}
h2.part {
  margin: 32px 0 4px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--line);
  font-size: 1.25rem; font-weight: 650; letter-spacing: -0.02em;
}
h3.section {
  margin: 24px 0 6px;
  font-size: 1rem; font-weight: 600; letter-spacing: 0.01em;
  color: var(--accent-2);
}
.section-glyph { margin-right: 6px; }

/* ── A HEADING THE PARSER DID NOT CLAIM ─────────────────────────────────
   \`## 🟢 QUICK VERDICT — the cut is on rails\` is not a SECTION: the
   reader requires a shouted title, and that one carries a lowercase
   clause. It is therefore body text, and markdown renders it as an
   \`h2\` — at browser-default sizing, which is larger than the real
   section headings above it and reads as the most important thing on the
   page. These rules put the document's own heading levels back in
   proportion. */
.md h1, .md h2, .md h3, .md h4 {
  margin: 18px 0 6px;
  font-weight: 650;
  letter-spacing: -0.01em;
}
.md h1 { font-size: 1.05rem; }
.md h2 { font-size: 1rem; }
.md h3, .md h4 { font-size: 0.95rem; color: var(--muted); }
p { margin: 8px 0; }
a { color: var(--accent-2); }
strong { font-weight: 650; }

/* ── ASCII must survive verbatim ─────────────────────────────────────────
   Ligatures off so \`─\` and \`═\` cannot fuse into a single glyph, and
   \`pre\` never wraps — a wrapped ASCII table is not a table. It scrolls
   inside its own box instead. */
pre.report-pre {
  overflow-x: auto;
  white-space: pre;
  tab-size: 2;
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
  font-variant-ligatures: none;
  font-size: 12px; line-height: 1.35;
  background: rgba(255,255,255,0.03);
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 10px 12px;
  margin: 12px 0;
}
pre.report-pre code { font: inherit; }

/* Tables scroll inside their own box rather than forcing the page sideways. */
.table-wrap, .md table {
  overflow-x: auto;
  border: 1px solid var(--line);
  border-radius: 12px;
  margin: 12px 0;
}
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { padding: 7px 10px; text-align: left; border-bottom: 1px solid var(--line); }
th { color: var(--muted); font-weight: 600; white-space: nowrap; }
tbody tr:nth-child(even) { background: rgba(255,255,255,0.02); }
tbody tr:last-child td { border-bottom: none; }
/* Numerals hold their column as values change length. */
.num, td { font-variant-numeric: tabular-nums; }

/* The banner box at the head of a report. */
.hero {
  margin: 16px 0;
  padding: 14px 16px;
  border: 1px solid var(--line);
  border-radius: 20px;
  background: linear-gradient(135deg, rgba(124,92,255,0.18), rgba(56,225,255,0.06));
}
.hero-headline { margin: 0 0 8px; font-size: 1.05rem; font-weight: 650; }
.hero-chips { display: flex; flex-wrap: wrap; gap: 6px; }
.hero-line { margin: 6px 0 0; color: var(--muted); font-size: 13px; }
.chip {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  background: rgba(255,255,255,0.08);
  color: var(--muted);
  font-size: 11px;
}

/* Status leads: a badge, then the sentence. */
p.lead { margin: 10px 0; }
.badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px; font-weight: 600;
  margin-right: 8px;
}
.badge.good { background: rgba(61,255,176,0.16); color: var(--good); }
.badge.warn { background: rgba(255,177,61,0.16); color: var(--warn); }
.badge.bad  { background: rgba(255,69,58,0.16);  color: var(--bad); }
.badge.info { background: rgba(56,225,255,0.16); color: var(--info); }
.lead-rest { color: var(--text); }

/* Text progress bars and the TDEE ladder share a track. */
.bars, .ladder { margin: 12px 0; display: grid; gap: 8px; }
.bar-row, .ladder-row {
  display: grid;
  /* Three columns, always. A fourth child — the "adopted" chip — used to wrap
     onto a full-width row of its own and read as a separate anchor. */
  grid-template-columns: minmax(0,1fr) 96px minmax(0,auto);
  align-items: center;
  gap: 8px;
  font-size: 13px;
}
.ladder-value { display: flex; align-items: center; gap: 6px; justify-content: flex-end; }
.bar-label, .ladder-label { color: var(--muted); overflow-wrap: anywhere; }
.bar-track {
  height: 6px; border-radius: 999px;
  background: rgba(255,255,255,0.07);
  overflow: hidden;
}
.bar-fill { display: block; height: 100%; border-radius: 999px; background: var(--accent); }
.bar-fill[data-tone="over"] { background: var(--warn); }
.bar-fill[data-tone="good"] { background: var(--good); }
.bar-fill[data-tone="mid"]  { background: var(--accent-2); }
.bar-fill[data-tone="low"]  { background: var(--bad); }
.bar-value { color: var(--text); font-variant-numeric: tabular-nums; }

@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
`

async function main() {
  rmSync(TMP, { recursive: true, force: true })

  // One IIFE, everything inlined, no code splitting and no module preload — the
  // output has to be a single file that a `file://` load can run.
  await build({
    root: ROOT,
    logLevel: 'warn',
    configFile: false,
    build: {
      outDir: TMP,
      emptyOutDir: true,
      target: 'safari16',
      // Not minified, and not because it would be hard: this file is read from
      // the app bundle with no download in front of it, so the only thing
      // minification buys is a diff nobody can review. `esbuild` is also no
      // longer a Vite dependency, and adding one to shrink a local file would
      // be a poor trade.
      minify: false,
      lib: {
        entry: join(ROOT, 'scripts/src/report/renderer.ts'),
        formats: ['iife'],
        name: 'OnyxReport',
        fileName: () => 'renderer.js',
      },
    },
  })

  const script = readFileSync(join(TMP, 'renderer.js'), 'utf8')

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<!-- No scaling: the native side owns the text size, and a report that pinch-zooms
     inside a native scroll view fights the gesture that scrolls it. -->
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<!-- Nothing may be fetched. The bundle is self-contained and a report body is
     arbitrary pasted text, so a remote image in one must not become a request. -->
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:;">
<title>Onyx report</title>
<style>${CSS}</style>
</head>
<body>
<div id="root"></div>
<script>${script}</script>
</body>
</html>
`

  mkdirSync(OUT_DIR, { recursive: true })
  // A flat, uniquely-named file rather than `report/index.html`: Xcode copies
  // resources into the bundle root unless the folder is a folder REFERENCE, so
  // a nested `index.html` is a lookup that works on one machine's project file
  // and not on the next regeneration.
  writeFileSync(join(OUT_DIR, 'ReportRenderer.html'), html, 'utf8')
  rmSync(TMP, { recursive: true, force: true })

  const kb = (Buffer.byteLength(html) / 1024).toFixed(0)
  console.log(`native/Onyx/Resources/ReportRenderer.html  (${kb} kB, self-contained)`)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
