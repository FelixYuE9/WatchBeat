# macOS, Xcode and real-iPhone validation required

This repository was initialized on Windows 10, where Swift and Xcode were unavailable. Work has since
moved to a macOS 26.7 host. Xcode 26.6 (build 17F113) is now installed at `~/Downloads/Xcode.app`
with the iOS 26.5 SDKs, but **no iOS simulator runtime and no iOS 26.5 device support** are
downloaded. Steps 1, 2 and the unit-test half of 3 are done; running on a simulator or device
(step 3 runtime, steps 4 and 5) remains blocked. Record versions, commands, outputs and
failures whenever the blocking tool becomes available.

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

Still to do once the platform/runtime is installed: build and test through the real scheme and
destination, then replace the placeholder bundle identifier `com.watchbeat.WatchBeat` and sign with
a real team. Do not add PeakSwift or any other candidate yet.

Configure:

- HealthKit capability and entitlement.
- A read-purpose description that clearly says the app reads saved ECGs for on-device research
  analysis.
- ECG read authorization only; `toShare` is empty.
- No network, analytics, crash-upload, iCloud health-data container or background modes.

Check the generated project for user-specific signing values before commit. Do not commit
provisioning profiles, certificates or device IDs.

## 3. Simulator and unit checks — UNIT CHECKS DONE, SIMULATOR STILL UNAVAILABLE

With Xcode 26.6 present the iPhoneSimulator 26.5 SDK is available, but
`xcrun simctl list runtimes` is empty and no device exists, so no simulator destination can be
created or run. Downloading the runtime (Xcode > Settings > Components, several GB) is required
first. The unit checks below were executed through SwiftPM on macOS
(`bash Tools/run-app-tests.sh --parallel`, 16 tests pass under both Swift 6.2.4 and Swift 6.3.3).

Simulator/mock tests may cover navigation, typed errors, cancellation, stale-result protection,
unit conversion, measurement ordering, missing voltage and sample-count mismatch. They do not count
as HealthKit end-to-end evidence.

Run the actual scheme and destination names, for example:

```bash
xcodebuild -scheme <AppScheme> -destination 'platform=iOS Simulator,name=<Device>' build
xcodebuild -scheme <AppScheme> -destination 'platform=iOS Simulator,name=<Device>' test
```

Replace placeholders rather than copying these commands verbatim into a pass report.

## 4. Real-iPhone acceptance steps

Use a compatible iPhone signed into a Health database containing Apple Watch ECG records.

1. Fresh install: confirm the research disclaimer appears before analysis.
2. Request access: inspect the Health permission sheet and confirm only ECG read access is requested.
3. Deny/withhold access: confirm the UI says no ECG is accessible and does not assert denial.
4. Grant access: confirm latest/history metadata loads and list navigation is responsive.
5. Open one ECG: compare start/end, duration, optional sampling frequency, declared measurement count,
   average heart rate, Apple classification and algorithm metadata against the Health record.
6. Verify every returned measurement keeps `timeSinceSampleStart` order and converts
   `.appleWatchSimilarToLeadI` to mV exactly once.
7. Exercise cancellation by switching records quickly; an older query must not replace the selected one.
8. Test records with missing lead quantity, missing sampling frequency and any available malformed edge
   case; confirm typed states rather than crash/force unwrap.
9. Export raw CSV and metadata JSON, then sample-check positions and values against the in-memory
   measurement sequence. Do not commit or attach the export.
10. Inspect device/network behavior: no ECG leaves the device and no sensitive values appear in logs.

## 5. Evidence to record safely

Record device model/OS in a non-identifying aggregate form, Xcode/Swift/app commit, pass/fail counts and
sanitized error codes. Do not record ECG waveforms, HealthKit identifiers, exact acquisition dates,
Apple account details or device identifiers in the repository.

Only after these checks may Milestone 1 be described as compiled and truthfully device-validated.
