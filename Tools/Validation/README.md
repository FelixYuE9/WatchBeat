# Offline validation tools

This directory is development-only and never ships in the iOS runtime.

Milestone 0 includes a standard-library raw CSV checker that mirrors only the structural invariants at
the `ECGSignal` boundary. It is not an ECG detector and produces no medical classification.

```bash
python validate_raw_ecg_csv.py path/to/export.csv
python -m unittest discover -s tests -v
```

Expected raw CSV columns are exactly `time_s,voltage_mV`; blank voltage represents a preserved missing
measurement. The checker reports count, missing/non-finite values, time-order defects, inferred rate
and interval relative MAD as JSON. A structurally invalid file exits non-zero.

The same standard-library test command also checks safety-critical iOS project configuration:
HealthKit must use `CODE_SIGN_ENTITLEMENTS`, the App must remain iPhone-only, its permission plist
must remain read-only, every embedded framework must have a unique bundle identifier, and the shared
scheme must include the unit-test bundle. These checks do not replace an Xcode build, signed-product
inspection or real-device HealthKit validation.

## Milestone 3 R-peak benchmark foundation

The first benchmark layer remains standard-library-only:

```bash
# Download and re-verify all 48 records (four bounded workers are the default).
python download_mitdb.py --workers 4

# Rebuild the deterministic manifest and prove that it matches the committed lock.
python build_mitdb_manifest.py

# Evaluate one detector prediction file against a frozen window manifest.
python evaluate_r_peaks.py output/mitdb-rpeak-manifest-v1.json predictions.json \
  --split development \
  --output output/report.json
```

`download_mitdb.py` is fixed to MIT-BIH Arrhythmia Database v1.0.0 and its official 48-record list.
It downloads only `.hea`, `.dat` and current `.atr` files, verifies each against the versioned official
`SHA256SUMS.txt`, and writes a local receipt plus attribution notice. Safe nested paths in the official
checksum file are accepted, while absolute paths, traversal and Windows drive syntax are rejected.
It refuses unknown record names and never runs automatically.

`build_mitdb_manifest.py` rehashes every required input against that receipt before parsing it. The
committed `mitdb_split_v1.json` keeps records 201 and 202 in one subject group, applies a reproducible
subject-level stratified split, and was frozen before any detector result was evaluated. The builder
prefers MLII and otherwise selects channel 0, parses official MIT binary annotations, and retains every
complete 30-second window—including windows with no reference QRS, where detections correctly count
as false positives.

The generated manifest is intentionally ignored because it is about 2.7 MB, but its exact content is
guarded by committed `mitdb_manifest_v1.lock.json`. The frozen result contains 48 records / 47 subjects,
2,880 windows and 109,150 reference QRS annotations. Default generation fails if any input, split or
serialized output differs from the lock. `--update-lock` is reserved for an intentionally reviewed
benchmark revision; it must never be used merely to silence a mismatch.

`evaluate_r_peaks.py` validates a version-1 manifest with:

- exact 30-second windows;
- explicit `subjectId`, `recordId`, channel and development/validation/held-out-test split;
- rejection of any subject or record present in more than one split;
- strictly increasing reference and detected sample indices;
- detector name/version plus a required lowercase SHA-256 hash of its frozen configuration;
- deterministic, order-preserving, one-to-one matching that first maximizes matched peaks and then
  minimizes total timing error;
- a frozen 150 ms match tolerance, matching the default window documented for PhysioNet WFDB `bxb`;
- per-window, per-split and aggregate TP/FP/FN, sensitivity/recall, positive predictivity/precision,
  F1, FP/FN per 30 seconds, and absolute timing-error median/p95.

The command requires an explicit `--split`. During detector development, use only `development`;
compare frozen finalists on `validation`, and run `held-out-test` once only after the detector and
configuration have been selected. Predictions must contain exactly the windows in the requested
stage, so a development report cannot silently consume held-out predictions.

The report is always marked `research-only-unvalidated` and requires a future cross-check against the
official `bxb` tool. It evaluates R-peak timing only, not PAC/PVC classification, and public-dataset
performance cannot establish Apple Watch performance. Reports include a SHA-256 of the selected
benchmark definition, including exact reference peak positions, so comparisons cannot mix changed
annotations under the same window IDs.

The isolated Swift candidate runner is documented in `../PeakSwiftBenchmark/README.md`. It is not a
dependency of `ECGCore` or the App. Its PeakSwift/native-code graph compiled and all four adapter
XCTest cases ran on the user's Intel Mac. No detector dataset result exists yet. Use
`../run-peakswift-development-benchmark.sh` to screen all nine public algorithms on `development`
only; its comparison tool rejects mixed datasets, benchmark definitions, windows, splits or matching
policies and never selects a production detector.

`data/` and `output/` are Git-ignored. The complete dataset and generated manifest exist only in the
local development workspace; neither is committed. The official WFDB `bxb` cross-check, detector
execution on macOS and any pinned third-party Python environment remain pending. No external Python
dependency is installed or declared yet.

Primary references:

- <https://physionet.org/content/mitdb/1.0.0/>
- <https://physionet.org/physiotools/wag/bxb-1.htm>
