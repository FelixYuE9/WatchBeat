#!/usr/bin/env bash
# Runs the ECGCore test suite.
#
# SwiftPM does not add Swift Testing's framework search path, macro plugin or rpath to its
# auto-generated test runner, and Package.swift cannot fix that, so the flags have to be passed on
# the command line. Tools/lib/swift_test_env.sh decides them from the active toolchain
# (Xcode, or Command Line Tools only).
#
# Usage:
#   bash Tools/run-core-tests.sh            # equivalent to --parallel
#   bash Tools/run-core-tests.sh --parallel
#   bash Tools/run-core-tests.sh --filter SomeTest

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

cd "$repo_root/ECGCore"

if [ "${#TEST_FLAGS[@]}" -gt 0 ]; then
    exec swift test "${args[@]}" "${TEST_FLAGS[@]}"
fi

exec swift test "${args[@]}"
