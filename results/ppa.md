# axi2apb bridge: synthesis and timing (measured: Yosys 0.33 + OpenSTA, Sky130 HD tt_025C_1v80, pre-layout)

Boundary: inputs 0.35 ns after the edge, outputs 0.15 ns before the next edge (assumption). T_min = 10 ns - WNS, verified at +/-2 %. `default` = `abc -D 10000`; `speed` = timing-driven ABC script (buffering + sizing). Power is not reported (no switching-activity file).

| RTL | mapping | cells | area (um^2) | flip-flops | T_min (ns) | F_max (MHz) | method check |
|---|---|---:|---:|---:|---:|---:|---|
| as-found (src/original) | default | 592 | 5370 | 138 | 4.611 | 216.9 | verified (WNS +0.092 / -0.092 ns) |
| as-found (src/original) | speed | 782 | 6399 | 138 | 1.681 | 594.9 | verified (WNS +0.034 / -0.033 ns) |
| fixed (src/axi2apb.v) | default | 595 | 5378 | 138 | 4.611 | 216.9 | verified (WNS +0.092 / -0.092 ns) |
| fixed (src/axi2apb.v) | speed | 784 | 6406 | 138 | 1.681 | 594.9 | verified (WNS +0.034 / -0.033 ns) |
