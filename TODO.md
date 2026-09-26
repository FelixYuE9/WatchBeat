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
- [ ] Run `swift package describe` and `swift test --parallel` (blocked: Swift unavailable).
- [ ] Compile with Xcode on macOS (blocked: Xcode unavailable).

Milestone 0 is source-complete but build-unverified until the last two items are executed. Do not mark
the milestone validated from Windows static checks alone.

## Milestone 1 — HealthKit ECG reader (next, requires macOS/Xcode)

- [ ] Create minimal iOS 17 SwiftUI project and test target in Xcode.
- [ ] Add HealthKit capability and read-purpose string; request ECG read only with empty `toShare`.
- [ ] Add typed `HealthKitClient`/repository/mapper boundaries.
- [ ] Query metadata-only latest/history list, sorted by start date.
- [ ] Load selected ECG voltage measurements lazily with cancellation/stale-request protection.
- [ ] Preserve measurement order, time, missing lead values and declared sample count.
- [ ] Convert `.appleWatchSimilarToLeadI` voltage to mV at the mapper boundary.
- [ ] Show separate states for unsupported/unavailable, no accessible records, query failure and
  measurement incompleteness; never infer read-denial from an empty result.
- [ ] Add mapping tests for unit conversion, ordering, count mismatch, missing voltage and rate inference.
- [ ] Add first-launch and result-page medical disclaimer.
- [ ] Build/test with recorded Xcode, SDK and destination versions.
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
