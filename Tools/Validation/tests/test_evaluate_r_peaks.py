from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "evaluate_r_peaks.py"
SPEC = importlib.util.spec_from_file_location("evaluate_r_peaks", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def manifest_payload() -> dict:
    return {
        "schemaVersion": 1,
        "windowDurationSeconds": 30.0,
        "matchingToleranceMilliseconds": 150.0,
        "dataset": {
            "name": "Synthetic unit-test fixture",
            "version": "1",
            "sourceURL": "https://example.invalid/not-a-dataset",
            "license": "Test fixture only",
        },
        "windows": [
            {
                "id": "record-a-000000-010800",
                "subjectId": "subject-a",
                "recordId": "record-a",
                "split": "development",
                "channelIndex": 0,
                "samplingFrequencyHz": 360.0,
                "startSample": 0,
                "endSampleExclusive": 10_800,
                "referencePeakSamples": [360, 720, 1_080],
            }
        ],
    }


def predictions_payload(peaks: list[int] | None = None) -> dict:
    return {
        "schemaVersion": 1,
        "detector": {
            "name": "Fixture detector",
            "version": "0",
            "configHash": "0" * 64,
        },
        "windows": [
            {
                "id": "record-a-000000-010800",
                "detectedPeakSamples": [358, 723, 1_080] if peaks is None else peaks,
            }
        ],
    }


class RPeakBenchmarkTests(unittest.TestCase):
    def test_matching_is_one_to_one_and_respects_tolerance(self) -> None:
        matches = MODULE.match_peaks(
            [1_000, 2_000, 3_000],
            [990, 2_050, 2_500, 3_200],
            sampling_frequency_hz=1_000,
            tolerance_milliseconds=150,
        )

        self.assertEqual(
            [(match.reference_sample, match.detected_sample) for match in matches],
            [(1_000, 990), (2_000, 2_050)],
        )

    def test_matching_chooses_lower_error_when_cardinality_is_equal(self) -> None:
        matches = MODULE.match_peaks(
            [100, 200],
            [160],
            sampling_frequency_hz=1_000,
            tolerance_milliseconds=100,
        )

        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].reference_sample, 200)
        self.assertEqual(matches[0].detected_sample, 160)
        self.assertEqual(matches[0].absolute_error_milliseconds, 40)

    def test_report_contains_counts_timing_and_split_aggregates(self) -> None:
        manifest = MODULE.validate_manifest(manifest_payload())
        predictions = MODULE.validate_predictions(predictions_payload(), manifest)

        report = MODULE.evaluate(manifest, predictions)

        self.assertEqual(report["claimStatus"], "research-only-unvalidated")
        self.assertTrue(report["matching"]["wfdbBxbCrossCheckRequired"])
        self.assertEqual(report["aggregate"]["truePositiveCount"], 3)
        self.assertEqual(report["aggregate"]["falsePositiveCount"], 0)
        self.assertEqual(report["aggregate"]["falseNegativeCount"], 0)
        self.assertEqual(report["aggregate"]["sensitivityRecall"], 1.0)
        self.assertIn("development", report["splits"])
        self.assertAlmostEqual(
            report["aggregate"]["absoluteTimingErrorP95Milliseconds"],
            1_000 * 3 / 360,
        )

    def test_empty_predictions_are_valid_and_count_as_missed_peaks(self) -> None:
        manifest = MODULE.validate_manifest(manifest_payload())
        predictions = MODULE.validate_predictions(predictions_payload([]), manifest)

        metrics = MODULE.evaluate(manifest, predictions)["aggregate"]

        self.assertEqual(metrics["truePositiveCount"], 0)
        self.assertEqual(metrics["falseNegativeCount"], 3)
        self.assertEqual(metrics["sensitivityRecall"], 0.0)
        self.assertIsNone(metrics["positivePredictivityPrecision"])
        self.assertEqual(metrics["f1"], 0.0)

    def test_empty_reference_window_is_kept_and_counts_false_positives(self) -> None:
        manifest_document = manifest_payload()
        manifest_document["windows"][0]["referencePeakSamples"] = []
        manifest = MODULE.validate_manifest(manifest_document)
        predictions = MODULE.validate_predictions(predictions_payload([360]), manifest)

        metrics = MODULE.evaluate(manifest, predictions)["aggregate"]

        self.assertEqual(metrics["truePositiveCount"], 0)
        self.assertEqual(metrics["falsePositiveCount"], 1)
        self.assertEqual(metrics["falseNegativeCount"], 0)
        self.assertIsNone(metrics["sensitivityRecall"])
        self.assertEqual(metrics["positivePredictivityPrecision"], 0.0)
        self.assertEqual(metrics["f1"], 0.0)

    def test_manifest_rejects_subject_leakage_between_splits(self) -> None:
        payload = manifest_payload()
        second = copy.deepcopy(payload["windows"][0])
        second.update(
            {
                "id": "record-b-000000-010800",
                "recordId": "record-b",
                "split": "held-out-test",
            }
        )
        payload["windows"].append(second)

        with self.assertRaisesRegex(
            MODULE.BenchmarkValidationError,
            "subjects appear in more than one split",
        ):
            MODULE.validate_manifest(payload)

    def test_manifest_rejects_non_thirty_second_window(self) -> None:
        payload = manifest_payload()
        payload["windows"][0]["endSampleExclusive"] = 10_799

        with self.assertRaisesRegex(
            MODULE.BenchmarkValidationError,
            "is not a 30.0-second window",
        ):
            MODULE.validate_manifest(payload)

    def test_predictions_must_cover_exact_manifest_windows(self) -> None:
        manifest = MODULE.validate_manifest(manifest_payload())
        payload = predictions_payload()
        payload["windows"] = []

        with self.assertRaisesRegex(
            MODULE.BenchmarkValidationError,
            "predictions are missing windows",
        ):
            MODULE.validate_predictions(payload, manifest)

    def test_predictions_require_sha256_configuration_hash(self) -> None:
        manifest = MODULE.validate_manifest(manifest_payload())
        payload = predictions_payload()
        payload["detector"].pop("configHash")

        with self.assertRaisesRegex(
            MODULE.BenchmarkValidationError,
            "configHash must be a non-empty string",
        ):
            MODULE.validate_predictions(payload, manifest)

    def test_split_projection_requires_an_explicit_valid_stage(self) -> None:
        manifest = MODULE.validate_manifest(manifest_payload())

        with self.assertRaisesRegex(
            MODULE.BenchmarkValidationError,
            "at least one benchmark split",
        ):
            MODULE.select_manifest_splits(manifest, [])
        with self.assertRaisesRegex(
            MODULE.BenchmarkValidationError,
            "unknown benchmark splits",
        ):
            MODULE.select_manifest_splits(manifest, ["future-split"])

    def test_split_projection_excludes_unrequested_windows(self) -> None:
        payload = manifest_payload()
        held_out = copy.deepcopy(payload["windows"][0])
        held_out.update(
            {
                "id": "record-b-000000-010800",
                "subjectId": "subject-b",
                "recordId": "record-b",
                "split": "held-out-test",
            }
        )
        payload["windows"].append(held_out)

        projected = MODULE.select_manifest_splits(
            MODULE.validate_manifest(payload),
            ["development"],
        )

        self.assertEqual([window.window_id for window in projected.windows], [
            "record-a-000000-010800"
        ])
        MODULE.validate_predictions(predictions_payload(), projected)


if __name__ == "__main__":
    unittest.main()
