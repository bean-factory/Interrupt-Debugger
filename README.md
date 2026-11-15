# Interrupt Debugger

An FPGA-hosted interrupt demonstrator for the **Spartan-3E XC3S1600E-FG320**
board. A Zet 8086-compatible CPU executes interrupt firmware through a KF8259
programmable interrupt controller. The desktop GUI reads and explains the
recorded digital waveforms over the board's existing USB-JTAG cable.

## Contents

- `host/`: desktop GUI, waveform display, capture transport, decoder and exports.
- `rtl/`: CPU/PIC integration, request sequencer, capture memory, JTAG and LCD.
- `firmware/`: 16-bit assembly for the four interrupt conditions.
- `constraints/`: board pins and timing constraints.
- `config/`: default GUI target and loopback bridge endpoint.
- `third_party/`: pinned CPU/PIC sources and their original licences.
- `tools/`: firmware preparation, FPGA build and live JTAG bridge.
- `bitstream/`: volatile FPGA configuration built from the supplied sources.
- `CREDITS.md` and `LICENSE`: attribution and licensing.

## Desktop setup (Windows, Python 3.11 or later)

Open PowerShell in this directory:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

The GUI runs on Windows. Xilinx ISE 14.7 and its USB-JTAG driver run inside the
Linux ISE VM. Connect the board's USB device to that VM and power the board.
No external CPU, PIC, serial adapter or extra GPIO wiring is needed.

## Program the FPGA

In the ISE VM, open iMPACT and initialize the JTAG chain. Check the device order:
**XC3S1600E**, two configuration PROMs, then CPLD. Assign
`bitstream/interrupt_debugger_volatile.bit` **only to the FPGA** (first device,
iMPACT position 1). Bypass the other devices and program only the FPGA.
Do not erase/program PROMs or the CPLD. Close iMPACT before starting the bridge.

This configuration is volatile: power removal or PROG loses/replaces it.
Reprogram the supplied image when needed. SOUTH resets the running design;
NORTH starts an experiment. Do not confuse NORTH with PROG.

## Connect the GUI

Power on the ISE VM and board, pass the USB-JTAG device to the VM, and close
iMPACT. **Double-click `run_gui.cmd`.** It starts the VM bridge and a loopback-only
SSH tunnel automatically, then opens the GUI with the correct endpoint. There is
no need to start a VM terminal or SSH tunnel manually. A free local port is chosen
automatically to avoid conflicts with existing sessions.

Use your VM password when prompted; it is not saved. SSH keys are also supported,
or an existing `ISE_VM_PASSWORD` environment variable may supply the password.
The first launch installs Paramiko if this dependency is missing from an older
environment. Keep the console window open; closing the GUI stops its bridge and
tunnel. Launching the GUI does **not** program, reset, start or read the FPGA.

VM address, username and ISE location are in `config/vm.json`. The public host key
for the supplied VM is pinned in `config/known_hosts`; no passwords or private keys
are included. If using a different/recreated VM, independently verify its host key
and update this file. Unknown or changed host keys are rejected, not silently trusted.

The equivalent command is:

```powershell
.\.venv\Scripts\python.exe tools\run_demo.py
```

Directly running `python -m host.app` opens only the viewer and does not establish
the connection. Use the managed launcher above for live hardware capture.

## Physical controls

- **SW3 ON** arms NORTH Start; OFF disarms it.
- **SW2 OFF / ON** selects sequential / simultaneous IRQ1 and IRQ3 requests.
- **SW1:SW0 = 00**: normal service.
- **SW1:SW0 = 01**: IRQ1 masked.
- **SW1:SW0 = 10**: IRQ3 masked.
- **SW1:SW0 = 11**: missing IRQ1 EOI.

Set the switches, press and release **NORTH**, then click **Read capture** in
the GUI (Ctrl+R). The GUI does not start experiments. Start is ignored during
readout to protect the frozen data. Reading again returns the same capture;
press NORTH for a new experiment.

The LCD's top row shows the condition and **SEQ/SIM**. While idle it follows the
switches; once started it labels the actual capture until the read confirmation
finishes, even if the switches move. The bottom row indicates:

- **Idle: push NORTH**: armed, no completed capture yet.
- **Capturing...**: experiment in progress (usually too brief to see).
- **Done: read GUI**: complete and ready to read.
- **Reading to GUI**: transfer in progress.
- **Read OK**: GUI validated and acknowledged the packet. After two seconds the
  display returns to **Idle: push NORTH**, with the current switch selection on
  top. Only NORTH starts another experiment; the frozen capture remains available
  to reread until then. If SW3 is off, the idle message instead shows disarmed.
- **Disarmed: SW3 ON**: idle with Start disabled.
- **CPU startup fail**: CPU did not initialize; not a successful experiment.

The GUI supports saving/reopening recordings, comparison, and waveform/event
exports. Scroll pans time; pinch or Ctrl+wheel zooms time; Home fits the capture.

## Build from source

Generated ROM and ISE-compatible PIC inputs are included, so rebuilding the FPGA
does not require NASM or sv2v. In the ISE VM:

```bash
bash tools/build_hosted_ise.sh
```

The script uses ISE 14.7, builds `fpga_jtag_top` for `xc3s1600e-4-fg320`, checks
timing and bitstream DRC, and produces the volatile `.bit` in its printed output
directory. It **never programs hardware**. Use a new output directory per build.
The `-keep_hierarchy soft` synthesis setting is required for this integration.

To change firmware or regenerate the converted PIC, install Python 3.11+, NASM
and sv2v v0.0.13 on PATH, then run `python tools/prepare_hosted.py` before building.
The original cores and notices are retained unmodified. See `CREDITS.md`.

## Design boundaries

The system/sample clock is **12.5 MHz**. Each capture has **8192 samples**,
covering **655.36 microseconds**. The CPU has 8 KiB RAM and four firmware ROM
pages. The JTAG bridge uses Xilinx's installed CSE libraries; those proprietary
libraries and ISE itself are not redistributed.

This is a compatible-core demonstration, not a cycle-exact Intel 8086/8259A
replica. The CPU adapter generates two interrupt-acknowledge pulses for the PIC.
Waveforms show digital transactions, not analog voltages. PIC-state explanations
are inferred where indicated; observing EOI alone does not prove IRET.
