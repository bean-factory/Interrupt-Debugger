"""Bounded serial capture; suitable for use from a GUI worker or CLI."""

import argparse
import json
from pathlib import Path
import threading
import time

import serial

from .protocol import Capture, HEADER, MAGIC, ProtocolError, validate_header


def hardware_metadata():
    path = Path(__file__).resolve().parents[1] / "config/hardware.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"status": "UNKNOWN"}


def receive(port, timeout=5.0, cancel=None, progress=None):
    cancel = cancel or threading.Event()
    deadline = time.monotonic() + timeout

    def exact(size):
        data = bytearray()
        while len(data) < size:
            if cancel.is_set():
                raise InterruptedError("Acquisition cancelled; partial frame discarded")
            if time.monotonic() >= deadline:
                raise TimeoutError("No complete capture before deadline; partial data discarded")
            chunk = port.read(min(4096, size - len(data)))
            data.extend(chunk)
            if progress:
                progress(len(data), size)
        return bytes(data)

    magic = bytearray()
    for _ in range(4096):
        magic.extend(exact(1))
        magic = magic[-4:]
        if magic == MAGIC:
            break
    else:
        raise ProtocolError("No IRQ2 header in first 4096 bytes")
    header = MAGIC + exact(HEADER.size - 4)
    count, _, _ = validate_header(header)
    return Capture.from_packet(header + exact(count * 4 + 2))


def acquire(port_name, command="A", metadata=None, timeout=5.0, cancel=None, progress=None,
            baudrate=None):
    if command not in ("A", "C", "P"):
        raise ValueError("Capture command must be A, C, or P")
    supplied = metadata or {}
    hosted = supplied.get("target") == "fpga_hosted"
    baudrate = baudrate or supplied.get("serial_baud") or (115200 if hosted else 500000)
    setup = b""
    if hosted:
        if command not in ("C", "P"):
            raise ValueError("The FPGA-hosted target supports sequential or simultaneous capture")
        scenario = supplied.get("requested_scenario", "normal")
        programs = {"normal": b"N", "masked": b"M", "missing_eoi": b"F"}
        if scenario not in programs:
            raise ValueError("Unknown hosted firmware scenario")
        setup = b"R" + programs[scenario]
    with serial.Serial(port_name, baudrate, timeout=0.05, write_timeout=1) as port:
        port.reset_input_buffer()
        port.write(setup + command.encode("ascii"))
        port.flush()
        try:
            capture = receive(port, timeout, cancel, progress)
        except (InterruptedError, TimeoutError, ProtocolError):
            port.write(b"R")
            port.flush()
            raise
    manifest = supplied.get("hardware_manifest", hardware_metadata())
    is_self_test = manifest.get("fpga_self_test") is True
    capture.metadata = {**supplied, "hardware_manifest": manifest,
                         "origin": "FPGA self-test via serial" if is_self_test else
                         "FPGA-hosted CPU/PIC via RS-232" if hosted else "serial",
                        "synthetic": bool(supplied.get("synthetic") or is_self_test),
                         "serial_port": port_name, "command": command,
                         "serial_baud": baudrate,
                         "target_provenance": "Operator-selected target; device identity not queried",
                         "host_time": time.time(), "decoder_version": "0.2.0"}
    return capture


def clear_device(port_name, baudrate=500000):
    with serial.Serial(port_name, baudrate, timeout=0.05, write_timeout=1) as port:
        port.write(b"R")
        port.flush()


def main():
    parser = argparse.ArgumentParser(description="Interrupt Debugger packet acquisition; board setup must be verified separately")
    parser.add_argument("--port", required=True)
    parser.add_argument("--command", choices=["A", "C", "P", "R"])
    parser.add_argument("--metadata", type=Path, help="Explicit operator-supplied profile/provenance JSON")
    parser.add_argument("--out", type=Path, default=Path("captures/latest"))
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--allow-stimulus", action="store_true", help="I verified wiring and isolated competing IR1/IR3 drivers")
    parser.add_argument("--target", choices=["external", "fpga_hosted"], default="external")
    parser.add_argument("--scenario", choices=["normal", "masked", "missing_eoi"], default="normal")
    parser.add_argument("--baud", type=int)
    args = parser.parse_args()
    args.command = args.command or ("C" if args.target == "fpga_hosted" else "A")
    if args.target == "fpga_hosted" and args.command == "A":
        parser.error("The FPGA-hosted target supports --command C or P, not passive A")
    if args.command == "R":
        clear_device(args.port, args.baud or (115200 if args.target == "fpga_hosted" else 500000))
        return
    if args.target == "external" and args.command in "CP" and not args.allow_stimulus:
        parser.error("C/P requires --allow-stimulus after physical safety checks; use A for passive recording")
    metadata = json.loads(args.metadata.read_text()) if args.metadata else {}
    metadata.update(target=args.target, requested_scenario=args.scenario)
    capture = acquire(args.port, args.command, metadata, args.timeout, baudrate=args.baud)
    capture.save(args.out)
    print(f"Saved {len(capture.samples)} verified packet samples to {args.out}")


if __name__ == "__main__":
    main()
