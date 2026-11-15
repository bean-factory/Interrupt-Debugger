"""Decode sampled requests and PIC bus transactions."""

from dataclasses import dataclass, field
import numpy as np

from .protocol import Capture


@dataclass
class Event:
    id: str
    kind: str
    start: int
    end: int
    fields: dict = field(default_factory=dict)
    confidence: str = "observed"
    evidence: list[str] = field(default_factory=list)
    description: str = ""
    why: str = ""
    state: dict = field(default_factory=dict)


def runs(active):
    """Half-open intervals; retain boundary flags instead of inventing edges."""
    a = np.asarray(active, dtype=bool)
    edges = np.diff(np.r_[False, a, False].astype(np.int8))
    return list(zip(np.flatnonzero(edges == 1).tolist(),
                    np.flatnonzero(edges == -1).tolist()))


def decode(capture: Capture) -> list[Event]:
    samples = capture.samples
    n = len(samples)
    events = []

    def add(kind, start, end, fields=None, confidence="observed", description="", evidence=None):
        event = Event(f"e{len(events):04d}", kind, int(start), int(end), fields or {},
                      confidence, evidence or [], description)
        events.append(event)
        return event

    def stable(start, end, mask):
        # Default 20 ns sampling: exclude the final two samples (40 ns) and
        # require a three-sample (60 ns) stable plateau. Board timing must verify
        # this window. Synchronizers alone do not establish bus coherence.
        if start == 0 or end == n or end - start < 7:
            return None
        values = samples[end - 5:end - 2] & np.uint32(mask)
        return int(values[0]) if len(values) == 3 and np.all(values == values[0]) else None

    for irq in range(8):
        values = ((samples >> (8 + irq)) & 1).astype(bool)
        for start, end in runs(values):
            add("request_present" if start == 0 else "request", start, end,
                {"irq": irq}, description=f"IR{irq} " + (
                    "already high at capture start; earlier edge unknown" if start == 0 else "asserted"))
    for start, end in runs((samples & (1 << 16)) != 0):
        add("int", start, end, {"boundary": start == 0}, description="PIC INT asserted")

    ack_runs = runs((samples & (1 << 17)) == 0)
    aligned = not ack_runs or ack_runs[0][0] != 0
    if not aligned:
        add("warning", 0, ack_runs[0][1], confidence="unknown",
            description="Capture starts inside /INTA; acknowledge pairing is unknown")
    pending = None
    max_gap = max(1, round(capture.sample_rate * 10e-6))
    for start, end in ack_runs:
        if end == n:
            add("warning", start, end, confidence="unknown", description="Truncated acknowledge pulse")
            continue
        if not aligned:
            add("ack_unknown", start, end, confidence="unknown", description="Unpaired /INTA pulse")
            continue
        if pending is not None and start - pending.end > max_gap:
            add("warning", pending.start, pending.end, confidence="unknown",
                description="No adjacent ACK2 within configured 10 us pairing window")
            pending = None
        if pending is None:
            pending = add("ack1", start, end, description="ACK1: controller accepts a request")
        else:
            second = add("ack2", start, end, description="ACK2: vector transfer")
            value = stable(start, end, 255)
            if value is None:
                add("warning", start, end, confidence="unknown",
                    description="ACK2 data lacks a complete stable decoding window",
                    evidence=[pending.id, second.id])
            else:
                add("vector", start, end, {"value": value},
                    description=f"Vector {value:02X}h", evidence=[pending.id, second.id])
            pending = None
    if pending is not None:
        add("warning", pending.start, pending.end, confidence="unknown", description="ACK1 without captured ACK2")

    for bit, kind in [(19, "write"), (20, "read")]:
        active = ((samples & (1 << 18)) == 0) & ((samples & (1 << bit)) == 0)
        for start, end in runs(active):
            value = stable(start, end, 255 | (1 << 21))
            if value is None:
                add("warning", start, end, confidence="unknown",
                    description=f"PIC {kind} has truncated/unstable data or register select")
            else:
                a0 = (value >> 21) & 1
                add(kind, start, end, {"value": value & 255, "a0": a0},
                    description=f"PIC {'data' if a0 else 'command'} {kind}: {value & 255:02X}h")
    # IRQ edges happen at assertion; bus transactions update state on completion.
    return sorted(events, key=lambda e: (e.start if e.kind in ("request", "request_present", "int", "ack1") else e.end, e.id))
