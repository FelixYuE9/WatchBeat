# ECG input and analysis output contracts

## Canonical input — `watchbeat.ecg.signal.v1`

The classifier accepts one platform-neutral type only:

```swift
ECGSignal(
    timeSeconds: [Double],          // seconds since this recording began
    voltageMillivolts: [Double?],   // Lead-I-like mV, index-aligned
    nominalSamplingRateHz: Double?  // source metadata; timestamps are verified independently
)
```

Contract rules:

- The two arrays have the same length and preserve source order.
- Index `i` always identifies the same original sample in both arrays and in model output.
- Missing voltage is `nil`; it is never replaced with zero and its timestamp is never deleted.
- Time is seconds relative to the recording start. Voltage is millivolts.
- The model may refuse invalid input, but no adapter may sort, interpolate or resample it silently.
- Apple ECG classification, symptoms, date, UUID and average heart rate are not model inputs.

`ECGHealthKitMapper` creates this signal from each
`HKElectrocardiogram.VoltageMeasurement`: `timeSinceSampleStart` becomes `timeSeconds`, and
`.appleWatchSimilarToLeadI` is converted once to mV. `ECGExampleFactory` creates the same type.
Both are wrapped in `ECGMeasurement`, whose initializer calls the same `analyzer.analyze(signal)`.

The lossless CSV wire encoding is exactly:

```csv
time_s,voltage_mV
0.0,0.012
0.002,
0.004,-0.007
```

One CSV row equals one array index; a missing voltage is an empty second field. MIT-BIH and other
offline formats must be converted by a separate adapter before analysis.

## Canonical output — `ECGAnalysisReport` schema 1

Both the Swift App and offline vertical slice use the same top-level shape and label vocabulary:

```json
{
  "schemaVersion": 1,
  "inputFormat": "watchbeat.ecg.signal.v1",
  "algorithmVersion": "1.0.1-rr-research",
  "configVersion": "1.0.0",
  "detectorIdentifier": "watchbeat-gradient-energy-rr-v1",
  "researchOnly": true,
  "parameters": {
    "detectionLowCutoffHz": 5.0,
    "detectionHighCutoffHz": 25.0,
    "refractoryPeriodMilliseconds": 250.0,
    "peakRefinementRadiusMilliseconds": 100.0,
    "rrBaselineWindowBeats": 8,
    "minimumRRBaselineBeatCount": 4,
    "prematurityThreshold": 0.8
  },
  "status": "notAnalyzed",
  "reason": "insufficientDetectedBeats",
  "samplingFrequencyHz": 500.0,
  "summary": {
    "rPeakCount": 0,
    "classifiedBeatCount": 0,
    "prematureCandidateCount": 0
  },
  "beats": []
}
```

An analyzed report contains beat objects with `sampleIndex`, `timeSeconds`, `rrBeforeMilliseconds`,
`localRRMilliseconds`, `prematurityRatio`, `classification`, `confidence` and `reasonCodes`.
Classifications used by this RR-only model are `normal`, `prematureUncertain` and `notAnalyzed`.
Here, `normal` means only “not early relative to the available local RR baseline”; it is not a
whole-record or medical diagnosis.

A refused report has `status: notAnalyzed`, a machine-readable `reason`, zero summary counts and an
empty `beats` array. Optional unavailable fields may be omitted by JSON encoders. Schema changes are
additive only within v1; a breaking field/meaning change requires schema v2.
