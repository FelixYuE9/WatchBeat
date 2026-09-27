from __future__ import annotations

import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "download_mitdb.py"
SPEC = importlib.util.spec_from_file_location("download_mitdb", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class MITDBDownloadTests(unittest.TestCase):
    def test_frozen_record_list_has_expected_population(self) -> None:
        self.assertEqual(len(MODULE.OFFICIAL_RECORDS), 48)
        self.assertEqual(MODULE.OFFICIAL_RECORDS[0], "100")
        self.assertEqual(MODULE.OFFICIAL_RECORDS[-1], "234")
        self.assertEqual(
            len(MODULE.required_file_names(MODULE.OFFICIAL_RECORDS)),
            1 + 48 * 3,
        )

    def test_checksum_manifest_parser_accepts_standard_format(self) -> None:
        first = "a" * 64
        second = "b" * 64

        result = MODULE.parse_sha256_manifest(
            f"{first} 100.hea\n{second} 100.dat\n"
        )

        self.assertEqual(result, {"100.hea": first, "100.dat": second})

    def test_checksum_manifest_rejects_unsafe_path(self) -> None:
        with self.assertRaisesRegex(
            MODULE.DownloadValidationError,
            "unsafe checksum path",
        ):
            MODULE.parse_sha256_manifest(f"{'a' * 64} ../100.dat\n")

    def test_verify_file_detects_hash_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "100.hea"
            path.write_bytes(b"fixture")
            expected = hashlib.sha256(b"fixture").hexdigest()

            MODULE.verify_file(path, expected)
            with self.assertRaisesRegex(
                MODULE.DownloadValidationError,
                "SHA-256 mismatch",
            ):
                MODULE.verify_file(path, "0" * 64)

    def test_unknown_record_is_rejected_before_network_access(self) -> None:
        with self.assertRaisesRegex(
            MODULE.DownloadValidationError,
            "unknown MIT-BIH",
        ):
            MODULE.validate_record_selection(["999"])

    def test_timeout_must_be_positive_and_finite(self) -> None:
        for value in (0, -1, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaisesRegex(
                MODULE.DownloadValidationError,
                "timeout must be greater than zero",
            ):
                MODULE._positive_timeout(value)


if __name__ == "__main__":
    unittest.main()
