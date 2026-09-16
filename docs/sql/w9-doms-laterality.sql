-- ─────────────────────────────────────────────────────────────────────────────
-- W9 · The body has two sides — `doms_logs` learns to hold a left and a right
--
-- Paste this into the Supabase SQL editor. Nothing in the repo can apply it:
-- this machine holds no service-role key and there is no staging database.
--
-- Safe to run twice, and safe to run on a table that has already had it.
--
-- ── WHAT WAS ACTUALLY WRONG, AND IT WAS NOT THE COLUMNS ──────────────────────
-- The plan said `doms_logs` had no `side` and no `sub_region`. It has both: the
-- retired web app added them, declared them NOT NULL, and spelled "the whole
-- muscle, both sides" as `side = 'both'` / `sub_region = ''`.
--
-- So the columns were never the problem. The problem is the UNIQUE KEY over
-- `(user_id, date, muscle_group)`, which allows exactly one rating per muscle
-- per day — a left glute and a right glute collide on insert no matter what the
-- other two columns say. That key is what this file replaces.
--
-- ── THE SPELLING THIS FILE SETTLES ───────────────────────────────────────────
-- `'both'` and `''` are the canonical values, because that is what the table
-- already holds and what its NOT NULL constraints already require. The native
-- app has been changed to write the same, so there is ONE spelling of "the whole
-- muscle, both sides" everywhere: in Postgres, in the phone's local store, on
-- the wire and in the export.
--
-- This matters more than it looks. A unique index treats `('both','')` and
-- `(NULL, NULL)` as DIFFERENT keys, so two spellings would mean re-rating a
-- muscle the web app had already rated INSERTS a second row beside the first
-- rather than updating it — one muscle, one day, two ratings, forever. Anything
-- in the table that does not already read as `left` or `right` is therefore
-- normalised to `'both'`, and an absent or blank sub-region to `''`.
--
-- Because both columns end up NOT NULL, the new index needs no `NULLS NOT
-- DISTINCT` and this file has no Postgres 15 requirement.
--
-- ── WHAT IT DOES NOT DO ──────────────────────────────────────────────────────
-- It never deletes a row on its own. If two ratings would collapse onto one key
-- it stops, rolls back, and points at a query that shows you what is involved.
--
-- No rescore is needed either: the scoring fold takes the MAX within a muscle,
-- so splitting a rating into a left and a right cannot move a battery that a
-- single row at the same peak did not already move.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- 1 ── The columns, for a database that somehow does not have them.
--      On the live table both of these are no-ops.
alter table public.doms_logs add column if not exists side       text;
alter table public.doms_logs add column if not exists sub_region text;

-- 2 ── The old key, whatever shape it was declared in.
--
-- A named constraint and a bare unique index are dropped by different
-- statements and the schema was never checked in, so both are attempted. The
-- DO block finds anything unique over exactly those three columns rather than
-- guessing at a name Supabase may have generated. A constraint's own index is
-- dropped with it, and the second loop skips constraint-backed indexes, so
-- nothing is dropped twice.
--
-- Both loops COUNT matching columns rather than comparing arrays. An earlier
-- draft compared `array_agg(a.attname)` against `array['date', …]` and failed
-- with `ERROR: 42883: operator does not exist: name[] = text[]`, because
-- `pg_attribute.attname` is `name` and not `text`. A count has no composite
-- type to get wrong and does not care what order the columns were declared in.
--
-- The index loop also avoids `unnest(x.indkey)`: `indkey` is an `int2vector`,
-- which is not an array type, so `unnest()` — declared over `anyarray` — does
-- not resolve against it. Its text form is space-separated numbers.
do $$
declare
  target text;
begin
  for target in
    select c.conname
      from pg_constraint c
     where c.conrelid = 'public.doms_logs'::regclass
       and c.contype = 'u'
       and coalesce(array_length(c.conkey, 1), 0) = 3
       and (
         select count(*)
           from unnest(c.conkey) as k(attnum)
           join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
          where a.attname in ('user_id', 'date', 'muscle_group')
       ) = 3
  loop
    execute format('alter table public.doms_logs drop constraint %I', target);
    raise notice 'dropped constraint %', target;
  end loop;

  for target in
    select i.relname
      from pg_index x
      join pg_class i on i.oid = x.indexrelid
     where x.indrelid = 'public.doms_logs'::regclass
       and x.indisunique
       and x.indnkeyatts = 3
       and not exists (select 1 from pg_constraint c where c.conindid = i.oid)
       and (
         select count(*)
           from unnest(string_to_array(x.indkey::text, ' ')::int2[]) as k(attnum)
           join pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
          where a.attname in ('user_id', 'date', 'muscle_group')
       ) = 3
  loop
    execute format('drop index public.%I', target);
    raise notice 'dropped index %', target;
  end loop;
end $$;

-- 3 ── One spelling, and then the constraints that keep it.
--
-- `left` and `right` survive, case- and whitespace-insensitively. EVERYTHING
-- else becomes `'both'` — including NULL, including a value nobody can explain.
-- That is the rule `BodySide(stored:)` applies in Swift, and it is the safe
-- direction: an unreadable side must not be able to claim a half of the body,
-- and "the whole muscle" is the only answer that cannot be wrong about which
-- half hurts. Whatever it collapsed is reported, so nothing goes quietly.
do $$
declare
  found_sides text;
  moved_side  bigint;
  moved_sub   bigint;
  collisions  bigint;
begin
  select string_agg(distinct coalesce(quote_literal(side), 'NULL'), ', ')
    into found_sides
    from public.doms_logs
   where side is null or lower(btrim(side)) not in ('left', 'right', 'both');
  if found_sides is not null then
    raise notice 'normalising these side values to ''both'': %', found_sides;
  end if;

  update public.doms_logs
     set side = case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' else 'both' end
   where side is distinct from
         (case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' else 'both' end);
  get diagnostics moved_side = row_count;

  update public.doms_logs
     set sub_region = coalesce(btrim(sub_region), '')
   where sub_region is distinct from coalesce(btrim(sub_region), '');
  get diagnostics moved_sub = row_count;

  raise notice 'normalised % side value(s) and % sub_region value(s)', moved_side, moved_sub;

  -- Normalising can only collide where the old three-column key was NOT
  -- enforcing one row per muscle per day. Where it was, every row for a
  -- (user, date, muscle) is already the only one, so collapsing its side and
  -- sub-region cannot meet a twin. Checked rather than assumed, because the
  -- index below would otherwise fail with a duplicate-key error that names a
  -- row and not a cause — and because the alternative is this file deleting
  -- rows from a production table without being asked.
  select count(*) into collisions from (
    select 1 from public.doms_logs
     group by user_id, date, muscle_group, side, sub_region
    having count(*) > 1
  ) dupes;

  if collisions > 0 then
    raise exception using
      errcode = 'unique_violation',
      message = format('%s duplicate (user, date, muscle, side, sub_region) group(s) after normalising', collisions),
      hint    = 'Nothing has been changed — this transaction rolls back. '
                'See the DEDUPE block in the comments at the end of this file, '
                'read what it would remove, then run it before this file again.';
  end if;
end $$;

-- The defaults are what let the app push a bilateral rating without naming
-- either column, and NOT NULL is what the live table already said. Both are
-- restated rather than assumed, so a database that had one and not the other
-- ends up in the same place as one that had both.
alter table public.doms_logs alter column side       set default 'both';
alter table public.doms_logs alter column sub_region set default '';
alter table public.doms_logs alter column side       set not null;
alter table public.doms_logs alter column sub_region set not null;

comment on column public.doms_logs.side is
  'both | left | right. ''both'' is a whole-muscle rating and the default.';
comment on column public.doms_logs.sub_region is
  'Traps, Erectors, Adductors, … '''' is the whole muscle and the default. Record-only: nothing in the scoring path reads it.';

-- 4 ── The wider key. This is what PostgREST's `on_conflict` resolves against,
--      and the column ORDER here is the order the client sends:
--      user_id, date, muscle_group, side, sub_region.
--
--      A plain column list: both columns are NOT NULL, so there are no NULLs
--      for the index to have an opinion about and no `NULLS NOT DISTINCT` is
--      needed. An expression index over `coalesce(...)` was the other option
--      and is unusable — PostgREST's `?on_conflict=` takes COLUMN NAMES and
--      emits `ON CONFLICT (a, b, c)`, so it cannot name an expression and every
--      upsert would fail with "no unique or exclusion constraint matching the
--      ON CONFLICT specification".
create unique index if not exists doms_logs_user_date_muscle_side_sub_key
  on public.doms_logs (user_id, date, muscle_group, side, sub_region);

-- 5 ── The vocabulary, stated where it cannot drift.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'doms_logs_side_check' and conrelid = 'public.doms_logs'::regclass
  ) then
    alter table public.doms_logs
      add constraint doms_logs_side_check
      check (side in ('both', 'left', 'right'));
  end if;
end $$;

commit;

-- ── VERIFY ───────────────────────────────────────────────────────────────────
-- Run all four after the commit and READ THE COUNTS — "no error" is not a pass.
--
--   select column_name, is_nullable, column_default
--     from information_schema.columns
--    where table_name = 'doms_logs' and column_name in ('side', 'sub_region');
--   -- expect 2 rows, both NO, defaults 'both'::text and ''::text
--
--   select indexname, indexdef
--     from pg_indexes
--    where tablename = 'doms_logs' and indexdef ilike '%unique%';
--   -- expect doms_logs_pkey and doms_logs_user_date_muscle_side_sub_key, the
--   -- second over (user_id, date, muscle_group, side, sub_region)
--
--   select count(*) as old_key_survivors
--     from pg_index x
--    where x.indrelid = 'public.doms_logs'::regclass
--      and x.indisunique and x.indnkeyatts = 3
--      and (select count(*)
--             from unnest(string_to_array(x.indkey::text, ' ')::int2[]) as k(attnum)
--             join pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
--            where a.attname in ('user_id', 'date', 'muscle_group')) = 3;
--   -- expect 0. Anything else means step 2 found nothing to drop, and a
--   -- one-sided rating will still collide with the whole-muscle one.
--
--   select count(*) as unreadable_rows from public.doms_logs
--    where side not in ('both', 'left', 'right') or sub_region is null;
--   -- expect 0
--
-- ── DEDUPE — ONLY IF STEP 3 RAISED ───────────────────────────────────────────
-- This file never deletes a row on its own. If step 3 stopped with "N duplicate
-- group(s) after normalising", two rows collapse onto one key — which can only
-- happen if the old three-column unique key was not there to prevent it.
--
-- Both statements below group by the NORMALISED value, not by the stored one.
-- That is not a detail: this file rolled back, so the un-normalised spellings
-- are still in the table when you run these, and grouping by the raw column
-- would put `'BOTH'` and `'both'` in different groups, find nothing to remove,
-- and leave you looping on the same error.
--
-- LOOK FIRST. This shows exactly what would go:
--
--   with n as (
--     select id, user_id, date, muscle_group, severity, created_at,
--            case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' else 'both' end as side_n,
--            coalesce(btrim(sub_region), '') as sub_n
--       from public.doms_logs)
--   select user_id, date, muscle_group, side_n as side, sub_n as sub_region,
--          count(*) as rows, array_agg(severity order by severity desc) as severities
--     from n
--    group by 1, 2, 3, 4, 5
--   having count(*) > 1;
--
-- Then, if you are happy with it, keep the WORST of each group and drop the
-- rest. Max-within-a-muscle is the fold the scoring engine, the export and the
-- summary line all already apply, so the row this keeps is the only one any of
-- them was ever reading — no battery, document or tile can move because of it:
--
--   with n as (
--     select id, user_id, date, muscle_group, severity, created_at,
--            case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' else 'both' end as side_n,
--            coalesce(btrim(sub_region), '') as sub_n
--       from public.doms_logs),
--   ranked as (
--     select id, row_number() over (
--              partition by user_id, date, muscle_group, side_n, sub_n
--              order by severity desc, created_at desc nulls last, id) as rn
--       from n)
--   delete from public.doms_logs d
--    using ranked
--    where ranked.id = d.id and ranked.rn > 1;
--
-- Then run this file again.
--
-- ── HOW THIS FILE WAS CHECKED ────────────────────────────────────────────────
-- Executed against a real PostgreSQL 17 cluster before being handed over, on
-- five starting shapes: the live one (both columns NOT NULL with 'both'/''
-- defaults and the three-column unique constraint, including the exact row the
-- third error named); the same with the columns NULLABLE; the same with the
-- columns absent entirely; a table whose old key was a bare unique INDEX with
-- the columns in a different order; and a table that never had the key at all.
-- Each was also run twice.
--
-- In every case: the old key is gone, the five-column index exists, both
-- columns are NOT NULL with defaults, and — the assertion that actually
-- matters — an `insert … on conflict (user_id, date, muscle_group, side,
-- sub_region)` that names NEITHER column, exactly as the app pushes a bilateral
-- rating, UPDATES the existing row in place rather than inserting beside it,
-- while a one-sided rating of the same muscle inserts as its own row.
