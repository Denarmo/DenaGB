"""Tests for the desktop latency log summary (docs/specs/desktop-shell.md).

    python -m unittest discover -s tools/rig -v
"""

from __future__ import annotations

import json
import unittest

import desktop_latency


def line(p95: float, frame: float = 16.67, missed: int = 0) -> str:
    return json.dumps({
        "t_ms": 1, "frames": 60,
        "input_to_post_ms": {"p50": p95 / 2, "p95": p95, "max": p95},
        "present_ms": None,
        "frame_interval_ms": {"p50": frame, "p99": frame, "max": frame},
        "missed_frames": missed, "audio_xruns": 0, "audio_underruns": 0,
        "audio_buffer_ms": 40.0, "audio_rate": 48000,
    })


class SummaryTest(unittest.TestCase):
    def test_worst_window_plus_two_frames(self):
        s = desktop_latency.summarise([line(8.0), line(12.0), line(10.0)])
        self.assertEqual(s.lines, 3)
        self.assertEqual(s.input_p95_ms, 12.0)
        self.assertAlmostEqual(s.estimate_ms, 12.0 + 2 * 16.67)
        self.assertTrue(s.passed)

    def test_over_the_gate_fails(self):
        s = desktop_latency.summarise([line(20.0, frame=16.67)])
        self.assertFalse(s.passed)

    def test_no_input_samples(self):
        quiet = json.dumps({"t_ms": 1, "input_to_post_ms": None,
                            "frame_interval_ms": {"p50": 16.7}})
        s = desktop_latency.summarise([quiet, "", "{broken"])
        self.assertEqual(s.lines, 1)
        self.assertIsNone(s.passed)


if __name__ == "__main__":
    unittest.main()
