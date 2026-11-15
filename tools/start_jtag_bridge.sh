#!/bin/bash
# Run in the ISE VM. Example: bash tools/start_jtag_bridge.sh 192.168.56.102 9374
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export XILINX=/opt/Xilinx/14.7/ISE_DS/ISE
export PATH="$XILINX/bin/lin64:$PATH"
export LD_LIBRARY_PATH="$XILINX/lib/lin64:/opt/Xilinx/14.7/ISE_DS/common/lib/lin64:${LD_LIBRARY_PATH:-}"
exec xtclsh "$ROOT/tools/jtag_bridge.tcl" --bind "${1:-127.0.0.1}" --port "${2:-9374}"
