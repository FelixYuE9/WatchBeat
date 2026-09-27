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
# Optional public dataset download; all 48 records are the default.
python download_mitdb.py --records 100

# Evaluate one detector prediction file against a frozen window manifest.
python evaluate_r_peaks.py manifest.json predictions.json --output output/report.json
```

`download_mitdb.py` is fixed to MIT-BIH Arrhythmia Database v1.0.0 and its official 48-record list.
It downloads only `.hea`, `.dat` and current `.atr` files, verifies each against the versioned official
`SHA256SUMS.txt`, and writes a local receipt plus attribution notice. It refuses unknown record names
and never runs automatically.

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

The report is always marked `research-only-unvalidated` and requires a future cross-check against the
official `bxb` tool. It evaluates R-peak timing only, not PAC/PVC classification, and public-dataset
performance cannot establish Apple Watch performance.

`data/` and `output/` are Git-ignored. Actual MIT-BIH download, the audited patient/record manifest,
WFDB adapters and pinned third-party Python environments remain pending. No external Python dependency
is installed or declared yet.

Primary references:

- <https://physionet.org/content/mitdb/1.0.0/>
- <https://physionet.org/physiotools/wag/bxb-1.htm>
