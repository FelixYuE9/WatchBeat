#!/usr/bin/env python3
"""Smoke-check the end-to-end premature-beat prototype on MIT-BIH development records."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

import numpy as np

from build_mitdb_manifest import (
    QRS_ANNOTATION_CODES,
    WFDBAnnotation,
    load_split_definition,
    parse_wfdb_header,
    parse_wfdb_annotations,
    read_record_list,
)
from prototype_premature_beats import PrototypeError, analyze, read_exported_csv


# WFDB codes for atrial/junctional premature beats and ventricular premature contractions.
PREMATURE_ANNOTATION_CODES = frozenset({4, 5, 7, 8, 9, 41})
TIMING_TOLERANCE_MILLISECONDS = 150.0


def compare_to_annotations(
    beats: list[dict], annotations: Sequence[WFDBAnnotation], frequency_hz: float
) -> dict:
    references = [annotation for annotation in annotations if annotation.annotation_type in QRS_ANNOTATION_CODES]
    tolerance_samples = TIMING_TOLERANCE_MILLISECONDS * frequency_hz / 1_000.0
    matched: list[tuple[int, int]] = []
    detection_index = 0
    reference_index = 0
    while detection_index < len(beats) and reference_index < len(references):
        delta = beats[detection_index]["sampleIndex"] - references[reference_index].sample
        if abs(delta) <= tolerance_samples:
            matched.append((detection_index, reference_index))
            detection_index += 1
            reference_index += 1
        elif delta < 0:
            detection_index += 1
        else:
            reference_index += 1

    matched_early = sum(
        beats[detected]["classification"] == "prematureUncertain"
        and references[reference].annotation_type in PREMATURE_ANNOTATION_CODES
        for detected, reference in matched
    )
    predicted_early = sum(beat["classification"] == "prematureUncertain" for beat in beats)
    annotated_early = sum(
        annotation.annotation_type in PREMATURE_ANNOTATION_CODES for annotation in references
    )
    return {
        "rPeaks": {
            "matched": len(matched),
            "falsePositive": len(beats) - len(matched),
            "falseNegative": len(references) - len(matched),
        },
        "prematureCandidates": {
            "matchedAnnotatedPremature": matched_early,
            "flaggedOtherOrUnmatched": predicted_early - matched_early,
            "missedAnnotatedPremature": annotated_early - matched_early,
            "predictedCount": predicted_early,
            "referenceCount": annotated_early,
        },
    }


def main(argv: Sequence[str] | None = None) -> int:
    tool_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record_id", help="development record ID, for example 200")
    parser.add_argument("csv_path", type=Path, help="already converted WatchBeat raw ECG CSV")
    parser.add_argument("--dataset-dir", type=Path, default=tool_dir / "data" / "mitdb-1.0.0")
    parser.add_argument("--split-definition", type=Path, default=tool_dir / "mitdb_split_v1.json")
    parser.add_argument("--output", type=Path, help="optional JSON report path")
    args = parser.parse_args(argv)

    try:
        records = read_record_list(args.dataset_dir / "RECORDS")
        split = load_split_definition(args.split_definition, records)
        if split.split_by_record.get(args.record_id) != "development":
            raise PrototypeError("prototype smoke check only accepts frozen development records")
        header = parse_wfdb_header(
            (args.dataset_dir / f"{args.record_id}.hea").read_text(encoding="ascii"),
            expected_record_id=args.record_id,
        )
        trace = read_exported_csv(args.csv_path)
        expected_times = np.arange(header.sample_count) / header.sampling_frequency_hz
        if len(trace.time_seconds) != header.sample_count or not np.allclose(
            trace.time_seconds, expected_times, rtol=0, atol=1e-9
        ):
            raise PrototypeError("canonical CSV row count or timestamps do not match the record")
        analysis = analyze(trace)
        if analysis["status"] != "analyzed":
            raise PrototypeError(f"record was not analyzed: {analysis['reason']}")
        annotations = parse_wfdb_annotations(
            (args.dataset_dir / f"{args.record_id}.atr").read_bytes()
        )
        comparison = compare_to_annotations(
            analysis["beats"], annotations, analysis["samplingFrequencyHz"]
        )
        report = {
            "schemaVersion": 1,
            "claimStatus": "research-only-development-smoke-check",
            "recordId": args.record_id,
            "split": "development",
            "detectorVersion": analysis["algorithmVersion"],
            "timingToleranceMilliseconds": TIMING_TOLERANCE_MILLISECONDS,
            "matchingPolicy": "order-preserving-greedy-prototype",
            "referencePrematureAnnotationCodes": sorted(PREMATURE_ANNOTATION_CODES),
            "comparison": comparison,
        }
        if args.output is not None:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError, KeyError) as error:
        print(f"Prototype evaluation error: {error}", file=sys.stderr)
        return 2

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
