# ONYX Native

The app. iPhone, Apple Watch, Home Screen widgets and a Live Activity, all
SwiftUI, all reading one GRDB store that syncs to Supabase through an outbox.

It began as a second app installed beside a web-shell predecessor (hence the
`.native` suffix on the bundle id). That predecessor was retired on 2026-09-12;
comments that say "a port of the web app's `lib/…`" name files that now exist
only in git history (last at commit `db9892b4`, under `src/`).

## Layout

```
native/
├── project.yml                  XcodeGen spec — the project file is GENERATED
├── Packages/
│   ├── OnyxCore/               pure domain. Foundation only. No SwiftUI, no GRDB.
│   │   └── Tests/.../Fixtures/  golden vectors — frozen, hand-maintained
│   ├── OnyxData/               GRDB store + outbox + Keychain + Supabase session
│   └── OnyxUI/                 design system, the generated atlas (source: scripts/src/atlas.ts), the widget tiles
├── Onyx/                 the SwiftUI app target (views + entry point)
├── OnyxWidgets/          widget extension: five families + Lock + Live Activity
└── Shared/                      OnyxWorkoutAttributes — in both native targets
```

The split is deliberate. `OnyxCore` and `OnyxData` **build and test for macOS
from the command line**, so almost all of the app stays verifiable without Xcode,
a device or a signing certificate — which matters on a free Apple team, where the
app itself expires every seven days. What is left in the Xcode target is views.

`OnyxData` and `OnyxUI` depend on `OnyxCore`. Never the other way round: the
domain does not know a database or a view exists, and `OnyxUI` never imports
`OnyxData` — a tile draws a `OnyxSnapshot`, it does not fetch one. The widget
extension reads the App Group database (`group.app.onyx.health`) read-only and
builds the snapshot itself; the app reloads the timelines after every commit.

## First run

```bash
brew install xcodegen                       # once

cd native
cp Onyx/Support/Secrets.example.xcconfig Onyx/Support/Secrets.xcconfig
$EDITOR Onyx/Support/Secrets.xcconfig   # fill in URL + anon key
xcodegen generate
open Onyx.xcodeproj
```

In Xcode: select your iPhone, then Product → Run.

> **The URL in `Secrets.xcconfig` has no `https://`.** An xcconfig treats `//` as
> the start of a comment, so the scheme truncates the value. Store the host only;
> `SupabaseConfig.fromBundle` glues the scheme back on.

If the app launches to "ONYX could not start", the message names the missing
setting. That screen exists because forgetting to copy the xcconfig is the one
mistake everybody makes, and a `fatalError` would tell you nothing.

## Verifying without Xcode

```bash
npm run swift:core     # domain: golden vectors + invariants
npm run swift:data     # store: migrations, outbox, Keychain
```

> **Use the npm scripts, not a bare `swift test`.** They pass `--scratch-path`
> into `~/Library/Caches/onyx-swift/`, which keeps SwiftPM's `.build` directory
> out of the repository. Left in place it is ~2 GB of vendored dependency source
> that `graphify update .` walks and indexes: it once made **74 % of the code
> graph** GRDB and supabase-swift internals, and a query for the workout logger
> answered with a Supabase example project.

## The golden vectors

`Packages/OnyxCore/Tests/OnyxCoreTests/Fixtures/*.json` — one file per domain
function, `{ input, expected }` pairs that `swift test` replays case by case.
They are the written specification of every number this domain has ever been
caught getting wrong (the unloaded-work `weight == 0` blind spot that printed
"1RM 0" for months, the TDEE that omitted TEF, the battery whose drain budget
exceeded its charge budget), plus the grids around them. The arithmetic here
breaks *silently* — a formula 3 % wrong renders a number nobody questions —
and a fixture is the only thing that catches it.

**Swift-owned since W1 (2026-09-10).** They used to be exported from the
shipping TypeScript (`npm run golden`) while the two implementations had to
agree. From W2 the Swift domain deliberately diverges from the web, so the
generator is gone and the fixtures are frozen test resources:

1. **A new case is hand-computed** and written into the JSON, with the file's
   `note` naming the wave that added it. Named regressions from the module's
   header comment, not just grids — every historical bug here lived at one
   specific, unremarkable-looking input.
2. **A formula change that moves an expected value is a spec change**, reviewed
   by `invariant-auditor` before the number is edited.
3. **Any domain module without a fixture does not ship.**

If a fixture's `input` is a partial object, write the **full** object: Swift's
synthesized `Decodable` requires every non-optional key, and a fixture the
domain cannot decode is a fixture that tests nothing.

### `jsRound`, and why it exists

`Math.round` rounds a half towards **positive infinity**; Swift's `rounded()`
rounds **away from zero**. They disagree on every negative half. The fixtures
were computed under the first rule and the stored scores on the server still
are, so `Rounding.swift` keeps the shim: use `jsRound`, never `rounded()`, in
domain arithmetic.

## Free-team constraints, and where they show up

Everything here is built to work without a paid Apple Developer Program, and to
gain the paid features by adding an entitlement rather than by being restructured.

| Missing | Consequence today | What changes at $99/yr |
|---|---|---|
| App Groups | The widget and Watch cannot read this app's data | The extension reads the shared container it is already written for |
| Keychain sharing group | `KeychainAuthStorage` is private to this target | The extensions can share the session |
| TestFlight | Provisioning expires every 7 days; re-sign from Xcode | Installs stay valid; updates arrive as a notification |
| APNs `content-available` | No server-pushed background refresh | Background sync becomes possible |

## Conventions

- **Never edit `Onyx.xcodeproj`.** Edit `project.yml` and regenerate. The
  project file is gitignored.
- **Migrations are append-only.** Never edit a registered migration; add another.
  An edited migration runs on a fresh install and not on yours.
- **Column names match Postgres exactly** (snake_case), so a row from PostgREST
  inserts locally with no translation layer. `columnNamesMatchPostgres` guards it.
- **Views read from GRDB and nowhere else.** Nothing in the UI awaits the network
  to draw.
- **`nil` is not `0`.** The domain distinguishes "absent" from "zero" in at least
  three places that have caused real bugs. Neither the store nor the port gets to
  erase that.
