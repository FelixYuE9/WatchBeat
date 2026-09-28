from __future__ import annotations

import copy
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


VALIDATION_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(VALIDATION_DIR))
MODULE_PATH = VALIDATION_DIR / "prepare_bxb_crosscheck.py"
SPEC = importlib.util.spec_from_file_location("prepare_bxb_crosscheck", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

from evaluate_r_peaks import BenchmarkValidationError


def manifest_payload() -> dict:
    return {
        "schemaVersion": 1,
        "windowDurationSeconds": 30.0,
        "matchingToleranceMilliseconds": 150.0,
        "dataset": {
            "name": "Fixture",
            "version": "1",
            "sourceURL": "https://example.invalid/fixture",
            "license": "Fixture only",
        },
        "windows": [
            {
                "id": f"record-a-{start}-{start + 10_800}",
                "subjectId": "subject-a",
                "recordId": "record-a",
                "split": "development",
                "channelIndex": 0,
                "samplingFrequencyHz": 360.0,
                "startSample": start,
                "endSampleExclusive": start + 10_800,
                "referencePeakSamples": [start + 360],
            }
            for start in (0, 10_800)
        ],
    }


def prediction_payload() -> dict:
    return {
        "schemaVersion": 1,
        "detector": {
            "name": "Fixture/vote",
            "version": "1",
            "configHash": "a" * 64,
        },
        "windows": [
            {"id": "record-a-0-10800", "detectedPeakSamples": [360, 720]},
            {"id": "record-a-10800-21600", "detectedPeakSamples": [11_160]},
        ],
    }


class BxbPreparationTests(unittest.TestCase):
    def test_prepares_contiguous_development_record_without_using_labels(self) -> None:
        plan, texts = MODULE.build_preparation(manifest_payload(), prediction_payload())
        self.assertEqual(plan["evaluatedSplit"], "development")
        self.assertEqual(plan["records"][0]["predictionCount"], 3)
        self.assertEqual(plan["records"][0]["bxbStopTime"], "0:01:00")
        self.assertEqual(texts["record-a"].splitlines()[0], "0:00:01.000 360 N 0 0 0")

        changed_manifest = manifest_payload()
        changed_manifest["windows"][0]["referencePeakSamples"] = [999_999]
        self.assertEqual(
            (plan, texts),
            MODULE.build_preparation(changed_manifest, prediction_payload()),
        )

    def test_roundtrip_verifier_rejects_changed_samples(self) -> None:
        plan, texts = MODULE.build_preparation(manifest_payload(), prediction_payload())
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            MODULE.write_preparation(output_dir, plan, texts)
            roundtrip = output_dir / "record-a.roundtrip.rdann.txt"
            roundtrip.write_text(texts["record-a"], encoding="ascii")
            self.assertEqual(MODULE.verify_roundtrip(output_dir)["verifiedRecordCount"], 1)

            roundtrip.write_text(
                texts["record-a"].replace(" 360 N ", " 361 N "),
                encoding="ascii",
            )
            with self.assertRaisesRegex(BenchmarkValidationError, "samples changed"):
                MODULE.verify_roundtrip(output_dir)

    def test_rejects_noncontiguous_record_or_extra_prediction_window(self) -> None:
        manifest = manifest_payload()
        manifest["windows"][1]["startSample"] = 10_801
        manifest["windows"][1]["endSampleExclusive"] = 21_601
        with self.assertRaisesRegex(BenchmarkValidationError, "contiguous"):
            MODULE.build_preparation(manifest, prediction_payload())

        unexpected = copy.deepcopy(prediction_payload())
        unexpected["windows"].append({
            "id": "held-out-window",
            "detectedPeakSamples": [],
        })
        with self.assertRaisesRegex(BenchmarkValidationError, "unknown prediction window"):
            MODULE.build_preparation(manifest_payload(), unexpected)

    def test_rejects_unsafe_record_id_before_writing_files(self) -> None:
        manifest = manifest_payload()
        for window in manifest["windows"]:
            window["recordId"] = "../outside"
        with self.assertRaisesRegex(BenchmarkValidationError, "unsafe"):
            MODULE.build_preparation(manifest, prediction_payload())


if __name__ == "__main__":
    unittest.main()
