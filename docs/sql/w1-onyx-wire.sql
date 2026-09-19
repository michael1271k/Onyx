-- ════════════════════════════════════════════════════════════════════════════
-- w1-onyx-wire.sql — the server half of `v32.onyxWire` (Onyx Expansion, W1)
--
-- Paste into the Supabase SQL editor and run the whole file.
--
-- ── RUN THIS *BEFORE* 7.0.0 REACHES ANY DEVICE ─────────────────────────────
-- Not "either order". `v32.onyxWire` is a GRDB migration: the migrator records
-- it by name and NEVER runs it again. Nothing rewrites a row that arrives
-- afterwards. So if 7.0.0 installs and syncs before this file has run, every
-- `set_events` row pulled in that window keeps the old stamp permanently, and
-- that movement's history splits in two — which is the whole failure this
-- migration exists to prevent. (7.0.0 also strips an unrecognised stamp when
-- it resolves a slug, so a straggler degrades instead of jamming the outbox;
-- that is a safety net, not a substitute for running this first.)
--
-- ── v2 — WHAT CHANGED AFTER THE FIRST ATTEMPT ──────────────────────────────
-- The founder ran v1 and Postgres refused it:
--
--   ERROR: 23514: new row for relation "plan_phases" violates check
--   constraint "plan_phases_era_check"
--
-- `plan_phases.era` carries a CHECK constraint that allows `ppl` and the
-- predecessor's value and nothing else. The UPDATE was correct; the column
-- would not accept it. §1 now drops that constraint, rewrites the rows, and
-- puts an equivalent constraint back naming the two values `PhaseEra`
-- actually has. That is DDL, so §1 is the only part of this file that changes
-- the schema, and it changes it back to the same SHAPE it had.
--
-- The seven stored reports (§5) are now part of the transaction too, at the
-- founder's instruction: zero trace of the old name anywhere.
--
-- ── WHY NOTHING BELOW SPELLS THE OLD NAME ──────────────────────────────────
-- The point of the wave is that the predecessor's name is gone from every byte
-- of the repository, and this file lives in it. It does not need the name:
--   · `plan_phases.era` has exactly TWO values in the domain (`PhaseEra`), so
--     "not ppl" names the rows exactly.
--   · an exercise slug was stamped `<word><digit>-<kebab-name>`, so
--     `^[a-z]+[0-9]-` matches the old stamp, and a migrated slug already
--     starts `onyx-`.
--   · the reports' masthead is `⬢ <word> OS ·`, so the word between is
--     replaced by position.
-- The BODY after the first hyphen is never touched, so every movement keeps
-- its identity and only the stamp in front of it changes.
--
-- ── AND WHY A uuid IS EXCLUDED BY NAME, NOT BY ARGUMENT ────────────────────
-- A uuid's first hyphen is at position nine, so any uuid whose first seven hex
-- characters are all letters a–f and whose eighth is a digit — `abcdefa1-…` —
-- matches `^[a-z]+[0-9]-`. About one in 1,500, and `set_events.body` holds a
-- MIX of resolved uuids and unresolved slugs, so it is not a theoretical
-- column. Re-stamping one would point a synced set at a catalogue row that
-- does not exist.
--
-- ── THE TWO HALVES MUST DECIDE IDENTICALLY ─────────────────────────────────
-- `AppDatabase.onyxWireId` answers the same question on the phone. If these
-- two predicates disagree about one id, that movement is renamed on one
-- machine and not the other. Change one, change both;
-- `OnyxWireMigrationTests.matchesThePostgresPredicate` pins the Swift side to
-- the regex below, case for case.
--
-- ── WHAT IS DELIBERATELY NOT HERE ──────────────────────────────────────────
-- Introspected from the live database on 2026-09-19, before a line was written:
--
--   workout_sets.exercise_id     uuid, 2500 rows, 0 matches — a uuid column
--                                CANNOT hold a slug. The slug reaches the
--                                server only inside `set_events.body`, and
--                                `ExerciseIndex` resolves it to a uuid on push.
--   personal_records.exercise_key  text, 81 rows, 0 matches — it holds a
--                                canonical DISPLAY NAME ("Seated Cable Row
--                                (V-Grip)"), never an id. Renaming keys here
--                                would invent a second history per lift.
--   plan_phases.era_tag          text, 8 rows, 0 matches — re-read live on
--                                2026-09-19: already "Onyx Cut", "Onyx · Week
--                                0", "PPL Bulk". The app renders THIS column,
--                                not `era`, so it was worth checking twice.
--                                It needs nothing.
--
-- Expected row counts, same introspection:
--   plan_phases.era      4 of 8
--   exercises.slug      46 of 46   (every row)
--   set_events.body    116 of 787
--   reports.content_md   7 of 17
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 0 · Before ──────────────────────────────────────────────────────────────
-- Read these. If every "rows_to_change" is 0 the work is already done.
SELECT 'plan_phases.era'  AS target, count(*) AS rows_to_change
  FROM plan_phases WHERE era IS NOT NULL AND era NOT IN ('ppl', 'onyx')
UNION ALL
SELECT 'exercises.slug',   count(*)
  FROM exercises   WHERE slug ~ '^[a-z]+[0-9]-'
   AND slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'set_events.body',  count(*)
  FROM set_events  WHERE body->'payload'->>'exercise_id' ~ '^[a-z]+[0-9]-'
   AND body->'payload'->>'exercise_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'reports.content_md', count(*)
  FROM reports     WHERE content_md ~ '⬢\s*\w+\s+OS\s*·';

-- Every CHECK constraint on the four tables, so a second refusal like the one
-- that stopped v1 is visible here rather than as an aborted transaction.
SELECT conrelid::regclass AS "table", conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE contype = 'c'
   AND conrelid IN ('public.plan_phases'::regclass, 'public.exercises'::regclass,
                    'public.set_events'::regclass,  'public.reports'::regclass)
 ORDER BY 1, 2;

-- ── 1 · plan_phases.era — the constraint, then the rows, then the constraint ─
-- THE ONLY DDL IN THIS FILE, and it is a replacement in kind: the column keeps
-- a CHECK that admits exactly the values `PhaseEra` can encode. `era` is
-- nullable and `PhaseDef.era` is Optional, so NULL stays admissible — absent
-- is not the same as an era, and rows that never claimed one must keep saying
-- so.
--
-- `IF EXISTS` so a re-run after a partial attempt does not fail on the drop.
ALTER TABLE plan_phases DROP CONSTRAINT IF EXISTS plan_phases_era_check;

UPDATE plan_phases
   SET era = 'onyx'
 WHERE era IS NOT NULL
   AND era NOT IN ('ppl', 'onyx');

ALTER TABLE plan_phases
  ADD CONSTRAINT plan_phases_era_check
  CHECK (era IS NULL OR era IN ('ppl', 'onyx'));

-- ── 2 · exercises.slug ──────────────────────────────────────────────────────
-- The catalogue's alias column — the map `ExerciseIndex.id(forSlug:)` resolves
-- a phone-stamped set through. All 46 rows carry the old stamp. This must
-- land, or a set logged on 7.0.0 finds no catalogue row.
UPDATE exercises
   SET slug = 'onyx-' || substring(slug from position('-' in slug) + 1)
 WHERE slug ~ '^[a-z]+[0-9]-'
   AND slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- ── 3 · set_events.body → payload → exercise_id ─────────────────────────────
-- The append log. The id is nested at `body.payload.exercise_id`; there is no
-- top-level `payload` column on this table (`routines.payload` and
-- `routine_templates.payload` are different tables and are not touched).
--
-- This cannot be skipped if §2 ran: any edit to a session reprojects it FROM
-- THIS LOG, so a log left on the old stamp would undo the projection and file
-- half a session under each name.
UPDATE set_events
   SET body = jsonb_set(
         body,
         '{payload,exercise_id}',
         to_jsonb('onyx-' || substring(
             body->'payload'->>'exercise_id'
             from position('-' in body->'payload'->>'exercise_id') + 1
         ))
       )
 WHERE body->'payload'->>'exercise_id' ~ '^[a-z]+[0-9]-'
   AND body->'payload'->>'exercise_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- ── 4 · reports.content_md — the seven stored reports ───────────────────────
-- Included at the founder's instruction (2026-09-19): zero trace anywhere.
--
-- These are DOCUMENTS, not identity values — nothing keys on them, and
-- `fmtV2.parseHeader` takes a report's title by POSITION, so they rendered
-- correctly either way. This is an archive decision, not a correctness fix,
-- and it rewrites seven historical documents to say something they did not say
-- when they were generated.
--
-- Structural, like everything above: it replaces the word between `⬢ ` and
-- ` OS ·` on the masthead, whatever that word is, and touches nothing else in
-- the body. `\w+` cannot cross the spaces around it, so a report body that
-- happens to contain the word elsewhere is untouched — only the masthead
-- matches the full `⬢ … OS ·` shape.
UPDATE reports
   SET content_md = regexp_replace(content_md, '(⬢\s*)\w+(\s+OS\s*·)', '\1ONYX\2', 'g')
 WHERE content_md ~ '⬢\s*\w+\s+OS\s*·';

-- ── 5 · AFTER ───────────────────────────────────────────────────────────────
-- Every number must be 0. If one is not, do NOT commit — ROLLBACK and say so.
SELECT 'plan_phases.era'  AS target, count(*) AS rows_left
  FROM plan_phases WHERE era IS NOT NULL AND era NOT IN ('ppl', 'onyx')
UNION ALL
SELECT 'exercises.slug',   count(*)
  FROM exercises   WHERE slug ~ '^[a-z]+[0-9]-'
   AND slug !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'set_events.body',  count(*)
  FROM set_events  WHERE body->'payload'->>'exercise_id' ~ '^[a-z]+[0-9]-'
   AND body->'payload'->>'exercise_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
UNION ALL
SELECT 'reports.content_md', count(*)
  FROM reports     WHERE content_md ~ '⬢\s*\w+\s+OS\s*·'
   AND content_md !~ '⬢\s*ONYX\s+OS\s*·';

-- And the constraint is back, admitting exactly the two values and NULL.
SELECT conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE conrelid = 'public.plan_phases'::regclass AND conname = 'plan_phases_era_check';

COMMIT;
-- ROLLBACK;   -- swap for COMMIT above if any "rows_left" came back non-zero
