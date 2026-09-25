---
version: 1
slug: "native-onyx-features-programs-programsview-swift"
primary_target: "native/Onyx/Features/Programs/ProgramsView.swift"
related_targets: ["native/Onyx/Features/Programs/ProgramEditorView.swift","native/Onyx/Features/Programs/TrainProgramsDoor.swift"]
---

# Surface brief — Programs (Train → Programs)

Shaped 2026-09-25 by `impeccable shape`, Precision sprint Lane E (E2). No live
interview: the lane brief makes § FOUNDER DECISIONS binding and forbids
questions; assumptions are marked.

## Scope and mode
Operate. `ProgramsView` (the user's `plans`), `ProgramEditorView` (one plan:
name, goal, active, days), the existing `RoutineDayEditor` as the day screen,
and `TrainProgramsDoor` — the one card Train shows. Settings → Routines now
opens `ProgramsView`. Inside the Stone world; no new world.

## Job and audience
The athlete, at home or on the sofa, not mid-set: "write my plan the way Hevy
lets me — days, movements, sets/reps/rest — and choose which plan I'm running."
Success = a new program from nothing or from a template, with a goal, days on
weekdays, activated, in under a minute; and the Train tab always says which
plan is running and what's next.

## Selected direction
Structural thesis: settings-shaped content is a grouped `List` (HIG; the
routine builder already is one) on `onyxFormBackground(.train)`. No card stack.
- Programs list: one row per plan — a 4 pt day-accent-style capsule is NOT
  used; instead the ACTIVE plan carries a filled train-accent ring glyph
  (`checkmark.circle.fill`), others a hairline `circle`; name (body semibold) ·
  meta line "5 days · Cut · since 15 Jul" · goal chip (micro, capsule, accent
  at 14 % only on the active row). Sections: "Programs" (live), "Start from a
  template" (Onyx-5 / Onyx-4 / Push/Pull/Legs with day counts, + "Blank
  program"), "Past programs" (is_legacy). Swipe: Make active · Delete.
- Editor: Section "Program" (Name field; Goal row → goal sheet, value
  "Cut · 72 kg in 12 wk"; Active row: "Running since 15 Jul" or a "Make
  active" button); then the routine builder's own sections (days, add day).
- Door: a full-width tile like Train's Trends door — train-accent glyph,
  "PROGRAM" micro label, program name (body semibold) + "Next · Upper B · Thu"
  caption, chevron. NOT a hero (the plan card's day label keeps that role).

## States and ranges
0–8 plans; 0–7 days; names 3–30 chars (wrap, never truncate). Empty account →
"Programs" section empty with the template rows doing the teaching. A plan with
no days → door says "No days yet · Add days". Delete refused for the active
plan and for a plan that has run (has `started_on`) — an alert says why.

## Interaction
Tap row → push editor. Make active → the existing `SettingsModel.activate`
phase switch (phase = the plan's goal phase, else the current phase). Template
row → creates a copy (not active) and pushes its editor. 44 pt targets, AX5
stacks meta under the name, VoiceOver rows combined with "active" state.

## Constraints and open decisions
- `WorkoutTabView` gets exactly one line (seam 6) after the plan card.
- Assumption: templates copy as NEW programs even if the account already runs
  one with the same template id — ids are minted from the name, never reused.
