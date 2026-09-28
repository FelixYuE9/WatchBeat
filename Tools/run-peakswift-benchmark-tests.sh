#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPOSITORY_ROOT/Tools/PeakSwiftBenchmark"

# PeakSwift v1.0.0 records wavelib with a GitHub SSH submodule URL. Rewrite it for only this
# process tree so a tester does not need a GitHub SSH key and global Git settings stay untouched.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf'
export GIT_CONFIG_VALUE_0='git@github.com:'

if [[ -d "$HOME/Downloads/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
fi

cd "$PACKAGE_DIR"
swift package resolve

cd "$REPOSITORY_ROOT"
python3 -m unittest discover -s Tools/Validation/tests -v

cd "$PACKAGE_DIR"
swift test --parallel
