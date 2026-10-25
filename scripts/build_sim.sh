#!/usr/bin/env bash
# build_sim.sh <build-dir> [extra verilator flags]  -> <build-dir>/Vtb_axi2apb      (env: DUT=path to the RTL, NO_CHECKER=1 to omit the assertions)
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$1"; shift
DUT="${DUT:-$HERE/src/axi2apb.v}"
mkdir -p "$OUT"
CHK="$HERE/verif/axi2apb_checker.sv $HERE/verif/checker_binds.sv"
[ -n "${NO_CHECKER:-}" ] && CHK=""
verilator --cc --exe --build --timing --assert --x-initial unique -j 4 -Wno-fatal -Wno-lint -Wno-style \
    --top-module tb_axi2apb --Mdir "$OUT" "$@" "$DUT" $CHK "$HERE/verif/apb_slave_model.sv" "$HERE/verif/tb_axi2apb.sv" "$HERE/verif/sim_main.cpp" > "$OUT/verilator.log" 2>&1 || { tail -30 "$OUT/verilator.log"; exit 1; }
