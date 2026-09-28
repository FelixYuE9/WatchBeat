from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from evaluate_swift_analyzer_mirror import mirror_classify, mirror_detect  # noqa: E402


def _signal(early_beat_time: float) -> tuple[float, np.ndarray, np.ndarray]:
    """Same triangle-pulse waveform as ECGCore's PublicContractTests."""
    fs = 250.0
    count = int(15 * fs)
    voltage = np.zeros(count)
    beat_times = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, early_beat_time, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5, 13.5]
    for beat_time in beat_times:
        center = int(round(beat_time * fs))
        for offset in range(-5, 6):
            if 0 <= center + offset < count:
                voltage[center + offset] += max(0.0, 1 - abs(offset) / 6)
    return fs, np.arange(count) / fs, voltage


class SwiftAnalyzerMirrorTests(unittest.TestCase):
    def test_flags_the_same_early_beat_as_the_swift_contract_test(self) -> None:
        fs, times, voltage = _signal(6.2)
        peaks = mirror_detect(voltage, fs)
        early = [times[sample] for sample, label in mirror_classify(peaks, times) if label == "prematureUncertain"]

        self.assertEqual(len(peaks), 14)
        self.assertEqual(len(early), 1)
        self.assertAlmostEqual(early[0], 6.2, delta=0.04)

    def test_regular_rhythm_and_dc_offset_do_not_create_candidates(self) -> None:
        fs, times, voltage = _signal(6.5)
        peaks = mirror_detect(voltage, fs)

        self.assertEqual(mirror_detect(voltage + 0.8, fs), peaks)
        self.assertNotIn("prematureUncertain", [label for _, label in mirror_classify(peaks, times)])


if __name__ == "__main__":
    unittest.main()
