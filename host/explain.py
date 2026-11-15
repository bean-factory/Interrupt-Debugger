"""Track single-PIC state and attach explanations to decoded events."""

from .decode import Event, decode
from .protocol import Capture


def default_profile(mask=0xF5, base=0x20):
    return {"vector_base": base, "mask": mask, "initial_isr": 0,
            "initial_pending": 0, "single": True, "mode_8086": True,
            "edge_triggered": True, "fixed_priority": True, "manual_eoi": True,
             "provenance": "Test configuration; initialization not captured."}


def analyze(capture: Capture) -> list[Event]:
    events = decode(capture)
    supplied = capture.metadata.get("profile")
    p = supplied if isinstance(supplied, dict) else {}
    keys = ("single", "mode_8086", "edge_triggered", "fixed_priority", "manual_eoi")
    supported = bool(p) and all(p.get(k) is True for k in keys)
    base, mask = p.get("vector_base"), p.get("mask")
    isr, pending = p.get("initial_isr"), p.get("initial_pending")
    provenance = p.get("provenance", "unknown initial configuration")
    if base is not None and (not isinstance(base, int) or base < 0 or base > 248 or base & 7):
        supported = False
        base = None
    def byte_or_unknown(value):
        return value if isinstance(value, int) and 0 <= value <= 255 else None
    mask, isr, pending = map(byte_or_unknown, (mask, isr, pending))
    init = None
    read_select = None
    last_vector = {}
    last_int = None
    ack_in_progress = False
    eligible_at_ack1 = None

    def known():
        return supported and all(x is not None for x in (base, mask, isr, pending))

    def blockers(irq):
        return [i for i in range(irq + 1) if isr is not None and isr & (1 << i)]

    for event in events:
        f = event.fields
        if event.kind == "warning":
            supported = False
            event.why = "The transaction history is incomplete or ambiguous. State tracking is paused until a known initialization sequence."
        elif event.kind == "int":
            last_int = event
            event.why = "The controller is requesting CPU attention; this is not proof the CPU accepted it."
        elif event.kind == "request":
            irq = f["irq"]
            if known():
                pending |= 1 << irq
                if ack_in_progress:
                    event.why = "A request changed during acknowledgement. Its latch timing is uncertain, so state tracking is paused."
                    event.confidence = "unknown"
                    supported = False
                elif mask & (1 << irq):
                    event.why = f"IR{irq} is masked: IMR bit {irq} is 1."
                elif blockers(irq):
                    block = blockers(irq)[0]
                    event.why = (f"IR{irq} is blocked by in-service IR{block} under the known fixed-priority/manual-EOI profile. "
                                 "No clearing EOI has been observed since that service.")
                    if block in last_vector:
                        event.evidence.append(last_vector[block])
                else:
                    event.why = f"IR{irq} is eligible: it is unmasked, with no higher-priority or equal-priority IRQ tracked in service."
                if event.confidence != "unknown":
                    event.confidence = "inferred"
            else:
                event.why = "Request observed, but the PIC configuration or starting state is unknown or unsupported; no causal diagnosis."
        elif event.kind == "request_present":
            event.why = "The request was already high when capture began. Its rising edge and earlier history were not recorded."
        elif event.kind == "ack1":
            ack_in_progress = True
            eligible_at_ack1 = None
            if known():
                eligible_at_ack1 = pending & ~mask & 255
                if isr:
                    eligible_at_ack1 &= (1 << min(i for i in range(8) if isr & (1 << i))) - 1
            if last_int is not None:
                delay = max(0, event.start - last_int.start)
                event.fields["int_to_ack_us"] = delay / capture.sample_rate * 1e6
                event.why = (f"Observed INT-to-ACK1 interval: {event.fields['int_to_ack_us']:.3f} us. "
                             "These pins do not reveal CPU IF, CLI/STI, or the current instruction.")
                event.evidence.append(last_int.id)
        elif event.kind == "vector":
            ack_in_progress = False
            value = f["value"]
            if base is not None and base <= value < base + 8:
                irq = value - base
                f["irq"] = irq
                event.description += f" → IR{irq}"
                event.why = f"ACK2 carried {value:02X}h; configured vector base {base:02X}h maps it to IR{irq}."
                if known():
                    eligible = eligible_at_ack1 if eligible_at_ack1 is not None else 0
                    choices = [i for i in range(8) if eligible & (1 << i)]
                    if len(choices) > 1 and choices[0] == irq:
                        event.why += f" Pending eligible levels {choices}: fixed priority selects IR{irq}."
                    elif choices and choices[0] != irq:
                        event.why += " Selection differs from the prediction; inspect source timing/context."
                    pending &= ~(1 << irq)
                    isr |= 1 << irq
                    last_vector[irq] = event.id
                    event.why += " The model now marks that IRQ in service."
            else:
                event.why = "Vector byte observed; vector base is unknown or the byte is outside its configured range."
                supported = False
        elif event.kind == "write":
            value, a0 = f["value"], f["a0"]
            if not a0 and value & 0x10:
                init = {"stage": "icw2", "single": bool(value & 2),
                        "edge": not bool(value & 8), "icw4": bool(value & 1)}
                supported = False
                isr = pending = 0
                mask = 0
                read_select = None
                event.description = f"ICW1 {value:02X}h: initialization begins"
                event.why = "State tracking resumes when the initialization sequence is complete."
            elif a0 and init is not None:
                stage = init["stage"]
                if stage == "icw2":
                    base = value & 0xF8
                    init["stage"] = "icw3" if not init["single"] else "icw4"
                elif stage == "icw3":
                    init["stage"] = "icw4"
                elif stage == "icw4":
                    supported = init["single"] and init["edge"] and bool(value & 1) and not bool(value & 0x1E)
                    provenance = "captured initialization; predicted state thereafter"
                    init = None
                event.description = f"{stage.upper()} {value:02X}h"
                if init is not None and not init["icw4"] and init["stage"] == "icw4":
                    init = None  # MCS-80 mode is outside scope.
                    supported = False
            elif a0:
                mask = value
                event.description = f"IMR ← {value:02X}h"
                event.why = "OCW1: 1 masks the corresponding IRQ; 0 unmasks it."
            elif value == 0x20 or value & 0xF8 == 0x60:
                specific = value != 0x20
                irq = (value & 7) if specific else (
                    min((i for i in range(8) if isr is not None and isr & (1 << i)), default=None))
                f["eoi_irq"] = irq
                event.kind = "eoi"
                event.description = "EOI" + (f" IR{irq}" if irq is not None else " (level unknown)")
                event.why = "EOI updates the PIC in-service state; it does not prove IRET or handler completion."
                if known() and irq is not None:
                    isr &= ~(1 << irq)
                    eligible = pending & ~mask & 255
                    if isr:
                        eligible &= (1 << min(i for i in range(8) if isr & (1 << i))) - 1
                    released = [i for i in range(8) if eligible & (1 << i)]
                    if released:
                        event.why += f" Predicted eligible requests after EOI: {released}."
            elif value & 0x18 == 0x08:
                if value & 4 or value & 0x40:
                    supported = False
                    event.why = "Polling and special-mask mode are not supported. State tracking is paused."
                if value & 2:
                    read_select = "isr" if value & 1 else "irr"
                event.description = f"OCW3 {value:02X}h"
            elif value != 0:
                supported = False
                event.why = "This control command is outside the supported profile. State tracking is paused until reinitialization."
        elif event.kind == "read":
            value, a0 = f["value"], f["a0"]
            register = "IMR" if a0 else (read_select or "unknown register").upper()
            event.description = f"Read {register} = {value:02X}h"
            event.why = "This byte was directly observed on a qualified PIC read."
            if a0:
                mask = value
            elif read_select == "isr":
                isr = value
            elif read_select == "irr":
                pending = value
        event.state = {"mask": mask, "predicted_isr": isr, "predicted_pending": pending,
                       "vector_base": base, "supported": supported,
                       "context": provenance, "model_known": known()}

    if known():
        for irq in range(8):
            if pending & (1 << irq):
                blocked = blockers(irq)
                if mask & (1 << irq):
                    text = f"The model still has IR{irq} pending at capture end, but its mask bit is set."
                elif blocked:
                    text = f"The model predicts IR{irq} is blocked by in-service IR{blocked[0]} at capture end. No clearing EOI was captured."
                else:
                    text = f"The model still has IR{irq} pending at capture end. Later service is outside this recording."
                events.append(Event(f"diagnosis-{irq}", "diagnosis", len(capture.samples)-1,
                                    len(capture.samples), {"irq": irq}, "inferred",
                                    [last_vector[i] for i in blocked if i in last_vector],
                                    text, text, dict(events[-1].state) if events else {}))
    return sorted(events, key=lambda e: (e.start, e.end, e.id))
