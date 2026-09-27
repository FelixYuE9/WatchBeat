# Roadmap and acceptance checklist

Checkboxes mean implemented artifacts exist, not that unavailable platform validation has passed.
Every milestone must update the related documents, versions, actual commands, failures and next risks.

## Milestone 0 — environment, license and architecture baseline

- [x] Audit working directory, Git, OS, Swift and Xcode availability.
- [x] Preserve the initially empty repository and avoid generated personal/signing data.
- [x] Add MIT project license and third-party notice baseline.
- [x] Add privacy-safe `.gitignore` and `PrivateValidationData/` guard.
- [x] Create platform-neutral `ECGCore` package without external dependencies.
- [x] Define HealthKit-independent signal, quality, detector and classifier contracts.
- [x] Add lossless timestamp/sample integrity inspector and deterministic test sources.
- [x] Centralize provisional research parameters and algorithm/config versions.
- [x] Record dependency registry and R-peak detector ADR.
- [x] Create offline validation-tool skeleton and standard-library raw CSV checker.
- [x] Document architecture, algorithm, validation, datasets, privacy and regulatory boundaries.
- [x] Run `swift package describe` and `swift test --parallel` (macOS, Swift 6.2.4, Command Line
  Tools only, no Xcode: 7 tests passed via `Tools/run-core-tests.sh --parallel`).
- [ ] Compile with Xcode on macOS (blocked: Xcode is not installed on this macOS host; only
  Command Line Tools are present).

Milestone 0 is source-complete and its `ECGCore` unit tests pass on a Command Line Tools-only macOS.
It is not validated end to end until the last item is executed. Do not mark the milestone validated
from static checks alone.

## Milestone 1 — HealthKit ECG reader (in progress; Xcode/real-iPhone items still blocked)

- [x] Create minimal iOS 17 SwiftUI project and test target: SwiftPM package under `iOS/`
  (`WatchBeatModels`, `WatchBeatHealthKit`, `WatchBeatApp`, `WatchBeatAppTests`).
- [x] Xcode app project: `iOS/WatchBeat.xcodeproj` with app, framework and unit-test targets;
  `xcodebuild -target` builds succeed for iPhoneOS 26.5 and iPhoneSimulator 26.5 SDKs
  (Xcode 26.6, build 17F113).
- [ ] Build and run through a real scheme + destination, and run the app on a simulator or iPhone
  (blocked: no iOS 26.5 device support and no simulator runtime installed).
- [x] Add HealthKit read-purpose string (`iOS/Resources/Info.plist`) and entitlement
  (`iOS/Resources/WatchBeatApp.entitlements`); request ECG read only with empty `toShare`.
- [x] Add typed `HealthKitClient`/repository/mapper boundaries (`ECGHealthKitReading`,
  `LiveHealthKitECGReader`, `ECGRepository`, `ECGHealthKitMapper`).
- [x] Query metadata-only latest/history list, sorted by start date (most recent first).
- [x] Load selected ECG voltage measurements lazily with cancellation/stale-request protection
  (generation numbers plus `Task.isCancelled` checks).
- [x] Preserve measurement order, time, missing lead values and declared sample count.
- [x] Convert `.appleWatchSimilarToLeadI` voltage to mV at the mapper boundary.
- [x] Show separate states for unsupported/unavailable, no accessible records, query failure and
  measurement incompleteness; never infer read-denial from an empty result.
- [x] Add mapping tests for unit conversion, ordering, count mismatch, missing voltage and rate inference.
- [x] Add first-launch and result-page medical disclaimer.
- [x] Build/test on this host with recorded versions: `swift build` (macOS 14), Mac Catalyst iOS 17
  triple, real iPhoneOS/iPhoneSimulator 26.5 SDKs, `xcodebuild -target` builds under Xcode 26.6
  (build 17F113), and 16 unit tests via `bash Tools/run-app-tests.sh --parallel`.
  See `Docs/VALIDATION.md`.
- [ ] Build/test with a real Xcode scheme + destination and run the app on a simulator or iPhone
  (blocked: iOS 26.5 device support and simulator runtime are not installed).
- [ ] Perform real-iPhone authorization/list/detail verification and record evidence without committing ECG.

## Milestone 2 — waveform and export

- [ ] Full-resolution analysis data remains separate from display downsampling.
- [ ] Scroll/zoom waveform with marker positions tied to real timestamps.
- [ ] User-triggered raw CSV and metadata JSON export through share sheet.
- [ ] Verify exported samples against selected HealthKit measurements on device.

## Milestone 3 — reproducible detector benchmark

- [ ] Freeze Python tool versions and lock hashes; add MIT-BIH v1.0.0 checksum download script.
- [ ] Define patient/record splits, 30 s window manifest, reference matching and tolerance.
- [ ] Add PeakSwift adapter pinned to exact tag/full SHA after full license/transitive audit.
- [ ] Compare at least two suitable PeakSwift detectors and Python references without Apple labels.
- [ ] Publish per-record R-peak metrics, timing errors, failures and detector-selection ADR.

## Milestones 4–9

- [ ] M4: dual-path preprocessing and objective signal-quality gate.
- [ ] M5: refined RR and robust premature-candidate detection.
- [ ] M6: independent personal template, QRS and morphology features.
- [ ] M7: conservative explainable PAC/PVC/Uncertain evidence classifier.
- [ ] M8: UI integration, research mode, feature export and settings reset.
- [ ] M9: end-to-end tests, independent Apple Watch domain validation and release audit.

## Deferred, not MVP

- watchOS app, custom acquisition, background monitoring or emergency alerts.
- server, login, sync, analytics, ads, subscriptions or clinician portal.
- Core ML/CNN until a rule-based and independently validated Apple Watch baseline exists.
- App Store publication until separate medical, legal, privacy and regulatory review is complete.
