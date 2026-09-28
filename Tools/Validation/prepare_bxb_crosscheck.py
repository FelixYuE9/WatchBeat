#!/usr/bin/env python3
"""Prepare development-only peak predictions for a WFDB wrann/bxb cross-check.

The preparation path uses window metadata and detected peaks, not reference annotations. The
official bxb run is separate because WFDB command-line tools are required on the execution host.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Sequence

from evaluate_r_peaks import BenchmarkValidationError, load_json_document, validate_predictions
from vote_r_peak_predictions import development_manifest


def _safe_record_id(record_id: Any) -> str:
    if not isinstance(record_id, str) or re.fullmatch(r"[A-Za-z0-9_-]+", record_id) is None:
        raise BenchmarkValidationError("record id is unsafe for a WFDB filename")
    return record_id


def _clock(milliseconds: int, *, fractional: bool) -> str:
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, millis = divmod(remainder, 1_000)
    base = f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{base}.{millis:03d}" if fractional else base


def render_rdann(samples: Sequence[int], sampling_frequency_hz: float) -> str:
    lines = []
    for sample in samples:
        elapsed_ms = round(sample * 1_000 / sampling_frequency_hz)
        lines.append(f"{_clock(elapsed_ms, fractional=True)} {sample} N 0 0 0")
    return "\n".join(lines) + ("\n" if lines else "")


def build_preparation(
    manifest_payload: Any,
    predictions_payload: Any,
) -> tuple[dict[str, Any], dict[str, str]]:
    manifest = development_manifest(manifest_payload)
    predictions = validate_predictions(predictions_payload, manifest)
    by_record: dict[str, list[Any]] = defaultdict(list)
    for window in manifest.windows:
        by_record[window.record_id].append(window)

    record_reports = []
    texts = {}
    for record_id, windows in sorted(by_record.items()):
        _safe_record_id(record_id)
        windows.sort(key=lambda window: window.start_sample)
        sampling_frequency_hz = windows[0].sampling_frequency_hz
        previous_end = 0
        samples = []
        for window in windows:
            if window.start_sample != previous_end:
                raise BenchmarkValidationError(
                    f"record {record_id} development windows must start at zero and be contiguous"
                )
            if window.sampling_frequency_hz != sampling_frequency_hz:
                raise BenchmarkValidationError(f"record {record_id} has mixed sample rates")
            samples.extend(predictions.peaks_by_window_id[window.window_id])
            previous_end = window.end_sample_exclusive
        if any(current <= previous for previous, current in zip(samples, samples[1:])):
            raise BenchmarkValidationError(f"record {record_id} peaks are not strictly increasing")
        stop_seconds = previous_end / sampling_frequency_hz
        if not math.isclose(stop_seconds, round(stop_seconds), abs_tol=1e-9):
            raise BenchmarkValidationError(f"record {record_id} stop time must be whole seconds")
        text = render_rdann(samples, sampling_frequency_hz)
        texts[record_id] = text
        record_reports.append({
            "recordId": record_id,
            "windowCount": len(windows),
            "samplingFrequencyHz": sampling_frequency_hz,
            "endSampleExclusive": previous_end,
            "bxbStopTime": _clock(round(stop_seconds) * 1_000, fractional=False),
            "predictionCount": len(samples),
            "wrannInputSHA256": hashlib.sha256(text.encode("ascii")).hexdigest(),
        })

    return {
        "schemaVersion": 1,
        "claimStatus": "research-only-unvalidated",
        "evaluatedSplit": "development",
        "detector": dict(predictions.detector),
        "comparison": {
            "referenceAnnotator": "atr",
            "testAnnotator": "vot",
            "includeFirstFiveMinutes": True,
            "endAtCompleteWindowBoundary": True,
            "matchWindowMilliseconds": 150,
            "note": "bxb uses continuous records and AAMI annotation rules; counts need not equal the window evaluator",
        },
        "records": record_reports,
    }, texts


def write_preparation(output_dir: Path, plan: dict[str, Any], texts: dict[str, str]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for record in plan["records"]:
        record_id = _safe_record_id(record["recordId"])
        (output_dir / f"{record_id}.input.rdann.txt").write_text(
            texts[record_id], encoding="ascii"
        )
    (output_dir / "records.tsv").write_text(
        "".join(
            f"{record['recordId']}\t{record['bxbStopTime']}\n"
            for record in plan["records"]
        ),
        encoding="ascii",
    )
    (output_dir / "plan.json").write_text(
        json.dumps(plan, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def _read_rdann_samples(text: str, source_name: str) -> list[int]:
    samples = []
    for line_number, line in enumerate(text.splitlines(), 1):
        fields = line.split()
        if len(fields) < 6 or fields[2:6] != ["N", "0", "0", "0"]:
            raise BenchmarkValidationError(
                f"{source_name}:{line_number} is not an N annotation with zero metadata"
            )
        try:
            sample = int(fields[1])
        except ValueError as error:
            raise BenchmarkValidationError(
                f"{source_name}:{line_number} has an invalid sample"
            ) from error
        samples.append(sample)
    return samples


def verify_roundtrip(output_dir: Path) -> dict[str, Any]:
    plan = load_json_document(output_dir / "plan.json")
    if not isinstance(plan, dict) or plan.get("evaluatedSplit") != "development":
        raise BenchmarkValidationError("cross-check plan must be development-only")
    records = plan.get("records")
    if not isinstance(records, list) or not records:
        raise BenchmarkValidationError("cross-check plan has no records")
    verified = []
    for record in records:
        record_id = _safe_record_id(record["recordId"])
        source = output_dir / f"{record_id}.input.rdann.txt"
        roundtrip = output_dir / f"{record_id}.roundtrip.rdann.txt"
        expected = _read_rdann_samples(source.read_text(encoding="ascii"), source.name)
        actual = _read_rdann_samples(roundtrip.read_text(encoding="ascii"), roundtrip.name)
        if actual != expected or len(actual) != record["predictionCount"]:
            raise BenchmarkValidationError(f"record {record_id} wrann/rdann samples changed")
        verified.append(record_id)
    return {"verifiedRecordCount": len(verified), "records": verified}


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare = subparsers.add_parser("prepare")
    prepare.add_argument("manifest", type=Path)
    prepare.add_argument("predictions", type=Path)
    prepare.add_argument("--output-dir", type=Path, required=True)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        if args.command == "prepare":
            plan, texts = build_preparation(
                load_json_document(args.manifest), load_json_document(args.predictions)
            )
            write_preparation(args.output_dir, plan, texts)
            print(f"Prepared {len(plan['records'])} development records in {args.output_dir}")
        else:
            result = verify_roundtrip(args.output_dir)
            print(f"Verified wrann/rdann roundtrip for {result['verifiedRecordCount']} records")
    except (BenchmarkValidationError, OSError, json.JSONDecodeError) as error:
        print(f"bxb preparation error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
