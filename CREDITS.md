# Interrupt Debugger credits and third-party code

## CPU: Zet

- **Authors:** Zeus Gomez Marmolejo and the Zet contributors. Individual source
  files retain their original copyright notices.
- **Project:** https://github.com/marmolejo/zet
- **Pinned revision:** `aaad74d51a4b558e48031df20d80f20e350cd771`.
- **License:** GNU GPL version 3 or later. See
  `third_party/zet/upstream/COPYING` and the source-file headers.
- **Role:** an open-source, 8086-compatible instruction-executing processor.
  Interrupt Debugger integrates the CPU core, not the upstream PC peripherals, BIOS,
  display, storage or SDRAM subsystem.
- **Build adaptation:** `tools/prepare_hosted.py` ports the packing procedure in
  Zet's PHP `micro2rom` utility to Python. A portable registered multiplier
  replaces the Altera-specific multiplier wrapper; upstream files are unchanged.

## Interrupt controller: KF8259

- **Author:** Kitune-san.
- **Project:** https://github.com/kitune-san/KF8259
- **Pinned revision:** `b432853d7bdbe1d6dcae17f97c415e6140700131`.
- **License:** MIT. See `third_party/kf8259/upstream/LICENSE`.
- **Role:** an 8259/8259A-like programmable interrupt controller. The project
  exercises a single controller in 8086, edge-triggered, fixed-priority,
  manual-EOI mode. It does not claim complete Intel chip or timing equivalence.
- **Toolchain adaptation:** upstream SystemVerilog is converted to Verilog for
  ISE using sv2v; original upstream files and notices are preserved separately.
  Generated localparam aliases inside generate loops are replaced by direct
  genvar references for XST parser compatibility; this does not change the logic.

## Interrupt Debugger integration

Project-specific work comprises the CPU/PIC bus adapter, program and data memory,
bare-metal interrupt demonstrations, request generation, sampled capture,
USB-JTAG transport, board switches/button, write-only LCD status,
waveform viewer, event decoder,
state-based explanations and
board-specific build integration. These additions must be distinguished from the
reused CPU and PIC cores in the report.

The Zet-derived combined FPGA design carries GPL obligations when distributed:
retain copyright/license notices and provide corresponding source, generated ROM
inputs and build scripts under the applicable GPL terms. The MIT notice for
KF8259 must also accompany its code. This file does not replace either license.

## Other tools and references

- **sv2v**, Zachary Snow and contributors: https://github.com/zachjs/sv2v,
  version `v0.0.13`, used for SystemVerilog-to-Verilog conversion.
- **NASM:** https://www.nasm.us/, used to assemble the 16-bit program.
- **Icarus Verilog:** https://github.com/steveicarus/iverilog, used for simulation.
- **Xilinx ISE 14.7:** FPGA implementation tools; third-party tool, not project code.
  The JTAG bridge calls the installed Xilinx CSE API. Xilinx libraries and example
  implementations are not redistributed as part of the project.
- **Xilinx UG257:** board documentation for the MicroBlaze Development Kit,
  Spartan-3E 1600E Edition. The kit name does not mean the project uses MicroBlaze.
- **Intel 8086 and 8259A documentation:** instruction and interrupt-protocol references.
- Desktop runtime dependencies are listed with versions in `requirements.txt`:
  PySide6, pyqtgraph, NumPy, pyserial and Paramiko (SSH connection management).

## Suggested report acknowledgement

> The FPGA-hosted interrupt system uses the open-source Zet 8086-compatible CPU
> by Zeus Gomez Marmolejo and contributors, and the KF8259 interrupt controller
> by Kitune-san. Our contribution is their integration into a controlled interrupt
> experiment with capture hardware, firmware, a waveform interface and
> evidence-linked explanations. The system demonstrates the supported interrupt
> behavior; it is not a cycle-exact reproduction of the Intel 8086 and 8259A.
