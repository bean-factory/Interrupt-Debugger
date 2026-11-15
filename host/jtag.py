"""Capture through the ISE VM's host-only TCP-to-JTAG bridge."""

import argparse
from datetime import datetime
from pathlib import Path
import socket
import threading
import time

from .capture import hardware_metadata, receive
from .protocol import ProtocolError


def address(endpoint):
    host, separator, port = endpoint.strip().rpartition(":")
    if not separator or not host:
        raise ValueError("Enter the JTAG bridge address as host:port")
    try:
        number = int(port)
    except ValueError as exc:
        raise ValueError("The bridge port must be a number") from exc
    if not 1 <= number <= 65535:
        raise ValueError("The bridge port must be between 1 and 65535")
    return host, number


class BridgeReader:
    def __init__(self, connection):
        self.connection = connection

    def read(self, count):
        try:
            data = self.connection.recv(count)
        except socket.timeout:
            return b""
        if not data:
            raise ConnectionError("The JTAG bridge closed the connection")
        return data


def response_line(connection, cancel, deadline, board=False):
    result = bytearray()
    while len(result) < 512:
        if cancel.is_set():
            raise InterruptedError("Capture cancelled")
        if time.monotonic() >= deadline:
            raise TimeoutError("The JTAG bridge did not respond in time")
        try:
            byte = connection.recv(1)
        except socket.timeout:
            continue
        if not byte:
            raise ConnectionError("The JTAG bridge closed the connection")
        if byte == b"\n":
            message = result.decode("utf-8", errors="replace").strip()
            if message.startswith("ERR "):
                raise RuntimeError(message[4:])
            if board:
                if message not in tuple("OK BOARD " + name + " " + pattern for name in ("normal", "masked_ir1", "masked", "missing_eoi") for pattern in ("C", "P")):
                    raise ProtocolError("Unexpected board-capture response")
            elif message != "OK":
                raise ProtocolError("Unexpected JTAG bridge response")
            return message
        result.extend(byte)
    raise ProtocolError("JTAG bridge response is too long")


def acquire(endpoint, command="C", metadata=None, timeout=30, cancel=None, progress=None):
    supplied = metadata or {}
    scenario = supplied.get("requested_scenario", "normal")
    if command not in ("C", "P", "B") or (command != "B" and scenario not in ("normal", "masked_ir1", "masked", "missing_eoi")):
        raise ValueError("Choose a built-in firmware program and sequential or simultaneous capture")
    cancel = cancel or threading.Event()
    if cancel.is_set():
        raise InterruptedError("Capture cancelled")
    deadline = time.monotonic() + timeout
    with socket.create_connection(address(endpoint), timeout=min(timeout, 5)) as connection:
        connection.settimeout(0.05)
        connection.sendall(b"READ_BOARD\n" if command == "B" else f"CAPTURE {scenario} {command}\n".encode("ascii"))
        try:
            response = response_line(connection, cancel, deadline, board=command == "B")
            board_mode = response.split()[2] if command == "B" else None
            board_pattern = response.split()[3] if command == "B" else None
            if board_mode:
                scenario = board_mode
            capture = receive(BridgeReader(connection), max(0.001, deadline-time.monotonic()), cancel, progress)
            if capture.flags != (8 if command == "P" or board_pattern == "P" else 0):
                raise ProtocolError("The FPGA capture pattern does not match the request")
            if command == "B":
                connection.sendall(b"RECEIVED\n")
                response_line(connection, cancel, min(deadline, time.monotonic()+5))
        except (InterruptedError, TimeoutError, ProtocolError):
            try:
                connection.sendall(b"CANCEL\n")
            except OSError:
                pass
            raise
    capture.metadata = {
        **supplied, "target": "fpga_jtag", "profile": None,
        "origin": "FPGA-hosted CPU/PIC via USB-JTAG",
        "target_provenance": "Interrupt Debugger JTAG v3 frozen condition/timing and CRC checked" + ("; read acknowledged" if command == "B" else "; diagnostic acquisition"),
        "synthetic": bool(supplied.get("synthetic")), "jtag_bridge": endpoint,
        "hardware_manifest": supplied.get("hardware_manifest", hardware_metadata()),
        "command": command, "requested_scenario": scenario,
        "board_mode": board_mode,
        "board_pattern": board_pattern,
        "host_time": time.time(), "decoder_version": "0.2.0",
    }
    return capture


def clear_device(endpoint, timeout=10):
    with socket.create_connection(address(endpoint), timeout=min(timeout, 5)) as connection:
        connection.settimeout(0.05)
        connection.sendall(b"CLEAR\n")
        response_line(connection, threading.Event(), time.monotonic()+timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", default=hardware_metadata().get("jtag_bridge", "127.0.0.1:9374"))
    parser.add_argument("--command", choices=["B", "C", "P", "R"], default="B")
    parser.add_argument("--scenario", choices=["normal", "masked", "missing_eoi"], default="normal")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.command == "R":
        clear_device(args.bridge)
        return
    destination = args.out or Path("captures/jtag") / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    if (destination / "capture.bin").exists():
        parser.error("The output folder already contains a capture; choose another folder")
    capture = acquire(args.bridge, args.command, {"requested_scenario": args.scenario}, timeout=90 if args.command == "B" else 30)
    capture.save(destination)
    print(f"Saved {len(capture.samples):,} samples to {destination}")


if __name__ == "__main__":
    main()
