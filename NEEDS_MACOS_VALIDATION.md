# macOS, Xcode and real-iPhone validation required

This repository was initialized on Windows 10. Swift and Xcode were unavailable, so none of the
following has been claimed as complete. Record versions, commands, outputs and failures when moving
to a suitable macOS host.

## 1. Validate ECGCore first

```bash
sw_vers
uname -a
swift --version
xcodebuild -version
cd ECGCore
swift package describe
swift test --parallel
```

Fix real compile/test failures without deleting tests or weakening safety assertions. Update
`Docs/VALIDATION.md` with exact results.

## 2. Create the iOS target

Use Xcode to create an iOS 17 SwiftUI application and unit-test target under `iOS/`. Add local
`ECGCore` as a package. Do not add PeakSwift or any other candidate yet.

Configure:

- HealthKit capability and entitlement.
- A read-purpose description that clearly says the app reads saved ECGs for on-device research
  analysis.
- ECG read authorization only; `toShare` is empty.
- No network, analytics, crash-upload, iCloud health-data container or background modes.

Check the generated project for user-specific signing values before commit. Do not commit
provisioning profiles, certificates or device IDs.

## 3. Simulator and unit checks

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
