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
cd ECGCore
swift test --parallel
```

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
