#!/usr/bin/env bash
# Builds the Swift package and assembles a runnable DevMissionControl.app bundle.
# Works with Command Line Tools only (no full Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="build/DevMissionControl.app"
BIN=".build/$CONFIG/DevMissionControl"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DevMissionControl"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign for a consistent launch identity.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
