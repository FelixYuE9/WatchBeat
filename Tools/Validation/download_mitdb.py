#!/usr/bin/env python3
"""Download a checksum-verified subset of MIT-BIH Arrhythmia Database v1.0.0.

Nothing is downloaded on import. The default CLI selection is the 48-record official RECORDS list,
and only the signal header, signal data, and current reference annotation are fetched. The target
directory is Git-ignored by repository policy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Sequence


DATASET_NAME = "MIT-BIH Arrhythmia Database"
DATASET_VERSION = "1.0.0"
BASE_URL = f"https://physionet.org/files/mitdb/{DATASET_VERSION}"
LANDING_PAGE_URL = f"https://physionet.org/content/mitdb/{DATASET_VERSION}/"
LICENSE_NAME = "Open Data Commons Attribution License v1.0"
LICENSE_URL = f"https://physionet.org/content/mitdb/view-license/{DATASET_VERSION}/"
DOI = "https://doi.org/10.13026/C2F305"

# Frozen from the versioned PhysioNet RECORDS file. The list is intentionally explicit so a changed
# remote index cannot silently alter the benchmark population.
OFFICIAL_RECORDS = (
    "100", "101", "102", "103", "104", "105", "106", "107", "108", "109",
    "111", "112", "113", "114", "115", "116", "117", "118", "119", "121",
    "122", "123", "124", "200", "201", "202", "203", "205", "207", "208",
    "209", "210", "212", "213", "214", "215", "217", "219", "220", "221",
    "222", "223", "228", "230", "231", "232", "233", "234",
)
REQUIRED_EXTENSIONS = ("hea", "dat", "atr")
SHA256_PATTERN = re.compile(r"^(?P<digest>[0-9a-f]{64})\s+(?P<name>\S+)$")


class DownloadValidationError(RuntimeError):
    """Raised when remote metadata or a downloaded file fails the frozen contract."""


def parse_sha256_manifest(text: str) -> dict[str, str]:
    checksums: dict[str, str] = {}
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        match = SHA256_PATTERN.fullmatch(line)
        if match is None:
            raise DownloadValidationError(
                f"invalid SHA256SUMS.txt line {line_number}: {raw_line!r}"
            )
        name = match.group("name")
        if Path(name).name != name or name in {".", ".."}:
            raise DownloadValidationError(f"unsafe checksum path at line {line_number}: {name}")
        if name in checksums:
            raise DownloadValidationError(f"duplicate checksum entry: {name}")
        checksums[name] = match.group("digest")
    if not checksums:
        raise DownloadValidationError("SHA256SUMS.txt contains no entries")
    return checksums


def validate_record_selection(records: Sequence[str]) -> tuple[str, ...]:
    if not records:
        raise DownloadValidationError("at least one record must be selected")
    selected: list[str] = []
    seen: set[str] = set()
    for record in records:
        if record not in OFFICIAL_RECORDS:
            raise DownloadValidationError(f"unknown MIT-BIH v1.0.0 record: {record}")
        if record not in seen:
            selected.append(record)
            seen.add(record)
    return tuple(selected)


def required_file_names(records: Sequence[str]) -> tuple[str, ...]:
    selected = validate_record_selection(records)
    return ("RECORDS",) + tuple(
        f"{record}.{extension}"
        for record in selected
        for extension in REQUIRED_EXTENSIONS
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_file(path: Path, expected_sha256: str) -> None:
    actual_sha256 = sha256_file(path)
    if actual_sha256 != expected_sha256:
        raise DownloadValidationError(
            f"SHA-256 mismatch for {path.name}: expected {expected_sha256}, got {actual_sha256}"
        )


def _request_bytes(url: str, timeout_seconds: float) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "WatchBeat-validation/0.1 (checksum-verified research download)"},
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return response.read()


def _download_verified_file(
    name: str,
    expected_sha256: str,
    destination: Path,
    timeout_seconds: float,
) -> str:
    target = destination / name
    if target.exists():
        verify_file(target, expected_sha256)
        return "verified-existing"

    temporary = destination / f".{name}.part"
    try:
        temporary.write_bytes(_request_bytes(f"{BASE_URL}/{name}", timeout_seconds))
        verify_file(temporary, expected_sha256)
        temporary.replace(target)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return "downloaded"


def download_dataset(
    destination: Path,
    records: Sequence[str] = OFFICIAL_RECORDS,
    timeout_seconds: float = 60.0,
) -> dict:
    selected = validate_record_selection(records)
    timeout_seconds = _positive_timeout(timeout_seconds)
    destination.mkdir(parents=True, exist_ok=True)

    manifest_bytes = _request_bytes(f"{BASE_URL}/SHA256SUMS.txt", timeout_seconds)
    try:
        manifest_text = manifest_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise DownloadValidationError("SHA256SUMS.txt is not valid UTF-8") from error
    checksums = parse_sha256_manifest(manifest_text)

    names = required_file_names(selected)
    missing_checksums = [name for name in names if name not in checksums]
    if missing_checksums:
        raise DownloadValidationError(
            "official checksum manifest is missing required files: "
            + ", ".join(missing_checksums)
        )

    statuses: dict[str, str] = {}
    for name in names:
        statuses[name] = _download_verified_file(
            name,
            checksums[name],
            destination,
            timeout_seconds,
        )

    (destination / "SHA256SUMS.txt").write_bytes(manifest_bytes)
    attribution = (
        f"{DATASET_NAME} v{DATASET_VERSION}\n"
        f"Source: {LANDING_PAGE_URL}\n"
        f"DOI: {DOI}\n"
        f"License: {LICENSE_NAME} ({LICENSE_URL})\n"
        "This local copy is development-only and must not be committed to the repository.\n"
    )
    (destination / "ATTRIBUTION.txt").write_text(attribution, encoding="utf-8")

    receipt = {
        "receiptSchemaVersion": 1,
        "dataset": {
            "name": DATASET_NAME,
            "version": DATASET_VERSION,
            "sourceURL": LANDING_PAGE_URL,
            "doi": DOI,
            "license": LICENSE_NAME,
            "licenseURL": LICENSE_URL,
        },
        "records": list(selected),
        "files": [
            {
                "name": name,
                "sha256": checksums[name],
                "status": statuses[name],
            }
            for name in names
        ],
    }
    (destination / "download-receipt.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return receipt


def main(argv: Sequence[str] | None = None) -> int:
    default_destination = Path(__file__).resolve().parent / "data" / "mitdb-1.0.0"
    parser = argparse.ArgumentParser(
        description="Download checksum-verified MIT-BIH Arrhythmia Database v1.0.0 files."
    )
    parser.add_argument(
        "--destination",
        type=Path,
        default=default_destination,
        help=f"download directory (default: {default_destination})",
    )
    parser.add_argument(
        "--records",
        nargs="+",
        default=list(OFFICIAL_RECORDS),
        help="official record names; defaults to all 48 records",
    )
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args(argv)

    try:
        receipt = download_dataset(
            args.destination,
            records=args.records,
            timeout_seconds=_positive_timeout(args.timeout),
        )
    except (
        DownloadValidationError,
        OSError,
        urllib.error.URLError,
        urllib.error.HTTPError,
    ) as error:
        print(f"MIT-BIH download error: {error}", file=sys.stderr)
        return 2

    downloaded = sum(file["status"] == "downloaded" for file in receipt["files"])
    existing = len(receipt["files"]) - downloaded
    print(
        f"Verified {len(receipt['records'])} records and {len(receipt['files'])} files "
        f"({downloaded} downloaded, {existing} already present)."
    )
    return 0


def _positive_timeout(value: float) -> float:
    if (
        not isinstance(value, (int, float))
        or not math.isfinite(float(value))
        or not float(value) > 0
    ):
        raise DownloadValidationError("timeout must be greater than zero")
    return float(value)


if __name__ == "__main__":
    raise SystemExit(main())
