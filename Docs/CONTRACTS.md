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

分析成功时还可包含 additive schema-v1 字段 `rhythmMetrics`：

```json
{
  "metricsVersion": "watchbeat.rr-summary.v1",
  "recordingDurationSeconds": 29.998,
  "plausibleRRIntervalCount": 29,
  "medianRRMilliseconds": 1000.0,
  "medianDetectedHeartRateBPM": 60.0,
  "rrInterquartileRangeMilliseconds": 18.0,
  "prematureCandidateFraction": 0.04
}
```

它只从模型已检测的、300–2,000 ms 的 R–R 间期生成，不改变分类。四分位距不是临床 HRV；
候选占比的分母是 `classifiedBeatCount`，不表示长期早搏负荷。字段保持 optional，使旧的 schema-v1
JSON 仍可解码；拒判报告不生成该摘要。

同样 additive 的还有 `recordingDescriptors`（`watchbeat.descriptors.v1`）和每个 beat 上的
`qrsPeakToTroughMillivolts`：

```json
{
  "descriptorsVersion": "watchbeat.descriptors.v1",
  "shortestRRMilliseconds": 532.0,
  "longestRRMilliseconds": 1182.0,
  "minimumInstantaneousHeartRateBPM": 50.8,
  "maximumInstantaneousHeartRateBPM": 112.8,
  "longRRIntervalCount": 0,
  "consecutiveCandidatePairCount": 0,
  "medianQRSPeakToTroughMillivolts": 1.27,
  "minimumQRSPeakToTroughMillivolts": 1.27,
  "maximumQRSPeakToTroughMillivolts": 1.72
}
```

- 最短/最长 R–R 覆盖所有相邻检测峰；逐搏心率范围只用 300–2,000 ms 的可信间期。
- `longRRIntervalCount` 统计 > 2,000 ms 的间期；它可能来自停搏样间歇，也可能来自漏检 R 峰。
- `consecutiveCandidatePairCount` 统计相邻两个都为 `prematureUncertain` 的 beat 对。
- QRS 峰谷电压差 = 原始（未滤波）采样在 R 峰 ±80 ms 内的最大值 − 最小值，缺测点跳过、不插值。
  由 `ECGQRSAmplitude.measure` 计算，App 波形上的青色标注调用同一函数，保证与导出一致。

这些数值在分类之后计算，不参与 RR 规则，因此不改变 `algorithmVersion`。拒判报告不生成。

A refused report has `status: notAnalyzed`, a machine-readable `reason`, zero summary counts and an
empty `beats` array. Optional unavailable fields may be omitted by JSON encoders. Schema changes are
additive only within v1; a breaking field/meaning change requires schema v2.

## RR variability in one recording

An analyzed report may also contain `rrVariability`, with
`metricsVersion: watchbeat.rr-variability.v1`. The optional field is absent from old schema-v1 JSON
and refused reports. At least two included intervals and a finite positive recording duration are
required. It is descriptive RR variability, not verified NN/clinical HRV.

| Field | Meaning |
| --- | --- |
| `recordingDurationSeconds` | Input timeline span, not the sum of included intervals |
| `detectedIntervalCount` | Number of adjacent detected R-peak intervals |
| `includedIntervalCount` | Finite intervals in the inclusive 300–2,000 ms range |
| `excludedIntervalCount` | Detected minus included count |
| `candidateAdjacentIntervalCount` | Included intervals touching any premature candidate at either endpoint, counted once each |
| `successivePairCount` | Pairs of included intervals adjacent in the original sequence; never bridge an excluded interval |
| `meanRRMilliseconds` | Arithmetic mean of included intervals |
| `sdrrMilliseconds` | Sample RR standard deviation, n−1 denominator; not SDNN |
| `coefficientOfVariationPercent` | 100 × SDRR / mean RR; not the CV of instantaneous heart rate |
| `successiveDifferenceRMSMilliseconds` | Square root of mean squared differences over original adjacent included pairs (RMSSD_RR) |
| `successiveDifferenceOver50MillisecondsPercent` | 100 × number of original adjacent included pairs with absolute difference >50 ms / pair count (pRR50) |

The final two fields are nil/omitted when no original adjacent pairs remain. The >50 ms comparison
uses a 1e−9 ms tolerance to prevent floating-point timestamp subtraction from counting exactly
50 ms as greater than 50. Candidates are retained in these raw RR values. Timing range checks are
not artifact correction, noise detection or confirmation of sinus beats. Neither a high value nor
zero candidates establishes good recovery or absence of arrhythmia.

The UI's 50 ms histogram and adjacent RR pair scatter plot use the same range mask as these metrics.
This additive computation runs after classification, does not change the algorithm version or the
compact screening cache, and does not modify or interpolate original samples.
