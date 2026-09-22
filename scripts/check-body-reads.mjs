#!/usr/bin/env node
// Gate: no synchronous store read inside a SwiftUI `var body`.
//
// A read that feeds a view goes through ValueObservation or an @Observable
// model loaded in `.task`. A read evaluated while the ViewBuilder runs blocks
// the main thread on every layout pass, and SwiftUI runs `body` far more often
// than anybody writing it expects. (Onyx Expansion W6, decision 16.)
//
// Reads inside an ACTION closure (`.task`, `.onAppear`, a Button's action …)
// are not render-time and are allowed — the scanner walks the brace stack and
// asks which construct opened each enclosing block.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const TARGETS = [
  "native/Onyx",
  "native/OnyxWatch",
  "native/OnyxWidgets",
  "native/Packages/OnyxUI/Sources",
];

// Blocks that run in response to something, not while drawing.
const ACTION =
  /(^|[^A-Za-z0-9_])(task|onAppear|onDisappear|onChange|onReceive|onSubmit|onDelete|onMove|refreshable|swipeActions|onKeyPress|dropDestination|Button|Task|assumeIsolated|action:|perform:)\s*(\(|\{)/;
// `.toolbar`, `.contextMenu`, `.alert` and `.confirmationDialog` are NOT here:
// their closures are ViewBuilders, evaluated while the screen draws. Only a
// block that runs in RESPONSE to something belongs above.
// Any computed property or function that returns a View is render-time,
// not just `body` itself: a card extracted into `private var volumeCard`
// runs on exactly the same pass.
const BODY =
  /\bvar\s+\w+\s*:\s*some\s+View\b|->\s*some\s+View\s*\{/;
// `environment.database.…` and `self.database.…` are how a view in this repo
// reaches the store — the first spelling of this excluded a leading `.`, so it
// matched the one form the codebase almost never writes and walked past the
// two it does. `model.database` and any other receiver count for the same
// reason: what matters is that a store read is happening while the view draws,
// not whose property it came off.
const READ = /(^|[^A-Za-z0-9_])(?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)*database\s*\./g;

function swiftFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) swiftFiles(p, out);
    else if (name.endsWith(".swift")) out.push(p);
  }
  return out;
}

// Crude but sufficient: drop line comments and string literals so their braces
// and their `database.` mentions do not confuse the brace walk.
// An interpolated literal is kept: `Text("\\(try? database…)")` is a read the
// ViewBuilder performs, and blanking the literal would hide it.
const strip = (line) =>
  line
    .replace(/"(?:[^"\\]|\\.)*"/g, (m) => (m.includes("\\(") ? m : '""'))
    .replace(/\/\/.*$/, "");

// DEBUG scaffolding: a harness seeds an in-memory store and reads it back on
// purpose, and it never ships. Holding it to the rule would mean threading a
// model through every fixture to avoid a cost no user pays.
const SCAFFOLDING = /(Previews|PreviewHarness|PreviewCatalogue|PreviewData)\.swift$/;

function scan(file) {
  const lines = readFileSync(file, "utf8").split("\n");
  const hits = [];
  let stack = []; // one entry per open brace: the text that opened it
  // A modifier's opening brace is often several lines below its own name
  // (`.task(id: Reload(\n  …\n)) {`), so a brace is judged together with the
  // six lines that led to it. Without this every multi-line `.task` read as a
  // ViewBuilder and the scanner reported six reads that were already correct.
  let recent = [];
  let inBody = false;

  for (let i = 0; i < lines.length; i++) {
    const code = strip(lines[i]);

    if (!inBody && BODY.test(code)) {
      inBody = true;
      stack = [];
      recent = [];
    }
    if (!inBody) continue;

    // Walk the line a character at a time so a read on the SAME line as the
    // closure that allows it (`.task { … database … }`) sees that brace.
    READ.lastIndex = 0;
    let next = READ.exec(code);
    for (let c = 0; c < code.length; c++) {
      while (next && next.index + next[1].length < c) next = READ.exec(code);
      if (
        next &&
        next.index + next[1].length === c &&
        stack.length > 0 &&
        !stack.some((s) => ACTION.test(s))
      ) {
        hits.push({ line: i + 1, text: lines[i].trim() });
      }
      if (code[c] === "{") {
        stack.push(recent.join(" ") + " " + code.slice(0, c + 1));
      } else if (code[c] === "}") {
        stack.pop();
        if (stack.length === 0) {
          inBody = false;
          break;
        }
      }
    }
    recent.push(code.trim());
    if (recent.length > 6) recent.shift();
  }
  return hits;
}

let total = 0;
for (const target of TARGETS) {
  for (const file of swiftFiles(join(ROOT, target))) {
    if (SCAFFOLDING.test(file)) continue;
    for (const hit of scan(file)) {
      console.error(`${relative(ROOT, file)}:${hit.line}: ${hit.text}`);
      total++;
    }
  }
}

if (total) {
  console.error(
    `\n${total} synchronous store read${total === 1 ? "" : "s"} inside a SwiftUI view builder.\n` +
      "Move each into a ValueObservation or an @Observable model loaded in .task."
  );
  process.exit(1);
}
console.log("check:body — no store reads inside a view body");
