-- ════════════════════════════════════════════════════════════════════════════
-- w7-exports.sql — the drop-box the Onyx MCP server reads (Onyx Expansion, W7)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS BEFORE THE BUILD REACHES THE PHONE ────────────────────────────
-- Same rule as `w1-onyx-wire.sql` and `w6-export-v6.sql`, and for w6's reason:
-- nothing here rewrites history, so a late run costs no data — but the app
-- POSTs an `exports` row the first time the export chip is tapped, and
-- PostgREST rejects an insert into a table it cannot find. Unlike the outbox's
-- rows this one is NOT retried (`ExportService.upload` is one best-effort
-- request, documented as such in its own header), so a week exported before
-- this file runs never reaches the server at all. The markdown still reaches
-- you through the share sheet; only the MCP server's copy is lost.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
-- §1  creates `public.exports` — one row per (athlete, span), holding the
--     whole `ExportEnvelope` as `jsonb`.
-- §2  gives it RLS in the `(select auth.uid()) = user_id` INITPLAN form every
--     other table here uses, `to authenticated` and never `to public`.
-- §3  reports the result.
--
-- ── WHY THE DOCUMENT IS STORED AND NOT RE-DERIVED ──────────────────────────
-- The MCP server is Node, it has a service key, and it could in principle read
-- `workout_sets` and build a week itself. It must not. The extraction lives in
-- ONE place (`WeeklyExportBuilder` → `WeeklyExport.build`), and a second
-- implementation in a second language is how two surfaces come to disagree
-- about the same week — which is the exact failure this sprint's W7 exists to
-- prevent. So the phone builds the document and files it here, and the server
-- serves what it finds. The server's other tools are raw rows and say so.
--
-- ── AND WHY THE THREE COLUMNS BESIDE THE JSON ──────────────────────────────
-- `range_start`, `range_end` and `version` are copies of fields inside the
-- envelope. Duplicated deliberately: they are the only things anything filters
-- or orders on, and an index on a `date` column is a different conversation
-- from an index on a `jsonb` path. The envelope remains the source of truth;
-- if they ever disagree, the envelope is right.
--
-- ── THE KEY IS THE SPAN, SO A RE-EXPORT REPLACES ───────────────────────────
-- `(user_id, range_start, range_end)`. Exporting the same span twice — sharing
-- "last complete week" on Monday and again on Tuesday — must leave one row, not
-- two documents differing only by their timestamp. `ExportService.conflict` is
-- this same tuple, spelled in Swift.
--
-- ── WHAT THIS FILE COULD NOT VERIFY, AND YOU SHOULD ────────────────────────
-- Introspected live on 2026-09-22 through PostgREST's OpenAPI document:
-- `exports` does not exist (35 tables, none of them this one); every table
-- that carries `user_id` declares it `uuid NOT NULL`; `created_at` is
-- `timestamptz DEFAULT now()` on all 21 tables that have one; and both
-- `gen_random_uuid()` and `extensions.uuid_generate_v4()` are live column
-- defaults elsewhere in this schema. What could NOT be read from this machine
-- is the BODY of any existing RLS policy — `pg_policies` is not reachable
-- through PostgREST and there is no database password here. §2 below is
-- therefore written to match `w6-export-v6.sql`, which you ran, rather than to
-- match an introspection. §3 prints the policies it created; compare them with
-- another table's before you trust them.
--
-- ── EXPECTED COUNTS ────────────────────────────────────────────────────────
-- Before: `exports` does not exist. After: 0 rows. The first row arrives the
-- first time the export chip's share sheet is actually completed.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
-- If `exists` is already true the table is in place and §1 is a no-op.
SELECT to_regclass('public.exports') IS NOT NULL AS exports_exists;

-- ── 1 · The table ───────────────────────────────────────────────────────────
-- NOT mirrored into the phone's GRDB store, and deliberately: the app never
-- reads this table. Mirroring it would mean carrying every document ever
-- exported in the local store, for no reader. So it is absent from
-- `native/schema/supabase.json` on purpose, and `npm run check:mirror` is not
-- wrong about it.
--
-- `gen_random_uuid()` and not `extensions.uuid_generate_v4()`: both are live in
-- this schema, and the newer tables (`cardio_logs`, `stress_logs`, `plans`,
-- `doms_logs`, …) all use the former.
CREATE TABLE IF NOT EXISTS public.exports (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    range_start date NOT NULL,
    range_end   date NOT NULL,
    version     integer NOT NULL,
    envelope    jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- A span ends no earlier than it starts, and is no longer than the app's own
-- cap. `ExportRange.maxDays` is 28 and `ExportRange.clamp` enforces it on the
-- phone; the constraint is here so a client that forgot cannot file a document
-- covering a year. 31 rather than 28 — the column should refuse an ABSURD span,
-- not police a product decision that may be widened next week.
ALTER TABLE public.exports DROP CONSTRAINT IF EXISTS exports_range_check;
ALTER TABLE public.exports
  ADD CONSTRAINT exports_range_check
  CHECK (range_end >= range_start AND range_end - range_start <= 31);

-- ONE DOCUMENT PER SPAN PER ATHLETE. This is what makes the phone's upsert an
-- upsert: `ExportService.conflict` names this tuple, and without the unique
-- index PostgREST's `on_conflict` has nothing to resolve against and the
-- request fails.
CREATE UNIQUE INDEX IF NOT EXISTS exports_user_range
  ON public.exports (user_id, range_start, range_end);

-- The read the MCP server's `list_exports` makes: this athlete's documents,
-- newest span first.
CREATE INDEX IF NOT EXISTS exports_user_recent
  ON public.exports (user_id, range_end DESC);

-- ── AND WHY THERE IS NO `updated_at` ───────────────────────────────────────
-- Every other table here has one, and this one had one too until it was read
-- properly: `DEFAULT now()` fires on INSERT only, and
-- `PostgRESTMirrorRemote.upsertRow` STRIPS both timestamp columns from every
-- body it sends. A re-export of the same span would therefore leave the column
-- frozen at the first insert while the envelope beside it carried a newer
-- `generatedAt` — a column that is permanently a lie. The envelope's own
-- `generatedAt` is the freshness figure, and it is the one the writer actually
-- sets.

-- ── 2 · Row level security ──────────────────────────────────────────────────
-- The `(select auth.uid()) = user_id` INITPLAN form, so the check is evaluated
-- once per query rather than once per row, and `TO authenticated` — never
-- `TO public`, which is the shape that leaked in W11.
--
-- The MCP server reads this table with the SERVICE key, which bypasses RLS by
-- design. That is the founder's own key on the founder's own machine, reading
-- the founder's own rows; it is never shipped and never given to a client.
--
-- Every statement re-runnable: `drop policy if exists` before each `create`.
ALTER TABLE public.exports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS exports_select_own ON public.exports;
CREATE POLICY exports_select_own ON public.exports
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS exports_insert_own ON public.exports;
CREATE POLICY exports_insert_own ON public.exports
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS exports_update_own ON public.exports;
CREATE POLICY exports_update_own ON public.exports
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS exports_delete_own ON public.exports;
CREATE POLICY exports_delete_own ON public.exports
  FOR DELETE TO authenticated
  USING ((select auth.uid()) = user_id);

-- ── 3 · After ───────────────────────────────────────────────────────────────
-- `exports_exists` must be true, `rls_enabled` must be true, and there must be
-- exactly FOUR policies, all of them `authenticated`. If any row below comes
-- back wrong, ROLLBACK rather than COMMIT.
SELECT to_regclass('public.exports') IS NOT NULL AS exports_exists;

SELECT relrowsecurity AS rls_enabled
  FROM pg_class WHERE oid = 'public.exports'::regclass;

SELECT policyname, cmd, roles::text, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'exports'
 ORDER BY policyname;

-- The columns, for comparison against `ExportService.Row` in
-- `native/Packages/OnyxData/Sources/OnyxData/History/ExportService.swift`.
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'exports'
 ORDER BY ordinal_position;

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if anything in §3 came back wrong
