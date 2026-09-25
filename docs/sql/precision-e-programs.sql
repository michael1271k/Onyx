-- Precision E1 — a program's goal, and a day's notes (item 12/13, Q13 scope).
--
-- Paste into the Supabase SQL editor BEFORE installing the build that carries
-- 9.x "Programs + Goals". Idempotent: `add column if not exists` skips the
-- whole clause — CHECK included — on a second run.
--
-- No new table. `plans` is already one row per program, `routines` one row per
-- program day (sets/reps/rest live in `payload`), and `plan_phase_goals` holds
-- the nutrition targets per (plan, phase). What was missing is the goal that
-- produced them.
--
-- All three are NULLABLE with no default, and the phone keeps them out of every
-- push body while they are nil (`encodeIfPresent`), so a build installed before
-- this paste still syncs every plan that has no goal. A plan GIVEN a goal on
-- such a build fails its push (PGRST204) and stays in the outbox until this
-- runs — nothing is lost.

-- What the program is for. Read by `PlanInfo.goal` (OnyxCore/Training/Programs.swift),
-- written by `AppDatabase.applyProgramGoal` (OnyxData/Plan/PlanWriter.swift).
alter table public.plans
  add column if not exists goal_kind text
  check (goal_kind in ('bulk', 'cut', 'recomp', 'muscle_mass', 'body_fat'));

-- Where the goal is heading: {target_weight_kg, target_body_fat_pct,
-- target_muscle_mass_kg, weekly_rate_kg, horizon_weeks, start_weight_kg} — every
-- key optional (`ProgramGoalTarget`). jsonb because the target's unit follows
-- the kind, and five nullable columns for one choice would be four blanks.
alter table public.plans
  add column if not exists goal_target jsonb;

-- A day's own note ("deload the last set", "superset 3+4"). Read and written by
-- the routine day editor (`RoutineDay.notes`).
alter table public.routines
  add column if not exists notes text;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- 1. The three columns are live (expect 3 rows):
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and ((table_name = 'plans' and column_name in ('goal_kind', 'goal_target'))
    or (table_name = 'routines' and column_name = 'notes'))
order by table_name, column_name;

-- 2. The CHECK is in place (expect one row naming the five kinds):
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.plans'::regclass and contype = 'c';

-- 3. The in-app "Delete program" removes rows from plans, routines,
--    plan_phase_goals, plan_phase_volume and program_day_layout. Each needs an
--    owner DELETE policy (expect a row per table with cmd DELETE or ALL):
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('plans', 'routines', 'plan_phase_goals', 'plan_phase_volume', 'program_day_layout')
order by tablename, cmd;
