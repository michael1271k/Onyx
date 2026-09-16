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
DEVICE="${2:-iPhone 17 Pro}"
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
UDID="$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE'." >&2
  exit 1
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# ── The build ──────────────────────────────────────────────────────────────
# Never `-sdk iphoneos`: it drags a watch AppIcon check into an iPhone-only
# project and fails on an asset that does not exist.
echo "Building…"
(cd "$ROOT/native" && xcodegen generate >/dev/null)
xcodebuild -project "$ROOT/native/Onyx.xcodeproj" \
  -scheme Onyx \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Onyx.app"
xcrun simctl install "$UDID" "$APP"

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
  # (`SHOT_THEME=Ember`) or a custom pair of hexes (`SHOT_THEME=E0645A,4FD1C5`).
  # It is a launch argument, so it dies with the process and cannot leave the
  # simulator's container holding a colour the next run would inherit.
  if [ -n "${SHOT_THEME:-}" ]; then
    xcrun simctl launch "$UDID" "$BUNDLE_ID" --onyx-screen "$screen" --onyx-theme "$SHOT_THEME" >/dev/null
  else
    xcrun simctl launch "$UDID" "$BUNDLE_ID" --onyx-screen "$screen" >/dev/null
  fi
  # The launch returns as soon as the process exists; the first frame is a
  # few hundred ms later. Shooting too early photographs the launch screen —
  # or, on the first launch after an install, a black window: 3.5 s was enough
  # on a warm 402 pt device and produced eight solid-black PNGs on a freshly
  # created one, which is a shot that reviews as "the screen is broken".
  sleep 8
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$screen$suffix.png" >/dev/null
  echo "  $OUT/$screen$suffix.png"
}

# A space-separated list shoots several screens off ONE build, which is what
# the store loop wants: `native-shot.sh "today train fuel" "iPhone 17 Pro Max"`.
read -ra SCREENS <<< "$SCREEN"
if [ "$SCREEN" = "all" ]; then
  # Keep in step with `PreviewHarness.Screen` — the harness is the authority and
  # an unknown name there renders a visible error rather than failing silently.
  SCREENS=(signin backfill today today-mega today-edit today-edit-still today-sheet today-sheet-vitals today-sheet-steps today-sheet-muscle today-sheet-records today-stack-linked today-weighin today-board train train-done train-pending train-cardio train-empty train-monday train-past train-past-open train-customize train-customized mini-player logger logger-stats logger-lifts logger-paused logger-finish logger-timer set-row set-row-split set-row-cardio set-row-records set-options effort-picker day day-rows day-past day-session day-two day-empty day-stress day-soreness day-hero pulse-squares pulse-squares-evening pulse-squares-empty sleep-edit stress stress-log stress-day fatigue quick-log scale scale-first day-swap doms stack stack-add fuel fuel-over fuel-empty nutrients macro-edit you levers sync-status sync-doctor plan body volume library exercise reports report report-edit history history-week session session-ledger session-records session-pairs session-cardio exercise-history trends trends-empty body-trends body-trends-empty body-trends-stress appearance appearance-locked widgets)
fi

# `widgets` is a contact sheet of every tile; the harness pages it because a
# scroll view screenshots its first screen only. Page count = WidgetPreviews.pages,
# which packs rows to 372pt and pages to 760pt — 24 since the dashboard-polish
# wave added the Today face's logged state. A page number past the end renders the whole
# scroll view instead, so this bound is not free to be generous.
if [ "$SCREEN" = "widgets" ] || [ "$SCREEN" = "all" ]; then
  SCREENS=("${SCREENS[@]/widgets}")
  for i in $(seq 0 23); do SCREENS+=("widgets-$i"); done
  # Two pages since W2: the three Lock Screen cards, then the Dynamic Island's
  # expanded and compact faces plus the Smart Stack card. One page was taller
  # than the display and photographed its own middle.
  SCREENS+=("widgets-activity" "widgets-island")
fi

for s in "${SCREENS[@]}"; do
  [ -z "$s" ] && continue
  echo "$s"
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
