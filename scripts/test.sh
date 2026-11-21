#!/usr/bin/env bash
# Runs `swift test`. With Command Line Tools only, SwiftPM doesn't find the
# swift-testing macro plugin on its own, so point it there explicitly.
set -euo pipefail

cd "$(dirname "$0")/.."

PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
