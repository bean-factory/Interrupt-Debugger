# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the hosted CPU ROM inputs and ISE-compatible PIC source.

Upstream sources remain unmodified. Requires NASM and sv2v on PATH, or their
project-local installations under build/. Generated build inputs are retained in
rtl/hosted/generated so an ISE VM does not need these development tools.
The microcode packing follows Zet's micro2rom script by Zeus Gomez Marmolejo.
"""

import argparse
from collections import OrderedDict
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "rtl/hosted/generated"


def executable(name, candidate):
    path = shutil.which(name)
    if path:
        return path
    if candidate.exists():
        return str(candidate)
    raise SystemExit(f"{name} is required on PATH; see README.md")


def microcode():
    source = ROOT / "third_party/zet/upstream/cores/zet/rtl/altera/microcode.txt"
    instructions = OrderedDict()
    for block in source.read_text().split("######")[1:]:
        for line in block.splitlines()[1:]:
            match = re.match(r"\s*([A-Z][A-Z0-9]{2,5})\s+([01xdms_]+)\s*(?://.*)?$", line)
            if not match or "__" not in match[2]:
                break
            instructions.setdefault(match[1], []).append(match[2])
    if not instructions:
        raise ValueError("No Zet microinstructions found")
    words, definitions = [], []
    for name, codes in instructions.items():
        definitions.append((name, len(words)))
        for index, code in enumerate(codes):
            bits = re.sub("[xdms]", "0", code.replace("_", ""))
            words.append(str(int(index == len(codes) - 1)) + bits)
    width = len(words[0])
    assert all(len(word) == width for word in words)
    address_bits = (len(words) - 1).bit_length()
    words += ["0" * width] * ((1 << address_bits) - len(words))
    (OUT / "micro_rom.dat").write_text("\n".join(words) + "\n")
    header = [f"`define MICRO_DATA_WIDTH {width}", f"`define MICRO_ADDR_WIDTH {address_bits}"]
    header += [f"`define {name} {address_bits}'d{address}" for name, address in definitions]
    (OUT / "rom_def.v").write_text("\n".join(header) + "\n")
    return {"word_bits": width, "words": len(words), "sequences": len(instructions)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    nasm = executable("nasm", ROOT / "build/sim-tools/ucrt64/bin/nasm.exe")
    sv2v = executable("sv2v", ROOT / "build/sv2v/sv2v-Windows/sv2v.exe")
    rom = microcode()
    firmware = []
    words = []
    for scenario in range(4):
        destination = OUT / f"scenario{scenario}.bin"
        subprocess.run([nasm, "-f", "bin", f"-DSCENARIO={scenario}",
                        str(ROOT / "firmware/fpga_demo.asm"), "-o", str(destination)],
                       check=True, timeout=30)
        data = destination.read_bytes()
        if len(data) > 2048:
            raise ValueError("Firmware exceeds its 2 KiB ROM page")
        firmware.append({"scenario": scenario, "bytes": len(data),
                         "sha256": hashlib.sha256(data).hexdigest()})
        page = data + b"\x90" * (2048 - len(data))
        words += [f"{int.from_bytes(page[index:index+2], 'little'):04x}" for index in range(0, 2048, 2)]
    # Four firmware pages fit the existing 4096-word block ROM.
    (OUT / "program.hex").write_text("\n".join(words) + "\n")
    pic = ROOT / "third_party/kf8259/upstream/HDL"
    result = subprocess.run([sv2v, "--top=KF8259", "-I" + str(pic),
                             *map(str, sorted(pic.glob("*.sv")))],
                            check=True, capture_output=True, text=True, timeout=60)
    notice = "// Generated with sv2v v0.0.13 from KF8259 (Kitune-san, MIT).\n"
    notice += "// Preserve third_party/kf8259/upstream/LICENSE when distributing.\n"
    # XST's older parser rejects sv2v's localparam alias inside a generate loop.
    # A direct reference to the same genvar has identical elaboration semantics.
    converted = result.stdout
    for alias, genvar in re.findall(r"localparam (\w+) = (_gv_\w+);", converted):
        converted = re.sub(r"\s*localparam " + alias + r" = " + genvar + ";", "", converted)
        converted = re.sub(r"\b" + alias + r"\b", genvar, converted)
    notice += "// XST compatibility: generate-localparam aliases replaced by their genvars.\n"
    (OUT / "kf8259.v").write_text(notice + converted, encoding="utf-8")
    receipt = {"zet_microcode": rom, "firmware": firmware,
               "nasm": subprocess.check_output([nasm, "-v"], text=True).strip(),
               "sv2v": subprocess.check_output([sv2v, "--version"], text=True).strip()}
    (OUT / "build-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
