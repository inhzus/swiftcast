#!/usr/bin/env bash
# Builds a release binary and wraps it in build/SwiftCast.app.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/SwiftCast.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SwiftCast" "$APP/Contents/MacOS/SwiftCast"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "Built $APP"
