#!/usr/bin/env python3
"""Convert a local MIT-BIH format-212 channel to WatchBeat's raw ECG CSV contract.

Every source sample becomes one CSV row. Row position remains the original sample
index; time is sample index / sampling frequency and voltage is in millivolts.
This adapter never reads reference annotations.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from pathlib import Path
from typing import Sequence

import numpy as np


RECORD_ID_PATTERN = re.compile(r"[0-9]{3}\Z")


class MITDBConversionError(ValueError):
    """The source record is not the supported two-channel WFDB format-212 shape."""


def _parse_gain_and_baseline(signal_fields: list[str]) -> tuple[float, int]:
    if len(signal_fields) < 9 or signal_fields[1] != "212":
        raise MITDBConversionError("MIT-BIH input requires a two-channel WFDB format-212 record")
    gain_token = signal_fields[2].split("/", 1)[0]
    gain_text = gain_token.split("(", 1)[0]
    try:
        gain = float(gain_text)
        if "(" in gain_token:
            baseline = int(gain_token.split("(", 1)[1].split(")", 1)[0])
        else:
            baseline = int(signal_fields[4])
    except ValueError as error:
        raise MITDBConversionError("invalid WFDB gain or baseline") from error
    if not math.isfinite(gain) or gain <= 0:
        raise MITDBConversionError("WFDB gain must be finite and positive")
    return gain, baseline


def read_mitdb_record(
    dataset_dir: Path, record_id: str, channel: int = 0
) -> tuple[float, np.ndarray]:
    if not RECORD_ID_PATTERN.fullmatch(record_id):
        raise MITDBConversionError("MIT-BIH record ID must contain exactly three digits")
    if channel not in (0, 1):
        raise MITDBConversionError("format-212 channel must be 0 or 1")
    header_lines = [
        line.split()
        for line in (dataset_dir / f"{record_id}.hea").read_text(encoding="ascii").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    if len(header_lines) < 3 or len(header_lines[0]) < 4:
        raise MITDBConversionError("incomplete WFDB header")
    first = header_lines[0]
    try:
        signal_count = int(first[1])
        frequency_hz = float(first[2].split("/", 1)[0])
        sample_count = int(first[3])
    except ValueError as error:
        raise MITDBConversionError("invalid WFDB record header") from error
    if (
        first[0] != record_id
        or signal_count != 2
        or not math.isfinite(frequency_hz)
        or frequency_hz <= 0
        or sample_count <= 0
    ):
        raise MITDBConversionError("unsupported WFDB record header")
    data_names = [fields[0] for fields in header_lines[1:3]]
    if data_names != [f"{record_id}.dat"] * 2:
        raise MITDBConversionError("WFDB channels must share the expected local data file")
    gain, baseline = _parse_gain_and_baseline(header_lines[channel + 1])
    _parse_gain_and_baseline(header_lines[2 - channel])
    packed_bytes = (dataset_dir / f"{record_id}.dat").read_bytes()
    if len(packed_bytes) != sample_count * 3:
        raise MITDBConversionError("WFDB format-212 byte count does not match the header")
    triplets = np.frombuffer(packed_bytes, dtype=np.uint8).reshape(-1, 3).astype(np.int16)
    if channel == 0:
        values = triplets[:, 0] | ((triplets[:, 1] & 0x0F) << 8)
    else:
        values = triplets[:, 2] | ((triplets[:, 1] & 0xF0) << 4)
    signed = np.where(values >= 0x800, values - 0x1000, values)
    return frequency_hz, (signed - baseline) / gain


def convert_record(dataset_dir: Path, record_id: str, channel: int, output: Path) -> int:
    frequency_hz, millivolts = read_mitdb_record(dataset_dir, record_id, channel)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(("time_s", "voltage_mV"))
        for sample_index, millivolt in enumerate(millivolts):
            writer.writerow((repr(sample_index / frequency_hz), repr(float(millivolt))))
    return len(millivolts)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record_id")
    parser.add_argument("--channel", type=int, default=0, choices=(0, 1))
    parser.add_argument(
        "--dataset-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "data" / "mitdb-1.0.0",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        sample_count = convert_record(args.dataset_dir, args.record_id, args.channel, args.output)
    except (MITDBConversionError, OSError) as error:
        print(f"MIT-BIH conversion error: {error}", file=sys.stderr)
        return 2
    print(f"Wrote {sample_count} samples in WatchBeat raw CSV format to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
