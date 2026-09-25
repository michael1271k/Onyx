# Product

<!-- impeccable:product-schema 1 -->

> Written by `impeccable init` on 2026-09-25 (Precision sprint, Lane B) with a
> **structured simulated user** built from `docs/Plan-Onyx-Precision.md`
> § FOUNDER DECISIONS — the lane brief forbids a live interview ("founder
> decisions are binding; do not ask questions"). Facts marked *(inferred)* come
> from the repository, not from a founder answer; correct them in place.

## Platform

ios

(One native SwiftUI app for iPhone plus a watchOS companion, Home Screen and
Lock Screen widgets, a Live Activity and watch complications. Portrait only,
dark appearance only — `native/project.yml`.)

## Users

- **The athlete who logs every set.** A person training 4–6 days a week on a
  written program (Upper/Lower, PPL, "Onyx 5"), logging each set live on the
  phone between sets and reading the summary seconds after the last one. Hands
  sweaty, attention split, standing in a gym. Also reads the day's body state
  (sleep, heart, readiness, soreness) in the morning to decide how hard to go.
- **The same person away from the phone** — on the wrist during a workout and
  at a glance from the Home Screen and Lock Screen.
- App Store metadata must never position the app for a single person
  (guideline 4.2/4.3, `docs/APP_STORE.md`).

## Product Purpose

Onyx is a training log and body dashboard in one: it records every set, turns
the session into truthful figures (tonnage, sets, records, heart rate), and
reads Apple Health to say how ready the body is for the next one. Success is
the athlete trusting the numbers enough to train by them — the figures agree
with Hevy's arithmetic, a record means a record, and the first screen after a
workout answers "what did I just do" without a scroll.

## Positioning

The log and the body live in the same app and inform each other: the session a
person just finished moves tomorrow's readiness, fatigue and soreness, and the
body tab shows the day as one ring with six petals (sleep, water, food, heart,
steps, stress). A workout-only log or a health-only dashboard cannot say both.

## Operating Context

- Live logging mid-workout (one-handed, glanceable, between sets); the post-
  workout summary read standing up; morning check of the body state.
- Data sources: the app's own GRDB store synced to Supabase; Apple Health
  (sleep, HR, HRV, steps, nutrition, body composition); the watch app; Hevy is
  the external comparison standard for tonnage (decision Q13).
- Sharing: the session replay is shared to Instagram Stories / messages as a
  PNG, a Stories PNG and a 10 s MP4 (decision Q21).

## Capabilities and Constraints

- Tabs *(inferred from `RootView`)*: Today, Train, Body (was Pulse, decision
  Q19), History, You/Settings.
- Train owns workouts; Body owns the body (Q19): readiness ring hero + six
  petals, then vitals, sleep, stress, soreness, scale — no workout cards.
- Tonnage on the Hevy basis (Q13); "Sets" = working + warm-up + cardio bouts,
  "Working" secondary (Q10); a first-ever exercise shows "Baseline", never a
  trophy (Q12).
- Eight "stone" themes (Slate default, Lagoon, Sage, Iris, Clay, Ochre, Moss,
  Rosewood); fixed inks that never follow the theme: heart red, water blue,
  record gold, the 16-muscle anatomical palette, sleep stages.
- Free Apple developer team today: no App Group, no TestFlight, no background
  refresh (Gate 0 in `docs/APP_STORE.md`). No DDL runs from the dev machine.
- No sex/age inputs in nutrition setup (App Review 5.1.1).

## Brand Commitments

- Name **ONYX**, the Onyx mark + wordmark (`OnyxMark`, `OnyxWordmark`), the
  2048 founder icon render (onyx slab with a pearl/lavender light vein).
- Material language "Stone": onyx-black ground, frosted slab surfaces, no drop
  shadows, corners 12/20/28 *(inferred from `OnyxGlass`, memory
  `overhaul-sprint`)*.
- Voice: plain, factual, numbers first; a caption says what a figure means,
  never cheers *(inferred from shipped copy)*.

## Evidence on Hand

- The founder's own training history (sessions since the Notion era), synced
  from Supabase; the preview fixtures in `PreviewHarness` and
  `OnyxSnapshot.sample` for screenshots.
- No testimonials, press, user counts or benchmarks exist — never fabricate
  them.

## Product Principles

1. **Truth over flattery.** A figure is either measured, derived by a stated
   rule, or absent — never a guess dressed as a reading.
2. **The first screen is the answer.** Every face (summary, banner, Body tab,
   widget) answers its question without a scroll; detail is one tap away.
3. **One hero per screen.** One `.hero` numeral per screen; everything else
   supports it.
4. **Fixed meaning, themed mood.** Inks that carry meaning (heart, water,
   record, muscles, sleep) never change with the theme; the theme owns accent,
   mood and the ground's light.
5. **Train owns workouts, Body owns the body.**

## Accessibility & Inclusion

- Dynamic Type to AX5 on every screen (shots at default and AX5); rings and
  heroes may cap at `accessibility1`.
- Contrast ≥ 4.5:1 for text over every ground (`TokenDisciplineTests`);
  Reduce Transparency flattens every wash; Reduce Motion shows final frames.
- VoiceOver labels on every figure; 44 pt minimum targets.
