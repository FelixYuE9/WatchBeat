# PeakSwift benchmark adapter

This Swift package is a **development-only candidate harness**. It is deliberately separate from
`ECGCore` and the iOS App: resolving or building it cannot turn an unvalidated detector into a
shipping dependency.

The package pins PeakSwift v1.0.0 and Surge 2.3.2, while `Package.resolved` and
`dependency-lock.json` record their full reviewed revisions plus PeakSwift's IIR and wavelib
submodule revisions. The upstream wavelib URL uses SSH; use the repository script so Git rewrites
that one URL to HTTPS only for the child process, without modifying global Git configuration:

```bash
bash Tools/run-peakswift-benchmark-tests.sh
```

After the package builds on macOS and the frozen MIT-BIH data/manifest have been generated, create
label-blind development predictions for one candidate:

```bash
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf' \
GIT_CONFIG_VALUE_0='git@github.com:' \
swift run --package-path Tools/PeakSwiftBenchmark PeakSwiftBenchmark \
  --manifest Tools/Validation/output/mitdb-rpeak-manifest-v1.json \
  --dataset-dir Tools/Validation/data/mitdb-1.0.0 \
  --algorithm neurokit \
  --split development \
  --output Tools/Validation/output/peakswift-neurokit-development.json

python Tools/Validation/evaluate_r_peaks.py \
  Tools/Validation/output/mitdb-rpeak-manifest-v1.json \
  Tools/Validation/output/peakswift-neurokit-development.json \
  --split development \
  --output Tools/Validation/output/peakswift-neurokit-development-report.json
```

Supported names are `christov`, `nabian2018`, `hamilton`, `two-average`, `neurokit`,
`pan-tompkins`, `unsw`, `engzee`, and `kalidas`. Start with development only. Validation is for
frozen finalists; held-out-test requires an additional explicit `--allow-held-out-test` flag and
must not be run until the detector and configuration have been selected.

The adapter:

- decodes the official two-channel MIT WFDB format 212 files to physical millivolts using header
  gain and baseline;
- reads only window identity/timing/channel metadata, not `referencePeakSamples`;
- runs each 30-second window independently, matching the intended short-ECG use case;
- rejects upstream duplicate, unsorted or out-of-window peak indices instead of silently repairing
  detector output;
- writes evaluator-compatible global sample indices and a SHA-256 hash of the exact detector/input
  configuration.

No result from this harness is an Apple Watch accuracy claim, PAC/PVC classifier, diagnosis, or
production-detector selection. Official WFDB `bxb` cross-checking and Apple Watch-domain validation
remain separate gates.

The dependency graph and four adapter XCTest cases passed on the user's Intel Mac on 2026-09-28.
The user subsequently ran the complete development-only screen of all nine algorithms. To
reproduce that screen on macOS, return to the repository root and run:

```bash
bash Tools/run-peakswift-development-benchmark.sh
```

That command verifies the reviewed dependency revisions, downloads only the public checksum-verified
MIT-BIH files, uses release configuration, keeps each run in a unique ignored output directory,
continues after an individual candidate failure, and produces JSON plus Markdown comparison artifacts.
It cannot request `validation` or `held-out-test`. Three candidate prediction files can also be
combined by the development-only voting experiment in `../Validation/vote_r_peak_predictions.py`;
that experiment is not part of PeakSwift or the App.
