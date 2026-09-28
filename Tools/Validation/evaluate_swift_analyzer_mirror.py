#!/usr/bin/env python3
"""Evaluate a NumPy mirror of ECGCore's Swift analyzer on MIT-BIH 30-second windows.

`mirror_detect` and `mirror_classify` follow `GradientEnergyRPeakDetector.swift` and
`PrematureBeatAnalyzer.swift` step by step (same biquads, edge padding, centered integration
window, chunk thresholds, refinement and RR rule), so offline numbers describe the App's
algorithm rather than the SciPy prototype. Each 30 s window is analyzed independently, like an
Apple Watch recording. Development records only; this is a research smoke check, not a claim of
Apple Watch accuracy.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Sequence

import numpy as np
from scipy.signal import lfilter

from build_mitdb_manifest import (
    QRS_ANNOTATION_CODES,
    load_split_definition,
    parse_wfdb_annotations,
    read_record_list,
)
from convert_mitdb_to_watchbeat_csv import read_mitdb_record
from evaluate_prototype_premature_beats import PREMATURE_ANNOTATION_CODES

WINDOW_SECONDS = 30.0
TOLERANCE_SECONDS = 0.150


def _biquad(cutoff_hz: float, fs: float, high_pass: bool) -> tuple[list[float], list[float]]:
    omega = 2 * math.pi * cutoff_hz / fs
    cosine, sine = math.cos(omega), math.sin(omega)
    alpha = sine / (2 * math.sqrt(0.5))
    a0 = 1 + alpha
    b0 = (1 + cosine) / 2 if high_pass else (1 - cosine) / 2
    b1 = -(1 + cosine) if high_pass else 1 - cosine
    return [b0 / a0, b1 / a0, b0 / a0], [1.0, (-2 * cosine) / a0, (1 - alpha) / a0]


def _zero_phase(values: np.ndarray, coefficients, padding: int) -> np.ndarray:
    b, a = coefficients
    pad = min(padding, len(values) - 1)
    head = 2 * values[0] - values[pad:0:-1]
    tail = 2 * values[-1] - values[-2 : -pad - 2 : -1]
    extended = np.concatenate([head, values, tail])
    forward = lfilter(b, a, extended)
    backward = lfilter(b, a, forward[::-1])[::-1]
    return backward[pad : pad + len(values)]


def _centered_mean(values: np.ndarray, window: int) -> np.ndarray:
    prefix = np.concatenate([[0.0], np.cumsum(values)])
    index = np.arange(len(values))
    lower = np.clip(index - window // 2, 0, len(values))
    upper = np.clip(index - window // 2 + window, 0, len(values))
    return (prefix[upper] - prefix[lower]) / (upper - lower)


def _percentile(values: np.ndarray, fraction: float) -> float:
    ordered = np.sort(values)
    return float(ordered[int(round((len(ordered) - 1) * fraction))])


def mirror_detect(voltage: np.ndarray, fs: float) -> list[int]:
    padding = max(1, int(round(fs)))
    filtered = _zero_phase(np.asarray(voltage, float), _biquad(5.0, fs, True), padding)
    filtered = _zero_phase(filtered, _biquad(25.0, fs, False), padding)
    energy = np.zeros(len(filtered))
    energy[1:] = np.diff(filtered) ** 2
    integrated = _centered_mean(energy, max(1, int(round(0.12 * fs))))
    refractory = max(1, int(round(0.25 * fs)))
    refinement = max(1, int(round(0.10 * fs)))
    chunk = max(1, int(round(30 * fs)))
    count = len(integrated)

    candidates: list[int] = []
    start = 0
    while start < count:
        end = min(start + chunk, count)
        if count - end < chunk // 2:
            end = count
        part = integrated[start:end]
        background = _percentile(part, 0.5)
        mad = _percentile(np.abs(part - background), 0.5)
        threshold = max(background + 4 * mad, _percentile(part, 0.95) * 0.25)
        if threshold > 0 and end - start >= 3:
            for index in range(max(1, start), min(count - 2, end - 1) + 1):
                value = integrated[index]
                if not (value >= threshold and value >= integrated[index - 1] and value > integrated[index + 1]):
                    continue
                left = integrated[max(0, index - refinement) : index + 1].min()
                right = integrated[index : min(count - 1, index + refinement) + 1].min()
                if value - max(left, right) < threshold * 0.5:
                    continue
                if candidates and index - candidates[-1] < refractory:
                    if value > integrated[candidates[-1]]:
                        candidates[-1] = index
                else:
                    candidates.append(index)
        start = end

    magnitude = np.abs(filtered)
    refined: list[int] = []
    for candidate in candidates:
        lower = max(0, candidate - refinement)
        upper = min(len(filtered) - 1, candidate + refinement)
        peak = lower + int(np.argmax(magnitude[lower : upper + 1]))
        if refined and peak - refined[-1] < refractory:
            keeps_order = len(refined) < 2 or peak - refined[-2] >= refractory
            if magnitude[peak] > magnitude[refined[-1]] and keeps_order:
                refined[-1] = peak
        elif not refined or peak > refined[-1]:
            refined.append(peak)
    return refined


def mirror_classify(peaks: list[int], times: np.ndarray) -> list[tuple[int, str]]:
    rr = np.diff(times[peaks]) * 1_000
    beats = []
    for position, sample in enumerate(peaks):
        previous = rr[position - 1] if position > 0 else None
        upper = max(0, position - 1)
        context = [value for value in rr[max(0, upper - 8) : upper] if 300 <= value <= 2_000]
        local = float(np.median(context)) if len(context) >= 4 else None
        early = previous is not None and local is not None and 300 <= previous < 0.8 * local
        beats.append((sample, "notAnalyzed" if local is None else "prematureUncertain" if early else "normal"))
    return beats


def _match(detected: list[int], references: list[tuple[int, int]], tolerance: float) -> list[tuple[int, int]]:
    pairs, i, j = [], 0, 0
    while i < len(detected) and j < len(references):
        delta = detected[i] - references[j][0]
        if abs(delta) <= tolerance:
            pairs.append((i, j))
            i += 1
            j += 1
        elif delta < 0:
            i += 1
        else:
            j += 1
    return pairs


def evaluate(dataset_dir: Path, split_path: Path) -> dict:
    records = read_record_list(dataset_dir / "RECORDS")
    split = load_split_definition(split_path, records)
    totals = dict.fromkeys(
        ["windows", "rTP", "rFP", "rFN", "earlyTP", "earlyFP", "earlyFN"], 0
    )
    for record_id in (r for r in records if split.split_by_record.get(r) == "development"):
        fs, voltage = read_mitdb_record(dataset_dir, record_id, 0)
        annotations = [
            (a.sample, a.annotation_type)
            for a in parse_wfdb_annotations((dataset_dir / f"{record_id}.atr").read_bytes())
            if a.annotation_type in QRS_ANNOTATION_CODES
        ]
        width = int(WINDOW_SECONDS * fs)
        times = np.arange(width) / fs
        for start in range(0, len(voltage) - width + 1, width):
            totals["windows"] += 1
            peaks = mirror_detect(voltage[start : start + width], fs)
            beats = mirror_classify(peaks, times) if len(peaks) >= 6 else []
            references = [(s - start, t) for s, t in annotations if start <= s < start + width]
            pairs = _match([b[0] for b in beats], references, TOLERANCE_SECONDS * fs)
            totals["rTP"] += len(pairs)
            totals["rFP"] += len(beats) - len(pairs)
            totals["rFN"] += len(references) - len(pairs)
            matched = dict(pairs)
            flagged_refs = set()
            for index, (_, label) in enumerate(beats):
                if label != "prematureUncertain":
                    continue
                reference = matched.get(index)
                if reference is not None and references[reference][1] in PREMATURE_ANNOTATION_CODES:
                    totals["earlyTP"] += 1
                    flagged_refs.add(reference)
                else:
                    totals["earlyFP"] += 1
            # The first five beats of a window cannot have an RR baseline; do not count them as misses.
            totals["earlyFN"] += sum(
                1
                for index, (_, kind) in enumerate(references)
                if kind in PREMATURE_ANNOTATION_CODES and index >= 5 and index not in flagged_refs
            )

    def ratio(numerator: int, denominator: int) -> float | None:
        return round(numerator / denominator, 4) if denominator else None

    return {
        "claimStatus": "research-only-development-smoke-check",
        "algorithm": "ECGCore 1.0.1-rr-research (NumPy mirror)",
        "windowSeconds": WINDOW_SECONDS,
        "toleranceMilliseconds": TOLERANCE_SECONDS * 1_000,
        "counts": totals,
        "rPeakSensitivity": ratio(totals["rTP"], totals["rTP"] + totals["rFN"]),
        "rPeakPositivePredictivity": ratio(totals["rTP"], totals["rTP"] + totals["rFP"]),
        "prematureSensitivity": ratio(totals["earlyTP"], totals["earlyTP"] + totals["earlyFN"]),
        "prematurePositivePredictivity": ratio(totals["earlyTP"], totals["earlyTP"] + totals["earlyFP"]),
    }


def main(argv: Sequence[str] | None = None) -> int:
    tool_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-dir", type=Path, default=tool_dir / "data" / "mitdb-1.0.0")
    parser.add_argument("--split-definition", type=Path, default=tool_dir / "mitdb_split_v1.json")
    args = parser.parse_args(argv)
    try:
        report = evaluate(args.dataset_dir, args.split_definition)
    except (OSError, ValueError, KeyError) as error:
        print(f"Mirror evaluation error: {error}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
