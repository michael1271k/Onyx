#!/usr/bin/env bash
#
# The OnyxUI test suite. `swift test` cannot run it: the package declares no
# macOS platform (it is SwiftUI + WidgetKit), so the only runner is a simulator
# through the generated project.
#
# Its own derived-data path, NOT `shot-derived`: the screenshot loop installs
# whatever it finds there, and a test build racing a shot run gives you either
# "database is locked" or screenshots of the wrong code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ── THE DEFAULT HAS TO BE A DEVICE THAT EXISTS (Expansion W1) ──────────────
# This said `iPhone 17 Pro`, which is not installed here — and because of the
# bug fixed immediately below, that made `npm run check` exit 1 with NO OUTPUT
# AT ALL. The gate was dead and looked quiet, which is the failure mode this
# script's own header calls "the worst kind". `iPhone 15` is the simulator the
# sprint pairs and documents (`docs/SIMULATORS.md`).
DEVICE="${UI_TEST_DEVICE:-iPhone 15}"

# The same selection as scripts/native-shot.sh — never a hardcoded UDID.
#
# `|| true`: under `set -e` a non-matching `grep` fails the pipeline, fails the
# command substitution, fails the assignment, and kills the script RIGHT HERE —
# so the message below never printed and the caller got a bare exit 1. `grep -o`
# for the UDID rather than `sed` on the whole line, so a line that carries no
# UDID yields empty and the guard actually guards instead of passing a device
# name through as an id.
UDID="$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | grep -oE '[0-9A-F-]{36}' || true)"
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE'." >&2
  echo "Installed: $(xcrun simctl list devices available | grep -oE 'iPhone [^(]*' | sort -u | tr '\n' ' ')" >&2
  echo "Override with UI_TEST_DEVICE=… — see docs/SIMULATORS.md." >&2
  exit 1
fi

(cd "$ROOT/native" && xcodegen generate >/dev/null)

LOG="$(mktemp -t onyx-ui-test)"
set +e
xcodebuild test -project "$ROOT/native/Onyx.xcodeproj" -scheme Onyx \
  -destination "id=$UDID" -only-testing:OnyxUITests \
  -derivedDataPath "$HOME/Library/Caches/onyx-swift/ui-test-derived" \
  CODE_SIGNING_ALLOWED=NO >"$LOG" 2>&1
status=$?
set -e
# ── THE FILTER HAS TO SHOW A CRASH, NOT JUST A FAILURE (W6) ────────────────
# A test that crashes the HOST prints none of the patterns above: Swift Testing
# relaunches, the per-suite lines start over, and the only record of what went
# wrong is the "Failing tests:" block and "** TEST FAILED **" at the very end.
# Without them this script exited 65 and printed four cheerful "Selected tests
# passed" lines, which is a gate that fails silently — the worst kind.
grep -E "Test Suite|Executed|error:|Test run with|✘|Failing tests|^\s+[A-Za-z0-9_]+\.[A-Za-z0-9_]+\(\)|\*\* TEST" "$LOG" | tail -24
rm -f "$LOG"
exit $status
