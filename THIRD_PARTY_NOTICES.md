# Third-party notices

## Current release contents (v0.5.0)

The shipping `ECGCore` and iOS App do **not** bundle, link, or declare any third-party runtime
package dependency. `ECGCore/Package.swift` and `iOS/Package.swift` have no external remote package.
The on-device waveform analyzer is implemented in this repository with Foundation/Swift only.

Offline validation tools under `Tools/Validation/` optionally use NumPy and SciPy (BSD-3-Clause,
versions in `prototype-requirements.txt`); they never ship in the App. The earlier development-only
PeakSwift benchmark package was removed in the MVP cleanup.

The project's own source is distributed under the MIT License in `LICENSE`.

## Other candidate components — not included

The following are evaluation candidates only and their code is not part of this repository:

- CardioKit/PeakWatch — license must be rechecked at the commit reviewed.
- StanfordSpezi/SpeziHealthKit — MIT License.
- MIT-LCP/wfdb-python — MIT License; planned development tool only.
- NeuroKit2 — MIT License; planned development tool only.
- BioSPPy — BSD 3-Clause License; optional development tool only.

If any candidate is added, replace this section with the exact version/commit, copyright statement,
license text location, NOTICE requirements, modifications, transitive components, and whether it is
distributed with the App. Referencing a candidate here does not incorporate or relicense it.

## Datasets

No ECG dataset or waveform is included. Future use of MIT-BIH v1.0.0 requires Open Data Commons
Attribution License v1.0 attribution; see `Docs/DATASETS.md`. Dataset licensing is separate from
software licensing.
