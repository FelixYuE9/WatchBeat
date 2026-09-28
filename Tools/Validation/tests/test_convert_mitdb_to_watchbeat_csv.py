from __future__ import annotations

import csv
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "convert_mitdb_to_watchbeat_csv.py"
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("convert_mitdb_to_watchbeat_csv", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def pack_212(left: int, right: int) -> bytes:
    left &= 0xFFF
    right &= 0xFFF
    return bytes((left & 0xFF, ((left >> 8) & 0x0F) | ((right >> 4) & 0xF0), right & 0xFF))


class MITDBAdapterTests(unittest.TestCase):
    def test_each_source_sample_becomes_one_canonical_csv_row(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "999.hea").write_text(
                "999 2 360 4\n"
                "999.dat 212 200 11 0 0 0 0 MLII\n"
                "999.dat 212 200 11 0 0 0 0 V1\n",
                encoding="ascii",
            )
            (root / "999.dat").write_bytes(
                b"".join(
                    pack_212(left, right)
                    for left, right in [(0, 50), (100, -50), (-100, 0), (2047, -2048)]
                )
            )
            output = root / "converted.csv"
            self.assertEqual(MODULE.convert_record(root, "999", 0, output), 4)
            with output.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.reader(handle))
            self.assertEqual(rows[0], ["time_s", "voltage_mV"])
            self.assertEqual(len(rows), 5)
            self.assertEqual([float(row[1]) for row in rows[1:]], [0, 0.5, -0.5, 10.235])
            self.assertEqual([float(row[0]) for row in rows[1:]], [index / 360 for index in range(4)])
            _, right = MODULE.read_mitdb_record(root, "999", 1)
            self.assertEqual(right.tolist(), [0.25, -0.25, 0, -10.24])

    def test_rejects_unsafe_record_id(self) -> None:
        with self.assertRaises(MODULE.MITDBConversionError):
            MODULE.read_mitdb_record(Path("."), "../200")


if __name__ == "__main__":
    unittest.main()
