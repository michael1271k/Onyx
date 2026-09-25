-- ════════════════════════════════════════════════════════════════════════════
-- precision-c-counts.sql — the "Working" figure beside "Sets" (Precision, Lane C)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS BEFORE THE BUILD REACHES THE PHONE ────────────────────────────
-- From 9.3.0 the phone writes `workout_sessions.working_set_count` on every
-- close, edit and one-time recount (founder decision Q10), and PostgREST
-- rejects an upsert naming a column it does not have (PGRST204). The outbox
-- holds and retries the item, but a pull that lands meanwhile writes the
-- server's old row over the local one. So this runs first. A row the phone
-- has not recounted sends no key at all (`encodeIfPresent`) and is unaffected.
--
-- ── WHAT IT DOES ───────────────────────────────────────────────────────────
-- §1  adds `working_set_count int`, NULLABLE, no default, beside `set_count`.
--     `set_count` keeps its name and becomes "Sets": everything performed —
--     working, warm-up and cardio bouts, a pair once, ghosts never.
--     `working_set_count` is "Working": the rule every screen used to headline.
-- §2  tells PostgREST to reload its schema cache, then reports the result.
--
-- No new table, no new RLS policy: the column sits on a table whose policies
-- already scope every column to `auth.uid() = user_id`. The backfill of both
-- columns for every user is `precision-c-backfill-sets.sql`, run after this.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · THE COLUMN ─────────────────────────────────────────────────────────
ALTER TABLE public.workout_sessions
  ADD COLUMN IF NOT EXISTS working_set_count int;

COMMENT ON COLUMN public.workout_sessions.working_set_count IS
  'Precision Lane C (Q10): working sets — no warm-up, no cardio bout, no ghost, a unilateral pair once. `set_count` is every set performed (pair once, ghosts excluded). Nullable: NULL = not recounted since 9.3.0.';

-- ── 2 · RELOAD + AFTER ─────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';

SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'workout_sessions'
   AND column_name IN ('set_count', 'working_set_count')
 ORDER BY column_name;

COMMIT;
