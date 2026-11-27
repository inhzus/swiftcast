#!/usr/bin/env bash
# Builds a universal release binary and wraps it in build/SwiftCast.app.
#
#   VERSION        CFBundleShortVersionString (default: the one in Resources/Info.plist)
#   SIGN_IDENTITY  codesign identity: a name like "Developer ID Application: …" or a SHA-1
#                  hash, e.g. of the self-signed release certificate (default: ad-hoc)
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/SwiftCast.app"
PLIST="$APP/Contents/Info.plist"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SwiftCast" "$APP/Contents/MacOS/SwiftCast"
cp Resources/Info.plist "$PLIST"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Secure timestamps are for Developer ID (notarization needs them); a self-signed
    # identity, given by name or SHA-1, signs without one.
    TIMESTAMP=--timestamp=none
    if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
        TIMESTAMP=--timestamp
    fi
    codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "Built $APP ($(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") ($BUILD_NUMBER))"
