# ADR-0001: Isolate and benchmark R-peak detector candidates

- Status: Accepted for Milestone 0
- Date: 2026-09-26
- Owners: Project contributors

## Context

The product needs robust R-peak detection for short, single-lead Apple Watch ECG, but a detector's
name or performance on another ECG domain does not establish Apple Watch performance. R-peak
detection is also distinct from PAC/PVC-like classification. The project targets a permissive main
license and must remain auditable and replaceable.

PeakSwift is an Apache-2.0 Swift package with multiple detector and signal-quality implementations.
Its visible stable release is `v1.0.0`; the package also includes internal C/C++ targets and a Surge
dependency. SpeziHealthKit is useful as a HealthKit API reference but would add broader framework
surface for a narrow query. WFDB, NeuroKit2, and BioSPPy are suitable only for offline validation.

## Decision

1. Keep `ECGCore` dependency-free in Milestone 0.
2. Define the `RPeakDetecting` protocol before integrating any implementation.
3. Treat PeakSwift as the preferred **candidate baseline**, not the selected production detector and
   never as a PAC/PVC classifier.
4. In Milestone 3, implement a `PeakSwiftRPeakDetector` adapter and benchmark at least two suitable
   PeakSwift algorithms on a frozen public-data protocol and available Apple Watch compatibility
   samples. Detector selection cannot use Apple's ECG classification.
5. If integrated, pin an exact released tag plus resolved full commit SHA; preserve Apache-2.0
   attribution/NOTICE and audit all transitive and vendored components.
6. Keep WFDB/NeuroKit2/BioSPPy in `Tools/Validation`; none enters App runtime.
7. Consider an independent pure-Swift detector only if PeakSwift build, performance, licensing, or
   validation is inadequate. Do not maintain two production implementations without evidence.

## Options considered

### A. Add PeakSwift immediately

Rejected for now. It would turn an unbenchmarked candidate into a de facto choice, add transitive
surface before Xcode is available, and cannot currently be compiled in this environment.

### B. Write a production detector from scratch now

Rejected for now. It duplicates established algorithms before the validation harness exists and
creates a second body of safety-critical code without comparative evidence.

### C. Protocol-first, benchmark before selection

Selected. It preserves replaceability, makes validation criteria explicit, and allows the rest of the
core to test against deterministic fakes without license or platform coupling.

## Consequences

- Milestone 0 cannot detect R peaks; this is intentional and visible.
- Milestone 3 has additional adapter, attribution, build, and benchmark work.
- Results remain comparable across implementations through a versioned result contract.
- A future default detector requires a separate ADR containing datasets, metrics, failures, device
  performance, exact dependency pins, and rationale.

## Evidence reviewed

- PeakSwift repository and Apache-2.0 declaration: <https://github.com/CardioKit/PeakSwift>
- PeakSwift releases (`v1.0.0` visible): <https://github.com/CardioKit/PeakSwift/releases>
- PeakSwift package manifest: <https://github.com/CardioKit/PeakSwift/blob/main/Package.swift>
- SpeziHealthKit repository and MIT declaration: <https://github.com/StanfordSpezi/SpeziHealthKit>
- Apple's voltage query documentation:
  <https://developer.apple.com/documentation/healthkit/hkelectrocardiogramquery>
