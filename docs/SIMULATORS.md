# Simulators

How a wave proves a screen. Two simulators, paired; two shot scripts; one rule
about build products that has already cost one review.

## The pair

```
4DF6408A-6E99-43C3-95FE-7365ED491B90  (active, connected)
    Watch: Apple Watch Ultra 2 (49mm)  247D32D9-FBC8-45FF-8093-5C4C4A350650
    Phone: iPhone 15                   B5C31206-88FE-4EC1-A587-E7E5699DACA4
```

Verify before anything else:

```bash
xcrun simctl list pairs
xcrun simctl list devices booted
```

### Pairing, if it is gone

```bash
xcrun simctl create "iPhone 15" "iPhone 15"
xcrun simctl create "Apple Watch Ultra 2 (49mm)" "Apple Watch Ultra 2 (49mm)"
xcrun simctl pair <watch-udid> <phone-udid>
xcrun simctl bootstatus <phone-udid> -b
xcrun simctl bootstatus <watch-udid> -b
```

**The pair is not a convenience.** The watch app's whole state arrives over
WatchConnectivity: `WatchContext` → `resolveDay` → a day → a session. On an
unpaired watch there is none, so every screen below `StartView` is unreachable
and the shot comes back as "Open Onyx on your iPhone" — a real screen, and
never the one under review. `watch-shot.sh` refuses to run unpaired for that
reason.

## The two scripts

```bash
scripts/native-shot.sh today                 # one phone screen, default + AX5
scripts/native-shot.sh all                   # the whole harness
scripts/watch-shot.sh  set                   # one watch screen
scripts/watch-shot.sh  "start set rest"      # several off one build
```

`native-shot.sh` drives `--onyx-screen`, which swaps the root view for a
`PreviewHarness` face backed by seeded in-memory data — deterministic, no
network. `watch-shot.sh` drives the launch ENVIRONMENT instead, because that is
what `OnyxWatchApp` reads.

### Which watch screens exist

| Screen | Hook | Status |
|---|---|---|
| `start` | none — the app's own first screen | ✅ |
| `set` | `ONYX_WATCH_AUTOSTART=1` | ✅ |
| `quality` | `…SCREEN=quality` + one slow swipe | ✅ W3 |
| `qualitytags` | the same, three swipes down the panel | ✅ W3 |
| `rest` | `…SCREEN=rest` | ✅ |
| `deck` | `…SCREEN=deck` | ✅ W3 |
| `deckswipe` | the same, plus a sideways swipe on row one | ✅ W3 |
| `pause` | `…SCREEN=pause` | ✅ W3 |
| `cancel` | `…SCREEN=cancel` | ✅ W3 |
| `finish` | `…SCREEN=finish` | ✅ W3 |
| `dashboard` | — | ❌ W4 builds the screen first |

Every one of these but `start` also passes `ONYX_WATCH_AUTOSTART=1`. The
missing one is presented by SwiftUI navigation inside a live session, and
nothing in `WatchModel` can be seeded to put it up yet. The script **refuses
it by name** rather than landing on `StartView` and writing the PNG under the
asked-for name. A plausible photograph of the wrong screen is worse than a
missing one — the phone loop shipped a twelve-shot run shifted by one exactly
that way.

To add one: seed the state in `WatchModel` (`#if DEBUG`, beside
`seedDebugRest`), add a case to `WatchModel.DebugScreen`, add a branch to the
`ONYX_WATCH_SCREEN` block in `OnyxWatchApp.swift`, and add the case to
`screen_env()` in the script.

### And two of them need a finger

`quality`, `qualitytags` and `deckswipe` are a SCROLL or a SWIPE away rather
than a state away, and no launch environment can seed a scroll offset. The app
carried a DEBUG `scrollPosition` write for exactly this and it never landed —
a scroll position written before layout is kept and never performed. So
`screen_gesture()` drives `axe` instead, with coordinates calibrated against
the accessibility tree (`axe describe-ui`) rather than by eye.

Two things were measured and are worth not rediscovering:

- **A fast flick comes back.** Whatever `scrollTargetBehavior` makes of a
  thrown synthetic gesture on this SDK, it returns to where it started. Only a
  slow drag (~1.5 s) of rather more than half a page moves and stays.
- **`.scrollInputBehavior(.disabled, for: .handGestureShortcut)` disables the
  scroll view's input ENTIRELY** on this SDK, not just the double pinch. With
  it on, no swipe of any length or speed moved the set screen's pager by a
  point. It is not in `SetView` for that reason, and the comment there says so.

## `SHOT_DERIVED` — the rule with teeth

**Always pass it when more than one wave may be building.**

```bash
SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-w3 scripts/native-shot.sh logger
```

The default derived-data path sits *outside* the worktree, so two worktrees
shooting at once point two builds at one `build.db`. The second fails with
`database is locked` — and the failure after that is the silent one: a shot run
that cannot rebuild **installs whatever is already there**, so the screenshots
come out plausible and photograph the other worktree's code. A review then
passes or fails on a build that does not contain the change.

**Delete your `SHOT_DERIVED` directory when your wave closes.** Nothing else
will. The Onyx Expansion close-out found thirty-nine directories under
`~/Library/Caches/onyx-swift/` totalling 103 GB — one per wave that had ever
shot a screen or run a test, largest 5.7 GB. Thirty-three were dead. Only six
are load-bearing: `OnyxCore`, `OnyxData`, `OnyxUI-ios`, `OnyxUI-watchos`,
`check-watch` and `onyxtests`, which are the paths the gates above name.

`SHOT_OUT` moves the PNGs the same way. Neither set is committed — since 3.8.0
`native/__screenshots__/` is gitignored, because 220 phone screens came to
144 MiB that turned over on every layout edit and no gate ever read them. They
are evidence you look at while the diff is in front of you.

## `xcodebuildmcp`

UI automation is enabled (AXe at `/opt/homebrew/bin/axe`,
`XCODEBUILDMCP_UI_AUTOMATION=1` in `~/.claude.json` → `mcpServers.xcodebuildmcp`),
which is what makes `snapshot_ui` and `tap` available. Server config is
per-user and stays out of the repo; the **session defaults** every wave sets are
recorded in `.mcp.json` under `onyx.xcodebuildmcpSessionDefaults`.

Set them before the first build of a wave:

```
session_set_defaults
  projectPath      native/Onyx.xcodeproj
  scheme           Onyx
  configuration    Debug
  simulatorName    iPhone 15
  derivedDataPath  $HOME/Library/Caches/onyx-swift/<wave>-derived
```

Then `session_show_defaults` to confirm, and `build_run_sim` with no arguments.

> **`native/Onyx.xcodeproj` is generated and gitignored.** Run
> `cd native && xcodegen generate` first or every one of these fails on a
> missing project.

## The gates

```bash
npm run check          # types, atlas, mirror, doms, OnyxUI tests, version
npm run swift:core     # domain + golden vectors
npm run swift:data     # store, migrations, outbox
npm run check:swift    # OnyxUI + OnyxCore cross-build for iOS
npm run check:watch    # the OnyxWatch target, watchOS simulator
```

`check:swift` does **not** cover the app or widget targets — a green run can
hide a broken app target. `check:watch` closes the watch half of that hole.

The OnyxTests app-target scheme runs from Xcode or `xcodebuild test`; its
baseline is **11 pre-existing failures**, and a wave's job is to add none.

> **Never run three `xcodebuild test` invocations at once.** Concurrent runs
> wedge the simulator and every later run in the session inherits it.

## The 40 mm floor a 49 mm screenshot cannot prove

Every watch screen is laid out for **40 mm — 162 × 197 pt**. The paired
simulator is an Ultra 2 at 49 mm (205 pt wide), which hides exactly the
overflow the budget exists to catch. A watch screenshot is evidence about
*look*, never about *fit*: the floor is asserted at 162 pt in
`OnyxWatchLayoutTests`, and that test is the gate.
