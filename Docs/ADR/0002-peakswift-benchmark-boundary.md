# ADR-0002: Pin PeakSwift only inside an offline benchmark boundary

- Status: Accepted for Milestone 3 benchmark implementation
- Date: 2026-09-28
- Owners: Project contributors

## Context

The MIT-BIH data, split, window manifest and evaluator are frozen, so a Swift detector can now emit
predictions without influencing reference labels. PeakSwift v1.0.0 is still a candidate rather than
a selected production detector. Adding it directly to `ECGCore` or the App before comparison would
make an unvalidated algorithm and its native-code dependencies part of every App build.

The exact upstream audit found:

- PeakSwift tag `v1.0.0` resolves to `18fe5e7c674f915c3666e0414c7f2ac39b241bb9`
  and is Apache-2.0 with no NOTICE file at that revision;
- it declares Surge `2.3.2..<3.0.0`; the reviewed 2.3.2 revision is
  `6e4a47e63da8801afe6188cf039e9f04eb577721` under MIT;
- its IIR submodule is `9ef2a04ac3a44a8762b6a209c18e3bdb00394e5b` under MIT;
- its wavelib submodule is `a92456d2e20451772dd76c2a0a3368537ee94184` under BSD-3-Clause;
- wavelib is recorded upstream with an SSH URL, while the package also contains C, C++ and
  Objective-C++ targets and imports HealthKit in its main target;
- a dependency package's own `Package.resolved` does not pin transitive versions for a consuming
  top-level package, so relying on PeakSwift's checked-in lock would not be reproducible.

## Decision

1. Add a separate `Tools/PeakSwiftBenchmark` Swift package. It is not a dependency of `ECGCore`,
   `iOS/Package.swift`, or `WatchBeat.xcodeproj`.
2. Constrain PeakSwift and Surge to exact released versions at the top level and commit a resolved
   file plus a machine-readable audit containing every reviewed full revision and license.
3. Use a process-local Git URL rewrite in the test script for the upstream SSH submodule; never
   modify the tester's global Git configuration.
4. Decode MIT WFDB format 212 independently, pass physical millivolts to PeakSwift, and expose only
   the nine detector algorithms advertised by its README.
5. Do not decode reference labels in Swift. Require an explicit split, lock held-out-test behind a
   second flag, and reject invalid upstream peak indices instead of silently normalizing them.
6. Keep production integration, default detector selection and real HealthKit R–R labels blocked
   until at least two candidates pass reproducible development/validation comparison, official
   WFDB `bxb` cross-checking and a separate selection ADR.

## Consequences

- A failed dependency resolution, native build or detector benchmark cannot break the existing App.
- The macOS test must exercise SwiftPM submodule resolution and Apple framework compilation; Windows
  static checks cannot establish that result.
- Exact pins improve reproducibility but do not make the algorithm medically valid.
- If PeakSwift is later shipped, App-facing third-party notices and license text must be added to the
  distributed product, not only the repository documentation.

## Evidence reviewed

- <https://github.com/CardioKit/PeakSwift/releases/tag/v1.0.0>
- <https://github.com/CardioKit/PeakSwift/blob/v1.0.0/Package.swift>
- <https://github.com/CardioKit/PeakSwift>
- <https://github.com/Jounce/Surge/tree/2.3.2>
- <https://github.com/berndporr/iir1>
- <https://github.com/rafat/wavelib>
- `Tools/PeakSwiftBenchmark/dependency-lock.json`
