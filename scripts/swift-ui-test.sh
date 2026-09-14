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
DEVICE="${UI_TEST_DEVICE:-iPhone 17 Pro}"

# The same selection as scripts/native-shot.sh — never a hardcoded UDID.
UDID="$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [ -z "$UDID" ]; then
  echo "No available simulator named '$DEVICE'." >&2
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
grep -E "Test Suite|Executed|error:|Test run with|✘" "$LOG" | tail -20
rm -f "$LOG"
exit $status
