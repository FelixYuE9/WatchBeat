#!/usr/bin/env python3
"""Build a deterministic 30-second R-peak benchmark manifest from MIT-BIH v1.0.0.

This tool reads only checksum-verified local files produced by ``download_mitdb.py``. It implements
the documented MIT WFDB annotation format with the Python standard library, extracts only official
QRS annotation codes, keeps records 201 and 202 in one subject group, and emits the schema consumed
by ``evaluate_r_peaks.py``. It does not run a detector or make a medical claim.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


SCHEMA_VERSION = 1
WINDOW_DURATION_SECONDS = 30.0
MATCHING_TOLERANCE_MILLISECONDS = 150.0
VALID_SPLITS = ("development", "validation", "held-out-test")

# Numeric values are the predefined WFDB beat annotation codes documented in ecgcodes.h.
QRS_ANNOTATION_CODES = frozenset(
    {
        1,   # NORMAL
        2,   # LBBB
        3,   # RBBB
        4,   # ABERR
        5,   # PVC
        6,   # FUSION
        7,   # NPC
        8,   # APC
        9,   # SVPB
        10,  # VESC
        11,  # NESC
        12,  # PACE
        13,  # UNKNOWN
        25,  # BBB
        30,  # LEARN
        34,  # AESC
        35,  # SVESC
        38,  # PFUS
        41,  # RONT
    }
)
SKIP_CODE = 59
NUM_CODE = 60
SUB_CODE = 61
CHN_CODE = 62
AUX_CODE = 63


class MITDBManifestError(ValueError):
    """Raised when local MIT-BIH inputs violate the frozen benchmark contract."""


@dataclass(frozen=True)
class WFDBHeader:
    record_id: str
    signal_count: int
    sampling_frequency_hz: float
    sample_count: int
    signal_names: tuple[str, ...]


@dataclass(frozen=True)
class WFDBAnnotation:
    sample: int
    annotation_type: int


@dataclass(frozen=True)
class SplitDefinition:
    dataset: Mapping[str, str]
    split_by_record: Mapping[str, str]
    subject_by_record: Mapping[str, str]
    strategy: Mapping[str, Any]
    sha256: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_json_document(value: Any) -> str:
    canonical = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _require_mapping(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise MITDBManifestError(f"{path} must be an object")
    return value


def _require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise MITDBManifestError(f"{path} must be an array")
    return value


def _require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise MITDBManifestError(f"{path} must be a non-empty string")
    return value


def parse_wfdb_header(text: str, expected_record_id: str | None = None) -> WFDBHeader:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        raise MITDBManifestError("WFDB header is empty")
    first = lines[0].split()
    if len(first) < 4:
        raise MITDBManifestError("WFDB header first line must have at least four fields")

    record_id = first[0]
    if expected_record_id is not None and record_id != expected_record_id:
        raise MITDBManifestError(
            f"WFDB header record {record_id!r} does not match {expected_record_id!r}"
        )
    try:
        signal_count = int(first[1])
        sampling_frequency_hz = float(first[2].split("/", 1)[0])
        sample_count = int(first[3])
    except ValueError as error:
        raise MITDBManifestError("WFDB header contains invalid numeric fields") from error
    if signal_count <= 0 or sample_count <= 0:
        raise MITDBManifestError("WFDB signal and sample counts must be positive")
    if not math.isfinite(sampling_frequency_hz) or sampling_frequency_hz <= 0:
        raise MITDBManifestError("WFDB sampling frequency must be finite and positive")
    if len(lines) < 1 + signal_count:
        raise MITDBManifestError("WFDB header has fewer signal lines than declared")

    signal_names: list[str] = []
    for index, line in enumerate(lines[1 : 1 + signal_count]):
        fields = line.split()
        if len(fields) < 2 or fields[0].startswith("#"):
            raise MITDBManifestError(f"invalid WFDB signal line {index + 1}")
        signal_names.append(fields[-1])

    return WFDBHeader(
        record_id=record_id,
        signal_count=signal_count,
        sampling_frequency_hz=sampling_frequency_hz,
        sample_count=sample_count,
        signal_names=tuple(signal_names),
    )


def _read_pdp11_long(data: bytes, offset: int) -> tuple[int, int]:
    if offset + 4 > len(data):
        raise MITDBManifestError("truncated SKIP interval in annotation file")
    high_word = data[offset] | (data[offset + 1] << 8)
    low_word = data[offset + 2] | (data[offset + 3] << 8)
    value = (high_word << 16) | low_word
    if value & 0x80000000:
        value -= 1 << 32
    return value, offset + 4


def parse_wfdb_annotations(data: bytes) -> tuple[WFDBAnnotation, ...]:
    """Parse the MIT binary annotation format documented by PhysioNet ANNOT(5)."""

    annotations: list[WFDBAnnotation] = []
    offset = 0
    sample = 0
    saw_end_marker = False

    while offset < len(data):
        if offset + 2 > len(data):
            raise MITDBManifestError("annotation file has an odd trailing byte")
        word = data[offset] | (data[offset + 1] << 8)
        offset += 2
        annotation_type = word >> 10
        interval = word & 0x03FF

        if annotation_type == 0:
            if interval != 0:
                raise MITDBManifestError("annotation type 0 must be the zero end marker")
            saw_end_marker = True
            if any(data[offset:]):
                raise MITDBManifestError("non-zero data follows annotation end marker")
            break
        if annotation_type == SKIP_CODE:
            if interval != 0:
                raise MITDBManifestError("SKIP annotation must have a zero inline interval")
            skipped, offset = _read_pdp11_long(data, offset)
            sample += skipped
            if sample < 0:
                raise MITDBManifestError("annotation SKIP moved before sample zero")
            continue
        if annotation_type in {NUM_CODE, SUB_CODE, CHN_CODE}:
            continue
        if annotation_type == AUX_CODE:
            padded_length = interval + (interval % 2)
            if offset + padded_length > len(data):
                raise MITDBManifestError("truncated AUX payload in annotation file")
            offset += padded_length
            continue
        if annotation_type > 58:
            raise MITDBManifestError(f"unsupported WFDB annotation control code {annotation_type}")

        sample += interval
        annotations.append(WFDBAnnotation(sample=sample, annotation_type=annotation_type))

    if not saw_end_marker:
        raise MITDBManifestError("annotation file has no zero end marker")
    return tuple(annotations)


def qrs_samples_from_annotations(
    annotations: Sequence[WFDBAnnotation],
) -> tuple[int, ...]:
    samples = tuple(
        annotation.sample
        for annotation in annotations
        if annotation.annotation_type in QRS_ANNOTATION_CODES
    )
    if not samples:
        raise MITDBManifestError("annotation file contains no QRS annotations")
    if any(current <= previous for previous, current in zip(samples, samples[1:])):
        raise MITDBManifestError("QRS annotation samples must be strictly increasing")
    return samples


def _validate_split_derivation(
    strategy: Mapping[str, Any],
    split_by_record: Mapping[str, str],
    subject_by_record: Mapping[str, str],
) -> None:
    if strategy.get("name") != "subject-level-stratified-sha256-v1":
        raise MITDBManifestError("unsupported split strategy")
    if strategy.get("frozenBeforeDetectorEvaluation") is not True:
        raise MITDBManifestError("split strategy must be frozen before detector evaluation")
    prefix = _require_string(strategy.get("hashInputPrefix"), "splitDefinition.strategy.hashInputPrefix")
    paced_records = {
        _require_string(value, f"splitDefinition.strategy.pacedRecords[{index}]")
        for index, value in enumerate(
            _require_list(strategy.get("pacedRecords"), "splitDefinition.strategy.pacedRecords")
        )
    }
    if not paced_records or not paced_records.issubset(split_by_record):
        raise MITDBManifestError("split strategy pacedRecords must be known records")

    raw_allocations = _require_mapping(
        strategy.get("allocations"),
        "splitDefinition.strategy.allocations",
    )
    stratum_names = ("paced", "randomNonPaced", "selectedNonPaced")
    if set(raw_allocations) != set(stratum_names):
        raise MITDBManifestError("split strategy allocations contain unexpected strata")

    records_by_subject: dict[str, list[str]] = {}
    for record, subject_id in subject_by_record.items():
        records_by_subject.setdefault(subject_id, []).append(record)
    subjects_by_stratum: dict[str, list[str]] = {name: [] for name in stratum_names}
    for subject_id, records in records_by_subject.items():
        if any(record in paced_records for record in records):
            stratum = "paced"
        elif all(int(record) < 200 for record in records):
            stratum = "randomNonPaced"
        else:
            stratum = "selectedNonPaced"
        subjects_by_stratum[stratum].append(subject_id)

    expected_split_by_subject: dict[str, str] = {}
    for stratum in stratum_names:
        ranked_subjects = sorted(
            subjects_by_stratum[stratum],
            key=lambda subject_id: hashlib.sha256(f"{prefix}{subject_id}".encode("utf-8")).digest(),
        )
        raw_stratum_allocation = _require_mapping(
            raw_allocations.get(stratum),
            f"splitDefinition.strategy.allocations.{stratum}",
        )
        if set(raw_stratum_allocation) != set(VALID_SPLITS):
            raise MITDBManifestError(f"allocation for {stratum} must name all splits")
        cursor = 0
        for split in VALID_SPLITS:
            count = raw_stratum_allocation.get(split)
            if isinstance(count, bool) or not isinstance(count, int) or count < 0:
                raise MITDBManifestError(f"allocation for {stratum}/{split} must be non-negative")
            for subject_id in ranked_subjects[cursor : cursor + count]:
                expected_split_by_subject[subject_id] = split
            cursor += count
        if cursor != len(ranked_subjects):
            raise MITDBManifestError(
                f"allocation for {stratum} covers {cursor} of {len(ranked_subjects)} subjects"
            )

    mismatches = sorted(
        record
        for record, split in split_by_record.items()
        if expected_split_by_subject[subject_by_record[record]] != split
    )
    if mismatches:
        raise MITDBManifestError(
            "explicit splits do not match the frozen SHA-256 derivation: " + ", ".join(mismatches)
        )


def load_split_definition(path: Path, expected_records: Sequence[str]) -> SplitDefinition:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MITDBManifestError(f"cannot read split definition: {error}") from error
    root = _require_mapping(payload, "splitDefinition")
    if root.get("schemaVersion") != SCHEMA_VERSION:
        raise MITDBManifestError(f"splitDefinition.schemaVersion must equal {SCHEMA_VERSION}")

    raw_dataset = _require_mapping(root.get("dataset"), "splitDefinition.dataset")
    dataset = {
        key: _require_string(raw_dataset.get(key), f"splitDefinition.dataset.{key}")
        for key in ("name", "version", "sourceURL", "license")
    }
    strategy = dict(_require_mapping(root.get("strategy"), "splitDefinition.strategy"))
    raw_splits = _require_mapping(root.get("splits"), "splitDefinition.splits")
    if set(raw_splits) != set(VALID_SPLITS):
        raise MITDBManifestError(
            "splitDefinition.splits must contain exactly " + ", ".join(VALID_SPLITS)
        )

    split_by_record: dict[str, str] = {}
    for split in VALID_SPLITS:
        records = _require_list(raw_splits.get(split), f"splitDefinition.splits.{split}")
        if not records:
            raise MITDBManifestError(f"splitDefinition.splits.{split} must not be empty")
        for index, value in enumerate(records):
            record = _require_string(value, f"splitDefinition.splits.{split}[{index}]")
            if record in split_by_record:
                raise MITDBManifestError(f"record {record} appears in more than one split")
            split_by_record[record] = split

    expected = set(expected_records)
    actual = set(split_by_record)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise MITDBManifestError(
            f"split record mismatch; missing={missing or 'none'}, extra={extra or 'none'}"
        )

    subject_by_record = {record: f"mitdb-subject-{record}" for record in expected_records}
    seen_subject_ids: set[str] = set()
    grouped_records: set[str] = set()
    for index, raw_group_value in enumerate(
        _require_list(root.get("subjectGroups"), "splitDefinition.subjectGroups")
    ):
        group_path = f"splitDefinition.subjectGroups[{index}]"
        raw_group = _require_mapping(raw_group_value, group_path)
        subject_id = _require_string(raw_group.get("id"), f"{group_path}.id")
        if subject_id in seen_subject_ids:
            raise MITDBManifestError(f"duplicate grouped subject id: {subject_id}")
        seen_subject_ids.add(subject_id)
        records = [
            _require_string(value, f"{group_path}.records[{record_index}]")
            for record_index, value in enumerate(
                _require_list(raw_group.get("records"), f"{group_path}.records")
            )
        ]
        if len(records) < 2:
            raise MITDBManifestError(f"{group_path}.records must contain at least two records")
        if any(record not in expected for record in records):
            raise MITDBManifestError(f"{group_path} contains an unknown record")
        if grouped_records.intersection(records):
            raise MITDBManifestError(f"{group_path} overlaps another subject group")
        group_splits = {split_by_record[record] for record in records}
        if len(group_splits) != 1:
            raise MITDBManifestError(f"{group_path} crosses benchmark splits")
        grouped_records.update(records)
        for record in records:
            subject_by_record[record] = subject_id

    _validate_split_derivation(strategy, split_by_record, subject_by_record)

    return SplitDefinition(
        dataset=dataset,
        split_by_record=split_by_record,
        subject_by_record=subject_by_record,
        strategy=strategy,
        sha256=sha256_json_document(root),
    )


def read_record_list(path: Path) -> tuple[str, ...]:
    records = tuple(line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
    if not records or len(set(records)) != len(records):
        raise MITDBManifestError("RECORDS must contain a non-empty unique record list")
    return records


def verify_download_receipt(dataset_dir: Path, records: Sequence[str]) -> tuple[Mapping[str, Any], str]:
    receipt_path = dataset_dir / "download-receipt.json"
    try:
        receipt = _require_mapping(
            json.loads(receipt_path.read_text(encoding="utf-8")),
            "downloadReceipt",
        )
    except (OSError, json.JSONDecodeError) as error:
        raise MITDBManifestError(f"cannot read download receipt: {error}") from error
    dataset = _require_mapping(receipt.get("dataset"), "downloadReceipt.dataset")
    if dataset.get("version") != "1.0.0":
        raise MITDBManifestError("download receipt is not for MIT-BIH v1.0.0")
    receipt_records = _require_list(receipt.get("records"), "downloadReceipt.records")
    if set(receipt_records) != set(records):
        raise MITDBManifestError("download receipt record population does not match RECORDS")

    file_entries: dict[str, Mapping[str, Any]] = {}
    for index, raw_entry in enumerate(
        _require_list(receipt.get("files"), "downloadReceipt.files")
    ):
        entry = _require_mapping(raw_entry, f"downloadReceipt.files[{index}]")
        name = _require_string(entry.get("name"), f"downloadReceipt.files[{index}].name")
        digest = _require_string(entry.get("sha256"), f"downloadReceipt.files[{index}].sha256")
        if name in file_entries:
            raise MITDBManifestError(f"duplicate download receipt file: {name}")
        if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
            raise MITDBManifestError(f"invalid SHA-256 in download receipt for {name}")
        file_entries[name] = entry

    required_names = {"RECORDS"}
    for record in records:
        required_names.update({f"{record}.hea", f"{record}.dat", f"{record}.atr"})
    missing = sorted(required_names - set(file_entries))
    if missing:
        raise MITDBManifestError("download receipt is missing files: " + ", ".join(missing))
    for name in sorted(required_names):
        path = dataset_dir / name
        if not path.is_file():
            raise MITDBManifestError(f"verified dataset file is missing: {name}")
        expected_digest = str(file_entries[name]["sha256"])
        actual_digest = sha256_file(path)
        if actual_digest != expected_digest:
            raise MITDBManifestError(
                f"dataset file changed after download verification: {name}"
            )
    stable_content_claim = {
        "dataset": dict(dataset),
        "records": list(records),
        "files": [
            {"name": name, "sha256": str(file_entries[name]["sha256"])}
            for name in sorted(required_names)
        ],
    }
    return receipt, sha256_json_document(stable_content_claim)


def _select_channel(signal_names: Sequence[str]) -> int:
    try:
        return signal_names.index("MLII")
    except ValueError:
        return 0


def build_manifest(dataset_dir: Path, split_definition_path: Path) -> dict[str, Any]:
    records = read_record_list(dataset_dir / "RECORDS")
    receipt, dataset_content_sha256 = verify_download_receipt(dataset_dir, records)
    split_definition = load_split_definition(split_definition_path, records)

    window_reports: list[dict[str, Any]] = []
    record_reports: list[dict[str, Any]] = []
    split_counts = {
        split: {"recordCount": 0, "subjectIds": set(), "windowCount": 0, "referencePeakCount": 0}
        for split in VALID_SPLITS
    }

    for record in records:
        header_path = dataset_dir / f"{record}.hea"
        annotation_path = dataset_dir / f"{record}.atr"
        header = parse_wfdb_header(
            header_path.read_text(encoding="ascii"),
            expected_record_id=record,
        )
        annotations = parse_wfdb_annotations(annotation_path.read_bytes())
        qrs_samples = qrs_samples_from_annotations(annotations)
        if qrs_samples[-1] >= header.sample_count:
            raise MITDBManifestError(f"record {record} has a QRS annotation outside the signal")

        window_sample_count_float = WINDOW_DURATION_SECONDS * header.sampling_frequency_hz
        window_sample_count = int(round(window_sample_count_float))
        if not math.isclose(window_sample_count, window_sample_count_float, abs_tol=1e-9):
            raise MITDBManifestError(f"record {record} cannot form exact 30-second windows")
        full_window_count = header.sample_count // window_sample_count
        if full_window_count <= 0:
            raise MITDBManifestError(f"record {record} is shorter than one benchmark window")

        split = split_definition.split_by_record[record]
        subject_id = split_definition.subject_by_record[record]
        channel_index = _select_channel(header.signal_names)
        record_peak_count = 0
        qrs_index = 0

        for window_index in range(full_window_count):
            start_sample = window_index * window_sample_count
            end_sample_exclusive = start_sample + window_sample_count
            while qrs_index < len(qrs_samples) and qrs_samples[qrs_index] < start_sample:
                qrs_index += 1
            peak_end_index = qrs_index
            while peak_end_index < len(qrs_samples) and qrs_samples[peak_end_index] < end_sample_exclusive:
                peak_end_index += 1
            reference_peaks = list(qrs_samples[qrs_index:peak_end_index])
            qrs_index = peak_end_index
            record_peak_count += len(reference_peaks)
            window_reports.append(
                {
                    "id": f"mitdb-{record}-{start_sample:09d}-{end_sample_exclusive:09d}",
                    "subjectId": subject_id,
                    "recordId": record,
                    "split": split,
                    "channelIndex": channel_index,
                    "samplingFrequencyHz": header.sampling_frequency_hz,
                    "startSample": start_sample,
                    "endSampleExclusive": end_sample_exclusive,
                    "referencePeakSamples": reference_peaks,
                }
            )

        split_counts[split]["recordCount"] += 1
        split_counts[split]["subjectIds"].add(subject_id)
        split_counts[split]["windowCount"] += full_window_count
        split_counts[split]["referencePeakCount"] += record_peak_count
        record_reports.append(
            {
                "recordId": record,
                "subjectId": subject_id,
                "split": split,
                "samplingFrequencyHz": header.sampling_frequency_hz,
                "sampleCount": header.sample_count,
                "signalNames": list(header.signal_names),
                "selectedChannelIndex": channel_index,
                "selectedChannelName": header.signal_names[channel_index],
                "fullWindowCount": full_window_count,
                "excludedTailSamples": header.sample_count - full_window_count * window_sample_count,
                "referencePeakCountInWindows": record_peak_count,
            }
        )

    split_summary = {
        split: {
            "recordCount": int(values["recordCount"]),
            "subjectCount": len(values["subjectIds"]),
            "windowCount": int(values["windowCount"]),
            "referencePeakCount": int(values["referencePeakCount"]),
        }
        for split, values in split_counts.items()
    }
    return {
        "schemaVersion": SCHEMA_VERSION,
        "windowDurationSeconds": WINDOW_DURATION_SECONDS,
        "matchingToleranceMilliseconds": MATCHING_TOLERANCE_MILLISECONDS,
        "dataset": dict(split_definition.dataset),
        "provenance": {
            "verifiedDatasetContentSHA256": dataset_content_sha256,
            "splitDefinitionSHA256": split_definition.sha256,
            "referenceAnnotator": "atr",
            "annotationFormat": "WFDB MIT binary",
            "channelPolicy": "MLII when present, otherwise signal 0",
            "sourceFileCount": len(_require_list(receipt.get("files"), "downloadReceipt.files")),
        },
        "splitStrategy": dict(split_definition.strategy),
        "summary": {
            "recordCount": len(records),
            "subjectCount": len(set(split_definition.subject_by_record.values())),
            "windowCount": len(window_reports),
            "referencePeakCount": sum(
                int(values["referencePeakCount"]) for values in split_summary.values()
            ),
            "splits": split_summary,
        },
        "records": record_reports,
        "windows": window_reports,
    }


def build_manifest_lock(manifest: Mapping[str, Any], serialized_manifest: bytes) -> dict[str, Any]:
    windows = _require_list(manifest.get("windows"), "manifest.windows")
    records = _require_list(manifest.get("records"), "manifest.records")
    return {
        "lockSchemaVersion": 1,
        "dataset": dict(_require_mapping(manifest.get("dataset"), "manifest.dataset")),
        "manifest": {
            "schemaVersion": manifest.get("schemaVersion"),
            "sha256": hashlib.sha256(serialized_manifest).hexdigest(),
            "byteCount": len(serialized_manifest),
        },
        "provenance": dict(
            _require_mapping(manifest.get("provenance"), "manifest.provenance")
        ),
        "summary": dict(_require_mapping(manifest.get("summary"), "manifest.summary")),
        "edgeCases": {
            "zeroReferencePeakWindowIds": [
                str(window["id"])
                for window in windows
                if not _require_list(window.get("referencePeakSamples"), "window.referencePeakSamples")
            ],
            "nonMLIISelectedChannels": [
                {
                    "recordId": str(record["recordId"]),
                    "selectedChannelName": str(record["selectedChannelName"]),
                }
                for record in records
                if record.get("selectedChannelName") != "MLII"
            ],
        },
    }


def _serialize_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def main(argv: Sequence[str] | None = None) -> int:
    tool_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Build a checksum-verified MIT-BIH v1.0.0 30-second R-peak manifest."
    )
    parser.add_argument(
        "--dataset-dir",
        type=Path,
        default=tool_dir / "data" / "mitdb-1.0.0",
    )
    parser.add_argument(
        "--split-definition",
        type=Path,
        default=tool_dir / "mitdb_split_v1.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=tool_dir / "output" / "mitdb-rpeak-manifest-v1.json",
    )
    parser.add_argument(
        "--lock",
        type=Path,
        default=tool_dir / "mitdb_manifest_v1.lock.json",
    )
    parser.add_argument(
        "--update-lock",
        action="store_true",
        help="intentionally replace the committed manifest summary lock",
    )
    args = parser.parse_args(argv)

    try:
        manifest = build_manifest(args.dataset_dir, args.split_definition)
        # Import here so unit tests can exercise this module independently while the CLI still proves
        # that its output satisfies the evaluator's public contract.
        from evaluate_r_peaks import validate_manifest

        validate_manifest(manifest)
        serialized = _serialize_json_bytes(manifest)
        expected_lock = build_manifest_lock(manifest, serialized)
        if args.update_lock:
            args.lock.write_bytes(_serialize_json_bytes(expected_lock))
        else:
            try:
                actual_lock = json.loads(args.lock.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                raise MITDBManifestError(
                    f"cannot read manifest lock {args.lock}; use --update-lock intentionally: {error}"
                ) from error
            if actual_lock != expected_lock:
                raise MITDBManifestError(
                    "generated manifest does not match the committed lock; inspect the change and "
                    "use --update-lock only when intentionally revising the benchmark"
                )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Write bytes so the generated manifest uses UTF-8/LF identically on Windows and macOS.
        args.output.write_bytes(serialized)
    except (MITDBManifestError, OSError, json.JSONDecodeError, ValueError) as error:
        print(f"MIT-BIH manifest error: {error}", file=sys.stderr)
        return 2

    summary = manifest["summary"]
    print(
        f"Wrote {summary['windowCount']} windows from {summary['recordCount']} records / "
        f"{summary['subjectCount']} subjects with {summary['referencePeakCount']} QRS annotations "
        f"to {args.output}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
