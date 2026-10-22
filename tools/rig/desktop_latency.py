"""Summarise a desktop latency log against the 50 ms gate.

The desktop host library appends one metrics line per second while a game
plays when an empty ``latency`` file sits in the storage root, or with
``DENA_LATENCY_LOG=1`` (docs/specs/desktop-shell.md, Latency). This reads
``<root>/logs/latency.jsonl`` and prints the worst one-second windows.

The software numbers stop at the frame handed to Flutter; Flutter then needs
up to two display frames to composite and show it, and the panel adds its
scan-out. So the estimate is ``p95 input_to_post + 2 frames``, a lower bound
for input-to-photon. The probe (docs/specs/rig.md) gives the real figure.

    python tools/rig/desktop_latency.py %APPDATA%\\Dena.emu\\logs\\latency.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass

GATE_MS = 50.0
COMPOSITE_FRAMES = 2


@dataclass
class Summary:
    lines: int
    input_p95_ms: float | None
    frame_ms: float | None
    missed_frames: int
    audio_underruns: int
    estimate_ms: float | None

    @property
    def passed(self) -> bool | None:
        return None if self.estimate_ms is None else self.estimate_ms < GATE_MS


def summarise(lines: list[str]) -> Summary:
    rows = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # a line cut short when the app closed
    inputs = [r["input_to_post_ms"]["p95"] for r in rows if r.get("input_to_post_ms")]
    frames = [r["frame_interval_ms"]["p50"] for r in rows if r.get("frame_interval_ms")]
    input_p95 = max(inputs) if inputs else None
    frame = sorted(frames)[len(frames) // 2] if frames else None
    last = rows[-1] if rows else {}
    estimate = (
        None if input_p95 is None or frame is None else input_p95 + COMPOSITE_FRAMES * frame
    )
    return Summary(
        lines=len(rows),
        input_p95_ms=input_p95,
        frame_ms=frame,
        missed_frames=int(last.get("missed_frames", 0)),
        audio_underruns=int(last.get("audio_underruns", 0)),
        estimate_ms=estimate,
    )


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("log", help="latency.jsonl from the storage root's logs folder")
    args = ap.parse_args(argv)
    with open(args.log, encoding="utf-8") as f:
        s = summarise(f.readlines())
    if s.estimate_ms is None:
        print(f"{s.lines} lines, no input samples: press buttons while the game runs")
        return 2
    print(f"lines {s.lines}  worst p95 input-to-post {s.input_p95_ms:.1f} ms  "
          f"frame {s.frame_ms:.2f} ms  missed {s.missed_frames}  "
          f"audio underruns {s.audio_underruns}")
    verdict = "PASS" if s.passed else "FAIL"
    print(f"estimate {s.estimate_ms:.1f} ms (+{COMPOSITE_FRAMES} frames to composite) "
          f"vs gate {GATE_MS:.0f} ms: {verdict}")
    return 0 if s.passed else 1


if __name__ == "__main__":
    sys.exit(main())
