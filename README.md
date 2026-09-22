<div align="center">

# ⬢ Onyx

### The native training and recovery OS for iPhone and Apple Watch

*Train. Recover. Fuel. One loop, closed — on your wrist, in your pocket, offline.*

[![Platform](https://img.shields.io/badge/platform-iOS%2018%20%C2%B7%20watchOS%2011-000000?style=flat-square&logo=apple&logoColor=white)](#-getting-started)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0071E3?style=flat-square&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Backend](https://img.shields.io/badge/Supabase-Postgres-3ECF8E?style=flat-square&logo=supabase&logoColor=white)](https://supabase.com)
[![Offline](https://img.shields.io/badge/offline-first-111111?style=flat-square)](#-architecture)

[![Download on the App Store](https://img.shields.io/badge/Download_on_the-App_Store-000000?style=for-the-badge&logo=apple&logoColor=white)](#-getting-started)

<sub>Listing pending review — the badge links here until the App Store URL exists.</sub>

</div>

---

## The pitch

Most training apps are a logbook with a chart bolted on. Onyx is the other way
round: the log is the raw material, and what you get back is a **decision you can
act on before your first warm-up set** — how recovered you are, what that means
for today's loads, and whether last week's eating supported any of it.

It reads Apple Health. It logs strength and cardio, meals, water, soreness,
fatigue and stress. It turns all of it into a readiness score, a recovery
battery and a small set of trends that fit on one screen. Everything is written
to the phone first and syncs to a private Postgres database you own.

> **Onyx never calls a model.** There is no inference call anywhere in this tree.
> The weekly report is a copy-brief-out, paste-analysis-back loop you perform
> deliberately, with the assistant of your choosing.

---

## ⬢ Core philosophy

<table>
<tr>
<td width="33%" valign="top">

### 🏋️ Train

The session is the unit. Sets, reps, load, rest, RPE, laterality, warm-ups,
drop-sets and cardio bouts — logged in the time it takes to rack the bar,
on the watch if your phone is in the bag.

Personal records file themselves. Progression queues itself.

</td>
<td width="33%" valign="top">

### 🔋 Recover

Sleep, HRV, resting heart rate and soreness fold into a **readiness score** and
a **recovery battery** that spends and refills across the week.

Soreness is a contour map of sixteen muscles and their sub-regions, not a
one-to-ten slider.

</td>
<td width="33%" valign="top">

### 🍽️ Fuel

Calories, protein, carbs, fat, water and the micros that actually move —
against phase targets that change when your plan does.

A deficit week and a lean-bulk week are not the same question, so they are not
scored the same way.

</td>
</tr>
</table>

---

## ✨ Features

**On the phone**
- Session logger with live rest timing, per-set quality tags, unilateral sides and cardio metrics
- Readiness, recovery battery and stress engines, each with a stated model and golden test vectors
- Sixteen-muscle body atlas with soreness contours and per-sub-region history
- Nutrition with phase-aware targets, meal grain, water and a supplement stack
- Trends: tonnage, volume per muscle, PR timeline, body composition, sleep and HRV
- Weekly export — a single self-contained HTML brief, rendered offline

**On the wrist**
- Standalone logging: pick up a session mid-set with the phone out of range
- Live workout session with heart-rate capture, written back to Apple Health
- Digital Crown load and rep entry, haptic set commits

**Everywhere else**
- Five Home Screen widget families plus Lock Screen accessories
- Live Activity for a running workout
- Deep links, Face ID lock, full account deletion from inside the app

---

## 🏗 Architecture

**100% native. No web view, no bridge, no JavaScript runtime on device.**

```
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│   Onyx (iOS)      │   │  OnyxWidgets      │   │  OnyxWatch        │
│   SwiftUI         │   │  WidgetKit        │   │  watchOS          │
└─────────┬─────────┘   └─────────┬─────────┘   └─────────┬─────────┘
          │                       │                       │
          └───────────┬───────────┴───────────┬───────────┘
                      ▼                       ▼
        ┌──────────────────────┐  ┌──────────────────────┐
        │  OnyxUI              │  │  OnyxCore            │
        │  tokens · atlas      │  │  pure domain, zero   │
        │  tiles = widget faces│  │  dependencies        │
        └──────────┬───────────┘  └──────────┬───────────┘
                   └───────────┬─────────────┘
                               ▼
                 ┌──────────────────────────┐
                 │  OnyxData                │
                 │  GRDB · outbox · sync    │
                 │  HealthKit · Keychain    │
                 └────────────┬─────────────┘
                              ▼
                 ┌──────────────────────────┐
                 │  Supabase / Postgres     │
                 │  RLS · PostgREST · RPC   │
                 └──────────────────────────┘
```

**Offline-first, not offline-tolerant.** Every write lands in local SQLite
(GRDB) inside a transaction and is queued in an **outbox** that drains through
exponential backoff whenever the network returns. The UI reads the local
database through `ValueObservation`, so a set appears the instant it commits —
there is no request in the render path and no spinner to wait on. Thirty-two
mirrored tables come down as deltas against per-table cursors.

**Two clients, one truth.** The phone and the watch both write. Convergence is
an append-only set-event log folded into rows, with an explicit pencil
(ownership) so two devices cannot silently interleave the same session.

**HealthKit, both directions.** The phone **reads** — sleep, HRV, resting heart
rate, steps, active energy, body mass — and shares nothing back. The watch
**writes** the workout: an `HKWorkoutSession` with live heart rate, saved to
Health when you finish. Read and write are deliberately split by device, so the
phone can never overwrite a measurement it did not make.

**Generated, not hand-copied.** The body atlas, the soreness vocabularies and the
mirrored table models are emitted into Swift from a single source by the
generators in `scripts/`. `npm run check` fails if the checked-in Swift has
drifted — one anatomy, one schema, one spelling.

---

## 🚀 Getting started

### For athletes

1. Install Onyx from the App Store.
2. Sign in, or create an account — it is your private Postgres row, not a profile.
3. Grant Health access when asked. Onyx only reads.
4. Pick a plan, or build a routine day by day.
5. Log your first session. The scores need about a week of data before they say
   anything worth hearing — they will tell you so until then.

### For developers

```bash
git clone <this repo> && cd Onyx
npm install
npm run check          # generators + version SSoT in sync — the gate before any commit
npm run native:gen     # version:sync, then xcodegen generate
open native/Onyx.xcodeproj
```

`native/README.md` covers the first run: `Secrets.xcconfig`, the App Group, and
what a free Apple Developer team cannot sign.

<details>
<summary><b>Every command</b></summary>

```bash
npm run check         # version + types + atlas + mirror + doms — the pre-commit gate
npm run check:swift   # OnyxCore + OnyxUI cross-build for the iOS simulator
npm run swift:core    # OnyxCore tests and golden vectors
npm run swift:data    # OnyxData tests
npm run atlas         # regenerate OnyxAtlas.swift from scripts/src/atlas.ts
npm run doms          # regenerate the soreness vocabularies
npm run mirror        # regenerate MirrorModels.swift from native/schema/supabase.json
npm run report:bundle # rebuild the offline report renderer
npm run icons         # rasterise resources/icon.png into the app and watch icons
npm run native:gen    # version:sync, then xcodegen generate
```

Never edit or commit `native/Onyx.xcodeproj` — XcodeGen owns it.

</details>

---

## 🧱 Tech stack

| Layer | What it is |
|---|---|
| **App** | Swift 6, SwiftUI, Observation, WidgetKit, ActivityKit, HealthKit, WatchConnectivity |
| **Local store** | SQLite via GRDB — migrations, `ValueObservation`, an outbox queue, an append-only event log |
| **Backend** | Supabase: Postgres with row-level security, PostgREST, Realtime, RPC for account deletion |
| **Project** | XcodeGen from `native/project.yml`; three local Swift packages |
| **Generators** | Node + TypeScript, emitting Swift and one bundled HTML renderer |
| **Site** | Static HTML on Netlify: privacy, support, and the Apple App Site Association file |

---

## 📁 Layout

| Path | What it is |
|---|---|
| `native/` | The app. `project.yml` (XcodeGen), the `Onyx` target, `OnyxWidgets`, `OnyxWatch`, and the packages `OnyxCore` (domain) · `OnyxData` (store, sync, HealthKit) · `OnyxUI` (design system, atlas, tiles). See `native/README.md`. |
| `scripts/` | The generators and the version SSoT. `scripts/src/` holds the TypeScript they read: the body atlas, the soreness vocabularies and the report renderer. |
| `site/` | The static Netlify site — privacy, support, AASA. No build step. |
| `docs/` | `CHANGELOG.md`, `APP_STORE.md`, `SIMULATORS.md`, the scoring models. Retired sprint plans, with their wave summaries, live in `docs/Done/`. |

> **Code convention:** comments describe *what the code does* — never release or
> development phases. No "Phase N" tags or temporary developmental labels in code
> comments, ever. Program and era names the athlete chose (e.g. "Lean Bulk") are allowed,
> because they are values a user chose, not branding.

There is no web app. It was retired on 2026-09-12; its source is in git history
before that commit.

---

## 🗄 Supabase

Supabase is the schema of record, and the live database is the only truth about
it — introspect before assuming a column exists. There are no migration files in
the tree; applied DDL lives in git history. The service-role scripts read
`NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from `.env.local` —
see `.env.example`.

## 🏷 Versioning

`package.json` → `"version"` is the single source of truth for the app, the
widget extension and the watch app. `npm run version:sync` writes it into
`native/project.yml`; `npm run version:check` fails the gate on drift. Release
notes go in `docs/CHANGELOG.md`.

## 📚 Repo docs

- [`CLAUDE.md`](CLAUDE.md) — versioning rules and the knowledge-graph workflow
- [`docs/GIT.md`](docs/GIT.md) — one trunk, wave branches, the push guard
- [`docs/APP_STORE.md`](docs/APP_STORE.md) — the listing, review notes, compliance pages
- [`docs/READINESS_MODEL.md`](docs/READINESS_MODEL.md) · [`docs/STRESS_MODEL.md`](docs/STRESS_MODEL.md) — the scoring models
- [`native/README.md`](native/README.md) — first run, App Groups, free-team constraints

---

<div align="center">
<sub>Built for one athlete who wanted the whole picture, and written so anyone can use it.</sub>
</div>
