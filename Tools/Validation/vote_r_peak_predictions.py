#!/usr/bin/env python3
"""Build a development-only R-peak voting candidate from three prediction files.

This tool uses window metadata and detector peaks, never reference annotations. Its greedy
alignment policy is an experiment, not a production detector or a validated clinical rule.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from itertools import combinations
from pathlib import Path
from typing import Any, Sequence

from evaluate_r_peaks import (
    BenchmarkManifest,
    BenchmarkValidationError,
    DetectorPredictions,
    load_json_document,
    select_manifest_splits,
    validate_manifest,
    validate_predictions,
)


POLICY = "highest-vote-narrowest-span-greedy-v1"
METADATA_FIELDS = (
    "id",
    "subjectId",
    "recordId",
    "split",
    "channelIndex",
    "samplingFrequencyHz",
    "startSample",
    "endSampleExclusive",
)


def development_manifest(payload: Any) -> BenchmarkManifest:
    if not isinstance(payload, dict) or not isinstance(payload.get("windows"), list):
        raise BenchmarkValidationError("manifest must contain a windows array")
    windows = []
    for index, raw_window in enumerate(payload["windows"]):
        if not isinstance(raw_window, dict):
            raise BenchmarkValidationError(f"manifest.windows[{index}] must be an object")
        metadata = {field: raw_window.get(field) for field in METADATA_FIELDS}
        metadata["referencePeakSamples"] = []
        windows.append(metadata)

    metadata_only = {
        "schemaVersion": payload.get("schemaVersion"),
        "windowDurationSeconds": payload.get("windowDurationSeconds"),
        "matchingToleranceMilliseconds": payload.get("matchingToleranceMilliseconds"),
        "dataset": payload.get("dataset"),
        "windows": windows,
    }
    return select_manifest_splits(validate_manifest(metadata_only), ["development"])


def _positive_tolerance(value: float) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value <= 0
        or value > 150
    ):
        raise BenchmarkValidationError("alignment tolerance must be greater than 0 and at most 150 ms")
    return value


def _center(samples: Sequence[int]) -> int:
    ordered = sorted(samples)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle] + 1) // 2


def vote_window(
    peak_sets: Sequence[Sequence[int]],
    sampling_frequency_hz: float,
    min_votes: int,
    alignment_tolerance_ms: float,
) -> tuple[list[int], list[int]]:
    events = sorted(
        (sample, source_index)
        for source_index, peaks in enumerate(peak_sets)
        for sample in peaks
    )
    max_span_samples = math.floor(
        alignment_tolerance_ms * sampling_frequency_hz / 1_000.0 + 1e-9
    )
    proposals: list[tuple[int, ...]] = []
    for first in range(len(events)):
        nearby: list[int] = []
        for next_index in range(first + 1, len(events)):
            if events[next_index][0] - events[first][0] > max_span_samples:
                break
            if events[next_index][1] != events[first][1]:
                nearby.append(next_index)
        for size in range(min_votes - 1, len(peak_sets)):
            for trailing in combinations(nearby, size):
                group = (first, *trailing)
                if len({events[index][1] for index in group}) == len(group):
                    proposals.append(group)

    def priority(group: tuple[int, ...]) -> tuple[Any, ...]:
        samples = tuple(events[index][0] for index in group)
        center = _center(samples)
        return (
            -len(group),
            samples[-1] - samples[0],
            sum(abs(sample - center) for sample in samples),
            center,
            tuple(events[index] for index in group),
        )

    used: set[int] = set()
    selected: list[tuple[int, int]] = []
    for group in sorted(proposals, key=priority):
        if any(index in used for index in group):
            continue
        selected.append((_center([events[index][0] for index in group]), len(group)))
        used.update(group)

    selected.sort()
    samples = [sample for sample, _ in selected]
    if any(current <= previous for previous, current in zip(samples, samples[1:])):
        raise BenchmarkValidationError("voting produced duplicate peak samples")
    return samples, [votes for _, votes in selected]


def build_voted_predictions(
    manifest_payload: Any,
    source_payloads: Sequence[Any],
    *,
    min_votes: int = 2,
    alignment_tolerance_ms: float = 120.0,
) -> dict[str, Any]:
    if len(source_payloads) != 3:
        raise BenchmarkValidationError("this experiment requires exactly three detectors")
    if isinstance(min_votes, bool) or min_votes not in (2, 3):
        raise BenchmarkValidationError("min_votes must be 2 or 3")
    tolerance = _positive_tolerance(alignment_tolerance_ms)
    manifest = development_manifest(manifest_payload)
    sources: list[DetectorPredictions] = [
        validate_predictions(payload, manifest) for payload in source_payloads
    ]
    sources.sort(key=lambda source: (
        source.detector["name"], source.detector["version"], source.detector["configHash"]
    ))
    names = [source.detector["name"] for source in sources]
    if len(set(names)) != len(names):
        raise BenchmarkValidationError("voting sources must use distinct detector names")

    configuration: dict[str, Any] = {
        "policy": POLICY,
        "minVotes": min_votes,
        "alignmentToleranceMilliseconds": tolerance,
        "sourceDetectors": [dict(source.detector) for source in sources],
    }
    canonical = json.dumps(configuration, sort_keys=True, separators=(",", ":"))
    config_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    windows = []
    for window in manifest.windows:
        peaks, votes = vote_window(
            [source.peaks_by_window_id[window.window_id] for source in sources],
            window.sampling_frequency_hz,
            min_votes,
            tolerance,
        )
        windows.append({
            "id": window.window_id,
            "detectedPeakSamples": peaks,
            "voteCounts": votes,
        })

    return {
        "schemaVersion": 1,
        "claimStatus": "research-only-unvalidated",
        "evaluatedSplit": "development",
        "detector": {
            "name": "OfflineEnsemble/vote",
            "version": "1",
            "configHash": config_hash,
        },
        "ensemble": configuration,
        "windows": windows,
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("predictions", type=Path, nargs=3)
    parser.add_argument("--min-votes", type=int, choices=(2, 3), default=2)
    parser.add_argument("--alignment-tolerance-ms", type=float, default=120.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        result = build_voted_predictions(
            load_json_document(args.manifest),
            [load_json_document(path) for path in args.predictions],
            min_votes=args.min_votes,
            alignment_tolerance_ms=args.alignment_tolerance_ms,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )
    except (BenchmarkValidationError, OSError, json.JSONDecodeError) as error:
        print(f"R-peak voting error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
