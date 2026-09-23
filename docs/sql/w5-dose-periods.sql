-- ════════════════════════════════════════════════════════════════════════════
-- w5-dose-periods.sql — a supplement's dose history (App Store sprint, W5)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS BEFORE THE BUILD REACHES THE PHONE ────────────────────────────
-- From 7.13.0 the phone writes `custom_supplements.dose_periods` the first time
-- a dose is changed, and PostgREST rejects an upsert naming a column it does
-- not have (PGRST204). The outbox HOLDS that item and retries it — nothing is
-- lost on the server's side — but the table is pulled WHOLE, and a pull that
-- lands while the push is held writes the server's old row over the local one:
-- the new dose and its history are reverted on the phone. So this runs first.
-- A row that never had its dose changed pushes no `dose_periods` key at all
-- and is unaffected either way.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
-- §1  adds `dose_periods jsonb`, NULLABLE, no default, beside `schedule`.
-- §2  a CHECK that it is null or a JSON array — the only shape the phone reads.
-- §3  tells PostgREST to reload its schema cache, then reports the result.
--
-- No new table, no new RLS policy (founder decision 4): the column sits on a
-- table whose policies already scope every column to `auth.uid() = user_id`.
-- No backfill: null means "this item has only ever had the dose on its row",
-- which is true of all ten rows today.
--
-- ── THE SHAPE ──────────────────────────────────────────────────────────────
-- An array of the doses the item USED to be taken at, oldest first:
--
--   [{"until": "2026-09-23", "dose": "300 mg", "doseAmount": 300,
--     "doseUnit": "mg"}]
--
-- `until` is the first day that dose was NOT in force — the day it was
-- changed. The row's own `dose` / `dose_amount` / `dose_unit` / `schedule`
-- trainingDose + restDose are the dose from the last `until` onward, exactly as
-- they have always been, so every reader that does not know this column still
-- reads today's dose correctly. camelCase inside, like `schedule` beside it;
-- absent keys are nulls. `OnyxCore.Supplements.doseAt(_:on:)` is the one
-- reader.
--
-- ── WHAT THIS FILE COULD NOT VERIFY, AND YOU SHOULD ────────────────────────
-- Introspected live on 2026-09-23 through PostgREST's OpenAPI document:
-- `custom_supplements` has 14 columns, `dose_periods` is not one of them,
-- `schedule` and `micros` are `jsonb`, `archived_at` is `timestamptz`,
-- `user_id` is NOT NULL, 10 rows, 0 archived. `pg_constraint` and
-- `pg_policies` are not reachable through PostgREST, so §2's constraint name
-- was checked against nothing; §3 prints it back.
--
-- ── EXPECTED COUNTS ────────────────────────────────────────────────────────
-- Before: `has_dose_periods` false. After: true, 10 rows, 0 with a history.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'custom_supplements'
      AND column_name = 'dose_periods'
) AS has_dose_periods;

-- ── 1 · The column ──────────────────────────────────────────────────────────
-- Read by `Supplements.doseAt` (the Stack checklist, the day's micronutrient
-- credit, the Stack tile's denominator and the weekly export); written only by
-- `AppDatabase.updateCustomSupplement` when the dose actually changes.
ALTER TABLE public.custom_supplements
    ADD COLUMN IF NOT EXISTS dose_periods jsonb;

COMMENT ON COLUMN public.custom_supplements.dose_periods IS
    'The doses this item USED to be taken at, oldest first: [{"until": "YYYY-MM-DD", "dose", "doseAmount", "doseUnit", "trainingDose", "restDose"}]. until = the day the dose changed (exclusive). The row''s own dose columns are the dose from the last until onward. Null = never changed. Read by Supplements.doseAt; appended, never rewritten.';

-- ── 2 · The shape ───────────────────────────────────────────────────────────
-- Drop-then-add so the file can be run twice.
ALTER TABLE public.custom_supplements
    DROP CONSTRAINT IF EXISTS custom_supplements_dose_periods_is_array,
    ADD CONSTRAINT custom_supplements_dose_periods_is_array
        CHECK (dose_periods IS NULL OR jsonb_typeof(dose_periods) = 'array');

COMMIT;

-- ── 3 · After ───────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';

SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'custom_supplements'
  AND column_name = 'dose_periods';

SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.custom_supplements'::regclass
  AND conname = 'custom_supplements_dose_periods_is_array';

SELECT count(*) AS rows,
       count(*) FILTER (WHERE dose_periods IS NOT NULL) AS with_history
FROM public.custom_supplements;
