# ADR-0003: Ship the minimal dependency-free RR vertical slice

- Status: Accepted for v0.4.0 end-to-end flow
- Date: 2026-09-28
- Scope: App integration baseline, not medical-performance selection

## Context

The repository had three disconnected pieces: a working HealthKit reader/UI, strong development-only
R-peak scores in an isolated PeakSwift benchmark, and a Python raw-CSV → R peak → RR →
`prematureUncertain` prototype. The product priority for v0.4.0 is to run one complete, auditable flow
on iPhone before optimizing detector scores or PAC/PVC subtyping.

The frozen MIT-BIH development screen reported R-peak F1 0.9826 for PeakSwift `neurokit`, 0.9808 for
`pan-tompkins`, and 0.9855 for a label-blind 2/3 vote at 100 ms. The Python vertical slice's one-record
smoke check found 2,592/2,601 reference QRS within 150 ms and flagged 458/856 annotated premature
beats. None of these figures is Apple Watch-domain or PAC/PVC validation.

## Decision

Ship an independent, dependency-free Swift implementation of the already working vertical-slice
shape:

1. Accept only `watchbeat.ecg.signal.v1` (`timeSeconds`, Lead-I-like mV, optional nominal Hz).
2. Apply a 5–25 Hz zero-phase gradient-energy detector and local peak refinement.
3. Build a preceding 4–8 interval median RR baseline.
4. Mark RR below 0.80 of that baseline as `prematureUncertain`; do not infer PAC/PVC.
5. Emit `ECGAnalysisReport` schema 1 and use that one report for UI markers, summary and export.
6. Refuse missing, non-finite, irregular, too-short or peak-insufficient input explicitly.

HealthKit and the built-in synthetic record both construct the same `ECGSignal` and enter through
`ECGMeasurement`'s single analyzer call. Apple classification is not an input.

## Why this option

- It closes the full iPhone data path without adding Python, a server, PeakSwift's native dependency
  graph or network access to the App.
- It preserves the raw sample index/time mapping needed for audit and export.
- It is small enough to test deterministically and replace behind the stable contract later.
- It prioritizes integration truth over selecting a detector from one development score.

## Consequences

- v0.4.0 can be packaged and installed as a self-contained iPhone App after normal Apple signing.
- The output is research screening only. `normal` means only “not early under this local RR rule.”
- No PeakSwift, Python or public-dataset score may be presented as this Swift detector's accuracy.
- Full quality gating, Apple Watch-domain validation, morphology and PAC/PVC subtyping remain future
  work. Replacing the detector must keep or deliberately version the input/output contracts.
