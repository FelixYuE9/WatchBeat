#!/usr/bin/env python3
"""Run a provisional ECG-to-premature-candidate pipeline on Windows or macOS.

This is a vertical-slice research prototype, not a PAC/PVC classifier or a
medical device. Reference annotations are never read by the detector.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import numpy as np
import scipy
from scipy.ndimage import uniform_filter1d
from scipy.signal import butter, find_peaks, sosfiltfilt

from validate_raw_ecg_csv import CSVContractError, EXPECTED_HEADER, inspect, parse_rows


ALGORITHM_VERSION = "prototype-rr-v0.1"
CONFIG_VERSION = "1.0.0-prototype"
DETECTOR_IDENTIFIER = "scipy-gradient-energy-rr-v0.1"
PREMATURITY_RATIO = 0.80
BASELINE_RR_COUNT = 8
MINIMUM_BASELINE_RR_COUNT = 4


class PrototypeError(ValueError):
    """The input cannot be analyzed without making an unsafe assumption."""


@dataclass(frozen=True)
class ECGTrace:
    time_seconds: np.ndarray
    voltage_millivolts: np.ndarray


def read_exported_csv(path: Path) -> ECGTrace:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != EXPECTED_HEADER:
            raise PrototypeError(f"expected CSV header {','.join(EXPECTED_HEADER)}")
        times, voltages = parse_rows(reader)
    report = inspect(times, voltages)
    if not report.structurally_valid:
        raise PrototypeError("CSV timestamps or finite values fail the export contract")
    return ECGTrace(
        time_seconds=np.asarray(times, dtype=np.float64),
        voltage_millivolts=np.asarray(
            [np.nan if value is None else value for value in voltages], dtype=np.float64
        ),
    )


def _detect_r_peaks(voltage: np.ndarray, frequency_hz: float) -> list[int]:
    filtered = sosfiltfilt(
        butter(2, [5.0, 25.0], btype="bandpass", fs=frequency_hz, output="sos"),
        voltage,
    )
    slope = np.diff(filtered, prepend=filtered[0])
    integrated = uniform_filter1d(slope * slope, size=max(1, round(0.12 * frequency_hz)))
    refractory_samples = max(1, round(0.25 * frequency_hz))
    refinement_samples = max(1, round(0.10 * frequency_hz))
    chunk_samples = max(1, round(30.0 * frequency_hz))
    candidates: list[int] = []

    for start in range(0, len(integrated), chunk_samples):
        end = min(start + chunk_samples, len(integrated))
        chunk = integrated[start:end]
        if len(chunk) < refractory_samples * 2:
            continue
        background = float(np.median(chunk))
        mad = float(np.median(np.abs(chunk - background)))
        threshold = max(background + 4.0 * mad, float(np.percentile(chunk, 95)) * 0.25)
        found, _ = find_peaks(
            chunk,
            height=threshold,
            prominence=threshold * 0.5,
            distance=refractory_samples,
        )
        for offset in found:
            position = start + int(offset)
            lower = max(0, position - refinement_samples)
            upper = min(len(filtered), position + refinement_samples + 1)
            candidates.append(lower + int(np.argmax(np.abs(filtered[lower:upper]))))

    selected: list[int] = []
    for candidate in sorted(candidates):
        if selected and candidate - selected[-1] < refractory_samples:
            if integrated[candidate] > integrated[selected[-1]]:
                selected[-1] = candidate
        elif not selected or candidate > selected[-1]:
            selected.append(candidate)
    return selected


def analyze(trace: ECGTrace) -> dict:
    times = trace.time_seconds
    voltage = trace.voltage_millivolts
    result: dict = {
        "schemaVersion": 1,
        "algorithmVersion": ALGORITHM_VERSION,
        "configVersion": CONFIG_VERSION,
        "detectorIdentifier": DETECTOR_IDENTIFIER,
        "researchOnly": True,
        # The CSV is the lossless wire encoding of the same semantic signal object used on iPhone.
        "inputFormat": "watchbeat.ecg.signal.v1",
        "parameters": {
            "detectionLowCutoffHz": 5.0,
            "detectionHighCutoffHz": 25.0,
            "refractoryPeriodMilliseconds": 250.0,
            "peakRefinementRadiusMilliseconds": 100.0,
            "rrBaselineWindowBeats": BASELINE_RR_COUNT,
            "minimumRRBaselineBeatCount": MINIMUM_BASELINE_RR_COUNT,
            "prematurityThreshold": PREMATURITY_RATIO,
        },
        "status": "notAnalyzed",
        "reason": None,
        "summary": {
            "rPeakCount": 0,
            "classifiedBeatCount": 0,
            "prematureCandidateCount": 0,
        },
        "beats": [],
    }
    if len(times) != len(voltage) or len(times) < 2:
        result["reason"] = "missingOrMismatchedSamples"
        return result
    if not np.all(np.isfinite(times)) or not np.all(np.isfinite(voltage)):
        result["reason"] = "missingOrNonFiniteSamples"
        return result
    intervals = np.diff(times)
    median_interval = float(np.median(intervals))
    if median_interval <= 0 or np.any(intervals <= 0):
        result["reason"] = "invalidTimestamps"
        return result
    frequency_hz = 1.0 / median_interval
    relative_mad = float(np.median(np.abs(intervals - median_interval))) / median_interval
    if (
        frequency_hz < 60.0
        or frequency_hz > 1_000.0
        or relative_mad > 0.05
        or float(np.max(intervals)) > 1.5 * median_interval
        or times[-1] - times[0] < 8.0
    ):
        result["reason"] = "unsupportedSamplingOrDuration"
        return result

    try:
        peaks = _detect_r_peaks(voltage, frequency_hz)
    except ValueError:
        result["reason"] = "filterFailed"
        return result
    if len(peaks) < MINIMUM_BASELINE_RR_COUNT + 2:
        result["reason"] = "insufficientDetectedBeats"
        return result

    rr = np.diff(times[peaks]) * 1_000.0
    beats: list[dict] = []
    for index, sample_index in enumerate(peaks):
        previous_rr = float(rr[index - 1]) if index > 0 else None
        previous_context = [
            float(value)
            for value in rr[max(0, index - 1 - BASELINE_RR_COUNT) : max(0, index - 1)]
            if 300.0 <= value <= 2_000.0
        ]
        baseline_rr = (
            float(np.median(previous_context))
            if len(previous_context) >= MINIMUM_BASELINE_RR_COUNT
            else None
        )
        ratio = previous_rr / baseline_rr if previous_rr is not None and baseline_rr else None
        is_early = ratio is not None and 300.0 <= previous_rr < PREMATURITY_RATIO * baseline_rr
        classification = (
            "prematureUncertain"
            if is_early
            else "normal" if baseline_rr is not None else "notAnalyzed"
        )
        beats.append(
            {
                "sampleIndex": int(sample_index),
                "timeSeconds": float(times[sample_index]),
                "rrBeforeMilliseconds": previous_rr,
                "localRRMilliseconds": baseline_rr,
                "prematurityRatio": ratio,
                "classification": classification,
                "confidence": "low" if baseline_rr is not None else "notApplicable",
                "reasonCodes": (
                    ["prematureRelativeToLocalBaseline"]
                    if is_early
                    else [] if baseline_rr is not None else ["unreliableRRContext"]
                ),
            }
        )

    classified_beat_count = sum(beat["classification"] != "notAnalyzed" for beat in beats)
    if classified_beat_count == 0:
        result["reason"] = "insufficientReliableRRContext"
        return result

    result["status"] = "analyzed"
    result["reason"] = None
    result["samplingFrequencyHz"] = frequency_hz
    result["runtimeVersions"] = {"numpy": np.__version__, "scipy": scipy.__version__}
    result["beats"] = beats
    result["summary"] = {
        "rPeakCount": len(beats),
        "classifiedBeatCount": classified_beat_count,
        "prematureCandidateCount": sum(
            beat["classification"] == "prematureUncertain" for beat in beats
        ),
    }
    return result


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path, help="WatchBeat raw ECG CSV contract")
    parser.add_argument("--output", type=Path, help="optional JSON result path")
    args = parser.parse_args(argv)

    try:
        trace = read_exported_csv(args.csv_path)
        report = analyze(trace)
        if args.output is not None:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(
                json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )
    except (CSVContractError, PrototypeError, OSError) as error:
        print(f"ECG prototype error: {error}", file=sys.stderr)
        return 2

    print(
        f"{report['status']}: {report['summary']['rPeakCount']} R peaks, "
        f"{report['summary']['prematureCandidateCount']} premature candidates"
    )
    if report["reason"]:
        print(f"Reason: {report['reason']}")
    candidates = [
        beat for beat in report["beats"] if beat["classification"] == "prematureUncertain"
    ]
    for beat in candidates[:10]:
        print(f"  {beat['timeSeconds']:.3f} s  RR ratio {beat['prematurityRatio']:.3f}")
    if len(candidates) > 10:
        print(f"  ... {len(candidates) - 10} more candidates in the JSON result")
    if args.output is not None:
        print(f"Result: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
