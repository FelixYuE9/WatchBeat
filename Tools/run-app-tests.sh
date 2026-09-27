#!/usr/bin/env bash
# Runs the iOS application package test suite (WatchBeatAppTests).
#
# Same situation as Tools/run-core-tests.sh: SwiftPM does not add Swift Testing's framework search
# path, macro plugin or rpath to its auto-generated test runner, so the flags must be applied on the
# command line. Tools/lib/swift_test_env.sh decides them from the active toolchain
# (Xcode, or Command Line Tools only).
#
# Usage:
#   bash Tools/run-app-tests.sh            # equivalent to --parallel
#   bash Tools/run-app-tests.sh --parallel
#   bash Tools/run-app-tests.sh --filter SomeTest

set -euo pipefail

tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$tools_dir/.." && pwd)"

# shellcheck source=lib/swift_test_env.sh
. "$tools_dir/lib/swift_test_env.sh"

args=("$@")
if [ "${#args[@]}" -eq 0 ]; then
    args=(--parallel)
fi

build_test_flags

cd "$repo_root/iOS"

if [ "${#TEST_FLAGS[@]}" -gt 0 ]; then
    exec swift test "${args[@]}" "${TEST_FLAGS[@]}"
fi

exec swift test "${args[@]}"
