-- ════════════════════════════════════════════════════════════════════════════
-- W1 — Apple Health tells the truth.  cardio_logs gains its key.
-- Paste into the Supabase SQL editor.  Safe to run more than once.
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY
-- ───
-- Nothing ever stored `HKWorkout.uuid`, so the import asked "is this the walk
-- you already have" of a table with no start column, and answered with a
-- five-minute window over `created_at`.  When `created_at` did not survive the
-- round trip the window missed and the bout was inserted again — on every sync,
-- on every launch.  `WeeklyExportBuilder` documents the cost in its own header:
-- one Friday exported 23 copies of a single walk.
--
-- The app writes `hk_uuid` from this build onward.  Until this file is pasted,
-- every imported bout's push is REJECTED for an unknown column: the failure is
-- per row, lands in the outbox, retries under backoff, and clears itself on the
-- first sync after the paste.  Nothing is lost while you wait — but nothing
-- new reaches the server either, so this is the first thing to run.
--
-- THERE IS NO BACKFILL OF hk_uuid, AND THERE CANNOT BE
-- ────────────────────────────────────────────────────
-- A uuid belongs to a HealthKit sample on a device.  A row written before this
-- build has no record of which bout it came from, and inventing a key would be
-- worse than leaving it null — the exact-match branch would answer for a bout
-- nobody has seen.  Historic rows keep `hk_uuid is null` and keep matching by
-- the five-minute window, exactly as they do today.  Block 2 below is what can
-- be recovered from `created_at`: the duplicates it already produced.


-- ── 1. The column ───────────────────────────────────────────────────────────
-- Nullable, no default.  Null means "a bout imported before the key existed,
-- or one typed by hand", and both of those still match by window.

alter table public.cardio_logs
  add column if not exists hk_uuid text;


-- ── 2. Collapse the duplicates already here ─────────────────────────────────
-- Keyed on what identifies a bout PHYSICALLY — when it started, how long it
-- lasted, how far it went — plus what it was and on which day.  This is the
-- same key `WeeklyExportBuilder` has deduped on at render time since it found
-- the 23 copies, applied to the data instead of to the view.
--
-- A row with NO `created_at` is skipped.  That is what "where unambiguous"
-- means here: the column is nullable with no default, and a key built from an
-- absence is the same key for every such row, so a Monday cycle and a Friday
-- swim would collapse into one another.
--
-- WHICH ROW SURVIVES — and this rule is deliberately written twice.  The one
-- carrying the most non-null figures, ties broken by the lowest `id`.  The app
-- runs the identical collapse locally (`AppDatabase` migration v27) and pushes
-- its deletions, so both halves must choose the SAME survivor or they delete
-- each other's keeper.  Most-non-null because duplicates are not identical: an
-- early import holds the heart rate, a later one may have gained a total
-- energy, and keeping the emptiest loses a measurement nothing can recover.

with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, date, kind, created_at, duration_min, distance_m
      order by
        ( (distance_m  is not null)::int
        + (duration_min is not null)::int
        + (kcal        is not null)::int
        + (active_kcal is not null)::int
        + (total_kcal  is not null)::int
        + (avg_hr      is not null)::int
        + (effort      is not null)::int
        + (incline_pct is not null)::int
        + (elevation_m is not null)::int ) desc,
        id asc
    ) as rn
  from public.cardio_logs
  where created_at is not null
)
delete from public.cardio_logs c
using ranked r
where c.id = r.id
  and r.rn > 1;


-- ── 3. And make it structurally impossible ──────────────────────────────────
-- PARTIAL, on `hk_uuid is not null`: every historic row is null and thousands
-- of nulls are not a collision.  From here a second insert of the same
-- HKWorkout is rejected by the database rather than caught by a heuristic in
-- the client — which is the only place a uniqueness claim can actually be kept.

create unique index if not exists cardio_logs_user_hk_uuid_key
  on public.cardio_logs (user_id, hk_uuid)
  where hk_uuid is not null;


-- ── 4. Confirm ──────────────────────────────────────────────────────────────
-- `duplicates` must be 0.  `keyed` climbs from 0 as the phone syncs the bouts
-- it has re-imported since the build landed; it is expected to be 0 right after
-- the paste and is not a failure.

select
  (select count(*) from public.cardio_logs)                              as bouts,
  (select count(*) from public.cardio_logs where hk_uuid is not null)    as keyed,
  (select count(*) from (
     select 1
     from public.cardio_logs
     where created_at is not null
     group by user_id, date, kind, created_at, duration_min, distance_m
     having count(*) > 1
   ) d)                                                                  as duplicates;
