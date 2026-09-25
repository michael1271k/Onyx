---
version: 1
slug: "native-onyx-features-programs-goalsetupsheet-swift"
primary_target: "native/Onyx/Features/Programs/GoalSetupSheet.swift"
related_targets: []
---

# Surface brief — Goal setup (3-screen sheet)

Shaped 2026-09-25 by `impeccable shape`, Precision sprint Lane E (E3). No live
interview (lane brief forbids questions); assumptions marked.

## Scope and mode
Operate. One sheet, three steps, opened from `ProgramEditorView` (that plan)
and from Settings → Plan & targets → "Goal" (the active plan). Same chrome as
onboarding (progress rail, heading, content, footer with Back + one specific
primary) because it is the same kind of task and a person has seen it once.

## Job and audience
"I want to cut to 72 kg by Christmas — what should I eat, and is that pace
sane?" Success: goal chosen, current metrics prefilled from the latest
weigh-in, a target and horizon produce an implied weekly rate judged against a
safe band, and editable macros are saved to the plan's phase goals and applied
if the plan is running.

## Selected direction
- Step 1 "Goal": five selectable rows (Bulk · Cut · Recomp · Muscle mass ·
  Body fat %) each with one line saying what it does — the onboarding goal-row
  vocabulary (radio glyph, `.row` slab).
- Step 2 "Where you are": a `.row` slab of current metrics (weight, body-fat %,
  muscle mass, BMR — `OnyxNumberRow`, prefilled, caption "From your weigh-in on
  24 Sep"), a slab with the target (its unit follows the goal) and a horizon
  stepper (weeks). The screen's ONE hero: the implied weekly rate
  ("−0.42 kg/wk") with a band bar under it: the safe band as a filled segment,
  the implied rate as a tick; verdict line in good green (inside) or record
  gold (outside — gold's allowed threshold job).
- Step 3 "Targets": kcal as the hero figure, then the four macros editable
  (`OnyxNumberRow`), the Atwater gap note (as onboarding), a recommended
  template card ("Recommended for a cut: Onyx-4 · 4 days") with one button —
  "Fill this program with it" when the program is empty, else "Start a program
  from it". Primary: "Save goal" (running plan: "Save and apply").

## States and ranges
No weigh-in → fields blank with 75 kg default only for weight? NO — assumption:
blank, and step 2's primary is disabled until weight is entered (the arithmetic
needs it); every other metric optional. Recomp target = weight (maintain), band
0. Body fat % target converts to a weight at constant lean mass; muscle-mass
target converts to a weight at constant everything-else (lower bound, stated
in a caption). Horizon 2–104 weeks.

## Constraints
No sex/age inputs (App Review 5.1.1). Kcal from `StartingTargetsBuilder`
(27/33/37 kcal/kg; recomp = 33 with the cut's protein). Nothing is written
until the last tap.
