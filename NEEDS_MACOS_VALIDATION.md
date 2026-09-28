# macOS, Xcode and real-iPhone validation required

This repository was initialized on Windows 10, where Swift and Xcode were unavailable. Work has since
moved to a macOS 26.7 host. Xcode 26.6 (build 17F113) is installed at `~/Downloads/Xcode.app`.
On 2026-09-27 user-provided screenshots confirmed the App running on an iPhone 17 Pro simulator
with iOS 26.5, rendering the 15,000-sample synthetic waveform and the v0.3.0 (3)
overview/language/R–R UI; the user reported the service was running normally. The exact scheme
command and earlier automated simulator output were not recorded. The user subsequently reported
that the requested v0.3.0 (4) Mac/Xcode check passed, including the persistent example-record change;
the exact test summary/count and all signed real-iPhone checks remain to be recorded.

## 1. Validate ECGCore first — DONE

```bash
sw_vers
uname -a
swift --version
xcodebuild -version
cd ECGCore
swift package describe
swift test --parallel
```

Actual results (2026-09-26):

- `sw_vers` → macOS 26.7, build 25G229; `uname -a` → Darwin 25.6.0 x86_64.
- `swift --version` → Apple Swift 6.2.4 (swiftlang-6.2.4.1.4, clang-1700.6.4.2), swift-driver 1.127.15.
- `xcodebuild -version` → **fails**: `tool 'xcodebuild' requires Xcode, but active developer
  directory '/Library/Developer/CommandLineTools' is a command line tools instance`.
- `Tools/run-core-tests.sh --parallel` (= `swift test --parallel` plus Swift Testing search paths)
  → `Test run with 7 tests in 2 suites passed`, exit 0.

Fix real compile/test failures without deleting tests or weakening safety assertions. Update
`Docs/VALIDATION.md` with exact results.

## 2. Create the iOS target — DONE (Xcode 26.6, build 17F113)

`iOS/WatchBeat.xcodeproj` now exists with five targets: `ECGCore`, `WatchBeatModels`,
`WatchBeatHealthKit` (frameworks), `WatchBeatApp` (application) and `WatchBeatAppTests`
(unit-test bundle). `ECGCore` is compiled from `../ECGCore/Sources` instead of being resolved as a
SwiftPM package dependency, which keeps `import ECGCore` working.

Verified on 2026-09-27 (`DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"`):

```bash
cd iOS
xcodebuild -project WatchBeat.xcodeproj -list
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -configuration Debug -sdk iphonesimulator26.5 -arch x86_64 CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatAppTests \
           -configuration Debug -sdk iphonesimulator26.5 -arch x86_64 CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -configuration Debug -sdk iphoneos26.5 -arch arm64 CODE_SIGNING_ALLOWED=NO build
```

All three builds report **BUILD SUCCEEDED**. `-target` is used instead of `-scheme` because a scheme
build requires a destination, and this host has no simulator runtime and no iOS 26.5 device support:

```text
xcodebuild: error: Unable to find a destination matching the provided destination specifier:
    { generic:1, platform:iOS Simulator }
  Ineligible destinations for the "WatchBeatApp" scheme:
    { platform:iOS, ..., error:iOS 26.5 is not installed. Please download and install the
      platform from Xcode > Settings > Components. }
```

The repository contains a shared `WatchBeatApp` scheme and an iPhone-only target. The simulator
runtime is now available. Before a real-iPhone run, replace the placeholder bundle identifier
`com.watchbeat.WatchBeat`, select a real team, then build through that scheme. The isolated
`Tools/PeakSwiftBenchmark` candidate must remain outside the App until benchmark selection.

Verify before the first signed run:

- `CODE_SIGN_ENTITLEMENTS` resolves to `Resources/WatchBeatApp.entitlements`, the HealthKit
  capability is enabled, and the signed App contains `com.apple.developer.healthkit`.
- A read-purpose description that clearly says the app reads saved ECGs for on-device research
  analysis.
- ECG read authorization only; `toShare` is empty.
- No network, analytics, crash-upload, iCloud health-data container or background modes.

Check the generated project for user-specific signing values before commit. Do not commit
provisioning profiles, certificates or device IDs.

## 3. Simulator and unit checks — USER-REPORTED PASS; EXACT TEST SUMMARY PENDING

The original 16 tests passed through SwiftPM on macOS under Swift 6.2.4 and Swift 6.3.3. The current
source adds 9 tests (expected total: 25). The user reports the requested build-4 test passed, but no
final Xcode summary/count was supplied. Re-run both commands below when retaining release evidence.

Simulator/mock tests may cover navigation, typed errors, cancellation, stale-result protection,
unit conversion, measurement ordering, missing voltage and sample-count mismatch. They do not count
as HealthKit end-to-end evidence.

Discover and use an actual destination:

```bash
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

Then launch the App and verify it opens on Overview; switch among Overview, Data and Settings; change
language among Follow System, Simplified Chinese and English; and confirm the change is immediate.
On Data, confirm one persistent `Example ECG Data` / `示例 ECG 数据` card is shown above the
separate Apple Health section and that the old `Explore built-in synthetic ECG` action is absent.
Open that record and confirm its orange synthetic label, a millisecond bracket between every
adjacent R peak (about 857 ms at 70 bpm), horizontal scrolling, 1×–8× zoom, raw CSV confirmation/share
sheet and metadata JSON confirmation/share sheet. The exported example filenames must contain
`synthetic-example`. A HealthKit record must show the detector-not-validated note rather than guessed
R–R labels.

## 4. PeakSwift offline candidate — MACOS BUILD AND DEVELOPMENT SCREEN PASSED

This development-only package is intentionally separate from the App. From the repository root run:

```bash
bash Tools/run-peakswift-benchmark-tests.sh
```

The script selects the existing Xcode under `~/Downloads` when present, applies a process-local HTTPS
rewrite for PeakSwift's SSH wavelib submodule, resolves the exact lock, runs all Python validation
tests, and compiles/runs the Swift adapter tests. It does not change global Git configuration, run a
detector on held-out data, or modify the iOS App. Retain the complete final Swift test summary and any
dependency-resolution error. Do not work around a revision mismatch by deleting `Package.resolved`.

Actual user-run result on 2026-09-28:

- PeakSwift `1.0.0` and Surge `2.3.2` resolved successfully;
- all 38 then-current Python validation tests passed;
- the native C/C++/Objective-C++ dependency graph linked successfully in 80.78 seconds;
- SwiftPM printed `[4/4]` for the four `WFDB212ReaderTests` XCTest cases on
  `x86_64-apple-macos14.0`;
- the final Swift Testing message reported zero tests because this package uses XCTest, not because
  the preceding four XCTest cases were skipped or failed.

The run emitted a harmless warning that the directly pinned Surge package was not named by a root
target. Surge is now declared as an explicit target product as well as an exact root constraint, so
future runs should retain the pin without that warning.

The user reran the test script after that change: 47 Python tests and all four adapter XCTest cases
passed. The user also ran the complete nine-algorithm development-only screen:

```bash
bash Tools/run-peakswift-development-benchmark.sh
```

The command verified exact dependency revisions, downloaded/re-verified public MIT-BIH data,
regenerated the locked manifest, ran all nine public PeakSwift algorithms in release configuration on
`development`, and wrote a research-only comparison under the ignored `Tools/Validation/output/`
directory. The user provided its comparison and three candidate prediction files; their reproducible
2/3 voting experiment is documented in `Tools/Validation/README.md` and `Docs/VALIDATION.md`.

The local development-only voting audit found one-algorithm-only misses in record 203 and shared
false positives in two zero-reference windows of record 207. The next macOS gate is the independent
WFDB `bxb` cross-check. After this checkout and the 2/3-at-100-ms prediction file are available on
Mac, install or locate official `wrann`, `rdann`, and `bxb`, then run the command in
`Tools/Validation/README.md`. The script verifies every written annotation by round-trip before
comparing; it has not yet been executed with WFDB tools. Freeze single-detector and/or voting
candidates only after inspecting that result, then use `validation`. `held-out-test` remains locked
until a detector/configuration ADR exists. No development result authorizes production integration.

## 5. Real-iPhone acceptance steps

Use a compatible iPhone signed into a Health database containing Apple Watch ECG records.

1. Fresh install: confirm the research disclaimer appears before analysis.
2. Request access: inspect the Health permission sheet and confirm only ECG read access is requested.
3. Deny/withhold access: confirm the UI says no ECG is accessible and does not assert denial.
4. Grant access: confirm latest/history metadata loads and list navigation is responsive.
5. Open one ECG: compare start/end, duration, optional sampling frequency, declared measurement count,
   average heart rate, Apple classification and symptoms metadata against the Health record.
6. Verify every returned measurement keeps `timeSinceSampleStart` order and converts
   `.appleWatchSimilarToLeadI` to mV exactly once.
7. Exercise cancellation by switching records quickly; an older query must not replace the selected one.
8. Test records with missing lead quantity, missing sampling frequency and any available malformed edge
   case; confirm typed states rather than crash/force unwrap.
9. Inspect the installed App's signed entitlements and confirm HealthKit is present and no unexpected
   capability was added.
10. Inspect device/network behavior: no ECG leaves the device and no sensitive values appear in logs.
11. Export raw CSV and metadata JSON through the share sheet. Compare CSV row count/order/timestamps/
    missing fields with the selected HealthKit measurements, confirm JSON says `dataSource: healthKit`,
    and confirm no HealthKit UUID appears in either filename or JSON.

The built-in synthetic example is a UI tutorial only and does not satisfy any real-iPhone item.

## 6. Evidence to record safely

Record device model/OS in a non-identifying aggregate form, Xcode/Swift/app commit, pass/fail counts and
sanitized error codes. Do not record ECG waveforms, HealthKit identifiers, exact acquisition dates,
Apple account details or device identifiers in the repository.

Only after these checks may Milestone 1 be described as compiled and truthfully device-validated.
