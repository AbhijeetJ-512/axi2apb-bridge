#!/usr/bin/env bash
# run_replay.sh [rtl.v] - replay the explorer model's per-cycle inputs through the real bridge and compare every output.
# vectors.txt was produced by the page's JavaScript model (one block per scenario: 11 input columns, then the expected state,
# registers and outputs). Exit status is non-zero if any cycle differs. Needs Icarus Verilog (iverilog, vvp).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RTL="${1:-$ROOT/src/axi2apb.v}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
python3 - "$HERE/vectors.txt" "$W" <<'PY'
import sys
cur=None
for l in open(sys.argv[1]):
    l=l.strip()
    if l.startswith('#'): cur=open('%s/%s.vec'%(sys.argv[2],l[2:].strip()),'w')
    elif l: cur.write(l+'\n')
PY
iverilog -g2005 -o "$W/replay.vvp" "$HERE/replay.v" "$RTL"
rc=0
for f in "$W"/*.vec; do
  out="$(vvp -n "$W/replay.vvp" +f="$f")"
  echo "$out" | grep -E "MISMATCH|REPLAY" | sed "s#$W/##" | head -4
  echo "$out" | grep -q "MISMATCH" && rc=1
done
exit $rc
