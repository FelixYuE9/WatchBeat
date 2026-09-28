from __future__ import annotations

import copy
import hashlib
import importlib.util
import sys
import unittest
from pathlib import Path


VALIDATION_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(VALIDATION_DIR))
MODULE_PATH = VALIDATION_DIR / "vote_r_peak_predictions.py"
SPEC = importlib.util.spec_from_file_location("vote_r_peak_predictions", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

from evaluate_r_peaks import BenchmarkValidationError, validate_manifest, validate_predictions


WINDOW_ID = "record-a-000000-010800"


def manifest_payload() -> dict:
    return {
        "schemaVersion": 1,
        "windowDurationSeconds": 30.0,
        "matchingToleranceMilliseconds": 150.0,
        "dataset": {
            "name": "Synthetic fixture",
            "version": "1",
            "sourceURL": "https://example.invalid/dataset",
            "license": "Fixture only",
        },
        "windows": [{
            "id": WINDOW_ID,
            "subjectId": "subject-a",
            "recordId": "record-a",
            "split": "development",
            "channelIndex": 0,
            "samplingFrequencyHz": 360.0,
            "startSample": 0,
            "endSampleExclusive": 10_800,
            "referencePeakSamples": [360, 720, 1080],
        }],
    }


def prediction(name: str, peaks: list[int]) -> dict:
    return {
        "schemaVersion": 1,
        "detector": {
            "name": f"PeakSwift/{name}",
            "version": "1.0.0",
            "configHash": hashlib.sha256(name.encode("utf-8")).hexdigest(),
        },
        "windows": [{"id": WINDOW_ID, "detectedPeakSamples": peaks}],
    }


def sources() -> list[dict]:
    return [
        prediction("neurokit", [360, 720, 1080]),
        prediction("pan-tompkins", [364, 719, 1300]),
        prediction("kalidas", [358, 725, 1075]),
    ]


class RPeakVotingTests(unittest.TestCase):
    def test_two_of_three_votes_and_evaluator_compatibility(self) -> None:
        manifest = manifest_payload()
        result = MODULE.build_voted_predictions(manifest, sources(), alignment_tolerance_ms=30)

        window = result["windows"][0]
        self.assertEqual(window["detectedPeakSamples"], [360, 720, 1078])
        self.assertEqual(window["voteCounts"], [3, 3, 2])
        self.assertEqual(result["ensemble"]["minVotes"], 2)
        self.assertEqual(result["claimStatus"], "research-only-unvalidated")
        self.assertEqual(result["evaluatedSplit"], "development")
        validate_predictions(result, validate_manifest(manifest))

    def test_three_of_three_excludes_two_vote_peak(self) -> None:
        result = MODULE.build_voted_predictions(
            manifest_payload(), sources(), min_votes=3, alignment_tolerance_ms=30
        )
        self.assertEqual(result["windows"][0]["detectedPeakSamples"], [360, 720])
        self.assertEqual(result["windows"][0]["voteCounts"], [3, 3])

    def test_configuration_hash_changes_with_vote_parameters(self) -> None:
        two_votes = MODULE.build_voted_predictions(manifest_payload(), sources())
        three_votes = MODULE.build_voted_predictions(manifest_payload(), sources(), min_votes=3)
        narrower = MODULE.build_voted_predictions(
            manifest_payload(), sources(), alignment_tolerance_ms=100
        )
        self.assertNotEqual(two_votes["detector"]["configHash"], three_votes["detector"]["configHash"])
        self.assertNotEqual(two_votes["detector"]["configHash"], narrower["detector"]["configHash"])

    def test_source_order_and_reference_labels_do_not_change_vote(self) -> None:
        original = MODULE.build_voted_predictions(manifest_payload(), sources())
        changed_manifest = manifest_payload()
        changed_manifest["windows"][0]["referencePeakSamples"] = [999_999]
        changed = MODULE.build_voted_predictions(changed_manifest, list(reversed(sources())))
        self.assertEqual(original, changed)

    def test_one_detector_cannot_cast_two_votes_for_one_peak(self) -> None:
        samples, votes = MODULE.vote_window([[360, 365], [362], []], 360, 2, 30)
        self.assertEqual(samples, [361])
        self.assertEqual(votes, [2])

    def test_alignment_does_not_chain_beyond_tolerance(self) -> None:
        samples, votes = MODULE.vote_window([[1000], [1050], [1100]], 1000, 3, 60)
        self.assertEqual(samples, [])
        self.assertEqual(votes, [])

    def test_rejects_duplicate_detectors_and_non_development_predictions(self) -> None:
        duplicated = sources()
        duplicated[2] = copy.deepcopy(duplicated[0])
        with self.assertRaisesRegex(BenchmarkValidationError, "distinct detector names"):
            MODULE.build_voted_predictions(manifest_payload(), duplicated)

        unexpected = sources()
        unexpected[0]["windows"].append({
            "id": "held-out-window",
            "detectedPeakSamples": [1],
        })
        with self.assertRaisesRegex(BenchmarkValidationError, "unknown prediction window"):
            MODULE.build_voted_predictions(manifest_payload(), unexpected)

    def test_rejects_unsafe_parameters(self) -> None:
        with self.assertRaisesRegex(BenchmarkValidationError, "min_votes"):
            MODULE.build_voted_predictions(manifest_payload(), sources(), min_votes=1)
        with self.assertRaisesRegex(BenchmarkValidationError, "alignment tolerance"):
            MODULE.build_voted_predictions(
                manifest_payload(), sources(), alignment_tolerance_ms=151
            )


if __name__ == "__main__":
    unittest.main()
