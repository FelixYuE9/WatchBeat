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
must remain read-only, and the shared scheme must include the unit-test bundle. These checks do not
replace an Xcode build, signed-product inspection or real-device HealthKit validation.

`data/` and `output/` are Git-ignored. Milestone 3 will add pinned WFDB/NeuroKit/BioSPPy environments,
MIT-BIH version/checksum download, deterministic 30 s manifests, one-to-one peak matching and metrics.
No external Python dependency is installed or declared yet.
