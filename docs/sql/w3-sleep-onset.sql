-- W3 · Sleep v2 (6.0.0) — two columns on sleep_sessions.
--
-- Paste in the Supabase SQL editor as `postgres` BEFORE installing the 6.0.0
-- build: the outbox upsert carries `onset_time` and `awakenings` from the first
-- night synced, and PostgREST rejects a column it cannot find.
--
-- Idempotent — safe to run again. Proved on a throwaway local PG17 cluster
-- (127.0.0.1) three times over: the W3 Wave Record has the probe.
--
-- onset_time  — when sleep began: the earliest asleep HealthKit sample. NULL on
--               every night written before W3; the scorer drops the latency term.
-- awakenings  — merged awake intervals of 5 min or more. NULL before W3; the
--               fragmentation term reads awake_min alone.

alter table public.sleep_sessions add column if not exists onset_time timestamptz;
alter table public.sleep_sessions add column if not exists awakenings int4;

-- VERIFY (read-only): both rows must come back, nullable, no default.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'sleep_sessions'
  and column_name in ('onset_time', 'awakenings')
order by column_name;
