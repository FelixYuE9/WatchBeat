from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


MODULE_PATH = Path(__file__).parents[1] / "prototype_premature_beats.py"
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("prototype_premature_beats", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def synthetic_trace(early_beat: bool = True) -> MODULE.ECGTrace:
    frequency_hz = 500
    times = np.arange(15 * frequency_hz, dtype=np.float64) / frequency_hz
    beat_times = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.2 if early_beat else 6.5]
    beat_times += [7.5, 8.5, 9.5, 10.5, 11.5, 12.5, 13.5]
    voltage = np.zeros_like(times)
    for beat_time in beat_times:
        voltage += np.exp(-0.5 * ((times - beat_time) / 0.012) ** 2)
        voltage += 0.18 * np.exp(-0.5 * ((times - beat_time - 0.28) / 0.055) ** 2)
    return MODULE.ECGTrace(times, voltage)


class PrototypePrematureBeatsTests(unittest.TestCase):
    def test_detects_premature_candidate_from_waveform(self) -> None:
        report = MODULE.analyze(synthetic_trace())
        self.assertEqual(report["status"], "analyzed")
        self.assertEqual(report["inputFormat"], "watchbeat.ecg.signal.v1")
        self.assertEqual(report["schemaVersion"], 1)
        self.assertEqual(report["parameters"]["prematurityThreshold"], 0.8)
        self.assertGreaterEqual(report["summary"]["rPeakCount"], 13)
        candidates = [
            beat for beat in report["beats"] if beat["classification"] == "prematureUncertain"
        ]
        self.assertEqual(len(candidates), 1)
        self.assertAlmostEqual(candidates[0]["timeSeconds"], 6.2, delta=0.03)
        self.assertAlmostEqual(candidates[0]["prematurityRatio"], 0.7, delta=0.05)

    def test_regular_waveform_has_no_premature_candidate(self) -> None:
        report = MODULE.analyze(synthetic_trace(early_beat=False))
        self.assertEqual(report["status"], "analyzed")
        self.assertEqual(report["summary"]["prematureCandidateCount"], 0)
        self.assertTrue(
            all(
                beat["classification"] in {"normal", "notAnalyzed"}
                for beat in report["beats"]
            )
        )

    def test_missing_voltage_does_not_produce_candidates(self) -> None:
        trace = synthetic_trace()
        trace.voltage_millivolts[100] = np.nan
        report = MODULE.analyze(trace)
        self.assertEqual(report["status"], "notAnalyzed")
        self.assertEqual(report["reason"], "missingOrNonFiniteSamples")
        self.assertEqual(report["beats"], [])

    def test_irregular_sampling_does_not_produce_candidates(self) -> None:
        trace = synthetic_trace()
        trace.time_seconds[100:] += 1.0
        report = MODULE.analyze(trace)
        self.assertEqual(report["status"], "notAnalyzed")
        self.assertEqual(report["reason"], "unsupportedSamplingOrDuration")

    def test_reads_watchbeat_csv_without_changing_sample_positions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ecg.csv"
            path.write_text("time_s,voltage_mV\n0,0.1\n0.002,\n0.004,-0.2\n", encoding="utf-8")
            trace = MODULE.read_exported_csv(path)
        self.assertEqual(trace.time_seconds.tolist(), [0.0, 0.002, 0.004])
        self.assertTrue(np.isnan(trace.voltage_millivolts[1]))
        self.assertEqual(trace.voltage_millivolts[[0, 2]].tolist(), [0.1, -0.2])

    def test_rejects_malformed_watchbeat_csv(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ecg.csv"
            path.write_text("time_s,voltage_mV\n0,0.1\n0,0.2\n", encoding="utf-8")
            with self.assertRaises(MODULE.PrototypeError):
                MODULE.read_exported_csv(path)

if __name__ == "__main__":
    unittest.main()
