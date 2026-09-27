#!/usr/bin/env bash
# Shared helper for the SwiftPM test scripts in Tools/. Source it; do not execute it.
#
# Why this exists:
#   SwiftPM does not add Swift Testing's framework search path, macro plugin or rpath to the
#   generated test runner, so those flags have to be passed on the command line (they cannot be
#   expressed in Package.swift). Which flags are needed depends on the active toolchain:
#
#   - Xcode: Testing.framework lives in <developer>/Platforms/MacOSX.platform/Developer/Library/
#     Frameworks. Only -F and -rpath are needed; the macro plugin comes from the toolchain.
#   - Command Line Tools only: Testing.framework and the macro plugin live under
#     /Library/Developer/CommandLineTools and both must be passed explicitly.
#
#   The active toolchain is taken from DEVELOPER_DIR, then from xcode-select, then from an
#   Xcode.app found in /Applications or ~/Downloads (xcode-select can still point at the
#   Command Line Tools right after a manual Xcode download; switching it needs sudo).

command_line_tools="/Library/Developer/CommandLineTools"
clt_frameworks="$command_line_tools/Library/Developer/Frameworks"
clt_macro_plugin="$command_line_tools/usr/lib/swift/host/plugins/testing"

resolve_developer_dir() {
    if [ -n "${DEVELOPER_DIR:-}" ] && [ -d "${DEVELOPER_DIR}" ]; then
        printf '%s' "${DEVELOPER_DIR}"
        return
    fi
    local selected
    selected="$(xcode-select -p 2>/dev/null || true)"
    if [ -n "$selected" ] && [ "$selected" != "$command_line_tools" ] && [ -d "$selected" ]; then
        printf '%s' "$selected"
        return
    fi
    local candidate
    for candidate in \
        "/Applications/Xcode.app/Contents/Developer" \
        "$HOME/Downloads/Xcode.app/Contents/Developer"; do
        if [ -d "$candidate" ]; then
            printf '%s' "$candidate"
            return
        fi
    done
    printf ''
}

# Fills TEST_FLAGS for the active toolchain. May leave it empty (Xcode with plain XCTest).
build_test_flags() {
    TEST_FLAGS=()
    local developer_dir
    developer_dir="$(resolve_developer_dir)"
    if [ -n "$developer_dir" ]; then
        local xcode_frameworks="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
        if [ -d "$xcode_frameworks/Testing.framework" ]; then
            export DEVELOPER_DIR="$developer_dir"
            TEST_FLAGS=(
                -Xswiftc "-F$xcode_frameworks"
                -Xlinker "-F$xcode_frameworks"
                -Xlinker -rpath
                -Xlinker "$xcode_frameworks"
            )
            return
        fi
    fi
    if [ -d "$clt_frameworks/Testing.framework" ] && [ -d "$clt_macro_plugin" ]; then
        TEST_FLAGS=(
            -Xswiftc "-F$clt_frameworks"
            -Xswiftc -plugin-path
            -Xswiftc "$clt_macro_plugin"
            -Xlinker "-F$clt_frameworks"
            -Xlinker -rpath
            -Xlinker "$clt_frameworks"
        )
    fi
}
