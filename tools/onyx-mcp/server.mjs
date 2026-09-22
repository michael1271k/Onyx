#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// onyx-mcp — the desktop's door into the Onyx database (Onyx Expansion, W7).
//
// ── IT SERVES. IT DOES NOT DERIVE. ──────────────────────────────────────────
// The weekly export is built in exactly one place — `WeeklyExportBuilder` reads
// the rows, `WeeklyExport.build` renders them — and the phone files the result
// in `public.exports` as an `ExportEnvelope`. This server hands those envelopes
// over. It has a service key and it could in principle read `workout_sets` and
// assemble a week itself; it must not, because a second implementation of the
// extraction in a second language is how two surfaces come to disagree about
// the same week, silently, for months.
//
// The live-row tools below are therefore deliberately THIN: a filter, a limit,
// and the rows as Postgres holds them. They answer "what is actually in the
// table", which is a different question from "what does the week look like",
// and they say so in their own descriptions.
//
// ── ENVIRONMENT ─────────────────────────────────────────────────────────────
//   SUPABASE_URL                 https://<ref>.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY    the service key — bypasses RLS, never shipped
//   ONYX_USER_ID                 the athlete's auth.users id
//
// The service key bypasses RLS by design, so every query here filters on
// `user_id` EXPLICITLY. That filter is the only thing standing between this
// process and somebody else's rows, which is why it is applied in one place
// (`select`) rather than at five call sites.
// ─────────────────────────────────────────────────────────────────────────────

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const URL_BASE = process.env.SUPABASE_URL?.replace(/\/+$/, "");
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const USER_ID = process.env.ONYX_USER_ID;

/** Missing configuration is reported per call, not at startup: a server that
 *  exits before it registers its tools gives the client nothing to show. The
 *  three are module constants, so the string is one too. */
const MISSING_ENV = (() => {
  const missing = [
    !URL_BASE && "SUPABASE_URL",
    !KEY && "SUPABASE_SERVICE_ROLE_KEY",
    !USER_ID && "ONYX_USER_ID",
  ].filter(Boolean);
  return missing.length
    ? `Not configured: ${missing.join(", ")} ${missing.length === 1 ? "is" : "are"} not set. ` +
      `See tools/onyx-mcp/README.md.`
    : null;
})();

/** One PostgREST GET, always scoped to this athlete.
 *
 *  `user_id` is set AFTER the spread, deliberately. With it first, a caller
 *  passing its own `user_id` key would silently replace the one filter this
 *  whole design rests on — and "nothing does that today" is not the same claim
 *  as "nothing can". */
async function select(table, params) {
  const query = new URLSearchParams({ ...params, user_id: `eq.${USER_ID}` });
  const response = await fetch(`${URL_BASE}/rest/v1/${table}?${query}`, {
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, Accept: "application/json" },
    // A hung socket must not mean a tool call that never returns: the client
    // waits forever with nothing to show.
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) {
    const body = await response.text();
    // The FIX goes in the message, not only in a comment. The commonest
    // failure by far is `exports` not existing yet, and the model reading this
    // is the one who has to say what to do about it.
    const hint =
      response.status === 404
        ? ` — the table does not exist. Run docs/sql/w7-exports.sql in the Supabase SQL editor.`
        : response.status === 401 || response.status === 403
          ? ` — check SUPABASE_SERVICE_ROLE_KEY.`
          : "";
    throw new Error(`${table}: HTTP ${response.status}${hint} ${body.slice(0, 400)}`);
  }
  return response.json();
}

/** Rows, with the two things a bare `[]` cannot say: whose they are, and
 *  whether the answer was cut off.
 *
 *  ── A TRUNCATED PAGE AND A SHORT PAGE LOOK IDENTICAL ────────────────────
 *  `PostgRESTRemote.swift` says so in its own header and pages by keyset to
 *  avoid it. This server does not page — five local tools do not need a cursor
 *  — so it does the next honest thing and SAYS when a result is the size of the
 *  limit, because a model reasoning confidently about a cut dataset is worse
 *  than a model told it has one. */
function rows(list, { limit, window }) {
  const note = [
    `${list.length} row${list.length === 1 ? "" : "s"} for user ${USER_ID}${window ? `, ${window}` : ""}.`,
    limit && list.length >= limit
      ? `TRUNCATED at the limit of ${limit} — there may be more. Narrow the range or raise the limit.`
      : null,
  ]
    .filter(Boolean)
    .join(" ");
  return ok(`${note}\n\n${JSON.stringify(list, null, 2)}`);
}

/** Every tool returns text; structured payloads go through as pretty JSON so a
 *  model can read them and a human can debug them in the same transcript. */
function ok(value) {
  // `?? ""` and not a bare stringify: `JSON.stringify(undefined)` returns the
  // VALUE undefined, and `{ type: "text", text: undefined }` fails the SDK's
  // result schema — the client then shows an opaque protocol error instead of
  // whatever this was trying to say.
  const text = typeof value === "string" ? value : (JSON.stringify(value, null, 2) ?? "");
  return { content: [{ type: "text", text }] };
}

function fail(message) {
  return { content: [{ type: "text", text: message }], isError: true };
}

/** Wrap a handler so a missing key or a dead network is an actionable tool
 *  error rather than a stack trace the client shows as a crash. */
function guarded(handler) {
  return async (args) => {
    if (MISSING_ENV) return fail(MISSING_ENV);
    try {
      return await handler(args);
    } catch (error) {
      return fail(String(error?.message ?? error));
    }
  };
}

const ISO_DATE = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "ISO date, YYYY-MM-DD");
const READ_ONLY = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true };

const server = new McpServer({ name: "onyx", version: "1.0.0" });

// ── The exports the phone already built ──────────────────────────────────────

server.registerTool(
  "list_exports",
  {
    title: "List Onyx exports",
    description:
      "Every weekly export this athlete's phone has filed, newest span first. " +
      "Returns the span, the envelope version and the id — not the document. " +
      "Use get_export or get_latest_markdown for the content.",
    inputSchema: {
      since: ISO_DATE.optional().describe("Only spans ending on or after this date."),
      limit: z.number().int().min(1).max(100).default(20).describe("How many rows."),
    },
    annotations: READ_ONLY,
  },
  guarded(async ({ since, limit }) => {
    const list = await select("exports", {
      select: "id,range_start,range_end,version,created_at",
      order: "range_end.desc",
      limit: String(limit),
      ...(since ? { range_end: `gte.${since}` } : {}),
    });
    return rows(list, { limit, window: since ? `spans ending on or after ${since}` : "all spans" });
  })
);

server.registerTool(
  "get_export",
  {
    title: "Get one Onyx export",
    description:
      "The whole ExportEnvelope for one export id: { version, rangeStart, rangeEnd, " +
      "generatedAt, input, markdown }. `input` is every row the document was built " +
      "from; `markdown` is the document itself. Get the id from list_exports.",
    // `.uuid()` not to stop an attack — `URLSearchParams` already encodes `&`
    // and `=`, so a value cannot introduce a second filter — but so a typo'd id
    // comes back as a readable zod message rather than as a raw Postgres 400.
    inputSchema: { id: z.string().uuid().describe("The export's id, from list_exports.") },
    annotations: READ_ONLY,
  },
  guarded(async ({ id }) => {
    const list = await select("exports", { select: "envelope", id: `eq.${id}`, limit: "1" });
    if (!list.length) return fail(`No export with id ${id}. Try list_exports.`);
    return ok(list[0].envelope);
  })
);

server.registerTool(
  "get_latest_markdown",
  {
    title: "Get the latest Onyx week",
    description:
      "The markdown document of the most recently exported span — the one thing to " +
      "read first when asked to audit the athlete's week. Nine sections; §9 states " +
      "how to answer with targets the app can apply.",
    inputSchema: {},
    annotations: READ_ONLY,
  },
  guarded(async () => {
    const list = await select("exports", {
      select: "range_start,range_end,envelope",
      // `created_at` breaks the tie: two spans can end today — "this week so
      // far" and "last 7 days" — and Postgres would otherwise pick one at
      // whim, so "the latest" would not be stable between two asks.
      order: "range_end.desc,created_at.desc",
      limit: "1",
    });
    if (!list.length) {
      return fail(
        "No exports yet. Open Onyx, tap Export on a week and complete the share sheet — " +
          "the phone files a copy here as it goes."
      );
    }
    const row = list[0];
    // The span, stated outside the document. It was already fetched, and a
    // model handed a week with no external statement of WHICH week has to take
    // the document's own word for it.
    return ok(`Onyx export · ${row.range_start} → ${row.range_end}\n\n${row.envelope?.markdown ?? ""}`);
  })
);

// ── The live tables, raw ─────────────────────────────────────────────────────

server.registerTool(
  "query_sets",
  {
    title: "Read workout sets",
    description:
      "Raw `workout_sets` rows with their session's start, newest session first. This is the " +
      "TABLE, not the week: no deduplication, no pairing of unilateral halves, no " +
      "prescription resolution, no warm-up filtering. For a week as the app " +
      "understands it, use get_export.",
    inputSchema: {
      since: ISO_DATE.describe(
        "Only sets whose SESSION started on or after this date, 00:00 UTC. The bound is " +
          "UTC and not the athlete's own zone, so a session logged late in the evening " +
          "west of UTC falls on the following day here."),
      until: ISO_DATE.optional().describe("And started BEFORE this date, 00:00 UTC. Omit for 'up to now'."),
      limit: z.number().int().min(1).max(1000).default(200).describe("How many rows."),
    },
    annotations: READ_ONLY,
  },
  guarded(async ({ since, until, limit }) => {
    // ── THE SERVER'S COLUMNS, NOT THE PHONE'S ────────────────────────────
    // Introspected live on 2026-09-22, because the obvious guesses are both
    // wrong: `workout_sets` has `set_number`, NOT the `set_index` the local
    // GRDB mirror calls it, and `workout_sessions` has no `date` column at
    // all — the day lives in `started_at` and `day_key`. Filtering on the
    // SESSION's start rather than on the set's `created_at` is deliberate: a
    // set logged retroactively was written today and performed last week, and
    // "sets since X" is a question about when they were performed.
    if (until && until < since) return fail(`"until" (${until}) is before "since" (${since}).`);
    const list = await select("workout_sets", {
      // `pair_id`, `est_1rm_kg` and `quality` are in the projection because the
      // description tells a reader the pairing is NOT done for them — saying
      // that and then withholding the key they would pair on is incoherent.
      select:
        "id,session_id,exercise_id,set_number,exercise_order,pair_id,weight_kg,reps,set_type," +
        "side,rpe,quality,est_1rm_kg,is_pr,created_at,workout_sessions!inner(started_at,day_key,split_day)",
      // One key, both bounds: PostgREST's logical operator on an embedded
      // resource. An object literal cannot hold `workout_sessions.started_at`
      // twice, and this is the documented form rather than a workaround.
      "workout_sessions.and": until
        ? `(started_at.gte.${since},started_at.lt.${until})`
        : `(started_at.gte.${since})`,
      // ── NEWEST FIRST, BECAUSE THIS TRUNCATES ─────────────────────────────
      // Ascending plus a limit cuts off the MOST RECENT sets, which are the
      // ones a weekly audit is about. And by the SESSION's start, not by
      // `created_at`: that column is the server's clock at the moment the
      // outbox drained, so a retroactively logged set and a replayed outbox
      // both order by when they arrived rather than by when they happened.
      order: "workout_sessions(started_at).desc,exercise_order.asc,set_number.asc",
      limit: String(limit),
    });
    return rows(list, {
      limit,
      window: `sessions started ${since}${until ? ` to ${until}` : " onwards"} (UTC), newest first`,
    });
  })
);

server.registerTool(
  "get_daily_scores",
  {
    title: "Read daily scores",
    description:
      "Raw `daily_scores` rows for a date range. These are the app's own opinion of " +
      "each day and are deliberately ABSENT from the export document, which carries " +
      "only figures a reader can recompute. Ask for them when the question is about " +
      "the app's scoring, not about the training.",
    inputSchema: {
      from: ISO_DATE.describe("First date, inclusive."),
      to: ISO_DATE.describe("Last date, inclusive."),
    },
    annotations: READ_ONLY,
  },
  guarded(async ({ from, to }) => {
    // Reversed arguments would return `[]`, which is indistinguishable from
    // "no data" — the one answer this server must never give by accident.
    if (to < from) return fail(`"to" (${to}) is before "from" (${from}).`);
    const limit = 400;
    const list = await select("daily_scores", {
      select: "*",
      date: `gte.${from}`,
      // `and=(…)` and not a second `date` key: an object literal cannot hold
      // one name twice. PostgREST reads this as a one-condition logic group,
      // ANDed with the filters beside it.
      and: `(date.lte.${to})`,
      order: "date.desc",
      limit: String(limit),
    });
    return rows(list, { limit, window: `${from} to ${to}, newest first` });
  })
);

await server.connect(new StdioServerTransport());
