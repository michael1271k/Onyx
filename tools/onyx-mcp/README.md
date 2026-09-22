# onyx-mcp

An MCP server that gives a desktop model read access to your Onyx data.

It **serves; it does not derive.** The weekly export is built in exactly one
place — `WeeklyExportBuilder` reads the rows, `WeeklyExport.build` renders them
— and the phone files the result in Supabase as an `ExportEnvelope`. This server
hands those envelopes over. It has a service key and could in principle read
`workout_sets` and assemble a week itself; it must not, because a second
implementation of the extraction in a second language is how two surfaces come
to disagree about the same week, silently, for months.

The live-row tools are therefore deliberately thin: a filter, a limit, and the
rows as Postgres holds them.

## Before it can answer

1. **Create the `exports` table.** Its DDL is `w7-exports.sql`, under
   "Appendix — applied server migrations" in `docs/CHANGELOG.md`; paste it into
   the Supabase SQL editor. Until the `exports` table exists, `list_exports`, `get_export` and `get_latest_markdown`
   report a 404 naming the missing table.
2. **Export a week from the phone.** History → a week → Export → pick a range →
   complete the share sheet. The phone files a copy as it goes. A share sheet
   that is cancelled files nothing, which is deliberate.

## Install

```bash
npm --prefix tools/onyx-mcp install
npm --prefix tools/onyx-mcp run smoke
```

The smoke test needs no credentials: with none set, every tool answers
`Not configured: …`, which is itself the assertion — a tool that can report its
own missing configuration is a tool that registered, took its arguments and ran
its handler. With credentials in the environment it goes further and lists your
real exports.

## Environment

| Variable | What |
|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | The **service** key. Bypasses RLS. Never ship it. |
| `ONYX_USER_ID` | Your `auth.users` id — Supabase → Authentication → Users. |

The service key bypasses RLS by design, so every query filters on `user_id`
explicitly. That filter is the only thing between this process and somebody
else's rows, which is why it is applied in one place rather than at five call
sites. This is a **local** server on your own machine reading your own account;
do not deploy it anywhere a key would be exposed.

## Register it

### Claude Code

```bash
claude mcp add onyx --scope user \
  --env SUPABASE_URL=https://YOUR_REF.supabase.co \
  --env SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_KEY \
  --env ONYX_USER_ID=YOUR_USER_ID \
  -- node /ABSOLUTE/PATH/TO/Onyx/tools/onyx-mcp/server.mjs
```

### Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "onyx": {
      "command": "node",
      "args": ["/ABSOLUTE/PATH/TO/Onyx/tools/onyx-mcp/server.mjs"],
      "env": {
        "SUPABASE_URL": "https://YOUR_REF.supabase.co",
        "SUPABASE_SERVICE_ROLE_KEY": "YOUR_SERVICE_KEY",
        "ONYX_USER_ID": "YOUR_USER_ID"
      }
    }
  }
}
```

Absolute paths in both: the server is launched with no working directory you
control. Restart the client afterwards.

## Tools

| Tool | Arguments | Answers |
|---|---|---|
| `list_exports` | `since?`, `limit` | The spans the phone has filed, newest first. Ids and dates, not documents. |
| `get_export` | `id` | The whole envelope — `{ version, rangeStart, rangeEnd, generatedAt, input, markdown }`. |
| `get_latest_markdown` | — | The most recent span's document. **Start here.** |
| `query_sets` | `since`, `until?`, `limit` | Raw `workout_sets` with their session's start. The table, not the week. |
| `get_daily_scores` | `from`, `to` | Raw `daily_scores`. The app's own opinion of each day. |

All five are read-only and annotated as such.

### A cut answer says it was cut

Neither row tool pages. Five local tools do not need a cursor — but a page
truncated at the limit and a genuinely short page look identical over
PostgREST, so both prepend a line stating the row count, whose rows they are,
the window they cover, and, when the result is exactly the size of the limit,
that it was **truncated**. Both order newest-first for the same reason: if rows
must be lost, the ones to lose are the oldest.

A bare `[]` is the one answer this server must never give by accident — a
wrong `ONYX_USER_ID` returns it from every tool, silently, and looks exactly
like an athlete who has never trained. Hence the user id in every count line.

### Why `daily_scores` is a separate tool and not in the document

The export document carries no Score and no Battery anywhere — both are the
app's opinion of a week, and a number the reader cannot recompute from the rows
beside it is one it has to either trust or ignore. `ReportsGoldenTests` bans the
words outright. So the scores are reachable, and reachable *separately*, for the
question that is actually about the app's scoring rather than about the
training.

### The column names are the server's, not the phone's

Introspected live on 2026-09-22, because the obvious guesses are wrong in two
places: `workout_sets` has `set_number`, not the `set_index` the phone's GRDB
mirror calls it, and `workout_sessions` has **no `date` column at all** — the day
lives in `started_at` and `day_key`. `query_sets` filters on the session's start
rather than on the set's `created_at`, deliberately: a set logged retroactively
was written today and performed last week, and "sets since X" is a question
about when they were performed.

## Paste-back

Every export ends with `## 9 · PASTE-BACK`, which tells the model how to answer
with targets the app can apply: a fenced `onyx-targets` block of JSON. Paste the
model's report into Onyx → Reports → a week, and "Apply targets" appears with a
diff of exactly what it would change. Nothing is written until that sheet is
confirmed, and whatever date the block names, the targets apply from today — a
report about last week never re-grades last week, and one about next week does
not freeze today's numbers waiting for it.
