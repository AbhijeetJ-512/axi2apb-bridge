#!/usr/bin/env python3
"""axi2apb_bridge diagrams (dgm.py). Run: python3 docs/portfolio/diagrams/make_diagrams.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)   # dgm.py sits next to this file
from dgm import Diagram  # noqa: E402


def architecture():
    d = Diagram("AXI4-Lite to APB3 bridge - architecture", 1320, 640)
    d.legend = ("data", "ctrl")
    d.legend_pos = (1110, 12)
    d.group("g", 235, 60, 835, 470, "axi2apb  (DATA_WIDTH = ADDR_WIDTH = 32, one clock, synchronous active-low reset)", label_pos="bottom")
    d.box("m", 20, 130, 190, 330, "AXI4-Lite master", "io", sub="AR: ARADDR ARVALID ARREADY\nR : RDATA RRESP RVALID RREADY\nAW: AWADDR AWVALID AWREADY\nW : WDATA WVALID WREADY\nB : BRESP BVALID BREADY", size=12)
    d.box("fsm", 290, 100, 400, 115, "Control FSM  (present_state / next_state)", "fsm", sub="IDLE, WRITE_ADDRESS_RECEIVED, WRITE_DATA_RECEIVED, PENABLE_WRITE,\nWDATA_TRANSFERRED, READ_ADDRESS_RECEIVED, PENABLE_READ,\nRDATA_TRANSFERRED   -   a read request wins in IDLE", size=11)
    d.box("dec", 740, 100, 300, 115, "Output decode", "ctrl", sub="ARREADY AWREADY WREADY RVALID BVALID\nPSEL PENABLE PWRITE\n(each a function of present_state)", size=11)
    d.box("sa", 290, 270, 170, 75, "sampled_addr", "block", sub="ARADDR or AWADDR,\nlatched in IDLE", size=11)
    d.box("pa", 510, 270, 180, 75, "PADDR / PWDATA regs", "block", sub="loaded when W is accepted\nor a read starts", size=11)
    d.box("rr", 290, 390, 400, 85, "Response registers", "accent", sub="RDATA <= PRDATA (if !PSLVERR);  BRESP, RRESP <= PSLVERR ? SLVERR (2'b10) : OKAY\n(the as-found RTL returned DECERR, 2'b11: change CH-001)", size=11)
    d.box("ap", 1100, 130, 190, 330, "APB3 slave", "io", sub="PADDR PSEL PENABLE\nPWRITE PWDATA\nPREADY PRDATA PSLVERR", size=12)
    d.arrow("h", "m", "fsm", kind="ctrl", sside="r", dside="l", sf=0.2, df=0.5, both=True, label="VALID / READY\nhandshakes", lpos=(250, 150))
    d.arrow("a1", "m", "sa", sside="r", dside="l", sf=0.5, df=0.5, label="ARADDR / AWADDR", lpos=(250, 285))
    d.arrow("a2", "sa", "pa", label="")
    d.arrow("a3", "pa", "ap", sside="r", dside="l", sf=0.5, df=0.5, label="PADDR, PWDATA", lpos=(900, 292))
    d.arrow("c1", "fsm", "dec", kind="ctrl", label="")
    d.arrow("c2", "dec", "ap", kind="ctrl", sside="r", dside="l", sf=0.3, df=0.2, label="PSEL, PENABLE, PWRITE", lpos=(1075, 118))
    d.arrow("c3", "ap", "fsm", kind="ctrl", sside="t", dside="t", sf=0.5, df=0.5, via=[(1195, 82), (490, 82)], label="PREADY", lpos=(850, 74))
    d.arrow("r1", "ap", "rr", sside="b", dside="b", sf=0.5, df=0.7, via=[(1195, 505), (570, 505)], label="PRDATA, PSLVERR", lpos=(900, 497))
    d.arrow("r2", "rr", "m", sside="l", dside="r", sf=0.5, df=0.9, label="RDATA, RRESP, BRESP", lpos=(235, 497))
    d.text("n", 20, 560, "One transaction at a time: a read or write is accepted in IDLE, one APB transfer is performed (setup phase, then access phase until PREADY), and the response is held until the master takes it.\n"
                         "AWREADY and WREADY are asserted together and only in WRITE_ADDRESS_RECEIVED, so write data that arrives before its address waits. A read request has priority over a simultaneous write request.", 11, italic=True)
    return d


def fsm_flow():
    d = Diagram("AXI4-Lite to APB3 bridge - FSM and transfer flowchart", 1250, 1000)
    d.legend = ("flow",)
    d.legend_pos = (1050, 12)
    d.box("idle", 480, 55, 280, 55, "IDLE", "term", sub="all VALID/READY outputs low; sample the address", size=12)
    d.box("dar", 480, 140, 280, 78, "ARVALID ?", "dec", sub="read has priority", size=12)
    d.box("daw", 480, 245, 280, 78, "AWVALID ?", "dec", size=12)
    # write column (left)
    d.box("wa", 40, 330, 300, 64, "WRITE_ADDRESS_RECEIVED", "proc", sub="AWREADY = WREADY = 1", size=12)
    d.box("dw", 40, 420, 300, 72, "WVALID ?", "dec", size=12)
    d.box("wd", 40, 520, 300, 64, "WRITE_DATA_RECEIVED  (APB setup)", "proc", sub="PSEL = 1, PWRITE = 1\nPADDR, PWDATA loaded", size=11)
    d.box("pw", 40, 612, 300, 64, "PENABLE_WRITE  (APB access)", "proc", sub="PSEL = PENABLE = PWRITE = 1", size=12)
    d.box("dpw", 40, 704, 300, 72, "PREADY ?", "dec", sub="no: stay (wait state)", size=12)
    d.box("wt", 40, 800, 300, 64, "WDATA_TRANSFERRED", "proc", sub="BRESP <= PSLVERR ? SLVERR : OKAY\nBVALID = 1", size=11)
    d.box("db", 40, 892, 300, 72, "BREADY ?", "dec", sub="no: hold BVALID, BRESP", size=12)
    # read column (right)
    d.box("ra", 900, 330, 300, 64, "READ_ADDRESS_RECEIVED  (APB setup)", "proc", sub="ARREADY = 1, PSEL = 1\nPADDR <= ARADDR", size=11)
    d.box("pr", 900, 430, 300, 64, "PENABLE_READ  (APB access)", "proc", sub="PSEL = PENABLE = 1, PWRITE = 0", size=12)
    d.box("dpr", 900, 522, 300, 72, "PREADY ?", "dec", sub="no: stay (wait state)", size=12)
    d.box("rt", 900, 620, 300, 64, "RDATA_TRANSFERRED", "proc", sub="RDATA <= PRDATA (if !PSLVERR)\nRRESP <= PSLVERR ? SLVERR : OKAY, RVALID = 1", size=11)
    d.box("dr", 900, 712, 300, 72, "RREADY ?", "dec", sub="no: hold RVALID, RDATA, RRESP", size=12)
    d.box("fin", 480, 912, 280, 55, "Back to IDLE", "term", size=12)
    cx = 620
    d.arrow("e1", "idle", "dar", kind="flow", sside="b", dside="t")
    d.arrow("e2", "dar", "daw", kind="flow", sside="b", dside="t", label="no", lpos=(cx + 20, 232))
    d.arrow("e3", "dar", "ra", kind="flow", sside="r", dside="t", sf=0.5, df=0.5, via=[(1050, 179)], label="yes", lpos=(870, 171))
    d.arrow("e4", "daw", "wa", kind="flow", sside="l", dside="t", sf=0.5, df=0.5, via=[(190, 284)], label="yes", lpos=(340, 276))
    d.arrow("e5", "daw", "idle", kind="flow", sside="r", dside="r", sf=0.5, df=0.5, via=[(820, 284), (820, 82)], label="no: idle", lpos=(790, 190))
    for a, b in [("wa", "dw"), ("dw", "wd"), ("wd", "pw"), ("pw", "dpw"), ("dpw", "wt"), ("wt", "db"), ("ra", "pr"), ("pr", "dpr"), ("dpr", "rt"), ("rt", "dr")]:
        yes = a in ("dw", "dpw", "dpr")
        d.arrow("w_" + a, a, b, kind="flow", sside="b", dside="t", label="yes" if yes else "", lpos=((d.node(a).x + 175), (d.node(a).y + d.node(a).h + d.node(b).y) / 2 + 0) if yes else None)
    # wait loops (the "no" branches)
    d.arrow("l1", "dw", "wa", kind="flow", sside="l", dside="l", sf=0.5, df=0.5, via=[(20, 456), (20, 362)], label="no", lpos=(34, 410))
    d.arrow("l2", "dpw", "pw", kind="flow", sside="l", dside="l", sf=0.5, df=0.5, via=[(20, 740), (20, 644)], label="no", lpos=(34, 690))
    d.arrow("l3", "db", "wt", kind="flow", sside="l", dside="l", sf=0.5, df=0.5, via=[(20, 928), (20, 832)], label="no", lpos=(34, 880))
    d.arrow("l4", "dpr", "pr", kind="flow", sside="r", dside="r", sf=0.5, df=0.5, via=[(1225, 558), (1225, 462)], label="no", lpos=(1214, 510))
    d.arrow("l5", "dr", "rt", kind="flow", sside="r", dside="r", sf=0.5, df=0.5, via=[(1225, 748), (1225, 652)], label="no", lpos=(1214, 700))
    d.arrow("e6", "db", "fin", kind="flow", sside="b", dside="l", sf=0.5, df=0.5, via=[(190, 984), (420, 984), (420, 939)], label="yes", lpos=(110, 975))
    d.arrow("e7", "dr", "fin", kind="flow", sside="b", dside="r", sf=0.5, df=0.5, via=[(1050, 939)], label="yes", lpos=(1030, 800))
    d.text("n", 360, 440, "One APB transfer = a setup phase\n(PSEL, no PENABLE) followed by an access\nphase (PSEL and PENABLE) that lasts\nuntil PREADY.\n\nA response is held until the AXI master\nasserts BREADY / RREADY; one transaction\nis outstanding at a time.", 11, italic=True)
    return d


if __name__ == "__main__":
    for n, f in (("axi2apb_architecture", architecture), ("axi2apb_flowchart", fsm_flow)):
        print(n, "overflow:", f().export_all(HERE, n))
