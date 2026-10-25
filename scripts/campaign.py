#!/usr/bin/env python3
"""campaign.py - the bridge's regression, baseline comparison, coverage run and injected-bug campaign.

    campaign.py seeds [--n 3000] [--seeds 1 2 3 4 5 6 7 8]      run the self-checking testbench over several seeds
    campaign.py baseline                                         the as-found RTL (src/original) against the same testbench
    campaign.py cov                                              merged coverage (cover points + line) over the seeds
    campaign.py mutants [--jobs 4]                               injected bugs; each must be caught by the testbench or an assertion
"""
import argparse
import concurrent.futures as cf
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_ARGS = ["+verilator+rand+reset+2"]


def build(out, dut=None, no_checker=False, extra=()):
    env = dict(os.environ)
    if dut:
        env["DUT"] = dut
    if no_checker:
        env["NO_CHECKER"] = "1"
    r = subprocess.run([os.path.join(ROOT, "scripts", "build_sim.sh"), out, *extra], env=env, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("build failed: " + r.stdout[-300:] + r.stderr[-200:])
    return os.path.join(out, "Vtb_axi2apb")


def run(exe, seed, n, extra=()):
    r = subprocess.run([exe, *SIM_ARGS, "+verilator+seed+%d" % seed, "+n=%d" % n, "+verilator+error+limit+100000", *extra], capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    fired = sorted(set(re.findall(r"Assertion failed in \S*?u_chk\.(?:\w+\.)*(a_\w+)", out)))
    tb_err = len(re.findall(r"TB ERROR", out))
    m = re.search(r"TB (PASS|FAIL)[^\n]*", out)
    return dict(passed=bool(m and m.group(1) == "PASS" and not fired), line=m.group(0) if m else "NO RESULT LINE (crash or hang): " + out[-120:].replace("\n", " "), fired=fired, tb_err=tb_err, out=out)


def cmd_seeds(a):
    exe = build(os.path.join(ROOT, "build", "sim"))
    lines, ok = [], True
    for s in a.seeds:
        r = run(exe, s, a.n)
        ok &= r["passed"]
        lines.append("seed %d: %s%s" % (s, r["line"], ("  ASSERTIONS FIRED: " + ",".join(r["fired"])) if r["fired"] else ""))
    lines.insert(0, "%d/%d seeds pass (%d random items each, plus the directed phases)" % (sum(1 for l in lines if ": TB PASS" in l and "ASSERTIONS" not in l), len(lines), a.n))
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    open(os.path.join(ROOT, "results", "regression.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if ok else 1


def cmd_baseline(a):
    exe = build(os.path.join(ROOT, "build", "sim_orig"), dut=os.path.join(ROOT, "src", "original", "axi2apb_original.v"))
    r = run(exe, 1, 3000)
    firing = {}
    for m in re.finditer(r"Assertion failed in \S*?u_chk\.(?:\w+\.)*(a_\w+)", r["out"]):
        firing[m.group(1)] = firing.get(m.group(1), 0) + 1
    first = [l for l in r["out"].splitlines() if l.startswith("TB ERROR")][:4]
    text = ["As-found RTL (src/original/axi2apb_original.v) against the same testbench and checker, seed 1, 3000 random items:",
            "  result: %s" % r["line"], "  testbench errors: %d" % r["tb_err"],
            "  assertions fired (name: times): " + ", ".join("%s: %d" % kv for kv in sorted(firing.items())), "  first testbench errors:"] + ["    " + l[:150] for l in first]
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    open(os.path.join(ROOT, "results", "baseline_original.txt"), "w").write("\n".join(text) + "\n")
    print("\n".join(text))


def cmd_cov(a):
    out = os.path.join(ROOT, "build", "cov")
    shutil.rmtree(out, ignore_errors=True)
    exe = build(out, extra=["--coverage"])
    dats = []
    for s in range(1, 9):
        dat = os.path.join(out, "c%d.dat" % s)
        subprocess.run([exe, *SIM_ARGS, "+verilator+seed+%d" % s, "+n=2000", "+cov_file=" + dat], capture_output=True, text=True)
        dats.append(dat)
    merged = os.path.join(out, "merged.dat")
    subprocess.check_call(["verilator_coverage", "--write", merged] + [d for d in dats if os.path.exists(d)], stdout=subprocess.DEVNULL)
    recs = []
    for line in open(merged, "rb").read().decode("latin-1").splitlines():
        m = re.match(r"^C '(.*)' (\d+)$", line)
        if m:
            f = {}
            for part in m.group(1).split("\x01")[1:]:
                k, _, v = part.partition("\x02")
                f[k] = v
            recs.append((f, int(m.group(2))))
    bins = [(f["h"], c) for f, c in recs if f.get("page", "").split("/")[0] == "v_user"]
    lines = collections = {}
    ln = {}
    for f, c in recs:
        if f.get("page", "").split("/")[0] == "v_line" and "axi2apb.v" in f.get("f", ""):
            ln[(f["f"], int(f["l"]))] = ln.get((f["f"], int(f["l"])), 0) + c
    zero = [n for n, c in bins if c == 0]
    unc = sorted(k[1] for k, c in ln.items() if c == 0)
    text = ["Merged coverage of 8 seeds x 2000 random items + the directed phases (results/coverage_summary.txt):",
            "  named cover points : %d total, %d hit, %d zero%s" % (len(bins), len(bins) - len(zero), len(zero), (" -> " + ", ".join(zero)) if zero else ""),
            "  axi2apb.v line blocks: %d total, %d covered, %d uncovered%s" % (len(ln), sum(1 for c in ln.values() if c), len(unc), (" (lines " + ", ".join(map(str, unc)) + ")") if unc else "")]
    open(os.path.join(ROOT, "results", "coverage_summary.txt"), "w").write("\n".join(text) + "\n")
    print("\n".join(text))
    return 0 if not zero and not unc else 1


MUTANTS = [
    ("B01", "PENABLE asserted already in the setup phase of a write", "        WRITE_DATA_RECEIVED_STATE: begin\n            M_APB_PSEL   = 1;\n            M_APB_PWRITE = 1;", "        WRITE_DATA_RECEIVED_STATE: begin\n            M_APB_PSEL   = 1;\n            M_APB_PENABLE = 1;\n            M_APB_PWRITE = 1;"),
    ("B02", "write ignores APB wait states (leaves the access phase at once)", "PENABLE_WRITE_SIGNAL: begin\n            if (M_APB_PREADY)", "PENABLE_WRITE_SIGNAL: begin\n            if (1'b1)"),
    ("B03", "read ignores APB wait states", "PENABLE_READ_SIGNAL: begin\n            if (M_APB_PREADY)", "PENABLE_READ_SIGNAL: begin\n            if (1'b1)"),
    ("B04", "APB write error swallowed: BRESP always OKAY", "S_AXI_BRESP <= (M_APB_PSLVERR) ? 2'b10 : 2'b00;", "S_AXI_BRESP <= 2'b00;"),
    ("B05", "APB read error swallowed: RRESP always OKAY", "S_AXI_RRESP <= (M_APB_PSLVERR) ? 2'b10 : 2'b00;", "S_AXI_RRESP <= 2'b00;"),
    ("B06", "write response dropped without waiting for BREADY", "WDATA_TRANSFERRED_STATE: begin\n            if (S_AXI_BREADY)", "WDATA_TRANSFERRED_STATE: begin\n            if (1'b1)"),
    ("B07", "read data dropped without waiting for RREADY", "RDATA_TRANSFERRED_STATE: begin\n            if (S_AXI_RREADY)", "RDATA_TRANSFERRED_STATE: begin\n            if (1'b1)"),
    ("B08", "read uses the write address", "M_APB_PADDR <= S_AXI_ARADDR;", "M_APB_PADDR <= S_AXI_AWADDR;"),
    ("B09", "write data is one beat stale", "M_APB_PWDATA <= S_AXI_WDATA;", "M_APB_PWDATA <= sampled_wdata;"),
    ("B10", "WREADY asserted in IDLE as well (data accepted before an address)", "        WRITE_ADDRESS_RECEIVED_STATE: begin\n            S_AXI_AWREADY = 1;\n            S_AXI_WREADY  = 1;\n        end", "        WRITE_ADDRESS_RECEIVED_STATE: begin\n            S_AXI_AWREADY = 1;\n            S_AXI_WREADY  = 1;\n        end\n        IDLE: S_AXI_WREADY = 1;"),
    ("B11", "PWRITE dropped in the access phase of a write", "        PENABLE_WRITE_SIGNAL: begin\n            M_APB_PSEL    = 1;\n            M_APB_PENABLE = 1;\n            M_APB_PWRITE  = 1;", "        PENABLE_WRITE_SIGNAL: begin\n            M_APB_PSEL    = 1;\n            M_APB_PENABLE = 1;"),
    ("B12", "write has priority over read when both are requested", "            if (S_AXI_ARVALID)\n                next_state = READ_ADDRESS_RECEIVED_STATE;\n            else if (S_AXI_AWVALID)\n                next_state = WRITE_ADDRESS_RECEIVED_STATE;", "            if (S_AXI_AWVALID)\n                next_state = WRITE_ADDRESS_RECEIVED_STATE;\n            else if (S_AXI_ARVALID)\n                next_state = READ_ADDRESS_RECEIVED_STATE;"),
    ("B13", "PSEL dropped in the setup phase of a read", "        READ_ADDRESS_RECEIVED_STATE: begin\n            S_AXI_ARREADY = 1;\n            M_APB_PSEL    = 1;", "        READ_ADDRESS_RECEIVED_STATE: begin\n            S_AXI_ARREADY = 1;"),
    ("B14", "read data captured without the PREADY qualifier (final value still correct)", "else if (present_state == PENABLE_READ_SIGNAL && M_APB_PREADY && !M_APB_PSLVERR)", "else if (present_state == PENABLE_READ_SIGNAL && !M_APB_PSLVERR)"),
    ("B15", "read data not registered: RDATA follows PRDATA combinationally is not possible here; RDATA stuck", "S_AXI_RDATA <= M_APB_PRDATA;", "S_AXI_RDATA <= S_AXI_RDATA;"),
]


def one_mutant(m):
    mid, desc, old, new = m
    wd = os.path.join(ROOT, "build", "mut", mid)
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(wd)
    src = open(os.path.join(ROOT, "src", "axi2apb.v")).read()
    if src.count(old) != 1:
        return mid, desc, "ERROR old text occurs %d times" % src.count(old), []
    dut = os.path.join(wd, "axi2apb.v")
    open(dut, "w").write(src.replace(old, new))
    try:
        exe = build(os.path.join(wd, "A"), dut=dut)
        exeB = build(os.path.join(wd, "B"), dut=dut, no_checker=True)
    except RuntimeError as e:
        return mid, desc, "ERROR " + str(e)[:80], []
    fired, bad = set(), False
    for s in (1, 2, 3):
        r = run(exe, s, 600)
        fired |= set(r["fired"])
        bad |= not r["passed"]
    layers_b = any(not run(exeB, s, 600)["passed"] for s in (1, 2, 3))
    return mid, desc, ("KILLED" if bad else "SURVIVED"), sorted(fired), ("testbench" if layers_b else "NOT CAUGHT")


def cmd_mutants(a):
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(one_mutant, MUTANTS))
    rows, killed = [], 0
    for r in res:
        if len(r) == 4:
            rows.append("%s  %s  %s" % (r[0], r[2], r[1]))
            continue
        mid, desc, verdict, fired, tb = r
        killed += verdict == "KILLED"
        rows.append("%-4s %-9s %-70s assertions: %-46s without assertions (testbench only): %s" % (mid, verdict, desc[:70], ",".join(fired) or "-", tb))
    summary = ["mutants: %d, caught %d (3 seeds x 600 random items + directed phases each; with and without the assertions)" % (len(res), killed),
               "survivors are annotated in the table; see docs for the reason (B14 is an equivalent mutant)"]
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    open(os.path.join(ROOT, "results", "mutants.txt"), "w").write("\n".join(summary + [""] + rows) + "\n")
    print("\n".join(summary + [""] + rows))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("seeds"); s.add_argument("--n", type=int, default=3000); s.add_argument("--seeds", type=int, nargs="+", default=list(range(1, 9)))
    sub.add_parser("baseline"); sub.add_parser("cov")
    m = sub.add_parser("mutants"); m.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    return {"seeds": cmd_seeds, "baseline": cmd_baseline, "cov": cmd_cov, "mutants": cmd_mutants}[a.cmd](a) or 0


if __name__ == "__main__":
    sys.exit(main())
