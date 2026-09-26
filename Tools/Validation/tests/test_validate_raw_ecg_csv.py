import importlib.util
import math
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "validate_raw_ecg_csv.py"
SPEC = importlib.util.spec_from_file_location("validate_raw_ecg_csv", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class RawECGCSVValidationTests(unittest.TestCase):
    def test_reads_expected_csv_contract(self) -> None:
        fixture = Path(__file__).parent / "fixtures" / "raw_valid.csv"

        report = MODULE.inspect_file(fixture)

        self.assertEqual(report.sample_count, 4)
        self.assertEqual(report.missing_voltage_indices, [2])
        self.assertTrue(report.structurally_valid)

    def test_infers_rate_and_preserves_missing_position(self) -> None:
        report = MODULE.inspect(
            [0.0, 0.002, 0.004, 0.006],
            [0.1, None, 0.3, 0.2],
        )

        self.assertEqual(report.sample_count, 4)
        self.assertEqual(report.missing_voltage_indices, [1])
        self.assertAlmostEqual(report.inferred_sampling_rate_hz, 500.0)
        self.assertTrue(report.structurally_valid)

    def test_reports_time_order_and_non_finite_values(self) -> None:
        report = MODULE.inspect(
            [0.0, 0.01, 0.01, 0.005, math.inf],
            [0.1, 0.2, 0.3, math.nan, 0.4],
        )

        self.assertEqual(report.duplicate_timestamp_indices, [2])
        self.assertEqual(report.decreasing_timestamp_indices, [3])
        self.assertEqual(report.non_finite_time_indices, [4])
        self.assertEqual(report.non_finite_voltage_indices, [3])
        self.assertFalse(report.structurally_valid)


if __name__ == "__main__":
    unittest.main()
