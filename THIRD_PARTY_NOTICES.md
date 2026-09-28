# Third-party notices

## Current release contents

The shipping `ECGCore` and iOS App still do **not** bundle, link, or declare any third-party runtime
package dependency. `ECGCore/Package.swift` and `iOS/Package.swift` have no external remote package.

Milestone 3 adds a separate, development-only `Tools/PeakSwiftBenchmark` package. Resolving that
tool downloads the following reviewed sources; none is currently linked into the App:

- CardioKit/PeakSwift v1.0.0, revision
  `18fe5e7c674f915c3666e0414c7f2ac39b241bb9` — Apache License 2.0, copyright 2023
  Maximilian Kapsecker; no NOTICE file was present at the reviewed revision.
- Jounce/Surge 2.3.2, revision `6e4a47e63da8801afe6188cf039e9f04eb577721` — MIT License,
  copyright 2014–2019 the Surge contributors.
- berndporr/iir1 submodule revision `9ef2a04ac3a44a8762b6a209c18e3bdb00394e5b` — MIT License,
  copyright Vinnie Falco and Bernd Porr.
- rafat/wavelib submodule revision `a92456d2e20451772dd76c2a0a3368537ee94184` — BSD
  3-Clause License, copyright Rafat Hussain and Holger Nahrstaedt.

Exact URLs and audit notes are in `Tools/PeakSwiftBenchmark/dependency-lock.json`. Licenses remain
in each package checkout managed by SwiftPM. If a detector is later selected for the App, the
distributed product must expose the required complete license texts and attributions before release.

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
