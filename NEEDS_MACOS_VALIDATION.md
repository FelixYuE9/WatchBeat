# macOS, Xcode and real-iPhone validation required

This repository was initialized on Windows 10, where Swift and Xcode were unavailable. Work has since
moved to a macOS 26.7 host. Xcode 26.6 (build 17F113) is installed at `~/Downloads/Xcode.app`.
On 2026-09-27 a user-provided screenshot confirmed the App running on an iPhone 17 Pro simulator
with iOS 26.5 and showing the expected empty HealthKit state. The exact scheme command, automated
simulator tests, current Milestone 2 UI and all signed real-iPhone checks remain to be recorded.

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
`com.watchbeat.WatchBeat`, select a real team, then build through that scheme. Do not add PeakSwift
or another detector candidate yet.

Verify before the first signed run:

- `CODE_SIGN_ENTITLEMENTS` resolves to `Resources/WatchBeatApp.entitlements`, the HealthKit
  capability is enabled, and the signed App contains `com.apple.developer.healthkit`.
- A read-purpose description that clearly says the app reads saved ECGs for on-device research
  analysis.
- ECG read authorization only; `toShare` is empty.
- No network, analytics, crash-upload, iCloud health-data container or background modes.

Check the generated project for user-specific signing values before commit. Do not commit
provisioning profiles, certificates or device IDs.

## 3. Simulator and unit checks — APP LAUNCH OBSERVED; CURRENT TESTS PENDING

The original 16 tests passed through SwiftPM on macOS under Swift 6.2.4 and Swift 6.3.3. Milestone 2
adds 7 tests (expected total: 23) that have only received Windows-side static/project checks so far.
Run both commands below and retain their final summaries.

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

Then launch the App and verify the built-in example is available from the empty state. Confirm its
orange synthetic label, horizontal scrolling, 1×–8× zoom, raw CSV confirmation/share sheet and
metadata JSON confirmation/share sheet. The exported example filenames must contain `synthetic-example`.

## 4. Real-iPhone acceptance steps

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

## 5. Evidence to record safely

Record device model/OS in a non-identifying aggregate form, Xcode/Swift/app commit, pass/fail counts and
sanitized error codes. Do not record ECG waveforms, HealthKit identifiers, exact acquisition dates,
Apple account details or device identifiers in the repository.

Only after these checks may Milestone 1 be described as compiled and truthfully device-validated.
