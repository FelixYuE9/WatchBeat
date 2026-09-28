from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "evaluate_prototype_premature_beats.py"
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("evaluate_prototype_premature_beats", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class PrototypeEvaluationTests(unittest.TestCase):
    def test_counts_r_peak_and_premature_candidate_errors_separately(self) -> None:
        references = [
            MODULE.WFDBAnnotation(sample=100, annotation_type=1),
            MODULE.WFDBAnnotation(sample=200, annotation_type=5),
            MODULE.WFDBAnnotation(sample=300, annotation_type=8),
            MODULE.WFDBAnnotation(sample=400, annotation_type=1),
        ]
        beats = [
            {"sampleIndex": 102, "classification": "normal"},
            {"sampleIndex": 198, "classification": "prematureUncertain"},
            {"sampleIndex": 299, "classification": "normal"},
            {"sampleIndex": 600, "classification": "prematureUncertain"},
        ]
        result = MODULE.compare_to_annotations(beats, references, frequency_hz=100.0)
        self.assertEqual(result["rPeaks"], {"matched": 3, "falsePositive": 1, "falseNegative": 1})
        self.assertEqual(
            result["prematureCandidates"],
            {
                "matchedAnnotatedPremature": 1,
                "flaggedOtherOrUnmatched": 1,
                "missedAnnotatedPremature": 1,
                "predictedCount": 2,
                "referenceCount": 2,
            },
        )


if __name__ == "__main__":
    unittest.main()
