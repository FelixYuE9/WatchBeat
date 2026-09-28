from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).parents[1]
MODULE_PATH = TOOLS_DIR / "build_mitdb_manifest.py"
SPEC = importlib.util.spec_from_file_location("build_mitdb_manifest", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

DOWNLOAD_SPEC = importlib.util.spec_from_file_location(
    "download_mitdb_for_manifest_tests",
    TOOLS_DIR / "download_mitdb.py",
)
assert DOWNLOAD_SPEC is not None and DOWNLOAD_SPEC.loader is not None
DOWNLOAD_MODULE = importlib.util.module_from_spec(DOWNLOAD_SPEC)
sys.modules[DOWNLOAD_SPEC.name] = DOWNLOAD_MODULE
DOWNLOAD_SPEC.loader.exec_module(DOWNLOAD_MODULE)


def annotation_word(annotation_type: int, interval: int) -> bytes:
    return ((annotation_type << 10) | interval).to_bytes(2, "little")


def pdp11_long(value: int) -> bytes:
    unsigned = value & 0xFFFFFFFF
    high_word = (unsigned >> 16) & 0xFFFF
    low_word = unsigned & 0xFFFF
    return high_word.to_bytes(2, "little") + low_word.to_bytes(2, "little")


class MITDBManifestBuilderTests(unittest.TestCase):
    def test_header_parser_preserves_signal_order(self) -> None:
        header = MODULE.parse_wfdb_header(
            "114 2 360 650000\n"
            "114.dat 212 200 11 1024 984 0 0 V5\n"
            "114.dat 212 200 11 1024 1024 0 0 MLII\n"
            "# fixture\n",
            expected_record_id="114",
        )

        self.assertEqual(header.signal_names, ("V5", "MLII"))
        self.assertEqual(MODULE._select_channel(header.signal_names), 1)
        self.assertEqual(header.sample_count, 650_000)

    def test_annotation_parser_handles_aux_and_long_skip(self) -> None:
        data = b"".join(
            [
                annotation_word(1, 100),
                annotation_word(MODULE.AUX_CODE, 3),
                b"abc\x00",
                annotation_word(14, 20),  # non-QRS noise marker
                annotation_word(5, 30),
                annotation_word(MODULE.SKIP_CODE, 0),
                pdp11_long(70_000),
                annotation_word(8, 5),
                b"\x00\x00",
            ]
        )

        annotations = MODULE.parse_wfdb_annotations(data)

        self.assertEqual(
            [(item.sample, item.annotation_type) for item in annotations],
            [(100, 1), (120, 14), (150, 5), (70_155, 8)],
        )
        self.assertEqual(MODULE.qrs_samples_from_annotations(annotations), (100, 150, 70_155))

    def test_annotation_parser_rejects_missing_end_marker(self) -> None:
        with self.assertRaisesRegex(MODULE.MITDBManifestError, "no zero end marker"):
            MODULE.parse_wfdb_annotations(annotation_word(1, 100))

    def test_frozen_split_covers_48_records_and_47_subjects(self) -> None:
        definition = MODULE.load_split_definition(
            TOOLS_DIR / "mitdb_split_v1.json",
            DOWNLOAD_MODULE.OFFICIAL_RECORDS,
        )

        self.assertEqual(len(definition.split_by_record), 48)
        self.assertEqual(len(set(definition.subject_by_record.values())), 47)
        self.assertEqual(
            definition.subject_by_record["201"],
            definition.subject_by_record["202"],
        )
        self.assertEqual(definition.split_by_record["201"], definition.split_by_record["202"])
        self.assertEqual(
            {
                split: sum(value == split for value in definition.split_by_record.values())
                for split in MODULE.VALID_SPLITS
            },
            {"development": 30, "validation": 9, "held-out-test": 9},
        )
        self.assertEqual(
            {
                split: len(
                    {
                        definition.subject_by_record[record]
                        for record, value in definition.split_by_record.items()
                        if value == split
                    }
                )
                for split in MODULE.VALID_SPLITS
            },
            {"development": 29, "validation": 9, "held-out-test": 9},
        )

    def test_download_receipt_rehashes_files_before_manifest_generation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = {
                "RECORDS": b"100\n",
                "100.hea": b"100 1 1 30\n100.dat 16 200 11 0 0 0 0 MLII\n",
                "100.dat": b"fixture signal",
                "100.atr": annotation_word(1, 10) + b"\x00\x00",
            }
            for name, data in contents.items():
                (root / name).write_bytes(data)
            receipt = {
                "dataset": {"version": "1.0.0"},
                "records": ["100"],
                "files": [
                    {
                        "name": name,
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "status": "downloaded",
                    }
                    for name, data in contents.items()
                ],
            }
            (root / "download-receipt.json").write_text(
                json.dumps(receipt),
                encoding="utf-8",
            )

            MODULE.verify_download_receipt(root, ["100"])
            (root / "100.dat").write_bytes(b"changed")
            with self.assertRaisesRegex(
                MODULE.MITDBManifestError,
                "changed after download verification",
            ):
                MODULE.verify_download_receipt(root, ["100"])


if __name__ == "__main__":
    unittest.main()
