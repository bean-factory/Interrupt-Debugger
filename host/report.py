"""Export decoded events and capture metadata for offline use."""

import argparse
from dataclasses import asdict
import csv
import json
from pathlib import Path

from .explain import analyze
from .protocol import Capture


def write_report(capture, directory, events=None):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    events = analyze(capture) if events is None else events
    with (directory / "events.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["id", "kind", "start_sample", "end_sample", "start_us", "confidence", "description", "why", "evidence"])
        for event in events:
            writer.writerow([event.id, event.kind, event.start, event.end,
                             event.start / capture.sample_rate * 1e6, event.confidence,
                             event.description, event.why, ";".join(event.evidence)])
    (directory / "events.json").write_text(json.dumps([asdict(e) for e in events], indent=2), encoding="utf-8")
    origin = "SYNTHETIC CAPTURE (generated test data)" if capture.metadata.get("synthetic") else capture.metadata.get("origin", "Unknown origin")
    summary = ["Interrupt Debugger", str(origin), f"{len(capture.samples)} samples at {capture.sample_rate} samples/s",
               f"PIC configuration source: {(capture.metadata.get('profile') or {}).get('provenance', 'unknown')}",
               "Internal state is predicted unless backed by an identified register read.",
               "EOI does not prove IRET; CPU IF and execution duration are not directly visible.", ""]
    summary += [f"{e.start/capture.sample_rate*1e6:.3f} us [{e.confidence}] {e.description}\n  {e.why}"
                for e in events if e.why or e.kind in ("warning", "diagnosis")]
    (directory / "summary.txt").write_text("\n".join(summary), encoding="utf-8")
    return events


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    destination = args.out or (args.capture if args.capture.is_dir() else args.capture.parent)
    events = write_report(Capture.load(args.capture), destination)
    print(f"Wrote {len(events)} events to {destination}")


if __name__ == "__main__":
    main()
