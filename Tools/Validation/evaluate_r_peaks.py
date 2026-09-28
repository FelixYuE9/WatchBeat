#!/usr/bin/env python3
"""Evaluate R-peak predictions without loading or modifying ECG waveforms.

The version-1 contract intentionally uses only the Python standard library. It validates fixed
30-second windows, rejects subject/record leakage across splits, and performs deterministic
one-to-one peak matching. The 150 ms tolerance mirrors the default PhysioNet WFDB ``bxb`` match
window, but this implementation must still be cross-checked against ``bxb`` before benchmark
results are used to select a production detector.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


SCHEMA_VERSION = 1
REPORT_SCHEMA_VERSION = 1
WINDOW_DURATION_SECONDS = 30.0
MATCHING_TOLERANCE_MILLISECONDS = 150.0
VALID_SPLITS = frozenset({"development", "validation", "held-out-test"})


class BenchmarkValidationError(ValueError):
    """Raised when a benchmark manifest or detector prediction violates the frozen contract."""


@dataclass(frozen=True)
class WindowSpec:
    window_id: str
    subject_id: str
    record_id: str
    split: str
    channel_index: int
    sampling_frequency_hz: float
    start_sample: int
    end_sample_exclusive: int
    reference_peak_samples: tuple[int, ...]


@dataclass(frozen=True)
class BenchmarkManifest:
    dataset: Mapping[str, str]
    windows: tuple[WindowSpec, ...]
    matching_tolerance_milliseconds: float = MATCHING_TOLERANCE_MILLISECONDS
    window_duration_seconds: float = WINDOW_DURATION_SECONDS


@dataclass(frozen=True)
class DetectorPredictions:
    detector: Mapping[str, str]
    peaks_by_window_id: Mapping[str, tuple[int, ...]]


@dataclass(frozen=True)
class PeakMatch:
    reference_sample: int
    detected_sample: int
    absolute_error_milliseconds: float


def _require_mapping(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise BenchmarkValidationError(f"{path} must be an object")
    return value


def _require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise BenchmarkValidationError(f"{path} must be an array")
    return value


def _require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise BenchmarkValidationError(f"{path} must be a non-empty string")
    return value


def _require_int(value: Any, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise BenchmarkValidationError(f"{path} must be an integer")
    return value


def _require_positive_float(value: Any, path: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BenchmarkValidationError(f"{path} must be a number")
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise BenchmarkValidationError(f"{path} must be finite and greater than zero")
    return result


def _require_sha256(value: Any, path: str) -> str:
    digest = _require_string(value, path)
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise BenchmarkValidationError(f"{path} must be a lowercase SHA-256 digest")
    return digest


def _require_peak_samples(
    value: Any,
    path: str,
    start_sample: int,
    end_sample_exclusive: int,
    *,
    allow_empty: bool,
) -> tuple[int, ...]:
    raw_samples = _require_list(value, path)
    if not raw_samples and not allow_empty:
        raise BenchmarkValidationError(f"{path} must contain at least one peak")

    samples: list[int] = []
    previous: int | None = None
    for index, raw_sample in enumerate(raw_samples):
        sample = _require_int(raw_sample, f"{path}[{index}]")
        if sample < start_sample or sample >= end_sample_exclusive:
            raise BenchmarkValidationError(
                f"{path}[{index}]={sample} is outside "
                f"[{start_sample}, {end_sample_exclusive})"
            )
        if previous is not None and sample <= previous:
            raise BenchmarkValidationError(f"{path} must be strictly increasing")
        samples.append(sample)
        previous = sample
    return tuple(samples)


def validate_manifest(payload: Any) -> BenchmarkManifest:
    root = _require_mapping(payload, "manifest")
    if root.get("schemaVersion") != SCHEMA_VERSION:
        raise BenchmarkValidationError(
            f"manifest.schemaVersion must equal {SCHEMA_VERSION}"
        )

    duration = _require_positive_float(
        root.get("windowDurationSeconds"),
        "manifest.windowDurationSeconds",
    )
    if not math.isclose(duration, WINDOW_DURATION_SECONDS, abs_tol=1e-9):
        raise BenchmarkValidationError(
            f"manifest.windowDurationSeconds must equal {WINDOW_DURATION_SECONDS}"
        )

    tolerance = _require_positive_float(
        root.get("matchingToleranceMilliseconds"),
        "manifest.matchingToleranceMilliseconds",
    )
    if not math.isclose(
        tolerance,
        MATCHING_TOLERANCE_MILLISECONDS,
        abs_tol=1e-9,
    ):
        raise BenchmarkValidationError(
            "manifest.matchingToleranceMilliseconds must equal "
            f"{MATCHING_TOLERANCE_MILLISECONDS} for schema version 1"
        )

    raw_dataset = _require_mapping(root.get("dataset"), "manifest.dataset")
    dataset = {
        key: _require_string(raw_dataset.get(key), f"manifest.dataset.{key}")
        for key in ("name", "version", "sourceURL", "license")
    }

    raw_windows = _require_list(root.get("windows"), "manifest.windows")
    if not raw_windows:
        raise BenchmarkValidationError("manifest.windows must not be empty")

    windows: list[WindowSpec] = []
    seen_window_ids: set[str] = set()
    subject_splits: dict[str, set[str]] = defaultdict(set)
    record_splits: dict[str, set[str]] = defaultdict(set)

    for index, raw_window_value in enumerate(raw_windows):
        path = f"manifest.windows[{index}]"
        raw_window = _require_mapping(raw_window_value, path)
        window_id = _require_string(raw_window.get("id"), f"{path}.id")
        if window_id in seen_window_ids:
            raise BenchmarkValidationError(f"duplicate window id: {window_id}")
        seen_window_ids.add(window_id)

        subject_id = _require_string(raw_window.get("subjectId"), f"{path}.subjectId")
        record_id = _require_string(raw_window.get("recordId"), f"{path}.recordId")
        split = _require_string(raw_window.get("split"), f"{path}.split")
        if split not in VALID_SPLITS:
            raise BenchmarkValidationError(
                f"{path}.split must be one of {sorted(VALID_SPLITS)}"
            )

        channel_index = _require_int(
            raw_window.get("channelIndex"),
            f"{path}.channelIndex",
        )
        if channel_index < 0:
            raise BenchmarkValidationError(f"{path}.channelIndex must be non-negative")

        sampling_frequency_hz = _require_positive_float(
            raw_window.get("samplingFrequencyHz"),
            f"{path}.samplingFrequencyHz",
        )
        start_sample = _require_int(raw_window.get("startSample"), f"{path}.startSample")
        end_sample_exclusive = _require_int(
            raw_window.get("endSampleExclusive"),
            f"{path}.endSampleExclusive",
        )
        if start_sample < 0 or end_sample_exclusive <= start_sample:
            raise BenchmarkValidationError(
                f"{path} must have 0 <= startSample < endSampleExclusive"
            )

        expected_sample_count = duration * sampling_frequency_hz
        actual_sample_count = end_sample_exclusive - start_sample
        if not math.isclose(actual_sample_count, expected_sample_count, abs_tol=0.5):
            raise BenchmarkValidationError(
                f"{path} is not a {duration:.1f}-second window at "
                f"{sampling_frequency_hz:g} Hz"
            )

        reference_peak_samples = _require_peak_samples(
            raw_window.get("referencePeakSamples"),
            f"{path}.referencePeakSamples",
            start_sample,
            end_sample_exclusive,
            allow_empty=True,
        )

        windows.append(
            WindowSpec(
                window_id=window_id,
                subject_id=subject_id,
                record_id=record_id,
                split=split,
                channel_index=channel_index,
                sampling_frequency_hz=sampling_frequency_hz,
                start_sample=start_sample,
                end_sample_exclusive=end_sample_exclusive,
                reference_peak_samples=reference_peak_samples,
            )
        )
        subject_splits[subject_id].add(split)
        record_splits[record_id].add(split)

    leaked_subjects = sorted(
        subject_id for subject_id, splits in subject_splits.items() if len(splits) > 1
    )
    leaked_records = sorted(
        record_id for record_id, splits in record_splits.items() if len(splits) > 1
    )
    if leaked_subjects:
        raise BenchmarkValidationError(
            "subjects appear in more than one split: " + ", ".join(leaked_subjects)
        )
    if leaked_records:
        raise BenchmarkValidationError(
            "records appear in more than one split: " + ", ".join(leaked_records)
        )

    return BenchmarkManifest(
        dataset=dataset,
        windows=tuple(windows),
        matching_tolerance_milliseconds=tolerance,
        window_duration_seconds=duration,
    )


def validate_predictions(payload: Any, manifest: BenchmarkManifest) -> DetectorPredictions:
    root = _require_mapping(payload, "predictions")
    if root.get("schemaVersion") != SCHEMA_VERSION:
        raise BenchmarkValidationError(
            f"predictions.schemaVersion must equal {SCHEMA_VERSION}"
        )

    raw_detector = _require_mapping(root.get("detector"), "predictions.detector")
    detector = {
        "name": _require_string(raw_detector.get("name"), "predictions.detector.name"),
        "version": _require_string(
            raw_detector.get("version"),
            "predictions.detector.version",
        ),
        "configHash": _require_sha256(
            raw_detector.get("configHash"),
            "predictions.detector.configHash",
        ),
    }

    manifest_windows = {window.window_id: window for window in manifest.windows}
    raw_windows = _require_list(root.get("windows"), "predictions.windows")
    peaks_by_window_id: dict[str, tuple[int, ...]] = {}

    for index, raw_window_value in enumerate(raw_windows):
        path = f"predictions.windows[{index}]"
        raw_window = _require_mapping(raw_window_value, path)
        window_id = _require_string(raw_window.get("id"), f"{path}.id")
        if window_id in peaks_by_window_id:
            raise BenchmarkValidationError(f"duplicate prediction window id: {window_id}")
        if window_id not in manifest_windows:
            raise BenchmarkValidationError(f"unknown prediction window id: {window_id}")
        spec = manifest_windows[window_id]
        peaks_by_window_id[window_id] = _require_peak_samples(
            raw_window.get("detectedPeakSamples"),
            f"{path}.detectedPeakSamples",
            spec.start_sample,
            spec.end_sample_exclusive,
            allow_empty=True,
        )

    missing = sorted(set(manifest_windows) - set(peaks_by_window_id))
    if missing:
        raise BenchmarkValidationError(
            "predictions are missing windows: " + ", ".join(missing)
        )

    return DetectorPredictions(
        detector=detector,
        peaks_by_window_id=peaks_by_window_id,
    )


def select_manifest_splits(
    manifest: BenchmarkManifest,
    splits: Sequence[str],
) -> BenchmarkManifest:
    """Project a frozen manifest to explicitly requested benchmark stages.

    Detector development must not silently include held-out-test windows. The CLI therefore
    requires at least one ``--split`` and validates predictions against only that projection.
    """

    requested = tuple(dict.fromkeys(splits))
    if not requested:
        raise BenchmarkValidationError("at least one benchmark split must be selected")
    invalid = sorted(set(requested) - VALID_SPLITS)
    if invalid:
        raise BenchmarkValidationError(
            "unknown benchmark splits: " + ", ".join(invalid)
        )
    windows = tuple(window for window in manifest.windows if window.split in requested)
    if not windows:
        raise BenchmarkValidationError(
            "selected benchmark splits contain no manifest windows"
        )
    return BenchmarkManifest(
        dataset=manifest.dataset,
        windows=windows,
        matching_tolerance_milliseconds=manifest.matching_tolerance_milliseconds,
        window_duration_seconds=manifest.window_duration_seconds,
    )


def match_peaks(
    reference_samples: Sequence[int],
    detected_samples: Sequence[int],
    sampling_frequency_hz: float,
    tolerance_milliseconds: float = MATCHING_TOLERANCE_MILLISECONDS,
) -> list[PeakMatch]:
    """Return a maximum-cardinality, minimum-total-error, order-preserving match."""

    sampling_frequency_hz = _require_positive_float(
        sampling_frequency_hz,
        "sampling_frequency_hz",
    )
    tolerance_milliseconds = _require_positive_float(
        tolerance_milliseconds,
        "tolerance_milliseconds",
    )
    references = tuple(reference_samples)
    detections = tuple(detected_samples)
    if any(
        isinstance(value, bool) or not isinstance(value, int)
        for value in references + detections
    ):
        raise BenchmarkValidationError("peak samples must be integers")
    if any(current <= previous for previous, current in zip(references, references[1:])):
        raise BenchmarkValidationError("reference samples must be strictly increasing")
    if any(current <= previous for previous, current in zip(detections, detections[1:])):
        raise BenchmarkValidationError("detected samples must be strictly increasing")

    reference_count = len(references)
    detection_count = len(detections)
    tolerance_samples = tolerance_milliseconds * sampling_frequency_hz / 1_000.0

    # Each cell stores (matched count, total absolute sample error). A lexicographic choice first
    # maximizes the number of matched beats, then minimizes timing error.
    scores: list[list[tuple[int, float]]] = [
        [(0, 0.0) for _ in range(detection_count + 1)]
        for _ in range(reference_count + 1)
    ]
    actions: list[list[str]] = [
        ["done" for _ in range(detection_count + 1)]
        for _ in range(reference_count + 1)
    ]

    for reference_index in range(reference_count):
        actions[reference_index][detection_count] = "skip-reference"
    for detection_index in range(detection_count):
        actions[reference_count][detection_index] = "skip-detection"

    for reference_index in range(reference_count - 1, -1, -1):
        for detection_index in range(detection_count - 1, -1, -1):
            reference_sample = references[reference_index]
            detected_sample = detections[detection_index]

            skip_reference = scores[reference_index + 1][detection_index]
            skip_detection = scores[reference_index][detection_index + 1]
            candidates: list[tuple[int, float, int, str]] = []

            # Tie priorities only make otherwise identical plans deterministic. Skipping the earlier
            # current event is preferred when neither possible plan changes cardinality or error.
            if detected_sample < reference_sample:
                skip_detection_priority, skip_reference_priority = 2, 1
            else:
                skip_detection_priority, skip_reference_priority = 1, 2
            candidates.append(
                (*skip_reference, skip_reference_priority, "skip-reference")
            )
            candidates.append(
                (*skip_detection, skip_detection_priority, "skip-detection")
            )

            absolute_error_samples = abs(reference_sample - detected_sample)
            if absolute_error_samples <= tolerance_samples:
                next_matches, next_error = scores[reference_index + 1][detection_index + 1]
                candidates.append(
                    (
                        next_matches + 1,
                        next_error + absolute_error_samples,
                        3,
                        "match",
                    )
                )

            best = max(candidates, key=lambda candidate: (candidate[0], -candidate[1], candidate[2]))
            scores[reference_index][detection_index] = (best[0], best[1])
            actions[reference_index][detection_index] = best[3]

    matches: list[PeakMatch] = []
    reference_index = 0
    detection_index = 0
    while reference_index < reference_count and detection_index < detection_count:
        action = actions[reference_index][detection_index]
        if action == "match":
            reference_sample = references[reference_index]
            detected_sample = detections[detection_index]
            matches.append(
                PeakMatch(
                    reference_sample=reference_sample,
                    detected_sample=detected_sample,
                    absolute_error_milliseconds=(
                        abs(reference_sample - detected_sample)
                        * 1_000.0
                        / sampling_frequency_hz
                    ),
                )
            )
            reference_index += 1
            detection_index += 1
        elif action == "skip-reference":
            reference_index += 1
        elif action == "skip-detection":
            detection_index += 1
        else:  # pragma: no cover - defensive guard for corrupted internal state
            raise RuntimeError(f"unexpected matching action: {action}")
    return matches


def _nearest_rank_percentile(values: Sequence[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def _metrics(
    reference_count: int,
    detection_count: int,
    true_positive_count: int,
    timing_errors_milliseconds: Sequence[float],
    window_count: int,
) -> dict[str, int | float | None]:
    false_negative_count = reference_count - true_positive_count
    false_positive_count = detection_count - true_positive_count
    sensitivity = (
        true_positive_count / reference_count if reference_count > 0 else None
    )
    positive_predictivity = (
        true_positive_count / detection_count if detection_count > 0 else None
    )
    f1_denominator = 2 * true_positive_count + false_positive_count + false_negative_count
    f1 = 2 * true_positive_count / f1_denominator if f1_denominator > 0 else None

    return {
        "windowCount": window_count,
        "referencePeakCount": reference_count,
        "detectedPeakCount": detection_count,
        "truePositiveCount": true_positive_count,
        "falsePositiveCount": false_positive_count,
        "falseNegativeCount": false_negative_count,
        "sensitivityRecall": sensitivity,
        "positivePredictivityPrecision": positive_predictivity,
        "f1": f1,
        "falsePositivesPer30Seconds": (
            false_positive_count / window_count if window_count > 0 else None
        ),
        "falseNegativesPer30Seconds": (
            false_negative_count / window_count if window_count > 0 else None
        ),
        "absoluteTimingErrorMedianMilliseconds": (
            statistics.median(timing_errors_milliseconds)
            if timing_errors_milliseconds
            else None
        ),
        "absoluteTimingErrorP95Milliseconds": _nearest_rank_percentile(
            timing_errors_milliseconds,
            0.95,
        ),
    }


def evaluate(
    manifest: BenchmarkManifest,
    predictions: DetectorPredictions,
) -> dict[str, Any]:
    benchmark_definition = json.dumps(
        asdict(manifest),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    benchmark_definition_sha256 = hashlib.sha256(benchmark_definition).hexdigest()
    window_reports: list[dict[str, Any]] = []
    grouped_counts: dict[str, list[tuple[int, int, int, list[float]]]] = defaultdict(list)

    for window in manifest.windows:
        detected_samples = predictions.peaks_by_window_id[window.window_id]
        matches = match_peaks(
            window.reference_peak_samples,
            detected_samples,
            window.sampling_frequency_hz,
            manifest.matching_tolerance_milliseconds,
        )
        timing_errors = [match.absolute_error_milliseconds for match in matches]
        counts = (
            len(window.reference_peak_samples),
            len(detected_samples),
            len(matches),
            timing_errors,
        )
        grouped_counts[window.split].append(counts)
        window_reports.append(
            {
                "id": window.window_id,
                "subjectId": window.subject_id,
                "recordId": window.record_id,
                "split": window.split,
                "channelIndex": window.channel_index,
                "startSample": window.start_sample,
                "endSampleExclusive": window.end_sample_exclusive,
                "metrics": _metrics(*counts, window_count=1),
            }
        )

    def aggregate(items: Sequence[tuple[int, int, int, list[float]]]) -> dict[str, Any]:
        reference_count = sum(item[0] for item in items)
        detection_count = sum(item[1] for item in items)
        true_positive_count = sum(item[2] for item in items)
        timing_errors = [error for item in items for error in item[3]]
        return _metrics(
            reference_count,
            detection_count,
            true_positive_count,
            timing_errors,
            window_count=len(items),
        )

    all_counts = [item for items in grouped_counts.values() for item in items]
    return {
        "reportSchemaVersion": REPORT_SCHEMA_VERSION,
        "claimStatus": "research-only-unvalidated",
        "benchmarkDefinitionSHA256": benchmark_definition_sha256,
        "dataset": dict(manifest.dataset),
        "detector": dict(predictions.detector),
        "matching": {
            "toleranceMilliseconds": manifest.matching_tolerance_milliseconds,
            "policy": "maximum-cardinality-minimum-total-error-one-to-one-v1",
            "wfdbBxbCrossCheckRequired": True,
        },
        "windowDurationSeconds": manifest.window_duration_seconds,
        "aggregate": aggregate(all_counts),
        "splits": {
            split: aggregate(items) for split, items in sorted(grouped_counts.items())
        },
        "windows": window_reports,
        "limitations": [
            "This report evaluates R-peak timing only; it does not evaluate PAC/PVC classification.",
            "Public-dataset performance does not establish Apple Watch ECG performance.",
            "Cross-check this evaluator against PhysioNet WFDB bxb before detector selection.",
        ],
    }


def load_json_document(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def build_report(
    manifest_path: Path,
    predictions_path: Path,
    splits: Sequence[str] | None = None,
) -> dict[str, Any]:
    manifest = validate_manifest(load_json_document(manifest_path))
    if splits is not None:
        manifest = select_manifest_splits(manifest, splits)
    predictions = validate_predictions(
        load_json_document(predictions_path),
        manifest,
    )
    return evaluate(manifest, predictions)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate timestamp-only R-peak predictions on frozen 30-second windows."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument("predictions", type=Path)
    parser.add_argument(
        "--split",
        action="append",
        choices=sorted(VALID_SPLITS),
        required=True,
        help="benchmark stage to evaluate; repeat only for an intentional combined report",
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    try:
        report = build_report(args.manifest, args.predictions, splits=args.split)
        serialized = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized, encoding="utf-8")
        else:
            sys.stdout.write(serialized)
    except (BenchmarkValidationError, OSError, json.JSONDecodeError) as error:
        print(f"R-peak benchmark error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
