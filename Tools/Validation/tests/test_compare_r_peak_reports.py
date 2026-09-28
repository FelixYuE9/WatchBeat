from __future__ import annotations

import copy
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "compare_r_peak_reports.py"
SPEC = importlib.util.spec_from_file_location("compare_r_peak_reports", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

EVALUATOR_PATH = Path(__file__).parents[1] / "evaluate_r_peaks.py"
EVALUATOR_SPEC = importlib.util.spec_from_file_location(
    "evaluate_r_peaks_for_comparison", EVALUATOR_PATH
)
assert EVALUATOR_SPEC is not None and EVALUATOR_SPEC.loader is not None
EVALUATOR = importlib.util.module_from_spec(EVALUATOR_SPEC)
sys.modules[EVALUATOR_SPEC.name] = EVALUATOR
EVALUATOR_SPEC.loader.exec_module(EVALUATOR)


def metrics_payload(*, detected: int, true_positive: int) -> dict:
    false_positive = detected - true_positive
    false_negative = 3 - true_positive
    denominator = 2 * true_positive + false_positive + false_negative
    return {
        "windowCount": 1,
        "referencePeakCount": 3,
        "detectedPeakCount": detected,
        "truePositiveCount": true_positive,
        "falsePositiveCount": false_positive,
        "falseNegativeCount": false_negative,
        "sensitivityRecall": true_positive / 3,
        "positivePredictivityPrecision": true_positive / detected if detected else None,
        "f1": 2 * true_positive / denominator if denominator else None,
        "falsePositivesPer30Seconds": float(false_positive),
        "falseNegativesPer30Seconds": float(false_negative),
        "absoluteTimingErrorMedianMilliseconds": 5.0 if true_positive else None,
        "absoluteTimingErrorP95Milliseconds": 8.0 if true_positive else None,
    }


def report_payload(name: str, hash_character: str, *, detected: int = 3) -> dict:
    metrics = metrics_payload(detected=detected, true_positive=3)
    return {
        "reportSchemaVersion": 1,
        "claimStatus": "research-only-unvalidated",
        "benchmarkDefinitionSHA256": "c" * 64,
        "dataset": {
            "name": "Synthetic fixture",
            "version": "1",
            "sourceURL": "https://example.invalid/dataset",
            "license": "Fixture only",
        },
        "detector": {
            "name": name,
            "version": "fixture-v1",
            "configHash": hash_character * 64,
        },
        "matching": {
            "toleranceMilliseconds": 150.0,
            "policy": "maximum-cardinality-minimum-total-error-one-to-one-v1",
            "wfdbBxbCrossCheckRequired": True,
        },
        "windowDurationSeconds": 30.0,
        "aggregate": copy.deepcopy(metrics),
        "splits": {"development": copy.deepcopy(metrics)},
        "windows": [
            {
                "id": "record-a-000000-010800",
                "split": "development",
                "metrics": copy.deepcopy(metrics),
            }
        ],
    }


class RPeakReportComparisonTests(unittest.TestCase):
    def _write_reports(self, root: Path, payloads: list[dict]) -> list[Path]:
        paths: list[Path] = []
        for index, payload in enumerate(payloads):
            path = root / f"report-{index}.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            paths.append(path)
        return paths

    def test_compares_two_compatible_reports_without_selecting_a_winner(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = self._write_reports(
                Path(directory),
                [
                    report_payload("Detector A", "a"),
                    report_payload("Detector B", "b", detected=4),
                ],
            )

            comparison = MODULE.build_comparison(paths, "development")
            markdown = MODULE.render_markdown(comparison)

        self.assertEqual(
            comparison["selectionStatus"],
            "screening-only-no-production-detector-selected",
        )
        self.assertEqual(
            [item["detector"]["name"] for item in comparison["detectors"]],
            ["Detector A", "Detector B"],
        )
        self.assertIn("Research-only, unvalidated", markdown)
        self.assertIn("Detector B", markdown)

    def test_compares_reports_created_by_the_evaluator(self) -> None:
        manifest = {
            "schemaVersion": 1,
            "windowDurationSeconds": 30.0,
            "matchingToleranceMilliseconds": 150.0,
            "dataset": report_payload("A", "a")["dataset"],
            "windows": [
                {
                    "id": "record-a-000000-010800",
                    "subjectId": "subject-a",
                    "recordId": "record-a",
                    "split": "development",
                    "channelIndex": 0,
                    "samplingFrequencyHz": 360.0,
                    "startSample": 0,
                    "endSampleExclusive": 10800,
                    "referencePeakSamples": [360, 720, 1080],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            reports = []
            for index, peaks in enumerate(([360, 720, 1080], [361, 720, 1080])):
                predictions_path = root / f"predictions-{index}.json"
                predictions_path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "detector": {
                                "name": f"Detector {index}",
                                "version": "fixture-v1",
                                "configHash": str(index) * 64,
                            },
                            "windows": [
                                {
                                    "id": "record-a-000000-010800",
                                    "detectedPeakSamples": peaks,
                                }
                            ],
                        }
                    ),
                    encoding="utf-8",
                )
                report_path = root / f"report-{index}.json"
                report_path.write_text(
                    json.dumps(
                        EVALUATOR.build_report(
                            manifest_path, predictions_path, splits=["development"]
                        )
                    ),
                    encoding="utf-8",
                )
                reports.append(report_path)

            comparison = MODULE.build_comparison(reports, "development")

        self.assertEqual(len(comparison["detectors"]), 2)
        self.assertEqual(len(comparison["benchmarkDefinitionSHA256"]), 64)

    def test_rejects_reports_with_different_windows(self) -> None:
        second = report_payload("Detector B", "b")
        second["windows"][0]["id"] = "different-window"
        with tempfile.TemporaryDirectory() as directory:
            paths = self._write_reports(
                Path(directory),
                [report_payload("Detector A", "a"), second],
            )
            with self.assertRaisesRegex(
                MODULE.ReportComparisonError,
                "same ordered windows",
            ):
                MODULE.build_comparison(paths, "development")

    def test_rejects_reports_with_different_reference_definitions(self) -> None:
        second = report_payload("Detector B", "b")
        second["benchmarkDefinitionSHA256"] = "d" * 64
        with tempfile.TemporaryDirectory() as directory:
            paths = self._write_reports(
                Path(directory),
                [report_payload("Detector A", "a"), second],
            )
            with self.assertRaisesRegex(
                MODULE.ReportComparisonError,
                "different benchmark definitions",
            ):
                MODULE.build_comparison(paths, "development")

    def test_rejects_window_metrics_that_disagree_with_aggregate(self) -> None:
        inconsistent = report_payload("Detector A", "a")
        inconsistent["windows"][0]["metrics"] = metrics_payload(
            detected=4, true_positive=3
        )
        with self.assertRaisesRegex(
            MODULE.ReportComparisonError,
            "window and aggregate detectedPeakCount differ",
        ):
            MODULE.validate_report(inconsistent, "fixture", "development")

    def test_rejects_inconsistent_counts_and_removed_safety_boundary(self) -> None:
        inconsistent = report_payload("Detector A", "a")
        inconsistent["aggregate"]["falsePositiveCount"] = 1
        with self.assertRaisesRegex(
            MODULE.ReportComparisonError,
            "falsePositiveCount is inconsistent",
        ):
            MODULE.validate_report(inconsistent, "fixture", "development")

        unsafe = report_payload("Detector A", "a")
        unsafe["matching"]["wfdbBxbCrossCheckRequired"] = False
        with self.assertRaisesRegex(
            MODULE.ReportComparisonError,
            "required WFDB bxb cross-check",
        ):
            MODULE.validate_report(unsafe, "fixture", "development")


if __name__ == "__main__":
    unittest.main()
