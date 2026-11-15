#!/bin/bash
# Build a volatile FPGA image only. Never accesses/programs the JTAG cable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HOME/interrupt-debugger-build-$(date +%Y%m%d-%H%M%S)}"
case "$OUT" in *[[:space:]]*) echo "Use a whitespace-free build path" >&2; exit 2;; esac
if [ -e "$OUT" ]; then echo "Choose a new build directory: $OUT" >&2; exit 2; fi
export XILINX=/opt/Xilinx/14.7/ISE_DS/ISE
export PATH="$XILINX/bin/lin64:$PATH"
export LD_LIBRARY_PATH="$XILINX/lib/lin64:/opt/Xilinx/14.7/ISE_DS/common/lib/lin64:${LD_LIBRARY_PATH:-}"
mkdir -p "$OUT/rtl"
cp "$ROOT"/rtl/*.v "$OUT/rtl/"
cp "$ROOT"/rtl/hosted/*.v "$OUT/rtl/"
cp "$ROOT"/rtl/hosted/generated/*.v "$OUT/rtl/"
cp "$ROOT"/third_party/zet/upstream/cores/zet/rtl/*.v "$OUT/rtl/"
cp "$ROOT"/rtl/hosted/generated/micro_rom.dat "$OUT/"
cp "$ROOT"/rtl/hosted/generated/program.hex "$OUT/"
cp "$ROOT/constraints/spartan3e_1600_jtag_candidate.ucf" "$OUT/board.ucf"
cd "$OUT"
exec > >(tee build.log) 2>&1
for source in rtl/*.v; do printf 'verilog work "%s"\n' "$source"; done > top.prj
cat > top.xst <<'EOF'
run
-ifn top.prj
-ifmt mixed
-ofn top
-ofmt NGC
-p xc3s1600e-4-fg320
-top fpga_jtag_top
-vlgincdir {rtl}
-opt_mode Speed
-opt_level 1
-keep_hierarchy soft
EOF
sha256sum rtl/*.v micro_rom.dat program.hex board.ucf top.xst > source.sha256
timeout 600 xst -ifn top.xst -ofn top.syr
timeout 180 ngdbuild -p xc3s1600e-4-fg320 -uc board.ucf top.ngc top.ngd
timeout 300 map -p xc3s1600e-4-fg320 -o top_map.ncd top.ngd top.pcf
timeout 600 par -w top_map.ncd top_routed.ncd top.pcf
timeout 120 trce -v 20 -u 1000 -tsi top.tsi -o top.twr top_routed.ncd top.pcf
if ! grep -Eq 'Timing errors:[[:space:]]+0[[:space:]]+Score:[[:space:]]+0' top.twr; then
    echo "Timing failed; refusing to generate a bitstream." >&2
    exit 3
fi
timeout 120 bitgen -g StartupClk:JtagClk -g UnusedPin:PullNone top_routed.ncd interrupt_debugger_volatile.bit top.pcf > bitgen.log 2>&1
if ! grep -q 'DRC detected 0 errors and 0 warnings' bitgen.log; then
    echo "Review bitgen.log; bitstream DRC was not clean." >&2
    exit 4
fi
sha256sum interrupt_debugger_volatile.bit > bitstream.sha256
echo "Build complete: $OUT/interrupt_debugger_volatile.bit"
echo "No hardware was accessed or programmed."
