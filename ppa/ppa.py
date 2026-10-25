#!/usr/bin/env python3
"""ppa.py - Yosys + OpenSTA for the bridge: as-found vs fixed RTL, default vs timing-driven mapping.

    ppa.py [--out results/ppa.md]

T_min = 10 ns - WNS(10 ns), verified by re-running STA at +/-2 % of T_min. Pre-layout, ideal clock, no wires, typical corner
(sky130_fd_sc_hd tt_025C_1v80). Power is NOT reported: no switching-activity file exists, and OpenSTA's default activity is not a measurement.
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sta(out, period):
    env = dict(os.environ, NETLIST=os.path.join(out, "synth.v"), SDC=os.path.join(ROOT, "constraints", "axi2apb.sdc"), CLK_PERIOD_NS=repr(float(period)))
    tcl = ("read_liberty %s\nread_verilog $::env(NETLIST)\nlink_design axi2apb\nread_sdc $::env(SDC)\nreport_checks -path_delay max -digits 3\nexit\n" %
           os.path.join(ROOT, "ppa", "lib", "sky130hd_tt.lib"))
    open(os.path.join(out, "sta.tcl"), "w").write(tcl)
    r = subprocess.run(["sta", "-no_splash", "-exit", os.path.join(out, "sta.tcl")], env=env, capture_output=True, text=True, cwd=ROOT)
    m = re.search(r"(-?[\d.]+)\s+slack", r.stdout)
    if not m:
        raise RuntimeError("sta failed: " + (r.stdout + r.stderr)[-300:])
    return float(m.group(1)), r.stdout


def point(name, src, abc):
    out = os.path.join(ROOT, "build", "ppa", "%s_%s" % (name, abc))
    os.makedirs(out, exist_ok=True)
    lib = os.path.join(ROOT, "build", "ppa", "sky130hd_synth.lib")
    cmd = ("abc -constr %s -script %s -liberty %s" % (os.path.join(ROOT, "ppa", "abc_speed.constr"), os.path.join(ROOT, "ppa", "abc_speed.script"), lib)) if abc == "speed" else \
          ("abc -D 10000 -liberty %s" % lib)
    ys = f"""read_verilog -sv {src}
read_liberty -lib {lib}
hierarchy -check -top axi2apb
proc
tribuf
log CHECK no-tribuf
select -assert-none t:$tribuf t:$_TBUF_
log PASS no-tribuf
log CHECK check-rtl
check -assert
log PASS check-rtl
synth -top axi2apb -flatten -noabc
log CHECK no-latch
select -assert-none t:$*latch* t:$_DLATCH*
log PASS no-latch
dfflegalize -cell $_DFF_P_ x
dfflibmap -liberty {lib}
{cmd}
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
opt_clean -purge
tee -o {out}/stat.txt stat -liberty {lib}
write_verilog -noattr {out}/synth.v
"""
    open(os.path.join(out, "synth.ys"), "w").write(ys)
    r = subprocess.run(["yosys", "-l", os.path.join(out, "yosys.log"), os.path.join(out, "synth.ys")], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("yosys failed: " + (r.stdout + r.stderr)[-300:])
    stat = open(os.path.join(out, "stat.txt")).read()
    cells = int(re.search(r"Number of cells:\s+(\d+)", stat).group(1))
    area = float(re.search(r"Chip area for module '[^']+': ([\d.]+)", stat).group(1))
    flops = sum(int(m.group(1)) for m in re.finditer(r"sky130_fd_sc_hd__df\w*\s+(\d+)", stat))
    wns, _ = sta(out, 10.0)
    tmin = 10.0 - wns
    hi, _ = sta(out, tmin * 1.02)
    lo, _ = sta(out, tmin * 0.98)
    return dict(cells=cells, area=area, flops=flops, tmin=tmin, ok=(hi >= 0 and lo < 0), hi=hi, lo=lo)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "results", "ppa.md"))
    a = ap.parse_args()
    os.makedirs(os.path.join(ROOT, "build", "ppa"), exist_ok=True)
    subprocess.check_call([sys.executable, os.path.join(ROOT, "ppa", "prune_lib.py"), os.path.join(ROOT, "ppa", "lib", "sky130hd_tt.lib"),
                           os.path.join(ROOT, "build", "ppa", "sky130hd_synth.lib"), "--drop", "sky130_fd_sc_hd__lpflow_", "--drop", "sky130_fd_sc_hd__probe"], stdout=subprocess.DEVNULL)
    rows = ["# axi2apb bridge: synthesis and timing (measured: Yosys 0.33 + OpenSTA, Sky130 HD tt_025C_1v80, pre-layout)", "",
            "Boundary: inputs 0.35 ns after the edge, outputs 0.15 ns before the next edge (assumption). T_min = 10 ns - WNS, verified at +/-2 %. "
            "`default` = `abc -D 10000`; `speed` = timing-driven ABC script (buffering + sizing). Power is not reported (no switching-activity file).", "",
            "| RTL | mapping | cells | area (um^2) | flip-flops | T_min (ns) | F_max (MHz) | method check |", "|---|---|---:|---:|---:|---:|---:|---|"]
    for name, src in (("as-found (src/original)", os.path.join(ROOT, "src", "original", "axi2apb_original.v")), ("fixed (src/axi2apb.v)", os.path.join(ROOT, "src", "axi2apb.v"))):
        for abc in ("default", "speed"):
            r = point(name.split()[0], src, abc)
            rows.append("| %s | %s | %d | %.0f | %d | %.3f | %.1f | %s |" % (name, abc, r["cells"], r["area"], r["flops"], r["tmin"], 1000 / r["tmin"],
                                                                         "verified (WNS %+.3f / %+.3f ns)" % (r["hi"], r["lo"]) if r["ok"] else "NOT VERIFIED"))
    open(a.out, "w").write("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
