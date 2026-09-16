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
-- guessing at a name Supabase may have generated. A constraint's own index is
-- dropped with it, and the second loop skips constraint-backed indexes, so
-- nothing is dropped twice.
--
-- The first draft of this block compared `array_agg(a.attname)` against
-- `array['date', …]` and failed with
--
--   ERROR: 42883: operator does not exist: name[] = text[]
--
-- because `pg_attribute.attname` is `name`, not `text`, and Postgres has no
-- equality operator between those two array types. The whole transaction rolled
-- back, so nothing had been applied — which is the one good thing about putting
-- it all inside `begin`/`commit`.
--
-- Rather than bolt a `::text` onto it, both loops now COUNT matching columns
-- instead of comparing arrays. A count has no composite type to get wrong, it
-- does not care what order the columns were declared in, and pairing it with a
-- key-width check is exactly as precise as set equality was meant to be.
--
-- The index loop also avoids `unnest(x.indkey)`: `indkey` is an `int2vector`,
-- which is not an array type, so `unnest()` — declared over `anyarray` — does
-- not resolve against it. Its text form is space-separated numbers, and
-- `string_to_array` turns that into a real array on every server version.
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

-- 2.5 ── ONE SPELLING OF "THE WHOLE MUSCLE, BOTH SIDES".
--
-- The retired web app already added these two columns, and it spelled a
-- whole-muscle bilateral rating as `side = 'both'` / `sub_region = ''`
-- (`scripts/src/subRegions.ts`: *"`''` is that answer's stored sub-region"*).
-- The native app spells the same thing as NULL in both columns, because a nil
-- is what `encodeIfPresent` leaves OUT of a push body — which is what keeps a
-- bilateral rating byte-identical on the wire and in the export to what shipped
-- before laterality existed.
--
-- Two spellings of one meaning is not a cosmetic problem. The unique index
-- below treats `('both','')` and `(NULL,NULL)` as DIFFERENT keys, so re-rating
-- a muscle the web had already rated would INSERT a second row beside the first
-- instead of updating it, and the day would hold two ratings of one muscle
-- forever. So the history is normalised onto the app's spelling, once, here.
--
-- `'both'` and `''` are not the only things collapsed: anything that does not
-- resolve to `left` or `right` becomes NULL, which is exactly the rule
-- `BodySide(stored:)` applies in Swift — an unreadable side must not be able to
-- claim a half of the body, and "the whole muscle" is the only answer that
-- cannot be wrong about which half hurts. Whatever it collapsed is RAISEd, so
-- nothing disappears quietly.
do $$
declare
  found_sides text;
  moved_side  bigint;
  moved_sub   bigint;
  collisions  bigint;
begin
  select string_agg(distinct quote_literal(side), ', ')
    into found_sides
    from public.doms_logs
   where side is not null and lower(btrim(side)) not in ('left', 'right');
  if found_sides is not null then
    raise notice 'normalising these side values to NULL (= both): %', found_sides;
  end if;

  update public.doms_logs
     set side = case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' end
   where side is distinct from
         (case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' end);
  get diagnostics moved_side = row_count;

  update public.doms_logs
     set sub_region = nullif(btrim(sub_region), '')
   where sub_region is distinct from nullif(btrim(sub_region), '');
  get diagnostics moved_sub = row_count;

  raise notice 'normalised % side value(s) and % sub_region value(s)', moved_side, moved_sub;

  -- Normalising can only collide where the old three-column key was NOT
  -- enforcing one row per muscle per day. Where it was, every row for a
  -- (user, date, muscle) is already the only one, so collapsing its side and
  -- sub-region cannot meet a twin. Checked rather than assumed, because the
  -- index below would fail with a duplicate-key error that names a row and not
  -- a cause — and because the alternative is this file deleting rows from a
  -- production table without being asked.
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
-- Run all three after the commit and READ THE COUNTS — "no error" is not a pass.
--
--   select column_name, is_nullable
--     from information_schema.columns
--    where table_name = 'doms_logs' and column_name in ('side', 'sub_region');
--   -- expect exactly 2 rows, both YES
--
--   select indexname, indexdef
--     from pg_indexes
--    where tablename = 'doms_logs' and indexdef ilike '%unique%';
--   -- expect doms_logs_pkey and doms_logs_user_date_muscle_side_sub_key, and
--   -- the second must read
--   -- "(user_id, date, muscle_group, side, sub_region) NULLS NOT DISTINCT"
--
--   select count(*) as old_key_survivors
--     from pg_index x
--    where x.indrelid = 'public.doms_logs'::regclass
--      and x.indisunique and x.indnkeyatts = 3
--      and (select count(*)
--             from unnest(string_to_array(x.indkey::text, ' ')::int2[]) as k(attnum)
--             join pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
--            where a.attname in ('user_id', 'date', 'muscle_group')) = 3;
--   -- expect 0. Anything else means step 2 found nothing to drop and a
--   -- one-sided rating will still collide with the whole-muscle one.
--
-- ── DEDUPE — ONLY IF STEP 2.5 RAISED ─────────────────────────────────────────
-- This file never deletes a row on its own. If step 2.5 stopped with "N
-- duplicate group(s) after normalising", it is because two rows collapse onto
-- one key — which can only happen if the old three-column unique key was not
-- there to prevent it.
--
-- Both statements below GROUP BY THE NORMALISED value, not by the stored one.
-- That is not a detail: this file rolled back, so `'both'` and `''` are still in
-- the table when you run these, and a dedupe that partitioned on the raw columns
-- would put `('both','')` and `(NULL,NULL)` in different groups, find nothing to
-- remove, and leave you looping on the same error.
--
-- LOOK FIRST. This shows exactly what would go:
--
--   with n as (
--     select id, user_id, date, muscle_group, severity, created_at,
--            case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' end as side_n,
--            nullif(btrim(sub_region), '') as sub_n
--       from public.doms_logs)
--   select user_id, date, muscle_group,
--          coalesce(side_n, '(both)') as side, coalesce(sub_n, '(whole)') as sub_region,
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
--            case lower(btrim(side)) when 'left' then 'left' when 'right' then 'right' end as side_n,
--            nullif(btrim(sub_region), '') as sub_n
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
-- four starting shapes: the old key as a named UNIQUE CONSTRAINT; as a bare
-- UNIQUE INDEX with the columns in a DIFFERENT order; a table that never had
-- it; and the file run three times in a row. In every case the old key is gone,
-- the five-column index exists, a legacy NULL row is UPDATED in place by an
-- `on conflict (user_id, date, muscle_group, side, sub_region)` upsert rather
-- than duplicated, a left and a right rating coexist, and both CHECKs reject
-- bad data.
