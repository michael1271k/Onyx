-- W1 · stress as an event log. Paste into the Supabase SQL editor.
-- 1. The event time. Existing rows take their creation time.
alter table public.stress_logs add column if not exists logged_at timestamptz;
update public.stress_logs set logged_at = created_at where logged_at is null;

-- 2. Drop the one-row-per-slot rule, whatever it is called: any UNIQUE
--    constraint or unique index whose columns are exactly (user_id, date, slot),
--    in any column order. Expect ONE "dropped …" notice. Zero notices means the
--    rule was never there — still read step 3's verify SELECTs before trusting it.
do $$
declare r record;
begin
  for r in
    select c.conname as name, 'constraint' as kind
    from pg_constraint c
    where c.conrelid = 'public.stress_logs'::regclass
      and c.contype = 'u'
      and (select array_agg(a.attname::text order by a.attname)
           from unnest(c.conkey) k join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k)
          = array['date','slot','user_id']
    union all
    select i.indexname, 'index'
    from pg_indexes i
    where i.schemaname = 'public' and i.tablename = 'stress_logs'
      and i.indexdef ilike 'create unique index%'
      and (select array_agg(trim(x) order by trim(x))
           from unnest(string_to_array(substring(i.indexdef from '\((.*)\)'), ',')) x)
          = array['date','slot','user_id']
      and not exists (select 1 from pg_constraint c where c.conname = i.indexname)
  loop
    if r.kind = 'constraint' then
      execute format('alter table public.stress_logs drop constraint %I', r.name);
    else
      execute format('drop index public.%I', r.name);
    end if;
    raise notice 'dropped % %', r.kind, r.name;
  end loop;
end $$;

-- 3. Verify: expect one primary key only, and logged_at present.
select conname, contype, pg_get_constraintdef(oid) from pg_constraint
 where conrelid = 'public.stress_logs'::regclass;
select column_name, data_type, is_nullable from information_schema.columns
 where table_schema = 'public' and table_name = 'stress_logs' order by ordinal_position;
