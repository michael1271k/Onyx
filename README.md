# Onyx

**Training, fuel and recovery — a native iPhone and Apple Watch app.**

Onyx reads Apple Health, logs strength and cardio sessions, meals, water,
soreness, fatigue and stress, and turns all of it into a readiness score, a
recovery battery and a small set of trends you can act on the same morning.
Everything lives on the phone first and syncs to a private Supabase database.

> **Code convention:** comments describe *what the code does* — never release or
> development phases. No "Phase N" tags or temporary developmental labels in code
> comments, ever. Program/era names in data (e.g. "Helix Cut") are allowed.

> **The app never calls a model.** There is no inference call anywhere in the
> tree. The weekly report is a copy-brief-out, paste-analysis-back loop performed
> by the user, deliberately.

## Layout

| Path | What it is |
|---|---|
| `native/` | The app: `project.yml` (XcodeGen), the `Onyx` app target, `OnyxWidgets`, `OnyxWatch`, and the three Swift packages `OnyxCore` (domain) · `OnyxData` (GRDB store, sync, HealthKit) · `OnyxUI` (design system, atlas, tiles). See `native/README.md`. |
| `scripts/` | Generators and the version SSoT. `scripts/src/` holds the TypeScript sources the generators read: the body atlas and soreness vocabularies (emitted as Swift) and the report renderer (bundled into `ReportRenderer.html`). Service-role maintenance scripts live here too — see the `backfill` skill before running one. |
| `site/` | The static Netlify site: privacy policy, support page and the Apple App Site Association file. No build step. |
| `docs/` | `CHANGELOG.md`, `APP_STORE.md`, the model notes, the epic sprint plan, and `sql/` — the migrations, pasted by hand into Supabase. |
| `design-system/` | The token record behind `OnyxUI`. |

There is no web app. It was retired on 2026-09-12 (3.0.0); its source is in git
history before that commit.

## Development

```bash
npm install
npm run check        # version + atlas + mirror + doms generators in sync — the gate before any commit
npm run check:swift  # OnyxCore + OnyxUI cross-build for the iOS simulator
npm run swift:core   # OnyxCore tests + golden vectors
npm run swift:data   # OnyxData tests
npm run native:gen   # version:sync, then xcodegen generate
npm run atlas        # regenerate OnyxAtlas.swift from scripts/src/atlas.ts
npm run doms         # regenerate the soreness vocabularies
npm run mirror       # regenerate MirrorModels.swift from native/schema/supabase.json
npm run report:bundle# rebuild the offline report renderer
npm run icons        # rasterise resources/icon.png into the app and watch icons
```

Open the app with `cd native && xcodegen generate && open Onyx.xcodeproj`.
`native/README.md` has the first-run steps (Secrets.xcconfig) and the free-team
constraints.

## Supabase

Supabase is the schema of record. There are no migration files in the repo
beyond `docs/sql/`, which are pasted by hand; introspect the live database
before assuming a column exists (the `schema` skill has the recipe). The
service-role scripts read `NEXT_PUBLIC_SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` from `.env.local` — see `.env.example`.

## Versioning

`package.json` → `"version"` is the single source of truth. `npm run
version:sync` writes it into `native/project.yml`; `npm run version:check`
fails the gate on drift. Release notes go in `docs/CHANGELOG.md`.

## Repo docs

- `CLAUDE.md` — versioning rules and the graphify knowledge-graph workflow
- `docs/GIT.md` — one trunk, wave branches, the push guard
- `docs/APP_STORE.md` — the listing, the review notes, the compliance pages
- `docs/READINESS_MODEL.md` · `docs/STRESS_MODEL.md` — the scoring models
