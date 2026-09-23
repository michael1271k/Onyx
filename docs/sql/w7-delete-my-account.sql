-- ════════════════════════════════════════════════════════════════════════════
-- w7-delete-my-account.sql — account deletion, written down (App Store sprint, W7)
--
-- Supabase's SQL editor shows only the LAST result of a run. So: select § 1a,
-- § 1b, § 1c, § 1d and § 2 one at a time and Run each (all read-only), then run
-- the whole file; its last statement is § 4, one pass/fail row. The change is
-- one `create or replace` plus grants — running it twice is a no-op.
--
-- ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
-- Settings → Delete account calls `rpc("delete_my_account")`
-- (`AppEnvironment.deleteAccount`). App Review 5.1.1(v) requires it to work.
-- Its SQL lived nowhere in this repo: `docs/sql/` was purged at 7.8.1.
--
-- Git history holds exactly ONE body for it — `docs/sql/e6-auth-deletion.sql`
-- (Phase 3 E6, 2026-09-07, last seen at `ebb78142^`). That body named 32
-- tables by hand, and two things have moved since:
--
--  1. It deletes from `notion_exports`, `notion_credentials`, `widget_tokens`
--     and `body_measurements`. None of the four exists live any more (the W1
--     cleanup of 2026-09-10 dropped them). PL/pgSQL resolves a table name when
--     the statement RUNS, not when the function is created, so the old body
--     compiles and then fails on the tenth statement: "relation
--     public.notion_exports does not exist". The whole call rolls back and
--     Settings says "Could not delete the account".
--  2. It never names `set_events`, `stress_logs`, `lever_periods`,
--     `plan_phases`, `prescriptions`, `routines` or `exports`, all added later.
--     `set_events.session_id` references `workout_sessions`, so even with (1)
--     fixed, a user who ever logged a set could not be deleted — and a user
--     who could would leave rows behind.
--
-- The live body could NOT be read from here: PostgREST exposes that the RPC
-- exists (`/rpc/delete_my_account`, 2026-09-23) and nothing about what it
-- does. If the live body is the E6 one, account deletion is broken today.
-- § 2 below shows you which it is before anything changes; § 3 replaces it
-- either way (as long as § 2's `returns` reads `void`).
--
-- ── THE SHAPE, AND WHY IT IS NOT A LIST ANY MORE ───────────────────────────
-- A hand-kept list is exactly what drifted. This body reads the list from the
-- catalog at call time: every ordinary table in `public` that has a `user_id`
-- column (36 on 2026-09-23). A table added next month is deleted from without
-- anyone remembering this file.
--
-- Order without the foreign-key graph: each pass deletes the caller's rows
-- from EVERY table; a table a foreign key holds (SQLSTATE 23503) is retried on
-- the next pass, once its children are gone, and a row a trigger wrote back
-- (see § 1d) is caught the same way. It stops on the first pass that deletes
-- nothing, or raises when a pass frees nothing while something is still held,
-- or after ten passes — and a raise rolls the ENTIRE call back.
-- A half-deleted account with a live login is the one outcome worse than a
-- failed delete.
--
-- Dynamic SQL in a `security definer` body is safe here only because nothing
-- in it comes from the caller: table names come from `pg_class` and are
-- quoted by `format('%I')`, and the user id is `auth.uid()`, bound as `$1`.
-- `set search_path = ''` stays — every name below is schema-qualified.
--
-- ── PROVED, BEFORE IT CAME TO YOU ──────────────────────────────────────────
-- On a local PostgreSQL 17 cluster shaped like the live project: the 36
-- `user_id` tables, the six foreign keys PostgREST reports between them (all
-- NO ACTION, the strictest reading), `user_id → auth.users` NO ACTION on every
-- table (an assumption — PostgREST cannot see the `auth` schema; § 1c shows the
-- live answer), and two users with rows in all 36. Result: the caller's rows gone from all
-- 36 and from `auth.users`, the other user's untouched, `anon` refused, a null
-- `auth.uid()` refused. The E6 body, run against the same cluster, fails with
-- `relation "public.notion_exports" does not exist`.
-- ════════════════════════════════════════════════════════════════════════════


-- ── § 1. Look first. Read-only. ────────────────────────────────────────────
-- § 1a. The tables it will clear. Expected: 36 rows.
-- A table you expected to see and do not has no `user_id` column; its rows
-- would survive a deletion.
select c.relname as table_name
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
join pg_catalog.pg_attribute a on a.attrelid = c.oid
where n.nspname = 'public' and c.relkind in ('r', 'p')
  and a.attname = 'user_id' and not a.attisdropped
order by 1;

-- § 1b. What the catalog sweep could MISS. Expected: zero rows. A row is a
-- table with no `user_id` that references one of the tables above: its rows
-- either block the delete (the call then fails and rolls back, loudly) or,
-- under `on delete set null`, outlive the account.
select con.conrelid::regclass as referencing_table,
       con.confrelid::regclass as referenced_table,
       con.confdeltype as on_delete
from pg_catalog.pg_constraint con
join pg_catalog.pg_class rc on rc.oid = con.conrelid
join pg_catalog.pg_namespace rn on rn.oid = rc.relnamespace
where con.contype = 'f' and rn.nspname = 'public'
  and not exists (select 1 from pg_catalog.pg_attribute a
                  where a.attrelid = con.conrelid and a.attname = 'user_id' and not a.attisdropped)
  and exists (select 1 from pg_catalog.pg_attribute a
              where a.attrelid = con.confrelid and a.attname = 'user_id' and not a.attisdropped);

-- § 1c. Each `user_id`: its type, and what its foreign key to `auth.users`
-- does on delete (a = no action, r = restrict, c = cascade, n = set null;
-- empty = no foreign key). Every type must be `uuid` — a `text` column fails
-- the whole call with 42883, loudly. An empty key is fine for the delete; it
-- only means nothing but this function keeps that table clean.
select c.relname as table_name,
       pg_catalog.format_type(a.atttypid, a.atttypmod) as user_id_type,
       (select con.confdeltype from pg_catalog.pg_constraint con
        where con.conrelid = c.oid and con.contype = 'f'
          and con.confrelid = 'auth.users'::regclass and a.attnum = any (con.conkey)
        limit 1) as fk_to_auth_users
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
join pg_catalog.pg_attribute a on a.attrelid = c.oid
where n.nspname = 'public' and c.relkind in ('r', 'p')
  and a.attname = 'user_id' and not a.attisdropped
order by 1;

-- § 1d. DELETE triggers on those tables. Expected, 2026-09-23: ONE row —
-- `nutrition_entries.trg_sync_daily_macros`, which recomputes `daily_logs`.
-- The function's repeat pass is what makes it harmless; a NEW row here is worth
-- reading before relying on the delete.
select t.tgrelid::regclass as table_name, t.tgname, pg_catalog.pg_get_triggerdef(t.oid) as definition
from pg_catalog.pg_trigger t
join pg_catalog.pg_class c on c.oid = t.tgrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal and (t.tgtype & 8) <> 0;


-- ── § 2. What is live now, before it is replaced ───────────────────────────
-- `names_dropped_table = true` means the E6 body is live and deletion is
-- failing today. Worth writing down, then run § 3 regardless. `returns` must be
-- `void`: `create or replace` cannot change a return type, and the whole run
-- would stop at § 3 with 42P13. If it is anything else, send it back.
select p.prosecdef as security_definer,
       p.proconfig as settings,
       pg_catalog.pg_get_function_result(p.oid) as returns,
       p.prosrc ~ 'notion_exports' as names_dropped_table,
       p.prosrc ~ 'reappearing' as is_this_file
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'delete_my_account';


-- ── § 3. The function ──────────────────────────────────────────────────────
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  swept text[];
  held text[];
  t text;
  freed boolean;
  n bigint;
  passes int := 0;
begin
  -- Without this an anonymous call would run every delete with
  -- `user_id = null`: nothing today, everything the day a column goes nullable.
  if uid is null then
    raise exception 'delete_my_account: no authenticated user';
  end if;

  select coalesce(array_agg(c.relname::text order by c.relname), '{}')
    into swept
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace ns on ns.oid = c.relnamespace
  join pg_catalog.pg_attribute a on a.attrelid = c.oid
  where ns.nspname = 'public' and c.relkind in ('r', 'p')
    and a.attname = 'user_id' and not a.attisdropped;

  -- EVERY table, EVERY pass, until a pass deletes nothing. A trigger can write
  -- a row back into a table this loop already cleared —
  -- `nutrition_entries.trg_sync_daily_macros` recomputes `daily_logs` on each
  -- delete, and `daily_logs` sorts first — so "every table was cleared once"
  -- is not "the account is gone". Bounded: a trigger that keeps writing rows
  -- back is a fault, and it raises rather than spins.
  loop
    passes := passes + 1;
    held := '{}';
    freed := false;
    foreach t in array swept loop
      begin
        execute format('delete from public.%I where user_id = $1', t) using uid;
        get diagnostics n = row_count;
        if n > 0 then freed := true; end if;
      exception when foreign_key_violation then
        -- Its children are still here; they go this pass, it goes next.
        held := held || t;
      end;
    end loop;
    exit when not freed and cardinality(held) = 0;
    if not freed then
      raise exception 'delete_my_account: rows in % are still referenced', held;
    end if;
    if passes >= 10 then
      raise exception 'delete_my_account: rows keep reappearing after % passes', passes;
    end if;
  end loop;

  -- Last, and only once every row above is gone: the identity itself. The
  -- client signs out straight after (`AppEnvironment.deleteAccount`), because
  -- the JWT it holds stays valid until it expires.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;


-- ── § 4. Verify — ONE row, because the editor shows only a run's last result.
-- Expected: security_definer t · search_path_empty t · names_dropped_table f ·
-- is_this_file t · anon_can_call f · authenticated_can_call t ·
-- tables_swept 36 · missed_references 0 · non_uuid_user_ids 0 ·
-- delete_triggers 1 (see § 1d). Anything else: send the row back first.
with swept as (
  select c.oid, a.atttypid
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_attribute a on a.attrelid = c.oid
  where n.nspname = 'public' and c.relkind in ('r', 'p')
    and a.attname = 'user_id' and not a.attisdropped
)
select p.prosecdef as security_definer,
       p.proconfig = array['search_path=""'] as search_path_empty,
       p.prosrc ~ 'notion_exports' as names_dropped_table,
       p.prosrc ~ 'reappearing' as is_this_file,
       pg_catalog.has_function_privilege('anon', p.oid, 'execute') as anon_can_call,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_call,
       (select count(*) from swept) as tables_swept,
       (select count(*) from pg_catalog.pg_constraint con
        where con.contype = 'f' and con.confrelid in (select oid from swept)
          and con.conrelid not in (select oid from swept)
          and con.conrelid in (select c.oid from pg_catalog.pg_class c
                               join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                               where n.nspname = 'public')) as missed_references,
       (select count(*) from swept where atttypid <> 'uuid'::regtype) as non_uuid_user_ids,
       (select count(*) from pg_catalog.pg_trigger t
        where t.tgrelid in (select oid from swept) and not t.tgisinternal
          and (t.tgtype & 8) <> 0) as delete_triggers
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'delete_my_account';
