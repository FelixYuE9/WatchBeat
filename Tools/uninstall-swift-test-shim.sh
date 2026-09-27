#!/usr/bin/env bash
# Removes the user-level `swift` wrapper installed by Tools/install-swift-test-shim.sh.

set -euo pipefail

wrapper="$HOME/.local/bin/swift"

if [ -f "$wrapper" ]; then
    rm -f "$wrapper"
    echo "Removed: $wrapper"
else
    echo "Not installed: $wrapper"
fi
