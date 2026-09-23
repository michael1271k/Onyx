#!/usr/bin/env bash
#
# The App Store screenshot set, from the same harness the visual diff uses.
#
# App Store Connect takes ONE required size for an iPhone-only app — 6.9" — and
# accepts 6.3" alongside it; anything else it scales down from the 6.9" set. So
# this shoots exactly those two and nothing else.
#
#   6.9"  iPhone 17 Pro Max   1320 × 2868
#   6.3"  iPhone 17 Pro       1206 × 2622
#
# Output is gitignored: it is 12 large PNGs that are regenerated in a few
# minutes and uploaded once. The committed shots under `__screenshots__` are the
# design-review set and stay the thing the diff watches.
#
#   scripts/store-shots.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Six screens, in the order they should appear on the product page: what the app
# opens on, then one per tab. `signin` is deliberately absent — a login wall is
# the worst possible first screenshot.
SCREENS="today train fuel day body-trends history"

for spec in '6.9in:iPhone 17 Pro Max' '6.3in:iPhone 17 Pro'; do
  size="${spec%%:*}"
  device="${spec#*:}"
  echo "── $size · $device ───────────────────────────────"
  # The device TYPES ship with Xcode; a simulator of them does not exist until
  # someone creates one (8.0.0 found only `iPhone 15` here). Create it rather
  # than fail — `simctl create` takes the newest runtime when none is named.
  xcrun simctl list devices available | grep -qE "^ +$device \(" ||
    xcrun simctl create "$device" "com.apple.CoreSimulator.SimDeviceType.${device// /-}" >/dev/null
  SHOT_OUT="$ROOT/native/__store__/$size" SHOT_AX=0 \
    "$ROOT/scripts/native-shot.sh" "$SCREENS" "$device"
  # One phone booted at a time. Two fresh iOS 27 simulators running their
  # first-boot daemons side by side drove the load average past 300 at 8.0.0,
  # and nine of twelve shots came back black at the 8 s wait. Shot alone,
  # after the load fell, all twelve drew.
  xcrun simctl shutdown "$device" 2>/dev/null || true
done

echo
echo "Upload from native/__store__/ — 6.9in is the required set."
