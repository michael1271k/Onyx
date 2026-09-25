#!/usr/bin/env bash
#
# The native visual-check loop: one PNG per screen, at the default text size and
# at the largest accessibility size.
#
# ── WHY NOT `ImageRenderer` AND A SNAPSHOT LIBRARY ──────────────────────────
# The whole design mandate for this app is material: `ultraThinMaterial` tiles,
# a mesh bleed behind the title, blur that samples what is behind it. Those are
# composited by the render server, and an off-screen `ImageRenderer` pass does
# not have one — a "screenshot" from it shows the layout and lies about the look,
# which is precisely the half a design review is for.
#
# So this boots a real simulator, installs a real build and asks the OS for a
# real screenshot. It is slower and it is the truth.
#
# ── AND WHY A LAUNCH ARGUMENT RATHER THAN A DEEP LINK ───────────────────────
# An early sketch used a different URL scheme. A deep link has to travel
# through the app's real navigation, which means a real session, which means
# Supabase credentials in the loop and screenshots that differ by whatever is in
# the database today. `--onyx-screen` swaps the root view for one screen backed
# by seeded in-memory data, so the shot is deterministic and needs no network.
# It is `#if DEBUG` only and cannot ship.
#
#   scripts/native-shot.sh you             # one screen
#   scripts/native-shot.sh all             # every screen the harness knows
#
set -euo pipefail

SCREEN="${1:-all}"
DEVICE="${2:-iPhone 15}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# `SHOT_OUT` sends the PNGs somewhere else — App Store shots go to a
# per-size folder rather than over the working set.
#
# Neither set is committed (3.8.0): 220 phone screens came to 144 MiB of PNG
# that turned over on every layout edit, and nothing in `npm run check` read
# them. They are evidence you look at while the diff is in front of you, so
# they live here and are regenerated on demand.
OUT="${SHOT_OUT:-$ROOT/native/__screenshots__}"
BUNDLE_ID="app.onyx.health.michael.native"
# `SHOT_DERIVED` moves the build products, for the same reason `SHOT_OUT` moves
# the PNGs — and for one more.
#
# ── TWO WORKTREES, ONE CACHE ────────────────────────────────────────────────
# This path used to be fixed, and it is OUTSIDE the worktree, so two waves
# shooting at once point two builds at one `build.db`. The second one fails
# with "database is locked", and the failure mode after that is worse than the
# error: a shot run that cannot rebuild INSTALLS WHAT IS ALREADY THERE, so the
# screenshots come out plausible and photograph the other worktree's code.
# A review then passes or fails on a build that does not contain the change.
#
# Pass `SHOT_DERIVED=$HOME/Library/Caches/onyx-swift/shot-<wave>` when another
# wave may be shooting. The default is unchanged.
DERIVED="${SHOT_DERIVED:-$HOME/Library/Caches/onyx-swift/shot-derived}"

mkdir -p "$OUT"

# ── The device ─────────────────────────────────────────────────────────────
# `|| true`: under `set -e` a non-matching grep kills the script BEFORE the
# error below can print — the silent exit 1 W1 fixed in `swift-ui-test.sh`.
# EXACT name, newest runtime. `grep -m1 "$DEVICE ("` took the first line that
# merely STARTED with the name, so "iPhone 15" resolved to W4's
# "iPhone 15 (W4 lane A 26.5)" and every run quietly moved to iOS 26.5.
UDID="$(xcrun simctl list devices available | awk -v n="$DEVICE" '{ l = $0; sub(/^ +/, "", l); u = substr(l, length(n) + 3, 36); if (index(l, n " (") == 1 && u ~ /^[0-9A-F-]+$/ && length(u) == 36) print u }' | tail -1 || true)"
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE'." >&2
  exit 1
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# ── The build ──────────────────────────────────────────────────────────────
# Never `-sdk iphoneos`: it drags a watch AppIcon check into an iPhone-only
# project and fails on an asset that does not exist.
# `SHOT_SKIP_BUILD=1` reuses the app the LAST run installed — for shooting the
# same build under a second and third `SHOT_THEME` without paying a rebuild
# (and a cold first launch) per theme. Only after a run in this same session
# built it: the installed app is otherwise whatever was there last.
if [ -z "${SHOT_SKIP_BUILD:-}" ]; then
echo "Building…"
(cd "$ROOT/native" && xcodegen generate >/dev/null)
# `SHOT_SIGN=1` signs ad hoc so the entitlements are EMBEDDED (W5). An
# unsigned simulator build carries none, and HealthKit refuses every call
# without `com.apple.developer.healthkit` — so the `telemetry-*` screens,
# which read the simulator's real Health store, photographed nothing. The
# default stays unsigned: every other screen needs no entitlement.
SIGNING=(CODE_SIGNING_ALLOWED=NO)
if [ -n "${SHOT_SIGN:-}" ]; then SIGNING=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-); fi
xcodebuild -project "$ROOT/native/Onyx.xcodeproj" \
  -scheme Onyx \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  "${SIGNING[@]}" \
  build >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Onyx.app"
xcrun simctl install "$UDID" "$APP"
fi

# ── THE WARM-UP LAUNCH, AND WHY IT IS NOT PARANOIA ─────────────────────────
# The FIRST launch after an install is slower than every one after it — the
# system has a new binary to page in, the dyld cache is cold, and SwiftUI has
# no compiled layout to reuse. `shoot` waits 8 s, which is enough for a warm
# process and is NOT enough for this one: W4 shot `widgets-activity` three
# times and got a solid-black PNG twice, both times as the FIRST screen of
# the run, while every screen after it in the same run was fine.
#
# A black PNG is the worst possible failure here, because it reviews as "the
# screen is broken" rather than as "the loop is broken" — and it lands under
# a correct filename. One throwaway launch pays the cost once, before
# anything is photographed.
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 6
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 1

# ── The shots ──────────────────────────────────────────────────────────────
# Dynamic Type is mandatory in this design system and the largest accessibility
# size is where fixed heights and truncated labels show up, so every screen is
# shot twice and both PNGs are committed.
shoot() {
  local screen="$1" size="$2" suffix="$3"
  xcrun simctl ui "$UDID" content_size "$size" >/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # `terminate` returns before the process is actually gone, and `launch` on an
  # app that is still dying ATTACHES to it — the new `--onyx-screen` is never
  # read and the shot photographs the previous screen under the new name. A
  # W4 run of twelve screens came out shifted by one that way, and a shifted
  # set is worse than a missing one: every PNG looks plausible.
  sleep 1
  # `SHOT_THEME` photographs a screen under a theme: a preset by name
  # (`SHOT_THEME=Obsidian`) or a custom pair of hexes
  # (`SHOT_THEME=E0645A,4FD1C5`). The NAME must be one `OnyxTheme.presets`
  # actually holds — an unknown one leaves the default in place and the run
  # photographs Ion under whatever filename you asked for.
  # It is a launch argument, so it dies with the process and cannot leave the
  # simulator's container holding a colour the next run would inherit.
  # `telemetry-*` read the simulator's REAL Health store, so they seed it
  # first (`TelemetrySeed`, W5). The first run shows a permission sheet that
  # has to be tapped once ("Turn On All"); after that the grant persists.
  # `${seed[@]+…}` and not `${seed[@]+"${seed[@]}"}`: bash 3.2 — which is what macOS
  # ships — treats an EMPTY array as unset under `set -u`, so every screen
  # that is not `telemetry-*` died on "unbound variable" before it was
  # photographed. The expansion below is the portable spelling.
  local seed=()
  case "$screen" in telemetry-*) seed=(--onyx-telemetry-seed) ;; esac
  if [ -n "${SHOT_THEME:-}" ]; then
    xcrun simctl launch "$UDID" "$BUNDLE_ID" --onyx-screen "$screen" --onyx-theme "$SHOT_THEME" ${seed[@]+"${seed[@]}"} >/dev/null
  else
    xcrun simctl launch "$UDID" "$BUNDLE_ID" --onyx-screen "$screen" ${seed[@]+"${seed[@]}"} >/dev/null
  fi
  # The launch returns as soon as the process exists; the first frame is a
  # few hundred ms later. Shooting too early photographs the launch screen —
  # or, on the first launch after an install, a black window: 3.5 s was enough
  # on a warm 402 pt device and produced eight solid-black PNGs on a freshly
  # created one, which is a shot that reviews as "the screen is broken".
  # `SHOT_WAIT` stretches it: with three lanes building at once (load 30–50)
  # 8 s photographed a black window for half a run (overhaul Lane B).
  sleep "${SHOT_WAIT:-8}"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$screen$suffix.png" >/dev/null
  echo "  $OUT/$screen$suffix.png"
}

# A space-separated list shoots several screens off ONE build, which is what
# the store loop wants: `native-shot.sh "today train fuel" "iPhone 15 Max"`.
read -ra SCREENS <<< "$SCREEN"
if [ "$SCREEN" = "all" ]; then
  # Keep in step with `PreviewHarness.Screen` — the harness is the authority and
  # an unknown name there renders a visible error rather than failing silently.
  SCREENS=(signin backfill today today-morning today-evening today-mega today-edit today-edit-still today-sheet today-sheet-vitals today-sheet-steps today-sheet-muscle today-sheet-records today-stack-linked today-weighin today-board train train-done train-pending train-cardio train-empty train-monday train-past train-past-open train-customize train-customized mini-player logger logger-stats logger-lifts logger-paused logger-finish logger-timer logger-rest telemetry-finish telemetry-detail hevy-card set-row set-row-split set-row-cardio set-row-records set-options effort-picker day day-rows day-past day-session day-two day-empty day-stress day-edit day-soreness day-hero pulse-squares pulse-squares-evening pulse-squares-empty sleep-edit stress stress-log stress-day fatigue quick-log log-day log-day-soreness log-day-water scale scale-first day-swap doms stack stack-add stack-import stack-import-label fuel fuel-over fuel-empty fuel-calendar nutrients macro-edit you levers sync-status sync-doctor plan body volume library exercise reports report report-edit history history-week session session-ledger session-margin session-records session-pairs session-cardio session-hr logger-edit exercise-history trends trends-empty body-trends body-trends-empty body-trends-stress appearance appearance-locked widgets
    # LANE-A
    logger-library logger-library-search logger-stopwatch finish finish-coverage
    # LANE-E
    programs programs-editor programs-day goal-1 goal-2 goal-3)
fi

# `widgets` is a contact sheet of every tile; the harness pages it because a
# scroll view screenshots its first screen only. Page count = WidgetPreviews.pages,
# which packs rows to 372pt and pages to 760pt — 29 since the Widgets/Sleep/Themes
# sprint's W7 replaced the fifteen `lock-*` cells with forty `acc-*` ones (ten
# wearable ids at three families, plus ten empty rectangulars). A page number
# past the end renders the whole scroll view instead, so this bound is not
# free to be generous — it carries exactly one page of slack, as it did before.
if [ "$SCREEN" = "widgets" ] || [ "$SCREEN" = "all" ]; then
  SCREENS=("${SCREENS[@]/widgets}")
  for i in $(seq 0 29); do SCREENS+=("widgets-$i"); done
  # Two pages since W2: the three Lock Screen cards, then the Dynamic Island's
  # expanded and compact faces plus the Smart Stack card. One page was taller
  # than the display and photographed its own middle.
  SCREENS+=("widgets-activity" "widgets-island")
  # W6: every readiness face over a night window with a six-hour hole in it.
  SCREENS+=("widgets-offwrist")
fi

for s in "${SCREENS[@]}"; do
  [ -z "$s" ] && continue
  echo "$s"
  # ── SHOT_SIZE: THE FOUR SIZES THE PAIR SKIPS ───────────────────────────────
  # The default pass and the AX5 pass BRACKET Dynamic Type — 17 pt and the
  # largest accessibility size — and photograph neither of the four ordinary
  # sizes between them. That gap hid W1's load column for a release: a floor of
  # 56 pt fits six monospaced glyphs at 17 pt and five at 23, so `18.75` shrank
  # for every reader above the default and for nobody the loop looked at.
  #
  #   SHOT_SIZE=extra-extra-extra-large scripts/native-shot.sh set-row
  #
  # One pass, suffixed with the size, so it never overwrites the pair.
  if [ -n "${SHOT_SIZE:-}" ]; then
    shoot "$s" "$SHOT_SIZE" "-$SHOT_SIZE"
    continue
  fi
  shoot "$s" medium ""
  # Tiles set their type in points, as WidgetKit does; Dynamic Type never
  # reaches them, so the AX5 shot would be the same PNG twice.
  case "$s" in widgets*) continue ;; esac
  # `SHOT_AX=0` for the App Store loop: Apple wants the shipping type size,
  # and a second PNG per screen at AX5 is just something to delete by hand.
  [ "${SHOT_AX:-1}" = "1" ] || continue
  shoot "$s" accessibility-extra-extra-extra-large "-ax5"
done

xcrun simctl ui "$UDID" content_size medium >/dev/null
echo
echo "open $OUT   # the shots"
