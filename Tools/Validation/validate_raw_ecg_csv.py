#!/usr/bin/env python3
"""Validate the lossless structural contract of an exported raw ECG CSV."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Optional


EXPECTED_HEADER = ["time_s", "voltage_mV"]


class CSVContractError(ValueError):
    """Raised when an export cannot be interpreted without guessing."""


@dataclass(frozen=True)
class RawECGCSVReport:
    sample_count: int
    missing_voltage_indices: list[int]
    non_finite_time_indices: list[int]
    non_finite_voltage_indices: list[int]
    duplicate_timestamp_indices: list[int]
    decreasing_timestamp_indices: list[int]
    median_sampling_interval_seconds: Optional[float]
    inferred_sampling_rate_hz: Optional[float]
    sampling_interval_relative_mad: Optional[float]

    @property
    def structurally_valid(self) -> bool:
        return not (
            self.non_finite_time_indices
            or self.non_finite_voltage_indices
            or self.duplicate_timestamp_indices
            or self.decreasing_timestamp_indices
        )


def parse_rows(rows: Iterable[dict[str, str]]) -> tuple[list[float], list[Optional[float]]]:
    times: list[float] = []
    voltages: list[Optional[float]] = []

    for index, row in enumerate(rows):
        try:
            raw_time = row["time_s"].strip()
            raw_voltage = row["voltage_mV"].strip()
        except (KeyError, AttributeError) as error:
            raise CSVContractError(f"row {index + 2}: missing required column") from error

        if not raw_time:
            raise CSVContractError(f"row {index + 2}: time_s must not be blank")

        try:
            times.append(float(raw_time))
        except ValueError as error:
            raise CSVContractError(f"row {index + 2}: invalid time_s") from error

        if raw_voltage == "":
            voltages.append(None)
        else:
            try:
                voltages.append(float(raw_voltage))
            except ValueError as error:
                raise CSVContractError(f"row {index + 2}: invalid voltage_mV") from error

    return times, voltages


def inspect(times: list[float], voltages: list[Optional[float]]) -> RawECGCSVReport:
    if len(times) != len(voltages):
        raise CSVContractError("time and voltage sample counts differ")

    missing = [index for index, value in enumerate(voltages) if value is None]
    non_finite_times = [index for index, value in enumerate(times) if not math.isfinite(value)]
    non_finite_voltages = [
        index
        for index, value in enumerate(voltages)
        if value is not None and not math.isfinite(value)
    ]
    duplicates: list[int] = []
    decreasing: list[int] = []
    positive_finite_deltas: list[float] = []

    for index in range(1, len(times)):
        previous = times[index - 1]
        current = times[index]
        if not (math.isfinite(previous) and math.isfinite(current)):
            continue
        delta = current - previous
        if delta == 0:
            duplicates.append(index)
        elif delta < 0:
            decreasing.append(index)
        else:
            positive_finite_deltas.append(delta)

    median_delta = (
        statistics.median(positive_finite_deltas) if positive_finite_deltas else None
    )
    inferred_rate = 1.0 / median_delta if median_delta is not None and median_delta > 0 else None
    relative_mad = None
    if median_delta is not None and median_delta > 0:
        deviations = [abs(delta - median_delta) for delta in positive_finite_deltas]
        relative_mad = statistics.median(deviations) / median_delta

    return RawECGCSVReport(
        sample_count=len(times),
        missing_voltage_indices=missing,
        non_finite_time_indices=non_finite_times,
        non_finite_voltage_indices=non_finite_voltages,
        duplicate_timestamp_indices=duplicates,
        decreasing_timestamp_indices=decreasing,
        median_sampling_interval_seconds=median_delta,
        inferred_sampling_rate_hz=inferred_rate,
        sampling_interval_relative_mad=relative_mad,
    )


def inspect_file(path: Path) -> RawECGCSVReport:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != EXPECTED_HEADER:
            raise CSVContractError(
                f"expected header {','.join(EXPECTED_HEADER)!r}, got {reader.fieldnames!r}"
            )
        times, voltages = parse_rows(reader)
    return inspect(times, voltages)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path)
    args = parser.parse_args(argv)

    try:
        report = inspect_file(args.csv_path)
    except (CSVContractError, OSError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2

    payload = asdict(report)
    payload["structurally_valid"] = report.structurally_valid
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if report.structurally_valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
