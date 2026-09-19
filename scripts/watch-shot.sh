#!/usr/bin/env bash
#
# The watch visual-check loop — `native-shot.sh` for the wrist.
#
# ── WHY THE WATCH NEEDS ITS OWN SCRIPT AND NOT A FLAG ──────────────────────
# Three things differ from the phone and every one of them is a whole branch:
# the destination is a watchOS simulator that must be PAIRED (an unpaired one
# boots, installs and then shows "Open Onyx on your iPhone" forever), the
# screens are reached through launch ENVIRONMENT rather than an argument
# (`simctl launch` passes env with a `SIMCTL_CHILD_` prefix, and the watch app
# reads plain names), and there is no Dynamic Type pass — watchOS has its own
# two text sizes and the layout floor this app actually cares about is the
# 40 mm width, which no screenshot on an Ultra 2 can prove. That last one is
# the trap: see the WIDTH note at the bottom.
#
#   scripts/watch-shot.sh set                      # one screen
#   scripts/watch-shot.sh "start set rest"         # several, one build
#   scripts/watch-shot.sh all                      # every screen that exists
#
set -euo pipefail

SCREEN="${1:-all}"
DEVICE="${2:-Apple Watch Ultra 2 (49mm)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SHOT_OUT:-$ROOT/native/__screenshots__/watch}"
BUNDLE_ID="app.onyx.health.michael.native.watchkitapp"
# `SHOT_DERIVED` for the reason `native-shot.sh` gives at length: two waves
# building at once share one `build.db`, the second fails with "database is
# locked", and the failure after that is silent — a run that cannot rebuild
# INSTALLS WHAT IS ALREADY THERE and photographs the other worktree's code.
# Pass a wave-specific path whenever another wave may be shooting.
DERIVED="${SHOT_DERIVED:-$HOME/Library/Caches/onyx-swift/watch-shot-derived}"

mkdir -p "$OUT"

# ── The screens ────────────────────────────────────────────────────────────
# Only what the app can actually be PUT INTO from the outside. `OnyxWatchApp`
# reads exactly two environment hooks (`ONYX_WATCH_AUTOSTART`,
# `ONYX_WATCH_SCREEN`), so this list is the truth about what is reachable —
# not a wish list.
#
# ── AND WHY AN UNKNOWN NAME IS A HARD ERROR ────────────────────────────────
# `deck`, `dashboard` and `finish` are presented by SwiftUI navigation from
# inside a running session; nothing in the model can be seeded to put them up,
# so a launch asking for one lands on StartView. A script that quietly wrote
# that PNG as `dashboard.png` would hand a reviewer a plausible photograph of
# the wrong screen — the exact failure `native-shot.sh` records having shipped
# once. So they are refused by name, with the hook that would make them work.
# W3 (deck, finish) and W4 (dashboard) add those hooks and this list with them.
screen_env() {
  case "$1" in
    start) echo "" ;;
    set)   echo "ONYX_WATCH_AUTOSTART=1" ;;
    rest)  echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=rest" ;;
    deck|dashboard|finish)
      echo "NOT_REACHABLE" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# ── The device ─────────────────────────────────────────────────────────────
# `|| true`: under `set -e` a non-matching `grep` fails the pipeline, which
# fails the command substitution, which kills the script — so without this the
# two lines below never print and the first person to run it gets a bare
# exit 1. The `grep -o` also means a device line that does not yield a UDID
# comes back EMPTY rather than as the whole line, so the guard actually guards.
UDID="$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | grep -oE '[0-9A-F-]{36}' || true)"
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE'." >&2
  echo "See docs/SIMULATORS.md — the pair has to exist before any wave shoots." >&2
  exit 1
fi

# ── It has to be PAIRED, not merely booted ─────────────────────────────────
# Without a paired phone the watch app has no `WatchContext`, `resolveDay`
# answers nothing and every screen below StartView is unreachable. That is a
# real screen, so the shot succeeds and shows the wrong thing.
if ! xcrun simctl list pairs | grep -q "$UDID"; then
  echo "'$DEVICE' ($UDID) is not in any pair." >&2
  echo "See docs/SIMULATORS.md § Pairing." >&2
  exit 1
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# ── The build ──────────────────────────────────────────────────────────────
echo "Building OnyxWatch…"
(cd "$ROOT/native" && xcodegen generate >/dev/null)
xcodebuild -project "$ROOT/native/Onyx.xcodeproj" \
  -scheme OnyxWatch \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP="$DERIVED/Build/Products/Debug-watchsimulator/OnyxWatch.app"
xcrun simctl install "$UDID" "$APP"

# ── The shots ──────────────────────────────────────────────────────────────
shoot() {
  local screen="$1"
  local env; env="$(screen_env "$screen")"

  case "$env" in
    UNKNOWN)
      echo "  unknown screen '$screen' — known: start set rest" >&2; return 1 ;;
    NOT_REACHABLE)
      echo "  '$screen' has no launch hook yet: it is presented by navigation" >&2
      echo "  inside a live session. Add a seed to WatchModel and a branch to" >&2
      echo "  OnyxWatchApp's ONYX_WATCH_SCREEN block first (W3/W4)." >&2
      return 1 ;;
  esac

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # `terminate` returns before the process is gone and `launch` ATTACHES to a
  # dying one — the new environment is never read and the shot photographs the
  # previous screen under the new name. The phone loop lost a whole twelve-shot
  # run to this, shifted by one.
  sleep 1

  # `SIMCTL_CHILD_` is how `simctl` passes environment INTO the launched app;
  # the app reads the plain name. Exported inline so nothing leaks into the
  # next launch — a stale `ONYX_WATCH_SCREEN` would put the rest cover over
  # every subsequent shot.
  # `${a[@]+"${a[@]}"}` rather than `"${a[@]}"`: under `set -u`, macOS's bash
  # 3.2 treats an EMPTY array expansion as an unbound variable and aborts. The
  # `start` screen needs no environment at all, so the empty case is the first
  # one this loop meets.
  local prefixed=()
  for pair in $env; do prefixed+=("SIMCTL_CHILD_${pair}"); done
  # ── CHECKED EXPLICITLY, BECAUSE errexit IS OFF IN HERE ────────────────
  # This function is called as `shoot "$s" || status=1`, and a function in a
  # tested context runs with `set -e` DISABLED for its whole body. So a failed
  # launch — app not installed, watch app crashed, bundle id drift — would
  # fall through to the sleep, screenshot whatever is on the display, and
  # print the success line. That is the "plausible photograph of the wrong
  # screen" this file refuses to produce twenty lines above.
  if ! env ${prefixed[@]+"${prefixed[@]}"} xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null; then
    echo "  launch failed — is OnyxWatch installed on $DEVICE?" >&2
    return 1
  fi

  # The watch is slower to first frame than the phone and `seedDebugContext`
  # runs in `.task` after it. Eight seconds is what the phone loop settled on
  # after a fresh device produced solid-black PNGs at 3.5 s.
  sleep 8
  if ! xcrun simctl io "$UDID" screenshot --type=png "$OUT/$screen.png" >/dev/null; then
    echo "  screenshot failed" >&2
    return 1
  fi
  echo "  $OUT/$screen.png"
}

read -ra SCREENS <<< "$SCREEN"
[ "$SCREEN" = "all" ] && SCREENS=(start set rest)

status=0
for s in ${SCREENS[@]+"${SCREENS[@]}"}; do
  [ -z "$s" ] && continue
  echo "$s"
  shoot "$s" || status=1
done

echo
echo "open $OUT   # the shots"
# ── THE WIDTH THESE PNGs CANNOT PROVE ──────────────────────────────────────
# Every watch screen in this app is laid out for 40 mm — 162 × 197 pt. The
# paired simulator is an Ultra 2 at 49 mm, which is 205 pt wide and hides
# exactly the overflow the budget exists to catch. A screenshot here is
# evidence about look, never about fit. The floor is asserted in
# `OnyxWatchLayoutTests` at 162 pt, and that test is the gate; this script is
# the second pair of eyes. Cross-wave law 11.
exit $status
