-- ════════════════════════════════════════════════════════════════════════════
-- precision-c-backfill-sets.sql — every user's set figures on the Q10 rule
--
-- Paste into the Supabase SQL editor AFTER `precision-c-counts.sql`.
-- Run the whole file; it is ONE idempotent statement plus a VERIFY.
--
-- ── THE RULE (founder decision Q10, `OnyxCore/Sessions/SessionCounts.swift`) ──
--   set_count          = every set performed: normal, failure, dropset, warm-up
--                        (a cardio bout is stored as one warm-up row, so it is
--                        one set); a unilateral L/R pair (rows sharing a
--                        non-empty pair_id) counts ONCE; a ghost never counts.
--   working_set_count  = the same, minus warm-ups (and so minus bouts).
--
-- Only FINISHED sessions that HAVE rows are touched — a session with no
-- `workout_sets` keeps whatever the client that held its sets wrote, exactly
-- as the phone's `SessionEditing.recountAll` behaves (Q11: both ways).
-- `total_volume_kg` is NOT recomputed here: the Hevy basis needs each user's
-- weigh-in and the bodyweight flag per movement, which the phone has and this
-- statement does not; the in-app door `onyx.recount.sets.v1` pushes it.
--
-- Idempotent: the WHERE clause writes only rows whose figures differ, so a
-- second run reports 0 rows updated.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── BEFORE (per user) ──────────────────────────────────────────────────────
WITH counted AS (
  SELECT s.session_id,
         count(DISTINCT COALESCE(NULLIF(s.pair_id::text, ''), s.id::text))
           FILTER (WHERE s.set_type IS DISTINCT FROM 'ghost')                                   AS total,
         count(DISTINCT COALESCE(NULLIF(s.pair_id::text, ''), s.id::text))
           FILTER (WHERE s.set_type IS DISTINCT FROM 'ghost' AND s.set_type IS DISTINCT FROM 'warmup') AS working
    FROM public.workout_sets s
   GROUP BY s.session_id)
SELECT ws.user_id,
       count(*)                                                          AS finished_with_rows,
       count(*) FILTER (WHERE ws.set_count IS DISTINCT FROM c.total)      AS set_count_to_change,
       count(*) FILTER (WHERE ws.working_set_count IS DISTINCT FROM c.working) AS working_to_change
  FROM public.workout_sessions ws
  JOIN counted c ON c.session_id = ws.id
 WHERE ws.ended_at IS NOT NULL
 GROUP BY ws.user_id
 ORDER BY ws.user_id;

-- ── THE ONE STATEMENT ──────────────────────────────────────────────────────
WITH counted AS (
  SELECT s.session_id,
         count(DISTINCT COALESCE(NULLIF(s.pair_id::text, ''), s.id::text))
           FILTER (WHERE s.set_type IS DISTINCT FROM 'ghost')                                   AS total,
         count(DISTINCT COALESCE(NULLIF(s.pair_id::text, ''), s.id::text))
           FILTER (WHERE s.set_type IS DISTINCT FROM 'ghost' AND s.set_type IS DISTINCT FROM 'warmup') AS working
    FROM public.workout_sets s
   GROUP BY s.session_id)
UPDATE public.workout_sessions ws
   SET set_count         = c.total,
       working_set_count = c.working
  FROM counted c
 WHERE c.session_id = ws.id
   AND ws.ended_at IS NOT NULL
   AND (ws.set_count IS DISTINCT FROM c.total
        OR ws.working_set_count IS DISTINCT FROM c.working);

-- ── VERIFY ─────────────────────────────────────────────────────────────────
-- Both numbers must be 0. If either is not, do NOT commit — ROLLBACK and say so.
WITH counted AS (
  SELECT s.session_id,
         count(DISTINCT COALESCE(NULLIF(s.pair_id::text, ''), s.id::text))
           FILTER (WHERE s.set_type IS DISTINCT FROM 'ghost')                                   AS total,
         count(DISTINCT COALESCE(NULLIF(s.pair_id::text, ''), s.id::text))
           FILTER (WHERE s.set_type IS DISTINCT FROM 'ghost' AND s.set_type IS DISTINCT FROM 'warmup') AS working
    FROM public.workout_sets s
   GROUP BY s.session_id)
SELECT 'set_count drift'         AS target, count(*) AS rows_left
  FROM public.workout_sessions ws JOIN counted c ON c.session_id = ws.id
 WHERE ws.ended_at IS NOT NULL AND ws.set_count IS DISTINCT FROM c.total
UNION ALL
SELECT 'working_set_count drift', count(*)
  FROM public.workout_sessions ws JOIN counted c ON c.session_id = ws.id
 WHERE ws.ended_at IS NOT NULL AND ws.working_set_count IS DISTINCT FROM c.working;

-- The founder's Thursday (2026-09-24, cb_b) should read 20 / 19.
SELECT id, day_key, started_at::date AS day, set_count, working_set_count
  FROM public.workout_sessions
 WHERE id = 'c6803c0f-985a-451a-9736-cb81aba1383f';

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if a "rows_left" came back non-zero
