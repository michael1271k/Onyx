-- ============================================================================
-- W11 · One store, one user — Row Level Security for every table in `public`.
--
-- Generated 2026-09-17 from a LIVE introspection of project kmbvsblihobqrhgpdrqo
-- (PostgreSQL 17.6): 34 tables, every one already RLS-enabled, 63 policies in
-- place. This file replaces those 63 with one uniform, audited set:
--
--   · every policy is `to authenticated` — the `anon` role had 34 policies
--     granted `to public`; with RLS on and no policy for its role it now
--     sees and writes nothing, which is what an anonymous key should do;
--   · every owner check is `(select auth.uid()) = user_id`, the INITPLAN
--     form, evaluated once per statement rather than once per row;
--   · `workout_sets` and `set_events` are additionally checked on WRITE
--     against their session's owner, so a set can never be filed under
--     somebody else's workout (both tables carry `user_id` NOT NULL live,
--     so their reads police that column directly);
--   · `set_events` gets no update policy: the log is append-only and the
--     client pushes it ON CONFLICT DO NOTHING;
--   · the founder's admin reads (`private.is_admin()`) are preserved on the
--     same 14 tables that had them, in the initplan form;
--   · `profiles.role` becomes read-only to the user: a column-level grant
--     replaces the table-level UPDATE that let any account promote itself
--     to admin and, through `private.is_admin()`, read everyone's rows;
--   · TRUNCATE — which Row Level Security does not govern — is revoked from
--     the API roles on every table.
--
-- Re-runnable: every statement is `if exists` / `drop … create`, and the
-- whole file runs in one transaction, so a failure leaves the database as
-- it was. Paste into the Supabase SQL editor as `postgres` and run once.
-- The VERIFY block at the end is read-only; its counts are the pass.
-- ============================================================================

begin;

-- ── body_composition ────────────────────────────────────────────────────────
alter table public.body_composition enable row level security;
drop policy if exists "admin_reads_body_composition" on public.body_composition;
drop policy if exists "user_owns_body_composition" on public.body_composition;
drop policy if exists "body_composition_select_own" on public.body_composition;
drop policy if exists "body_composition_insert_own" on public.body_composition;
drop policy if exists "body_composition_update_own" on public.body_composition;
drop policy if exists "body_composition_delete_own" on public.body_composition;
drop policy if exists "body_composition_select_admin" on public.body_composition;
create policy "body_composition_select_own" on public.body_composition
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "body_composition_insert_own" on public.body_composition
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "body_composition_update_own" on public.body_composition
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "body_composition_delete_own" on public.body_composition
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "body_composition_select_admin" on public.body_composition
  for select to authenticated
  using ((select private.is_admin()));

-- ── cardio_logs ─────────────────────────────────────────────────────────────
alter table public.cardio_logs enable row level security;
drop policy if exists "cardio_owner" on public.cardio_logs;
drop policy if exists "cardio_logs_select_own" on public.cardio_logs;
drop policy if exists "cardio_logs_insert_own" on public.cardio_logs;
drop policy if exists "cardio_logs_update_own" on public.cardio_logs;
drop policy if exists "cardio_logs_delete_own" on public.cardio_logs;
create policy "cardio_logs_select_own" on public.cardio_logs
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "cardio_logs_insert_own" on public.cardio_logs
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "cardio_logs_update_own" on public.cardio_logs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "cardio_logs_delete_own" on public.cardio_logs
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── custom_supplements ──────────────────────────────────────────────────────
alter table public.custom_supplements enable row level security;
drop policy if exists "custom_supp_owner" on public.custom_supplements;
drop policy if exists "custom_supplements_select_own" on public.custom_supplements;
drop policy if exists "custom_supplements_insert_own" on public.custom_supplements;
drop policy if exists "custom_supplements_update_own" on public.custom_supplements;
drop policy if exists "custom_supplements_delete_own" on public.custom_supplements;
create policy "custom_supplements_select_own" on public.custom_supplements
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "custom_supplements_insert_own" on public.custom_supplements
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "custom_supplements_update_own" on public.custom_supplements
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "custom_supplements_delete_own" on public.custom_supplements
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── daily_logs ──────────────────────────────────────────────────────────────
alter table public.daily_logs enable row level security;
drop policy if exists "admin_reads_daily_logs" on public.daily_logs;
drop policy if exists "user_owns_daily_logs" on public.daily_logs;
drop policy if exists "daily_logs_select_own" on public.daily_logs;
drop policy if exists "daily_logs_insert_own" on public.daily_logs;
drop policy if exists "daily_logs_update_own" on public.daily_logs;
drop policy if exists "daily_logs_delete_own" on public.daily_logs;
drop policy if exists "daily_logs_select_admin" on public.daily_logs;
create policy "daily_logs_select_own" on public.daily_logs
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_logs_insert_own" on public.daily_logs
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "daily_logs_update_own" on public.daily_logs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "daily_logs_delete_own" on public.daily_logs
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_logs_select_admin" on public.daily_logs
  for select to authenticated
  using ((select private.is_admin()));

-- ── daily_metrics ───────────────────────────────────────────────────────────
alter table public.daily_metrics enable row level security;
drop policy if exists "admin_reads_daily_metrics" on public.daily_metrics;
drop policy if exists "user_owns_daily_metrics" on public.daily_metrics;
drop policy if exists "daily_metrics_select_own" on public.daily_metrics;
drop policy if exists "daily_metrics_insert_own" on public.daily_metrics;
drop policy if exists "daily_metrics_update_own" on public.daily_metrics;
drop policy if exists "daily_metrics_delete_own" on public.daily_metrics;
drop policy if exists "daily_metrics_select_admin" on public.daily_metrics;
create policy "daily_metrics_select_own" on public.daily_metrics
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_metrics_insert_own" on public.daily_metrics
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "daily_metrics_update_own" on public.daily_metrics
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "daily_metrics_delete_own" on public.daily_metrics
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_metrics_select_admin" on public.daily_metrics
  for select to authenticated
  using ((select private.is_admin()));

-- ── daily_scores ────────────────────────────────────────────────────────────
alter table public.daily_scores enable row level security;
drop policy if exists "admin_reads_daily_scores" on public.daily_scores;
drop policy if exists "user_owns_daily_scores" on public.daily_scores;
drop policy if exists "daily_scores_select_own" on public.daily_scores;
drop policy if exists "daily_scores_insert_own" on public.daily_scores;
drop policy if exists "daily_scores_update_own" on public.daily_scores;
drop policy if exists "daily_scores_delete_own" on public.daily_scores;
drop policy if exists "daily_scores_select_admin" on public.daily_scores;
create policy "daily_scores_select_own" on public.daily_scores
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_scores_insert_own" on public.daily_scores
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "daily_scores_update_own" on public.daily_scores
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "daily_scores_delete_own" on public.daily_scores
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_scores_select_admin" on public.daily_scores
  for select to authenticated
  using ((select private.is_admin()));

-- ── daily_targets ───────────────────────────────────────────────────────────
alter table public.daily_targets enable row level security;
drop policy if exists "daily_targets_own" on public.daily_targets;
drop policy if exists "daily_targets_select_own" on public.daily_targets;
drop policy if exists "daily_targets_insert_own" on public.daily_targets;
drop policy if exists "daily_targets_update_own" on public.daily_targets;
drop policy if exists "daily_targets_delete_own" on public.daily_targets;
create policy "daily_targets_select_own" on public.daily_targets
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "daily_targets_insert_own" on public.daily_targets
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "daily_targets_update_own" on public.daily_targets
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "daily_targets_delete_own" on public.daily_targets
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── dashboard_layouts ───────────────────────────────────────────────────────
alter table public.dashboard_layouts enable row level security;
drop policy if exists "user_owns_dashboard_layouts" on public.dashboard_layouts;
drop policy if exists "dashboard_layouts_select_own" on public.dashboard_layouts;
drop policy if exists "dashboard_layouts_insert_own" on public.dashboard_layouts;
drop policy if exists "dashboard_layouts_update_own" on public.dashboard_layouts;
drop policy if exists "dashboard_layouts_delete_own" on public.dashboard_layouts;
create policy "dashboard_layouts_select_own" on public.dashboard_layouts
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "dashboard_layouts_insert_own" on public.dashboard_layouts
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "dashboard_layouts_update_own" on public.dashboard_layouts
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "dashboard_layouts_delete_own" on public.dashboard_layouts
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── doms_logs ───────────────────────────────────────────────────────────────
alter table public.doms_logs enable row level security;
drop policy if exists "own doms" on public.doms_logs;
drop policy if exists "doms_logs_select_own" on public.doms_logs;
drop policy if exists "doms_logs_insert_own" on public.doms_logs;
drop policy if exists "doms_logs_update_own" on public.doms_logs;
drop policy if exists "doms_logs_delete_own" on public.doms_logs;
create policy "doms_logs_select_own" on public.doms_logs
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "doms_logs_insert_own" on public.doms_logs
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "doms_logs_update_own" on public.doms_logs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "doms_logs_delete_own" on public.doms_logs
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── exercises ───────────────────────────────────────────────────────────────
alter table public.exercises enable row level security;
drop policy if exists "user_owns_exercises" on public.exercises;
drop policy if exists "exercises_select_own" on public.exercises;
drop policy if exists "exercises_insert_own" on public.exercises;
drop policy if exists "exercises_update_own" on public.exercises;
drop policy if exists "exercises_delete_own" on public.exercises;
create policy "exercises_select_own" on public.exercises
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "exercises_insert_own" on public.exercises
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "exercises_update_own" on public.exercises
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "exercises_delete_own" on public.exercises
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── fatigue_logs ────────────────────────────────────────────────────────────
alter table public.fatigue_logs enable row level security;
drop policy if exists "fatigue_owner" on public.fatigue_logs;
drop policy if exists "fatigue_logs_select_own" on public.fatigue_logs;
drop policy if exists "fatigue_logs_insert_own" on public.fatigue_logs;
drop policy if exists "fatigue_logs_update_own" on public.fatigue_logs;
drop policy if exists "fatigue_logs_delete_own" on public.fatigue_logs;
create policy "fatigue_logs_select_own" on public.fatigue_logs
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "fatigue_logs_insert_own" on public.fatigue_logs
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "fatigue_logs_update_own" on public.fatigue_logs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "fatigue_logs_delete_own" on public.fatigue_logs
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── joint_flags ─────────────────────────────────────────────────────────────
alter table public.joint_flags enable row level security;
drop policy if exists "joint_flags_own" on public.joint_flags;
drop policy if exists "joint_flags_select_own" on public.joint_flags;
drop policy if exists "joint_flags_insert_own" on public.joint_flags;
drop policy if exists "joint_flags_update_own" on public.joint_flags;
drop policy if exists "joint_flags_delete_own" on public.joint_flags;
create policy "joint_flags_select_own" on public.joint_flags
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "joint_flags_insert_own" on public.joint_flags
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "joint_flags_update_own" on public.joint_flags
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "joint_flags_delete_own" on public.joint_flags
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── lever_periods ───────────────────────────────────────────────────────────
alter table public.lever_periods enable row level security;
drop policy if exists "lever_periods_delete_own" on public.lever_periods;
drop policy if exists "lever_periods_insert_own" on public.lever_periods;
drop policy if exists "lever_periods_select_own" on public.lever_periods;
drop policy if exists "lever_periods_update_own" on public.lever_periods;
create policy "lever_periods_select_own" on public.lever_periods
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "lever_periods_insert_own" on public.lever_periods
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "lever_periods_update_own" on public.lever_periods
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "lever_periods_delete_own" on public.lever_periods
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── nutrition_entries ───────────────────────────────────────────────────────
alter table public.nutrition_entries enable row level security;
drop policy if exists "admin_reads_nutrition_entries" on public.nutrition_entries;
drop policy if exists "user_owns_nutrition_entries" on public.nutrition_entries;
drop policy if exists "nutrition_entries_select_own" on public.nutrition_entries;
drop policy if exists "nutrition_entries_insert_own" on public.nutrition_entries;
drop policy if exists "nutrition_entries_update_own" on public.nutrition_entries;
drop policy if exists "nutrition_entries_delete_own" on public.nutrition_entries;
drop policy if exists "nutrition_entries_select_admin" on public.nutrition_entries;
create policy "nutrition_entries_select_own" on public.nutrition_entries
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "nutrition_entries_insert_own" on public.nutrition_entries
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "nutrition_entries_update_own" on public.nutrition_entries
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "nutrition_entries_delete_own" on public.nutrition_entries
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "nutrition_entries_select_admin" on public.nutrition_entries
  for select to authenticated
  using ((select private.is_admin()));

-- ── personal_records ────────────────────────────────────────────────────────
alter table public.personal_records enable row level security;
drop policy if exists "pr_owner" on public.personal_records;
drop policy if exists "personal_records_select_own" on public.personal_records;
drop policy if exists "personal_records_insert_own" on public.personal_records;
drop policy if exists "personal_records_update_own" on public.personal_records;
drop policy if exists "personal_records_delete_own" on public.personal_records;
create policy "personal_records_select_own" on public.personal_records
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "personal_records_insert_own" on public.personal_records
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "personal_records_update_own" on public.personal_records
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "personal_records_delete_own" on public.personal_records
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── plan_phase_goals ────────────────────────────────────────────────────────
alter table public.plan_phase_goals enable row level security;
drop policy if exists "ppg_owner" on public.plan_phase_goals;
drop policy if exists "plan_phase_goals_select_own" on public.plan_phase_goals;
drop policy if exists "plan_phase_goals_insert_own" on public.plan_phase_goals;
drop policy if exists "plan_phase_goals_update_own" on public.plan_phase_goals;
drop policy if exists "plan_phase_goals_delete_own" on public.plan_phase_goals;
create policy "plan_phase_goals_select_own" on public.plan_phase_goals
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "plan_phase_goals_insert_own" on public.plan_phase_goals
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "plan_phase_goals_update_own" on public.plan_phase_goals
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "plan_phase_goals_delete_own" on public.plan_phase_goals
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── plan_phase_volume ───────────────────────────────────────────────────────
alter table public.plan_phase_volume enable row level security;
drop policy if exists "ppv_owner" on public.plan_phase_volume;
drop policy if exists "plan_phase_volume_select_own" on public.plan_phase_volume;
drop policy if exists "plan_phase_volume_insert_own" on public.plan_phase_volume;
drop policy if exists "plan_phase_volume_update_own" on public.plan_phase_volume;
drop policy if exists "plan_phase_volume_delete_own" on public.plan_phase_volume;
create policy "plan_phase_volume_select_own" on public.plan_phase_volume
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "plan_phase_volume_insert_own" on public.plan_phase_volume
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "plan_phase_volume_update_own" on public.plan_phase_volume
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "plan_phase_volume_delete_own" on public.plan_phase_volume
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── plan_phases ─────────────────────────────────────────────────────────────
alter table public.plan_phases enable row level security;
drop policy if exists "plan_phases_delete_own" on public.plan_phases;
drop policy if exists "plan_phases_insert_own" on public.plan_phases;
drop policy if exists "plan_phases_select_own" on public.plan_phases;
drop policy if exists "plan_phases_update_own" on public.plan_phases;
create policy "plan_phases_select_own" on public.plan_phases
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "plan_phases_insert_own" on public.plan_phases
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "plan_phases_update_own" on public.plan_phases
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "plan_phases_delete_own" on public.plan_phases
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── plans ───────────────────────────────────────────────────────────────────
alter table public.plans enable row level security;
drop policy if exists "plans_owner" on public.plans;
drop policy if exists "plans_select_own" on public.plans;
drop policy if exists "plans_insert_own" on public.plans;
drop policy if exists "plans_update_own" on public.plans;
drop policy if exists "plans_delete_own" on public.plans;
create policy "plans_select_own" on public.plans
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "plans_insert_own" on public.plans
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "plans_update_own" on public.plans
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "plans_delete_own" on public.plans
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── profiles ────────────────────────────────────────────────────────────────
alter table public.profiles enable row level security;
drop policy if exists "profiles_self" on public.profiles;
drop policy if exists "profiles_update_self" on public.profiles;
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_select_admin" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "profiles_select_admin" on public.profiles
  for select to authenticated
  using ((select private.is_admin()));

-- ── program_day_layout ──────────────────────────────────────────────────────
alter table public.program_day_layout enable row level security;
drop policy if exists "program_day_layout_owner" on public.program_day_layout;
drop policy if exists "program_day_layout_select_own" on public.program_day_layout;
drop policy if exists "program_day_layout_insert_own" on public.program_day_layout;
drop policy if exists "program_day_layout_update_own" on public.program_day_layout;
drop policy if exists "program_day_layout_delete_own" on public.program_day_layout;
create policy "program_day_layout_select_own" on public.program_day_layout
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "program_day_layout_insert_own" on public.program_day_layout
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "program_day_layout_update_own" on public.program_day_layout
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "program_day_layout_delete_own" on public.program_day_layout
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── reports ─────────────────────────────────────────────────────────────────
alter table public.reports enable row level security;
drop policy if exists "admin_reads_reports" on public.reports;
drop policy if exists "own reports" on public.reports;
drop policy if exists "user_owns_reports" on public.reports;
drop policy if exists "reports_select_own" on public.reports;
drop policy if exists "reports_insert_own" on public.reports;
drop policy if exists "reports_update_own" on public.reports;
drop policy if exists "reports_delete_own" on public.reports;
drop policy if exists "reports_select_admin" on public.reports;
create policy "reports_select_own" on public.reports
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "reports_insert_own" on public.reports
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "reports_update_own" on public.reports
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "reports_delete_own" on public.reports
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "reports_select_admin" on public.reports
  for select to authenticated
  using ((select private.is_admin()));

-- ── routine_templates ───────────────────────────────────────────────────────
alter table public.routine_templates enable row level security;
drop policy if exists "admin_reads_routine_templates" on public.routine_templates;
drop policy if exists "user_owns_routine_templates" on public.routine_templates;
drop policy if exists "routine_templates_select_own" on public.routine_templates;
drop policy if exists "routine_templates_insert_own" on public.routine_templates;
drop policy if exists "routine_templates_update_own" on public.routine_templates;
drop policy if exists "routine_templates_delete_own" on public.routine_templates;
drop policy if exists "routine_templates_select_admin" on public.routine_templates;
create policy "routine_templates_select_own" on public.routine_templates
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "routine_templates_insert_own" on public.routine_templates
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "routine_templates_update_own" on public.routine_templates
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "routine_templates_delete_own" on public.routine_templates
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "routine_templates_select_admin" on public.routine_templates
  for select to authenticated
  using ((select private.is_admin()));

-- ── routines ────────────────────────────────────────────────────────────────
alter table public.routines enable row level security;
drop policy if exists "routines_delete_own" on public.routines;
drop policy if exists "routines_insert_own" on public.routines;
drop policy if exists "routines_select_own" on public.routines;
drop policy if exists "routines_update_own" on public.routines;
create policy "routines_select_own" on public.routines
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "routines_insert_own" on public.routines
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "routines_update_own" on public.routines
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "routines_delete_own" on public.routines
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── schedule_overrides ──────────────────────────────────────────────────────
alter table public.schedule_overrides enable row level security;
drop policy if exists "own schedule_overrides" on public.schedule_overrides;
drop policy if exists "schedule_overrides_select_own" on public.schedule_overrides;
drop policy if exists "schedule_overrides_insert_own" on public.schedule_overrides;
drop policy if exists "schedule_overrides_update_own" on public.schedule_overrides;
drop policy if exists "schedule_overrides_delete_own" on public.schedule_overrides;
create policy "schedule_overrides_select_own" on public.schedule_overrides
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "schedule_overrides_insert_own" on public.schedule_overrides
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "schedule_overrides_update_own" on public.schedule_overrides
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "schedule_overrides_delete_own" on public.schedule_overrides
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── set_events ──────────────────────────────────────────────────────────────
alter table public.set_events enable row level security;
drop policy if exists "set_events_delete_own" on public.set_events;
drop policy if exists "set_events_insert_own" on public.set_events;
drop policy if exists "set_events_select_own" on public.set_events;
create policy "set_events_select_own" on public.set_events
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "set_events_insert_own" on public.set_events
  for insert to authenticated
  with check ((select auth.uid()) = user_id
    and exists (select 1 from public.workout_sessions s
                     where s.id = session_id and s.user_id = (select auth.uid())));
create policy "set_events_delete_own" on public.set_events
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── sleep_sessions ──────────────────────────────────────────────────────────
alter table public.sleep_sessions enable row level security;
drop policy if exists "admin_reads_sleep_sessions" on public.sleep_sessions;
drop policy if exists "user_owns_sleep_sessions" on public.sleep_sessions;
drop policy if exists "sleep_sessions_select_own" on public.sleep_sessions;
drop policy if exists "sleep_sessions_insert_own" on public.sleep_sessions;
drop policy if exists "sleep_sessions_update_own" on public.sleep_sessions;
drop policy if exists "sleep_sessions_delete_own" on public.sleep_sessions;
drop policy if exists "sleep_sessions_select_admin" on public.sleep_sessions;
create policy "sleep_sessions_select_own" on public.sleep_sessions
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "sleep_sessions_insert_own" on public.sleep_sessions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "sleep_sessions_update_own" on public.sleep_sessions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "sleep_sessions_delete_own" on public.sleep_sessions
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "sleep_sessions_select_admin" on public.sleep_sessions
  for select to authenticated
  using ((select private.is_admin()));

-- ── stress_logs ─────────────────────────────────────────────────────────────
alter table public.stress_logs enable row level security;
drop policy if exists "stress_logs_delete_own" on public.stress_logs;
drop policy if exists "stress_logs_insert_own" on public.stress_logs;
drop policy if exists "stress_logs_select_own" on public.stress_logs;
drop policy if exists "stress_logs_update_own" on public.stress_logs;
create policy "stress_logs_select_own" on public.stress_logs
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "stress_logs_insert_own" on public.stress_logs
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "stress_logs_update_own" on public.stress_logs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "stress_logs_delete_own" on public.stress_logs
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── supplement_log ──────────────────────────────────────────────────────────
alter table public.supplement_log enable row level security;
drop policy if exists "admin_reads_supplement_log" on public.supplement_log;
drop policy if exists "user_owns_supplement_log" on public.supplement_log;
drop policy if exists "supplement_log_select_own" on public.supplement_log;
drop policy if exists "supplement_log_insert_own" on public.supplement_log;
drop policy if exists "supplement_log_update_own" on public.supplement_log;
drop policy if exists "supplement_log_delete_own" on public.supplement_log;
drop policy if exists "supplement_log_select_admin" on public.supplement_log;
create policy "supplement_log_select_own" on public.supplement_log
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "supplement_log_insert_own" on public.supplement_log
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "supplement_log_update_own" on public.supplement_log
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "supplement_log_delete_own" on public.supplement_log
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "supplement_log_select_admin" on public.supplement_log
  for select to authenticated
  using ((select private.is_admin()));

-- ── target_profiles ─────────────────────────────────────────────────────────
alter table public.target_profiles enable row level security;
drop policy if exists "target_profiles_own" on public.target_profiles;
drop policy if exists "target_profiles_select_own" on public.target_profiles;
drop policy if exists "target_profiles_insert_own" on public.target_profiles;
drop policy if exists "target_profiles_update_own" on public.target_profiles;
drop policy if exists "target_profiles_delete_own" on public.target_profiles;
create policy "target_profiles_select_own" on public.target_profiles
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "target_profiles_insert_own" on public.target_profiles
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "target_profiles_update_own" on public.target_profiles
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "target_profiles_delete_own" on public.target_profiles
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ── user_goals ──────────────────────────────────────────────────────────────
alter table public.user_goals enable row level security;
drop policy if exists "admin_reads_user_goals" on public.user_goals;
drop policy if exists "user_owns_user_goals" on public.user_goals;
drop policy if exists "user_goals_select_own" on public.user_goals;
drop policy if exists "user_goals_insert_own" on public.user_goals;
drop policy if exists "user_goals_update_own" on public.user_goals;
drop policy if exists "user_goals_delete_own" on public.user_goals;
drop policy if exists "user_goals_select_admin" on public.user_goals;
create policy "user_goals_select_own" on public.user_goals
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "user_goals_insert_own" on public.user_goals
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "user_goals_update_own" on public.user_goals
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "user_goals_delete_own" on public.user_goals
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "user_goals_select_admin" on public.user_goals
  for select to authenticated
  using ((select private.is_admin()));

-- ── water_intake ────────────────────────────────────────────────────────────
alter table public.water_intake enable row level security;
drop policy if exists "admin_reads_water_intake" on public.water_intake;
drop policy if exists "user_owns_water_intake" on public.water_intake;
drop policy if exists "water_intake_select_own" on public.water_intake;
drop policy if exists "water_intake_insert_own" on public.water_intake;
drop policy if exists "water_intake_update_own" on public.water_intake;
drop policy if exists "water_intake_delete_own" on public.water_intake;
drop policy if exists "water_intake_select_admin" on public.water_intake;
create policy "water_intake_select_own" on public.water_intake
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "water_intake_insert_own" on public.water_intake
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "water_intake_update_own" on public.water_intake
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "water_intake_delete_own" on public.water_intake
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "water_intake_select_admin" on public.water_intake
  for select to authenticated
  using ((select private.is_admin()));

-- ── workout_sessions ────────────────────────────────────────────────────────
alter table public.workout_sessions enable row level security;
drop policy if exists "admin_reads_workout_sessions" on public.workout_sessions;
drop policy if exists "user_owns_workout_sessions" on public.workout_sessions;
drop policy if exists "workout_sessions_select_own" on public.workout_sessions;
drop policy if exists "workout_sessions_insert_own" on public.workout_sessions;
drop policy if exists "workout_sessions_update_own" on public.workout_sessions;
drop policy if exists "workout_sessions_delete_own" on public.workout_sessions;
drop policy if exists "workout_sessions_select_admin" on public.workout_sessions;
create policy "workout_sessions_select_own" on public.workout_sessions
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "workout_sessions_insert_own" on public.workout_sessions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "workout_sessions_update_own" on public.workout_sessions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "workout_sessions_delete_own" on public.workout_sessions
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "workout_sessions_select_admin" on public.workout_sessions
  for select to authenticated
  using ((select private.is_admin()));

-- ── workout_sets ────────────────────────────────────────────────────────────
alter table public.workout_sets enable row level security;
drop policy if exists "admin_reads_workout_sets" on public.workout_sets;
drop policy if exists "user_owns_workout_sets" on public.workout_sets;
drop policy if exists "workout_sets_select_own" on public.workout_sets;
drop policy if exists "workout_sets_insert_own" on public.workout_sets;
drop policy if exists "workout_sets_update_own" on public.workout_sets;
drop policy if exists "workout_sets_delete_own" on public.workout_sets;
drop policy if exists "workout_sets_select_admin" on public.workout_sets;
create policy "workout_sets_select_own" on public.workout_sets
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "workout_sets_insert_own" on public.workout_sets
  for insert to authenticated
  with check ((select auth.uid()) = user_id
    and exists (select 1 from public.workout_sessions s
                     where s.id = session_id and s.user_id = (select auth.uid())));
create policy "workout_sets_update_own" on public.workout_sets
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id
    and exists (select 1 from public.workout_sessions s
                     where s.id = session_id and s.user_id = (select auth.uid())));
create policy "workout_sets_delete_own" on public.workout_sets
  for delete to authenticated
  using ((select auth.uid()) = user_id);
create policy "workout_sets_select_admin" on public.workout_sets
  for select to authenticated
  using ((select private.is_admin()));

-- ── profiles.role is not the user's to change ──────────────────────────────
-- Table-level UPDATE let `update profiles set role = 'admin'` through the
-- update policy (the row IS the user's own). Only `display_name` is theirs.
revoke update on table public.profiles from anon, authenticated;
grant update (display_name) on table public.profiles to authenticated;

-- ── TRUNCATE is not governed by RLS ─────────────────────────────────────────
revoke truncate on all tables in schema public from anon, authenticated;

commit;

-- ============================================================================
-- VERIFY — read-only. Run after the commit. Expected results are stated.
-- ============================================================================

-- 1. Every public table has RLS enabled, and none is `forced` (forcing it
--    would break the SECURITY DEFINER trigger that creates a profile at
--    sign-up, because `postgres` owns the tables). Expect 34 rows, all
--    `rls = true`, `forced = false`.
select c.relname as "table", c.relrowsecurity as rls, c.relforcerowsecurity as forced
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
 order by 1;

-- 2. Policy counts. Expect 148 policies in total and this shape:
--    4 on a plain table, 5 where the admin read is preserved,
--    3 on set_events (no update), 4 on profiles (no delete, admin read).
select tablename as "table", count(*) as policies,
       string_agg(policyname, ', ' order by policyname) as names
  from pg_policies where schemaname = 'public'
 group by 1 order by 1;

-- 3. Nothing is granted to `public` or `anon` by policy any more. Expect 0 rows.
select tablename, policyname, roles from pg_policies
 where schemaname = 'public' and not (roles = '{authenticated}'::name[]);

-- 4. No per-row `auth.uid()` survives — every check is the initplan form.
--    Expect 0 rows.
select tablename, policyname from pg_policies
 where schemaname = 'public'
   and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(^|[^( ])auth\.uid\(\)';

-- 5. `role` is no longer updatable through the API. Expect exactly one row:
--    authenticated · display_name · UPDATE.
select grantee, column_name, privilege_type from information_schema.column_privileges
 where table_schema = 'public' and table_name = 'profiles'
   and privilege_type = 'UPDATE' and grantee in ('anon', 'authenticated')
 order by 1, 2;

-- 6. TRUNCATE is gone from the API roles. Expect 0 rows.
select table_name, grantee from information_schema.role_table_grants
 where table_schema = 'public' and privilege_type = 'TRUNCATE'
   and grantee in ('anon', 'authenticated');
