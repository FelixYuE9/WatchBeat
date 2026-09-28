#!/usr/bin/env python3
"""Compare already-evaluated R-peak reports without selecting a production detector.

The comparison is deliberately split-specific and accepts only evaluator reports that describe the
same dataset, windows and matching policy. It prints a compact development-screening table while
preserving the research-only boundary and the outstanding WFDB ``bxb`` cross-check requirement.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


COMPARISON_SCHEMA_VERSION = 1
REPORT_SCHEMA_VERSION = 1
VALID_SPLITS = ("development", "validation", "held-out-test")
CLAIM_STATUS = "research-only-unvalidated"
SELECTION_STATUS = "screening-only-no-production-detector-selected"


class ReportComparisonError(ValueError):
    """Raised when reports cannot be compared under the frozen contract."""


@dataclass(frozen=True)
class ReportSummary:
    source_name: str
    detector: Mapping[str, str]
    metrics: Mapping[str, int | float | None]
    benchmark_definition_sha256: str
    dataset: Mapping[str, str]
    matching: Mapping[str, Any]
    window_duration_seconds: float
    window_ids: tuple[str, ...]


def _require_mapping(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ReportComparisonError(f"{path} must be an object")
    return value


def _require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise ReportComparisonError(f"{path} must be an array")
    return value


def _require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReportComparisonError(f"{path} must be a non-empty string")
    return value


def _require_nonnegative_int(value: Any, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ReportComparisonError(f"{path} must be a non-negative integer")
    return value


def _require_optional_finite_number(value: Any, path: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ReportComparisonError(f"{path} must be a finite number or null")
    number = float(value)
    if not math.isfinite(number):
        raise ReportComparisonError(f"{path} must be finite")
    return number


def _require_sha256(value: Any, path: str) -> str:
    text = _require_string(value, path)
    if len(text) != 64 or any(character not in "0123456789abcdef" for character in text):
        raise ReportComparisonError(f"{path} must be a lowercase SHA-256 value")
    return text


def _validate_metrics(value: Any, path: str) -> dict[str, int | float | None]:
    raw = _require_mapping(value, path)
    integer_keys = (
        "windowCount",
        "referencePeakCount",
        "detectedPeakCount",
        "truePositiveCount",
        "falsePositiveCount",
        "falseNegativeCount",
    )
    optional_number_keys = (
        "sensitivityRecall",
        "positivePredictivityPrecision",
        "f1",
        "falsePositivesPer30Seconds",
        "falseNegativesPer30Seconds",
        "absoluteTimingErrorMedianMilliseconds",
        "absoluteTimingErrorP95Milliseconds",
    )
    metrics: dict[str, int | float | None] = {
        key: _require_nonnegative_int(raw.get(key), f"{path}.{key}")
        for key in integer_keys
    }
    metrics.update(
        {
            key: _require_optional_finite_number(raw.get(key), f"{path}.{key}")
            for key in optional_number_keys
        }
    )

    reference_count = int(metrics["referencePeakCount"])
    detection_count = int(metrics["detectedPeakCount"])
    true_positive_count = int(metrics["truePositiveCount"])
    if true_positive_count > min(reference_count, detection_count):
        raise ReportComparisonError(f"{path}.truePositiveCount is impossible")
    if metrics["falsePositiveCount"] != detection_count - true_positive_count:
        raise ReportComparisonError(f"{path}.falsePositiveCount is inconsistent")
    if metrics["falseNegativeCount"] != reference_count - true_positive_count:
        raise ReportComparisonError(f"{path}.falseNegativeCount is inconsistent")
    for key in ("sensitivityRecall", "positivePredictivityPrecision", "f1"):
        rate = metrics[key]
        if rate is not None and not 0.0 <= float(rate) <= 1.0:
            raise ReportComparisonError(f"{path}.{key} must be between zero and one")
    for key in optional_number_keys:
        value = metrics[key]
        if value is not None and value < 0:
            raise ReportComparisonError(f"{path}.{key} must be non-negative")
    return metrics


def validate_report(payload: Any, source_name: str, split: str) -> ReportSummary:
    root = _require_mapping(payload, source_name)
    if root.get("reportSchemaVersion") != REPORT_SCHEMA_VERSION:
        raise ReportComparisonError(
            f"{source_name}.reportSchemaVersion must equal {REPORT_SCHEMA_VERSION}"
        )
    if root.get("claimStatus") != CLAIM_STATUS:
        raise ReportComparisonError(f"{source_name}.claimStatus must remain {CLAIM_STATUS}")

    raw_detector = _require_mapping(root.get("detector"), f"{source_name}.detector")
    detector = {
        "name": _require_string(raw_detector.get("name"), f"{source_name}.detector.name"),
        "version": _require_string(
            raw_detector.get("version"), f"{source_name}.detector.version"
        ),
        "configHash": _require_sha256(
            raw_detector.get("configHash"), f"{source_name}.detector.configHash"
        ),
    }
    raw_dataset = _require_mapping(root.get("dataset"), f"{source_name}.dataset")
    dataset = {
        key: _require_string(raw_dataset.get(key), f"{source_name}.dataset.{key}")
        for key in ("name", "version", "sourceURL", "license")
    }
    benchmark_definition_sha256 = _require_sha256(
        root.get("benchmarkDefinitionSHA256"),
        f"{source_name}.benchmarkDefinitionSHA256",
    )
    matching = dict(_require_mapping(root.get("matching"), f"{source_name}.matching"))
    tolerance = _require_optional_finite_number(
        matching.get("toleranceMilliseconds"),
        f"{source_name}.matching.toleranceMilliseconds",
    )
    if tolerance is None or tolerance <= 0:
        raise ReportComparisonError(f"{source_name} has an invalid matching tolerance")
    if matching.get("wfdbBxbCrossCheckRequired") is not True:
        raise ReportComparisonError(f"{source_name} removed the required WFDB bxb cross-check")

    duration = _require_optional_finite_number(
        root.get("windowDurationSeconds"), f"{source_name}.windowDurationSeconds"
    )
    if duration is None or duration <= 0:
        raise ReportComparisonError(f"{source_name} has an invalid window duration")

    raw_splits = _require_mapping(root.get("splits"), f"{source_name}.splits")
    if set(raw_splits) != {split}:
        raise ReportComparisonError(
            f"{source_name} must contain exactly the requested {split!r} split"
        )
    metrics = _validate_metrics(root.get("aggregate"), f"{source_name}.aggregate")
    split_metrics = _validate_metrics(raw_splits[split], f"{source_name}.splits.{split}")
    if metrics != split_metrics:
        raise ReportComparisonError(f"{source_name} aggregate and split metrics differ")

    window_ids: list[str] = []
    count_keys = (
        "referencePeakCount",
        "detectedPeakCount",
        "truePositiveCount",
        "falsePositiveCount",
        "falseNegativeCount",
    )
    window_totals = {key: 0 for key in count_keys}
    for index, raw_window in enumerate(
        _require_list(root.get("windows"), f"{source_name}.windows")
    ):
        path = f"{source_name}.windows[{index}]"
        window = _require_mapping(raw_window, path)
        if window.get("split") != split:
            raise ReportComparisonError(f"{path}.split does not equal {split!r}")
        window_ids.append(_require_string(window.get("id"), f"{path}.id"))
        window_metrics = _validate_metrics(window.get("metrics"), f"{path}.metrics")
        if window_metrics["windowCount"] != 1:
            raise ReportComparisonError(f"{path}.metrics.windowCount must equal one")
        for key in count_keys:
            window_totals[key] += int(window_metrics[key])
    if not window_ids or len(set(window_ids)) != len(window_ids):
        raise ReportComparisonError(f"{source_name} must contain unique comparison windows")
    if metrics["windowCount"] != len(window_ids):
        raise ReportComparisonError(f"{source_name} window count is inconsistent")
    for key in count_keys:
        if window_totals[key] != metrics[key]:
            raise ReportComparisonError(f"{source_name} window and aggregate {key} differ")

    return ReportSummary(
        source_name=source_name,
        detector=detector,
        metrics=metrics,
        benchmark_definition_sha256=benchmark_definition_sha256,
        dataset=dataset,
        matching=matching,
        window_duration_seconds=duration,
        window_ids=tuple(window_ids),
    )


def build_comparison(report_paths: Sequence[Path], split: str) -> dict[str, Any]:
    if split not in VALID_SPLITS:
        raise ReportComparisonError(f"unsupported comparison split: {split}")
    if len(report_paths) < 2:
        raise ReportComparisonError("at least two detector reports are required")

    summaries: list[ReportSummary] = []
    for path in report_paths:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ReportComparisonError(f"cannot read {path}: {error}") from error
        summaries.append(validate_report(payload, path.name, split))

    baseline = summaries[0]
    seen_detectors: set[tuple[str, str]] = set()
    for summary in summaries:
        if summary.dataset != baseline.dataset:
            raise ReportComparisonError("reports describe different datasets")
        if summary.matching != baseline.matching:
            raise ReportComparisonError("reports use different matching policies")
        if summary.window_duration_seconds != baseline.window_duration_seconds:
            raise ReportComparisonError("reports use different window durations")
        if summary.window_ids != baseline.window_ids:
            raise ReportComparisonError("reports do not contain the same ordered windows")
        if summary.benchmark_definition_sha256 != baseline.benchmark_definition_sha256:
            raise ReportComparisonError("reports use different benchmark definitions")
        if summary.metrics["referencePeakCount"] != baseline.metrics["referencePeakCount"]:
            raise ReportComparisonError("reports contain different reference peak populations")
        identity = (summary.detector["name"], summary.detector["configHash"])
        if identity in seen_detectors:
            raise ReportComparisonError("duplicate detector/configuration report")
        seen_detectors.add(identity)

    return {
        "comparisonSchemaVersion": COMPARISON_SCHEMA_VERSION,
        "claimStatus": CLAIM_STATUS,
        "selectionStatus": SELECTION_STATUS,
        "split": split,
        "benchmarkDefinitionSHA256": baseline.benchmark_definition_sha256,
        "dataset": dict(baseline.dataset),
        "matching": dict(baseline.matching),
        "windowDurationSeconds": baseline.window_duration_seconds,
        "detectors": [
            {
                "sourceReport": summary.source_name,
                "detector": dict(summary.detector),
                "metrics": dict(summary.metrics),
            }
            for summary in summaries
        ],
        "limitations": [
            "No production detector is selected by this development-screening comparison.",
            "The evaluator still requires an official PhysioNet WFDB bxb cross-check.",
            "MIT-BIH performance does not establish Apple Watch ECG performance.",
            "R-peak timing does not evaluate PAC/PVC classification.",
        ],
    }


def _format_metric(value: int | float | None, digits: int = 6) -> str:
    if value is None:
        return "—"
    if isinstance(value, int):
        return str(value)
    return f"{value:.{digits}f}"


def render_markdown(comparison: Mapping[str, Any]) -> str:
    rows = [
        "# R-peak development screening",
        "",
        "> Research-only, unvalidated results. This table does not select a production detector.",
        "",
        "| Detector | F1 | Sensitivity | PPV | FP / 30 s | FN / 30 s | Median error (ms) | P95 error (ms) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for item in comparison["detectors"]:
        detector = item["detector"]
        metrics = item["metrics"]
        name = str(detector["name"]).replace("|", "\\|")
        rows.append(
            "| "
            + " | ".join(
                [
                    name,
                    _format_metric(metrics["f1"]),
                    _format_metric(metrics["sensitivityRecall"]),
                    _format_metric(metrics["positivePredictivityPrecision"]),
                    _format_metric(metrics["falsePositivesPer30Seconds"], 4),
                    _format_metric(metrics["falseNegativesPer30Seconds"], 4),
                    _format_metric(metrics["absoluteTimingErrorMedianMilliseconds"], 3),
                    _format_metric(metrics["absoluteTimingErrorP95Milliseconds"], 3),
                ]
            )
            + " |"
        )
    rows.extend(
        [
            "",
            f"Split: `{comparison['split']}`. Matching: "
            f"±{comparison['matching']['toleranceMilliseconds']} ms, one-to-one.",
            "",
            "Required next gates: official WFDB `bxb` cross-check, frozen validation finalists, "
            "and independent Apple Watch-domain validation.",
            "",
        ]
    )
    return "\n".join(rows)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare compatible research-only R-peak evaluator reports."
    )
    parser.add_argument("reports", type=Path, nargs="+")
    parser.add_argument("--split", choices=VALID_SPLITS, required=True)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-markdown", type=Path)
    args = parser.parse_args(argv)

    try:
        comparison = build_comparison(args.reports, args.split)
        markdown = render_markdown(comparison)
        if args.output_json is not None:
            args.output_json.parent.mkdir(parents=True, exist_ok=True)
            args.output_json.write_text(
                json.dumps(comparison, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                encoding="utf-8",
            )
        if args.output_markdown is not None:
            args.output_markdown.parent.mkdir(parents=True, exist_ok=True)
            args.output_markdown.write_text(markdown, encoding="utf-8")
    except (ReportComparisonError, OSError, ValueError) as error:
        print(f"R-peak report comparison error: {error}", file=sys.stderr)
        return 2

    print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
