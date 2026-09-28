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
- [x] Compile with Xcode on macOS: the `ECGCore` Xcode framework target was built as an App
  dependency with Xcode 26.6 against iPhoneOS/iPhoneSimulator 26.5 SDKs.

Milestone 0 is source- and build-complete. This does not validate the iOS App or any ECG algorithm
end to end; those claims remain governed by the later milestones and recorded runtime evidence.

## Milestone 1 — HealthKit ECG reader (simulator run complete; real-iPhone items pending)

- [x] Create minimal iOS 17 SwiftUI project and test target: SwiftPM package under `iOS/`
  (`WatchBeatModels`, `WatchBeatHealthKit`, `WatchBeatApp`, `WatchBeatAppTests`).
- [x] Xcode app project: `iOS/WatchBeat.xcodeproj` with app, framework and unit-test targets;
  `xcodebuild -target` builds succeed for iPhoneOS 26.5 and iPhoneSimulator 26.5 SDKs
  (Xcode 26.6, build 17F113).
- [x] Commit a shared `WatchBeatApp` scheme, configure the App as iPhone-only and wire the HealthKit
  entitlement with `CODE_SIGN_ENTITLEMENTS` (signed-product verification remains pending).
- [x] Build and run the app on an iPhone 17 Pro simulator with iOS 26.5. A user-provided screenshot
  on 2026-09-27 confirms installation, launch and the no-accessible-records state after the embedded
  framework bundle-identifier fix. The exact Xcode command/output was not captured.
- [x] Add HealthKit read-purpose string (`iOS/Resources/Info.plist`) and entitlement
  (`iOS/Resources/WatchBeatApp.entitlements`); request ECG read only with empty `toShare`. The
  capability is source-configured; a signed real-device build must still verify it.
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
- [ ] Run the shared scheme's automated test action on the installed simulator and record the exact
  command/result. App launch is observed; automated destination tests are not yet recorded.
- [ ] Perform real-iPhone authorization/list/detail verification and record evidence without committing ECG.

## Milestone 2 — waveform and export (implemented in source; macOS runtime validation pending)

- [x] Full-resolution analysis/export data remains separate from timestamp-preserving display
  downsampling, with original extrema and missing-value gaps represented.
- [x] Scroll/zoom waveform with an optional marker overlay positioned from real timestamps.
- [x] User-triggered raw CSV and metadata JSON export through the iPhone share sheet; temporary
  files use protection and are removed when sharing finishes.
- [x] Ship a deterministic built-in synthetic ECG tutorial, visibly and structurally distinguished
  from Apple Health data and available even when no HealthKit record is accessible.
- [x] Add a default card-style overview, bottom Overview/Data/Settings navigation and immediate
  Follow System/Simplified Chinese/English language selection.
- [x] Label every adjacent R–R interval in the synthetic tutorial in milliseconds, using exact marker
  timestamps from the generator rather than a detector. Real HealthKit ECG labels remain pending a
  benchmark-selected and validated R-peak detector.
- [x] Present the built-in synthetic ECG as a persistent, explicitly labelled `Example ECG Data`
  record in the Data list instead of a separate "view example" action.
- [ ] Verify exported samples against selected HealthKit measurements on device.

## Milestone 3 — reproducible detector benchmark

- [x] Add a version-fixed MIT-BIH v1.0.0 downloader that freezes the official 48-record list and
  verifies each selected `.hea`/`.dat`/`.atr` file against PhysioNet's SHA-256 manifest.
- [x] Define and test a versioned 30 s window/prediction contract, subject/record split-leakage
  checks, and deterministic one-to-one R-peak matching with the official `bxb` 150 ms default window.
- [x] Download and checksum-verify all 48 records locally, audit subject identities, and freeze the
  actual development/validation/held-out record manifest before detector evaluation.
- [ ] Cross-check evaluator output against the official WFDB `bxb` implementation.
- [x] Prepare and test development-only `wrann` inputs and a sample-exact `rdann` round-trip gate;
  official `bxb` execution remains pending on a host with WFDB tools.
- [ ] Freeze any required WFDB/NeuroKit/BioSPPy Python versions and hashes before adding them.
- [x] Audit and pin PeakSwift v1.0.0 plus Surge/IIR/wavelib full revisions in an isolated,
  development-only prediction adapter; its macOS dependency build and four adapter tests passed.
- [x] Add a development-only nine-algorithm runner and compatible-report comparison that cannot
  access validation or held-out-test splits.
- [x] Run all nine PeakSwift algorithms on the frozen development split and inspect per-record
  outliers; preserve these as research-only metrics, not an App accuracy claim.
- [x] Add and test a label-blind, development-only three-detector voting experiment with configurable
  2/3 or 3/3 vote threshold and peak-alignment tolerance.
- [ ] Cross-check vote grouping at difficult windows and freeze one or more candidate configurations
  before independent validation; do not assume a single detector must win.
- [ ] Add a production `RPeakDetecting` adapter only after benchmark selection and a new ADR.
- [ ] Compare at least two suitable PeakSwift detectors and Python references without Apple labels.
- [ ] Publish per-record R-peak metrics, timing errors, failures and detector-selection ADR.

## Milestones 4–9

- [ ] M4: dual-path preprocessing and objective signal-quality gate.
- [ ] M5: refined RR and robust premature-candidate detection.
- [ ] M6: independent personal template, QRS and morphology features.
- [ ] M7: conservative explainable PAC/PVC/Uncertain evidence classifier.
- [ ] M8: UI integration, research mode, feature export and settings reset; expose only validated,
  effective advanced parameters with configuration provenance and a baseline reset.
- [ ] M9: end-to-end tests, independent Apple Watch domain validation and release audit.
- [ ] M9 distribution: keep one App / one Bundle ID, review optional IAP tipping, and complete
  storefront-specific medical-device, privacy, tax, consumer and open-source compliance review.

## Deferred, not MVP

- watchOS app, custom acquisition, background monitoring or emergency alerts.
- server, login, sync, analytics, ads, subscriptions or clinician portal.
- Core ML/CNN until a rule-based and independently validated Apple Watch baseline exists.
- App Store publication until separate medical, legal, privacy and regulatory review is complete.
