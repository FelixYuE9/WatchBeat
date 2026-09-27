# Contributing

Contributions are welcome, but this project treats false certainty as a safety defect.

## Before a change

- Read `Docs/ARCHITECTURE.md`, `Docs/ALGORITHM.md`, `Docs/PRIVACY.md`, and the relevant ADR.
- Do not include personal ECG, identifiers, timestamps, certificates, profiles, secrets, or large
  public datasets.
- Open a design discussion before expanding medical claims, data sharing, cloud processing, runtime
  dependencies, or licensing scope.

## Code expectations

- Keep `ECGCore` independent from HealthKit and SwiftUI.
- Prefer deterministic pure functions and typed errors; never use force unwrap to hide invalid data.
- Preserve missing samples and timestamps until an explicit, documented quality decision.
- Put every algorithm parameter in versioned configuration; no hidden medical magic numbers.
- A poor-quality or ambiguous case must refuse classification rather than become Normal.
- Explanations derive from actual feature snapshots and reason codes.

## Validation

Run what the environment supports and report exactly what ran:

```bash
Tools/run-core-tests.sh --parallel        # ECGCore
bash Tools/run-app-tests.sh --parallel    # iOS app package (iOS/); chmod +x once to drop `bash`

cd iOS && swift build                # macOS target: SwiftUI + HealthKit
cd iOS && swift build --triple x86_64-apple-ios17.0-macabi --target WatchBeatHealthKit
```

The scripts wrap `swift test --parallel` and add the Swift Testing search paths that a
Command Line Tools-only macOS (no Xcode) needs. Use plain `swift test --parallel` only on a
machine with Xcode installed.

Test files must not import both `Testing` and `Foundation`: the Command Line Tools install on the
current host ships a broken `_Testing_Foundation` cross-import overlay, so such a file fails to
compile with `no such module '_Testing_Foundation'`. Put Foundation-dependent helpers in files that
do not import `Testing`.

## Building the Xcode app target

Xcode lives at `~/Downloads/Xcode.app` on the current host and `xcode-select` still points at the
Command Line Tools, so set the developer directory first:

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
cd iOS
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -sdk iphonesimulator26.5 -arch x86_64 CODE_SIGNING_ALLOWED=NO build
```

Use `-target`, not `-scheme`: a scheme build needs a destination and this host has no simulator
runtime and no iOS 26.5 device support. Re-run `Tools/install-swift-test-shim.sh` if you switch
`xcode-select` to Xcode — the wrapper has to stop passing Command Line Tools paths to the Xcode
toolchain.

The shared `WatchBeatApp` scheme is committed for destination-based builds and tests. Once a runtime
is installed, use `xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp -showdestinations`,
then run `build` and `test` against one of the listed destinations. An unsigned `-target` build does
not validate the entitlement in a signed product.

For algorithm changes, include deterministic tests, frozen fixtures/provenance, per-record metrics,
failure cases and Uncertain coverage. Public-dataset results must not be described as Apple Watch
accuracy. Never weaken rejection thresholds only to improve apparent coverage.

## Dependencies and attribution

Pin exact versions/commits, audit transitive dependencies, update `Docs/DEPENDENCIES.md`, add an ADR
when the choice affects architecture, and update `THIRD_PARTY_NOTICES.md`. Do not copy code from a
repository without an explicit compatible license. GPL-3.0 candidate code is not accepted into App
runtime or redistributed source under the current licensing strategy.

## Pull request checklist

- [ ] No private health data, credentials, signing material, or device identifiers.
- [ ] Build/test commands and actual results are recorded.
- [ ] New behavior has tests including rejection/failure cases.
- [ ] Algorithm/config versions are updated when outputs can change.
- [ ] Privacy, regulatory, dependency, dataset and attribution docs are updated as applicable.
- [ ] User-facing wording remains non-diagnostic.
