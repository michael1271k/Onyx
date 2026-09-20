-- ════════════════════════════════════════════════════════════════════════════
-- w6-export-v6.sql — the server half of `v33.prescriptions` (export v6)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS *BEFORE* THE BUILD REACHES THE PHONE ──────────────────────────
-- Same rule as `w1-onyx-wire.sql`, for a different reason. Nothing here
-- rewrites history, so a late run costs no data — but the outbox pushes a
-- `prescriptions` row the moment the first block is pasted, and PostgREST
-- rejects an INSERT into a table it cannot find. The row would sit in the
-- outbox retrying until the table existed. Run it first and there is no
-- window.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
-- §1  creates `public.prescriptions` — the CURRENT instruction per movement,
--     appended and never overwritten.
-- §2  gives it RLS in the `(select auth.uid()) = user_id` INITPLAN form every
--     other table here uses, `to authenticated` and never `to public`.
-- §3  reports what `daily_logs.hrv_overnight` already is. It is NOT created:
--     introspected live on 2026-09-20, the column exists and is `boolean`,
--     nullable, no default. It has been there since readiness v9 and was
--     missing from `native/schema/supabase.json`, which is why nothing on the
--     phone could read or write it. §3 exists so a founder running this file
--     against a database that somehow lacks it finds out here rather than from
--     a rejected push.
--
-- ── WHY `prescriptions` IS ITS OWN TABLE AND NOT A COLUMN ──────────────────
-- The export printed `ProgramExercise.wk1Kg` as `prescribed` — the load the
-- program was COMPILED with in July — while the coach moved Incline DB Press
-- 32 → 34, Lat Pulldown 45 → 50 and the RDL 30 → 40. Every `load Δ` in the
-- document was drawn against a number nobody had worked to since the block
-- began.
--
-- A prescription is an instruction with a DATE on it, and its history is the
-- argument a progression review is made of: "the top set went 34 → 36 on the
-- 14th" cannot be said by a row that is UPDATEd in place. So `version` is
-- per-movement and append-only, and `effective_from` is what decides which
-- version was in force on a given session's day.
--
-- ── AND WHY `exercise_key` IS A DISPLAY NAME ───────────────────────────────
-- Because `personal_records.exercise_key` is (introspected 2026-09-19: 81
-- rows, every one a canonical display name — "Seated Cable Row (V-Grip)",
-- never a slug). One movement, one key, across both tables, and no second
-- dictionary between them. `ExerciseAliases.canonicalName` is what produces
-- it on the phone.
--
-- ── EXPECTED COUNTS ────────────────────────────────────────────────────────
-- Before: `prescriptions` does not exist (introspected 2026-09-20 — 34 tables,
-- none of them this one). After: 0 rows. The first row arrives when the
-- founder pastes a block into You → Prescriptions.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
-- If `exists` is already true the table is in place and §1 is a no-op.
SELECT to_regclass('public.prescriptions') IS NOT NULL AS prescriptions_exists;

-- ── 1 · The table ───────────────────────────────────────────────────────────
-- Column for column with `native/schema/supabase.json`, which generates the
-- GRDB mirror. The two must agree or `npm run check:mirror` is checking the
-- wrong shape.
--
-- NULLABILITY IS THE CONTRACT. A prescription that states a load and leaves
-- the count to the plan is a real prescription, and a fabricated `3` is a
-- claim — so everything but the identity, the version, the day and the two
-- enumerated words is nullable. `structure` and `lead_rule` are NOT NULL with
-- defaults because they have a meaningful default (`STRAIGHT`, `NONE`) and an
-- absent one would be indistinguishable from it.
CREATE TABLE IF NOT EXISTS public.prescriptions (
    id             uuid PRIMARY KEY,
    user_id        uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    exercise_key   text NOT NULL,
    version        integer NOT NULL,
    effective_from date NOT NULL,
    load_kg        numeric,
    sets           integer,
    rep_range      text,
    rpe_cap        numeric,
    structure      text NOT NULL DEFAULT 'STRAIGHT',
    set_loads      numeric[],
    lead_rule      text NOT NULL DEFAULT 'NONE',
    notes          text,
    created_at     timestamptz NOT NULL DEFAULT now()
);

-- The two enumerated columns, as CHECKs. `Prescription.Structure` and
-- `Prescription.LeadRule` are the Swift half; a value either side cannot
-- encode is a value that survives a round trip as something else.
ALTER TABLE public.prescriptions DROP CONSTRAINT IF EXISTS prescriptions_structure_check;
ALTER TABLE public.prescriptions
  ADD CONSTRAINT prescriptions_structure_check
  CHECK (structure IN ('STRAIGHT', 'TOPSET_BACKOFF'));

ALTER TABLE public.prescriptions DROP CONSTRAINT IF EXISTS prescriptions_lead_rule_check;
ALTER TABLE public.prescriptions
  ADD CONSTRAINT prescriptions_lead_rule_check
  CHECK (lead_rule IN ('ALTERNATE', 'LEFT', 'RIGHT', 'NONE'));

-- ONE VERSION PER MOVEMENT PER ATHLETE. This is what makes the append-only
-- rule enforceable rather than merely intended: a second `v3` for one movement
-- is refused by the database, so a client that lost track of the ladder cannot
-- write a duplicate ordinal and make "which instruction was in force"
-- ambiguous forever.
CREATE UNIQUE INDEX IF NOT EXISTS prescriptions_user_exercise_version
  ON public.prescriptions (user_id, exercise_key, version);

-- The read the resolver makes: every version of one movement, newest first.
CREATE INDEX IF NOT EXISTS prescriptions_user_exercise
  ON public.prescriptions (user_id, exercise_key, effective_from DESC, version DESC);

-- ── 2 · Row level security ──────────────────────────────────────────────────
-- The `(select auth.uid()) = user_id` INITPLAN form, so the check is evaluated
-- once per query rather than once per row, and `TO authenticated` — never
-- `TO public`, which is the shape that leaked in W11 and is the reason this
-- comment exists.
--
-- Every statement re-runnable: `drop policy if exists` before each `create`.
ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prescriptions_select_own ON public.prescriptions;
CREATE POLICY prescriptions_select_own ON public.prescriptions
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS prescriptions_insert_own ON public.prescriptions;
CREATE POLICY prescriptions_insert_own ON public.prescriptions
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS prescriptions_update_own ON public.prescriptions;
CREATE POLICY prescriptions_update_own ON public.prescriptions
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS prescriptions_delete_own ON public.prescriptions;
CREATE POLICY prescriptions_delete_own ON public.prescriptions
  FOR DELETE TO authenticated
  USING ((select auth.uid()) = user_id);

-- ── 3 · `daily_logs.hrv_overnight` — REPORTED, not created ──────────────────
-- Introspected live on 2026-09-20: it is already there, `boolean`, nullable,
-- no default. `v33.prescriptions` adds the local half. If the row below comes
-- back empty this database is not the one that was introspected — stop, and
-- say so, before the phone starts writing a column that does not exist.
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'daily_logs' AND column_name = 'hrv_overnight';

-- ── 4 · After ───────────────────────────────────────────────────────────────
-- `prescriptions_exists` must be true, `rls_enabled` must be true, and there
-- must be exactly FOUR policies, all of them `authenticated`.
SELECT to_regclass('public.prescriptions') IS NOT NULL AS prescriptions_exists;

SELECT relrowsecurity AS rls_enabled
  FROM pg_class WHERE oid = 'public.prescriptions'::regclass;

SELECT policyname, cmd, roles::text, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'prescriptions'
 ORDER BY policyname;

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if anything in §3 or §4 came back wrong
