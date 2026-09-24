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
# A screen with no hook lands on StartView, and a script that quietly wrote
# that PNG as `dashboard.png` would hand a reviewer a plausible photograph of
# the wrong screen — the exact failure `native-shot.sh` records having shipped
# once. So an un-hooked name is refused BY NAME, with the hook that would make
# it work.
#
# W3 added the five it owns. Each is reached along the path a finger would
# take — `WatchModel.debugScreen` is read by whichever view owns the screen,
# the sets go in through `commitSet`, and the deck is a real push onto the
# real `NavigationStack`. W4 added the last four, including `dashboard`, which
# W1 named here as unreachable and which is the only name this list has ever
# refused.
screen_env() {
  case "$1" in
    # ── W2: `start` NEEDS THE CONTEXT NOW ──────────────────────────────────
    # The Start screen became page one of the dashboard, which is the app's
    # idle root. With no environment at all it draws the honest "Open Onyx on
    # your iPhone" empty state — a real screen under the right filename, and
    # not the one anybody asked to review. `nophone` is that state, by its own
    # name; `start` seeds the context and shows the hero.
    start)   echo "ONYX_WATCH_SCREEN=start" ;;
    # The state the founder complained about by name. It had no hook before
    # W2, which is why nobody had looked at it.
    restday) echo "ONYX_WATCH_SCREEN=restday" ;;
    banner)  echo "ONYX_WATCH_SCREEN=banner" ;;
    join)    echo "ONYX_WATCH_SCREEN=join" ;;
    glance)  echo "ONYX_WATCH_SCREEN=glance" ;;
    pulse)   echo "ONYX_WATCH_SCREEN=pulse" ;;
    # ⚠️ ONLY HONEST AS THE FIRST SCREEN OF A RUN, AFTER AN UNINSTALL. It has
    # no environment, so it draws whatever `WatchContextCache` is holding — and
    # every other screen in this list seeds one. Shot after `start` it comes
    # back as the hero, under this filename.
    nophone) echo "" ;;
    set)     echo "ONYX_WATCH_AUTOSTART=1" ;;
    rest)    echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=rest" ;;
    quality|qualitytags) echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=quality" ;;
    deck|deckswipe) echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=deck" ;;
    pause)   echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=pause" ;;
    cancel)  echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=cancel" ;;
    finish)  echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=finish" ;;
    # ── W4's four, re-pointed by W2 ────────────────────────────────────────
    # `dashboard` was the last name this script refused. W4 made it a pushed
    # screen; W2 made it the ROOT, so these three no longer push anything —
    # `DashboardView` reads the value and moves its own `TabView`. `dashboard`
    # is the Today page, which is page two now that Start is page one.
    #
    # NO autostart on the three: the dashboard is the screen you see when no
    # session is live, and a live session would root at `SetView` instead and
    # photograph the workout.
    dashboard) echo "ONYX_WATCH_SCREEN=dashboard" ;;
    train)     echo "ONYX_WATCH_SCREEN=train" ;;
    fuel)      echo "ONYX_WATCH_SCREEN=fuel" ;;
    # The live-workout widget's two faces, at their real sizes. Autostart AND
    # two sets, because the faces read the App Group suite and the only thing
    # that writes it is a live session's `publishLiveSnapshot` — a shot of the
    # idle faces would prove the view draws and nothing about the data path.
    #
    # ⚠️ This is NOT a photograph of the Smart Stack. Relevance is the
    # system's judgement about a workout there is no heart to drive, `simctl`
    # cannot force a stack to surface a card, and a screenshot of one that did
    # not is exactly the wrong-screen shot this file refuses. See
    # `LiveWidgetPreview`.
    widget)  echo "ONYX_WATCH_AUTOSTART=1 ONYX_WATCH_SCREEN=widget" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# ── The gestures a screen needs after launch ───────────────────────────────
# Some screens are a SCROLL away rather than a state away, and a scroll is the
# one thing no launch environment can seed. The quality panel is page two of
# `SetView`'s scroll view; the app had a DEBUG `scrollPosition` write for it
# and it never landed (a scroll position written before layout is kept and
# never performed), so the loop does what a finger does instead.
#
# `axe` is the UI-automation CLI the founder enabled before W1
# (`docs/SIMULATORS.md`). Absent, the screen is REFUSED rather than
# photographed unscrolled — a page-one PNG called `quality.png` is exactly the
# "plausible photograph of the wrong screen" this script exists to prevent.
#
# The y range is the scroll viewport at 49 mm: the content starts under the bar
# at ~64 pt and the pinned tick begins at ~158. A drag that starts on the
# button does not scroll, which cost one round.
AXE="${AXE:-/opt/homebrew/bin/axe}"

screen_gesture() {
  case "$1" in
    # Calibrated against the accessibility tree, not by eye: one drag puts the
    # panel's header at the top of the viewport, two put the quality grid
    # there. A FAST flick comes back — whatever `scrollTargetBehavior` makes of
    # a thrown gesture on this SDK, the measured answer is that it returns to
    # where it started, and only a slow drag moves and stays.
    quality)     echo "swipe 100 150 100 85 1.5 1" ;;
    qualitytags) echo "swipe 100 150 100 85 1.5 3" ;;
    # Sideways, on the first deck row, to reveal the leading actions.
    deckswipe)   echo "swipe 30 95 150 95 1.2 1" ;;
    *) echo "" ;;
  esac
}

# ── The device ─────────────────────────────────────────────────────────────
# `|| true`: under `set -e` a non-matching `grep` fails the pipeline, which
# fails the command substitution, which kills the script — so without this the
# two lines below never print and the first person to run it gets a bare
# exit 1. The `grep -o` also means a device line that does not yield a UDID
# comes back EMPTY rather than as the whole line, so the guard actually guards.
# EXACT name, newest runtime. `grep -m1 "$DEVICE ("` took the first line that
# merely STARTED with the name, so "iPhone 15" resolved to W4's
# "iPhone 15 (W4 lane A 26.5)" and every run quietly moved to iOS 26.5.
UDID="$(xcrun simctl list devices available | awk -v n="$DEVICE" '{ l = $0; sub(/^ +/, "", l); u = substr(l, length(n) + 3, 36); if (index(l, n " (") == 1 && u ~ /^[0-9A-F-]+$/ && length(u) == 36) print u }' | tail -1 || true)"
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
shoot() {
  local screen="$1"
  local env; env="$(screen_env "$screen")"

  case "$env" in
    UNKNOWN)
      echo "  unknown screen '$screen' — known: start restday banner join glance pulse nophone set quality qualitytags rest deck deckswipe pause cancel finish dashboard train fuel widget" >&2; return 1 ;;
    NOT_REACHABLE)
      echo "  '$screen' has no launch hook yet: it is presented by navigation" >&2
      echo "  inside a live session. Add a case to WatchModel.DebugScreen and a" >&2
      echo "  branch to OnyxWatchApp's ONYX_WATCH_SCREEN block first." >&2
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
  # `SHOT_THEME=<preset>` (overhaul A2): the palette rides the seeded
  # context, as the phone's does, and the PNG carries the name.
  [ -n "${SHOT_THEME:-}" ] && env="$env ONYX_WATCH_THEME=$SHOT_THEME"
  local file="$OUT/$screen${SHOT_THEME:+-$SHOT_THEME}.png"

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

  local gesture; gesture="$(screen_gesture "$screen")"
  if [ -n "$gesture" ]; then
    if [ ! -x "$AXE" ]; then
      echo "  '$screen' needs a swipe and axe is not at $AXE" >&2
      echo "  brew install cameroncooke/axe/axe — see docs/SIMULATORS.md" >&2
      return 1
    fi
    # shellcheck disable=SC2086
    set -- $gesture
    local times="${7:-1}"
    # ── SLOW AND SHORT, REPEATED ────────────────────────────────────────────
    # A fast flick comes back: whatever `scrollTargetBehavior` decides about a
    # thrown gesture on this SDK, the measured answer is that it snaps to
    # where it started. A slow drag of rather more than half a page moves and
    # stays. Repeating it is how a longer page is reached, and it is also what
    # a finger does.
    local i=1
    while [ "$i" -le "$times" ]; do
      if ! "$AXE" swipe --start-x "$2" --start-y "$3" --end-x "$4" --end-y "$5" \
          --duration "$6" --udid "$UDID" >/dev/null 2>&1; then
        echo "  swipe failed" >&2
        return 1
      fi
      sleep 1
      i=$((i + 1))
    done
    sleep 1
  fi
  if ! xcrun simctl io "$UDID" screenshot --type=png "$file" >/dev/null; then
    echo "  screenshot failed" >&2
    return 1
  fi
  echo "  $file"
}

read -ra SCREENS <<< "$SCREEN"
[ "$SCREEN" = "all" ] && SCREENS=(glance start restday banner join pulse set quality qualitytags rest deck deckswipe pause cancel finish dashboard train fuel widget)

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
