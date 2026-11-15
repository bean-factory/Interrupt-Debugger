"""IRQ2 packet framing, validation and CRC."""

from dataclasses import dataclass, field
import binascii
import json
from pathlib import Path
import struct

import numpy as np

MAGIC = b"IRQ2"
HEADER = struct.Struct("<4sIII")
MAX_SAMPLES = 32768
CHANNEL_MASK = (1 << 22) - 1
CHANNELS = [f"D{i}" for i in range(8)] + [f"IR{i}" for i in range(8)] + [
    "INT", "/INTA", "/CS", "/WR", "/RD", "A0"]


class ProtocolError(ValueError):
    pass


def crc16(data: bytes) -> int:
    """CCITT-FALSE; check vector b'123456789' -> 0x29B1."""
    return binascii.crc_hqx(data, 0xFFFF)


def validate_header(header: bytes) -> tuple[int, int, int]:
    if len(header) != HEADER.size:
        raise ProtocolError("Incomplete IRQ2 header")
    magic, count, rate, flags = HEADER.unpack(header)
    if magic != MAGIC:
        raise ProtocolError("Not an IRQ2 packet")
    if not 1 <= count <= MAX_SAMPLES:
        raise ProtocolError(f"Sample count outside 1..{MAX_SAMPLES}: {count}")
    if not 1 <= rate <= 100_000_000:
        raise ProtocolError(f"Invalid sample rate: {rate}")
    if flags & ~15:
        raise ProtocolError("Unknown packet flags")
    if flags & 6 and not flags & 1:
        raise ProtocolError("Passive trigger flags without passive mode")
    if flags & 1 and flags & 8:
        raise ProtocolError("Passive and generated pattern flags conflict")
    return count, rate, flags


@dataclass
class Capture:
    samples: np.ndarray
    sample_rate: int = 50_000_000
    flags: int = 0
    metadata: dict = field(default_factory=dict)
    packet: bytes | None = None

    @classmethod
    def from_packet(cls, packet: bytes, metadata: dict | None = None):
        if metadata is not None and not isinstance(metadata, dict):
            raise ProtocolError("Metadata must be a JSON object")
        if metadata and metadata.get("profile") is not None and not isinstance(metadata["profile"], dict):
            raise ProtocolError("Profile must be an object or null")
        count, rate, flags = validate_header(packet[:HEADER.size])
        expected = HEADER.size + count * 4 + 2
        if len(packet) != expected:
            raise ProtocolError(f"Packet length {len(packet)} != expected {expected}")
        if crc16(packet[:-2]) != int.from_bytes(packet[-2:], "big"):
            raise ProtocolError("CRC mismatch: do not decode corrupted data")
        samples = np.frombuffer(packet, dtype="<u4", offset=HEADER.size,
                                count=count).copy()
        if np.any(samples & np.uint32(~CHANNEL_MASK & 0xFFFFFFFF)):
            raise ProtocolError("Reserved sample bits 22..31 are not zero")
        return cls(samples, rate, flags, metadata or {}, packet)

    def to_packet(self) -> bytes:
        values = np.asarray(self.samples)
        if values.ndim != 1 or values.dtype.kind not in "ui":
            raise ProtocolError("Samples must be a one-dimensional unsigned/integer array")
        if np.any(values < 0) or np.any(values > CHANNEL_MASK):
            raise ProtocolError("Samples contain out-of-map bits")
        header = HEADER.pack(MAGIC, len(values), self.sample_rate, self.flags)
        validate_header(header)
        body = header + values.astype("<u4").tobytes()
        return body + crc16(body).to_bytes(2, "big")

    def save(self, directory: str | Path):
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        packet = self.packet if self.packet is not None else self.to_packet()
        checked = Capture.from_packet(packet)
        if (checked.sample_rate != self.sample_rate or checked.flags != self.flags
                or not np.array_equal(checked.samples, self.samples)):
            raise ProtocolError("Raw packet and in-memory capture disagree")
        (directory / "capture.bin").write_bytes(packet)
        metadata = {**self.metadata, "format": "IRQ2", "channel_map": CHANNELS,
                    "sample_count": len(self.samples), "sample_rate": self.sample_rate,
                    "packet_flags": self.flags}
        (directory / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    @classmethod
    def load(cls, path: str | Path):
        path = Path(path)
        directory = path if path.is_dir() else path.parent
        packet_path = directory / "capture.bin" if path.is_dir() else path
        meta_path = directory / "metadata.json"
        metadata = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
        capture = cls.from_packet(packet_path.read_bytes(), metadata)
        for key, actual in [("sample_count", len(capture.samples)),
                            ("sample_rate", capture.sample_rate), ("packet_flags", capture.flags)]:
            if key in metadata and metadata[key] != actual:
                raise ProtocolError(f"Sidecar {key} disagrees with packet")
        return capture
