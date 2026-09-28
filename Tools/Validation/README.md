# Offline validation tools

This directory is development-only and never ships in the iOS runtime.

Milestone 0 includes a standard-library raw CSV checker that mirrors only the structural invariants at
the `ECGSignal` boundary. It is not an ECG detector and produces no medical classification. The
provisional analyzer below additionally needs the versions in `prototype-requirements.txt`.

```bash
python validate_raw_ecg_csv.py path/to/export.csv
python -m unittest discover -s tests -v
```

Expected raw CSV columns are exactly `time_s,voltage_mV`; blank voltage represents a preserved missing
measurement. The checker reports count, missing/non-finite values, time-order defects, inferred rate
and interval relative MAD as JSON. A structurally invalid file exits non-zero.

The same test command also checks safety-critical iOS project configuration:
HealthKit must use `CODE_SIGN_ENTITLEMENTS`, the App must remain iPhone-only, its permission plist
must remain read-only, every embedded framework must have a unique bundle identifier, and the shared
scheme must include the unit-test bundle. These checks do not replace an Xcode build, signed-product
inspection or real-device HealthKit validation.

## Swift analyzer mirror (App algorithm on MIT-BIH)

`evaluate_swift_analyzer_mirror.py` is a NumPy transcription of the shipping Swift analyzer
(`GradientEnergyRPeakDetector.swift` + `PrematureBeatAnalyzer.swift`). It cuts every development
record into independent 30-second windows, like Apple Watch recordings, and scores them:

```bash
python evaluate_swift_analyzer_mirror.py
```

Result for ECGCore `1.0.1-rr-research` (1,800 windows, 150 ms tolerance, 2026-09-28, Windows,
Python 3.10.9 / NumPy 1.23.5 / SciPy 1.10.0):

| Metric | Value |
|---|---|
| R-peak sensitivity | 0.9836 |
| R-peak positive predictivity | 0.9969 |
| Premature candidate sensitivity (annotated PAC/PVC-type beats with ≥ 5 prior beats) | 0.449 |
| Premature candidate positive predictivity | 0.667 |

The R-peak stage is solid; the RR-only premature rule misses about half of annotated premature
beats (bigeminy, short coupling, AF records) and is the part to improve next. A normal-to-normal RR
baseline raised sensitivity to 0.51 but dropped predictivity to 0.54, so it was not adopted. If the
Swift algorithm changes, update the mirror in the same change. These are public-dataset development
numbers, not Apple Watch accuracy.

## Single-format premature-beat prototype

The analyzer accepts only WatchBeat's raw `time_s,voltage_mV` CSV. It neither parses MIT-BIH `.dat`
files nor reads annotations. The independent adapter preserves one CSV row per format-212 sample,
with row order as sample index, `sample index / Hz` as time and calibrated mV as voltage. A blank
voltage in an iPhone export is retained by the parser; this prototype reports `notAnalyzed` rather
than deleting or interpolating that sample. No PAC/PVC subtype is inferred from RR timing alone.
Its semantic input identifier and top-level output schema match `Docs/CONTRACTS.md`; implementation
and algorithm identifiers remain distinct from the Swift App so offline scores cannot be transferred.

On Windows, with the checksum-verified local MIT-BIH data already downloaded:

```powershell
python convert_mitdb_to_watchbeat_csv.py 200 --output output/mitdb-200-watchbeat-raw.csv
python prototype_premature_beats.py output/mitdb-200-watchbeat-raw.csv --output output/prototype-premature-200.json
python evaluate_prototype_premature_beats.py 200 output/mitdb-200-watchbeat-raw.csv
```

For a user-triggered iPhone export, run only `prototype_premature_beats.py` with that CSV path.
The evaluator is separate and accepts only frozen development records. It compares against `.atr`
after the analyzer has produced its decisions; its simple order-preserving greedy timing match is a
smoke check, not the official `bxb` score or a release claim. The 200-record run on Windows with
Python 3.10.9, NumPy 1.23.5 and SciPy 1.10.0 produced 2,593 R peaks and 466 RR candidates;
of 2,601 annotated QRS, 2,592 matched within 150 ms, and of 856 annotated premature beats,
458 were flagged. This one-record development check exposes substantial misses and does not
establish performance on Apple Watch data. v0.4.0 ports the same minimal data flow to an independent,
dependency-free Swift implementation in `ECGCore`; Python/NumPy/SciPy remain offline-only and the
one-record figures are not inherited as App performance.

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

`data/` and `output/` are Git-ignored. The complete dataset and generated manifest exist only in the
local development workspace; neither is committed. The earlier PeakSwift candidate benchmark, the
three-detector vote and the WFDB `bxb` preparation scripts were removed in the MVP cleanup; they
remain in Git history (commit `c3c3e0e`).

Primary references:

- <https://physionet.org/content/mitdb/1.0.0/>
- <https://physionet.org/physiotools/wag/bxb-1.htm>
