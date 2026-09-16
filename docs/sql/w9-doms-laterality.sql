-- ─────────────────────────────────────────────────────────────────────────────
-- W9 · The body has two sides — `doms_logs` grows `side` and `sub_region`
--
-- Paste this into the Supabase SQL editor. Nothing in the repo can apply it:
-- this machine holds no service-role key and there is no staging database.
--
-- Safe to run twice. Every statement is `if not exists` / `if exists`, and the
-- one destructive line drops a UNIQUE KEY that the new index replaces exactly.
--
-- ── WHAT IT CHANGES, AND WHY EACH PART ───────────────────────────────────────
--
--   1. Two nullable text columns. NULL is the pre-W9 meaning: `side` NULL is
--      "both", `sub_region` NULL is "the whole muscle". NOT NULL with a default
--      was the other option and was rejected — it would rewrite every existing
--      row's payload, and the app relies on a nil column being OMITTED from the
--      push body (`encodeIfPresent`) so that a bilateral rating's request and
--      its export token stay byte-identical to what v1 sent.
--
--   2. The old unique key over `(user_id, date, muscle_group)` goes. It is the
--      one thing making laterality impossible: with it in place a left glute
--      and a right glute collide on insert no matter what the new columns say.
--
--   3. A wider unique index, `NULLS NOT DISTINCT`.
--
--      ⚠ `NULLS NOT DISTINCT` needs Postgres 15 or newer. Supabase has shipped
--        15+ on every new project since 2023; if this line errors with a syntax
--        error near `NULLS`, the project predates that and needs a Postgres
--        upgrade before the rest of this file is meaningful.
--
--      Postgres treats NULLs as DISTINCT in a unique index by default, so
--      without this clause every legacy row (side NULL) would be unique against
--      every other legacy row — the constraint would not constrain, and, worse,
--      `ON CONFLICT` would never fire for a bilateral rating, so each re-rating
--      of a whole muscle would INSERT a second row instead of updating the
--      first. The clause is what lets absence keep meaning "both" instead of
--      meaning "a value nobody can match".
--
--      It is a plain column list and not an expression index over
--      `coalesce(side,'both')` for a mechanical reason: PostgREST's
--      `?on_conflict=` takes COLUMN NAMES and emits `ON CONFLICT (a, b, c)`. It
--      cannot spell a `coalesce(...)`, so an expression index would be
--      unreachable from the client and every upsert would fail outright with
--      "no unique or exclusion constraint matching the ON CONFLICT
--      specification".
--
--   4. Two CHECK constraints, so a row that reaches the scoring fold is one the
--      fold can read. `side` is the three words `DomsMuscles.sides` knows;
--      `sub_region` is non-empty when present, because `''` and NULL would
--      otherwise be two spellings of "the whole muscle" and the unique index
--      would let both exist for one muscle.
--
-- ── WHAT IT DOES NOT DO ──────────────────────────────────────────────────────
-- No backfill, and none is needed: every existing row is a whole-muscle
-- bilateral rating, which is exactly what NULL already says. No rescore either
-- — the scoring fold takes the MAX within a muscle, so splitting a rating into
-- a left and a right cannot move a battery a single row at the same peak did
-- not already move.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- 1 ── The columns.
alter table public.doms_logs add column if not exists side       text;
alter table public.doms_logs add column if not exists sub_region text;

comment on column public.doms_logs.side is
  'both | left | right. NULL means both — the pre-W9 meaning of an absent column.';
comment on column public.doms_logs.sub_region is
  'Traps, Erectors, Adductors, … NULL means the whole muscle. Record-only: nothing in the scoring path reads it.';

-- 2 ── The old key, whatever shape it was declared in.
--
-- A named constraint and a bare unique index are dropped by different
-- statements and the schema was never checked in, so both are attempted. The
-- DO block finds anything unique over exactly those three columns rather than
-- guessing at a name Supabase may have generated.
do $$
declare
  target text;
begin
  for target in
    select c.conname
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public'
       and t.relname = 'doms_logs'
       and c.contype = 'u'
       and (
         select array_agg(a.attname order by a.attname)
           from unnest(c.conkey) as k(attnum)
           join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
       ) = array['date', 'muscle_group', 'user_id']
  loop
    execute format('alter table public.doms_logs drop constraint %I', target);
    raise notice 'dropped constraint %', target;
  end loop;

  for target in
    select i.relname
      from pg_index x
      join pg_class i on i.oid = x.indexrelid
      join pg_class t on t.oid = x.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public'
       and t.relname = 'doms_logs'
       and x.indisunique
       and not exists (select 1 from pg_constraint c where c.conindid = i.oid)
       and (
         select array_agg(a.attname order by a.attname)
           from unnest(x.indkey) as k(attnum)
           join pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
       ) = array['date', 'muscle_group', 'user_id']
  loop
    execute format('drop index public.%I', target);
    raise notice 'dropped index %', target;
  end loop;
end $$;

-- 3 ── The wider key. This is the name PostgREST's `on_conflict` resolves
--      against, and the column ORDER here is the order the client sends:
--      user_id, date, muscle_group, side, sub_region.
create unique index if not exists doms_logs_user_date_muscle_side_sub_key
  on public.doms_logs (user_id, date, muscle_group, side, sub_region)
  nulls not distinct;

-- 4 ── The vocabulary, stated where it cannot drift.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'doms_logs_side_check' and conrelid = 'public.doms_logs'::regclass
  ) then
    alter table public.doms_logs
      add constraint doms_logs_side_check
      check (side is null or side in ('both', 'left', 'right'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'doms_logs_sub_region_check' and conrelid = 'public.doms_logs'::regclass
  ) then
    alter table public.doms_logs
      add constraint doms_logs_sub_region_check
      check (sub_region is null or length(sub_region) > 0);
  end if;
end $$;

commit;

-- ── VERIFY ───────────────────────────────────────────────────────────────────
-- Both columns present, one unique index over five columns, nothing unique over
-- three. Run it after the commit and read the counts — "no output" is not a pass.
--
--   select column_name, is_nullable
--     from information_schema.columns
--    where table_name = 'doms_logs' and column_name in ('side', 'sub_region');
--   -- expect exactly 2 rows, both YES
--
--   select indexname, indexdef
--     from pg_indexes
--    where tablename = 'doms_logs' and indexdef ilike '%unique%';
--   -- expect doms_logs_user_date_muscle_side_sub_key, and it must read
--   -- "(user_id, date, muscle_group, side, sub_region) NULLS NOT DISTINCT"
