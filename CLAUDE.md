## Versioning — NOT OPTIONAL

`package.json` → `"version"` is the single source of truth for the version of
every surface: the app, the widget extension and the watch app. Nothing else
is hand-edited.

**On the successful completion of any sprint, wave, or major feature — before
the merge commit — you MUST:**

1. Decide the bump from what shipped: MAJOR for a migration the user has to be
   told about, MINOR for a wave/sprint/engine that lands new capability, PATCH
   for a hotfix wave with no new capability.
2. Set `"version"` in `package.json` to that number.
3. Run `npm run version:sync`, then `cd native && xcodegen generate`.
4. Append a release section to `docs/CHANGELOG.md` — copy the template at the
   bottom of that file. Name the surfaces; a reader must be able to tell what
   they can now do, or what stopped being wrong.
5. Confirm `npm run version:check` passes. It is part of `npm run check`, so a
   drifted version fails the gate.

A wave that ships without a version bump and a changelog entry is not finished.
Do not defer either to "the next sprint" — the number and the notes are cheapest
to write while the work is still in the diff in front of you.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
