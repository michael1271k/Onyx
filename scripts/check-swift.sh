#!/usr/bin/env bash
#
# Typecheck the native packages that DRAW without Xcode.
#
# ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
# `swiftc -typecheck` used to run over the Capacitor widget extension; that
# extension is gone (Wave 5) and the tiles now live in `native/Packages/OnyxUI`,
# a real SwiftPM package that depends on OnyxCore. A package cross-builds for
# the iOS simulator from the command line — no project, no signing, no
# simulator booted — so the same "does it compile" signal survives the move,
# and it now covers OnyxCore as a side effect.
#
# ── AND WHY IT REGENERATES THE PROJECT FIRST ─────────────────────────────────
# `Onyx.xcodeproj` is a build artefact and gitignored, so it goes stale the
# moment a merge brings in a .swift file the last `xcodegen generate` never saw.
# Xcode then reports the new type as "cannot find in scope" from every file that
# uses it, and the cascade reads like four unrelated source bugs — the shape
# this line exists to prevent. Nothing detected it before: `scripts/native-shot.sh`
# regenerates on its way to a screenshot, so the shot loop stayed green through
# two whole waves while ⌘B in Xcode did not.
#
# Healing beats detecting here. The project file is untracked, so there is no
# committed baseline to diff against, and a detector would have to reimplement
# `project.yml`'s directory glob to know what SHOULD be in it.
#
# ── WHAT IT DOES NOT COVER ───────────────────────────────────────────────────
# OnyxData (Supabase + GRDB — `npm run swift:data` owns it), the app target and
# the widget extension target (both need `xcodebuild`, see the plan's §9), and
# anything about LAYOUT: a tile that compiles can still draw badly, and no
# compiler has an opinion about that. The shot loop does.
#
# Regenerating is not the same as COMPILING the app target — that is still four
# minutes of `xcodebuild` and still belongs to the shot loop and the ship gate.
# What it guarantees is narrower and is the thing that actually broke: the
# project Xcode opens lists every file on disk.
set -euo pipefail

if ! command -v xcrun >/dev/null 2>&1; then
  echo "swift check: xcrun not found — skipping (this is a macOS + Xcode check)"
  exit 0
fi

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK" ]; then
  echo "swift check: no iPhoneSimulator SDK — skipping"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Idempotent and about a second. Skipped rather than failed where xcodegen is
# not installed, matching the `xcrun` guard above — but NOT skipped quietly if
# it runs and fails: `set -e` is on, so a broken `project.yml` stops the check
# here instead of leaving a stale project behind and a green tick.
if [ -f "$ROOT/native/project.yml" ] && command -v xcodegen >/dev/null 2>&1; then
  (cd "$ROOT/native" && xcodegen generate >/dev/null)
  echo "✔ Onyx.xcodeproj regenerated from project.yml"
fi

# A scratch path OUTSIDE the repo, like `swift:core` and `swift:data`, so the
# build products never land in git and PyCharm never indexes them.
if ! out=$(swift build \
  --package-path "$ROOT/native/Packages/OnyxUI" \
  --scratch-path "$HOME/Library/Caches/onyx-swift/OnyxUI-ios" \
  --triple arm64-apple-ios18.0-simulator \
  --sdk "$SDK" 2>&1); then
  echo "$out" | grep -v "warning: using sysroot" | grep -E "error|warning|note" || echo "$out" | tail -20
  exit 1
fi
echo "✔ OnyxUI + OnyxCore build for the iOS simulator"

# ── AND FOR THE WATCH (W7) ──────────────────────────────────────────────────
# `OnyxUI/Accessory/` is the one unfenced drawing directory: it is the watch's
# complications as well as the phone's Lock Screen, and a `WidgetFamily` case
# that exists on one platform and not the other (`.systemSmall`,
# `.accessoryCorner`) is the class of error only a watchOS compile catches.
# The iOS build above says nothing about it.
WATCH_SDK="$(xcrun --sdk watchsimulator --show-sdk-path 2>/dev/null || true)"
if [ -n "$WATCH_SDK" ]; then
  if ! out=$(swift build \
    --package-path "$ROOT/native/Packages/OnyxUI" \
    --scratch-path "$HOME/Library/Caches/onyx-swift/OnyxUI-watchos" \
    --triple arm64-apple-watchos11.0-simulator \
    --sdk "$WATCH_SDK" 2>&1); then
    echo "$out" | grep -v "warning: using sysroot" | grep -E "error|warning|note" || echo "$out" | tail -20
    exit 1
  fi
  echo "✔ OnyxUI + OnyxCore build for the watchOS simulator"
else
  echo "swift check: no WatchSimulator SDK — watchOS cross-build skipped"
fi
