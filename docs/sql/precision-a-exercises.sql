-- Precision A1 — the fifteen movements the catalogue shipped without (Q4).
--
-- Paste into the Supabase SQL editor. Idempotent: run it twice and the second
-- run inserts nothing.
--
-- THE ID IS THE APP'S ID. The phone creates the same fifteen on the first
-- library open (`StarterMovements` in ExercisePickerSheet.swift) under
-- md5(lower(user_id) || ':' || name) read as a uuid — exactly the expression
-- below. Whichever runs first, the other lands on the same row: the phone's push
-- upserts on `id`, and this insert does `on conflict (id) do nothing`. The
-- `not exists` guard also skips a name the account already holds under another
-- id (typed by hand before this ran).
--
-- `muscle_groups` and `is_compound` are what the phone's own wire writes
-- (`ExerciseWire`: the MuscleMap movers, primary first; compound = has an
-- assisting muscle), so the two paths agree field for field. `split_day` is
-- 'custom', the phone's value for a catalogue row that belongs to no day.
--
-- STEP 0 — THE CHECK THE PHONE HAS FAILED SINCE W5 (2026-09-11). Live
-- `exercises_split_day_check` allows only push/pull/legs/upper/lower (migration
-- 005), but `ExerciseWire` has always pushed 'custom'. Every movement the phone
-- created since then was refused with 23514 and is still in the outbox — never
-- dropped, retried at most hourly — so it lands on its own once this runs.
-- Idempotent: re-adding the same list the second time changes nothing.

alter table public.exercises drop constraint if exists exercises_split_day_check;
alter table public.exercises add constraint exercises_split_day_check
  check (split_day in ('push', 'pull', 'legs', 'upper', 'lower', 'custom'));

with owner(user_id) as (
  values ('f405d57b-d09f-4a2e-8a33-0c112f2ec34c'::uuid)
),
starter(name, equipment, muscle_groups, is_compound, rest_sec, rep_floor, rep_ceiling) as (
  values
    ('Squat (Barbell)',         array['Barbell']::text[], array['quadriceps','glutes','hamstrings','lower back']::text[],                  true,  120, 5,  8),
    ('Deadlift (Barbell)',      array['Barbell']::text[], array['hamstrings','glutes','lower back','upper back','traps','forearms']::text[], true, 120, 5,  8),
    ('Pull Up',                 '{}'::text[],             array['lats','upper back','biceps','forearms']::text[],                          true,  120, 6,  10),
    ('Chin Up',                 '{}'::text[],             array['lats','biceps','upper back','forearms']::text[],                          true,  120, 6,  10),
    ('Bent Over Row (Barbell)', array['Barbell']::text[], array['upper back','lats','biceps','lower back','forearms']::text[],             true,  120, 6,  10),
    ('Dumbbell Row',            array['DB']::text[],      array['upper back','lats','biceps','forearms']::text[],                          true,  120, 8,  12),
    ('Dips',                    '{}'::text[],             array['chest','triceps','front_delts']::text[],                                  true,  120, 8,  12),
    ('Bulgarian Split Squat',   array['DB']::text[],      array['quadriceps','glutes','hamstrings']::text[],                               true,  120, 8,  12),
    ('Walking Lunge',           array['DB']::text[],      array['quadriceps','glutes','hamstrings']::text[],                               true,  120, 8,  12),
    ('Reverse Fly',             array['DB']::text[],      array['rear_delts','upper back']::text[],                                        true,   90, 12, 15),
    ('Push Up',                 '{}'::text[],             array['chest','triceps','front_delts']::text[],                                  true,  120, 10, 20),
    ('Shrug (Dumbbell)',        array['DB']::text[],      array['traps']::text[],                                                          false,  90, 10, 15),
    ('Front Squat',             array['Barbell']::text[], array['quadriceps','glutes','abdominals']::text[],                               true,  120, 5,  8),
    ('Skull Crusher',           array['Barbell']::text[], array['triceps']::text[],                                                        false,  90, 10, 15),
    ('Arnold Press',            array['DB']::text[],      array['front_delts','side_delts','triceps']::text[],                             true,  120, 8,  12)
)
insert into public.exercises
  (id, user_id, name, split_day, muscle_groups, is_compound, equipment, rest_sec, rep_floor, rep_ceiling)
select
  md5(lower(o.user_id::text) || ':' || s.name)::uuid,
  o.user_id, s.name, 'custom', s.muscle_groups, s.is_compound, s.equipment,
  s.rest_sec, s.rep_floor, s.rep_ceiling
from starter s
cross join owner o
where not exists (
  select 1 from public.exercises e
  where e.user_id = o.user_id and lower(e.name) = lower(s.name)
)
on conflict (id) do nothing;

-- VERIFY: fifteen rows, and each id equals the expression (true in `matches`).
select name, id, id = md5(lower(user_id::text) || ':' || name)::uuid as matches
from public.exercises
where user_id = 'f405d57b-d09f-4a2e-8a33-0c112f2ec34c'
  and name in ('Squat (Barbell)','Deadlift (Barbell)','Pull Up','Chin Up','Bent Over Row (Barbell)',
               'Dumbbell Row','Dips','Bulgarian Split Squat','Walking Lunge','Reverse Fly','Push Up',
               'Shrug (Dumbbell)','Front Squat','Skull Crusher','Arnold Press')
order by name;
