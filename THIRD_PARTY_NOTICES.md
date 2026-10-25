# Third-party files

The MIT license in `LICENSE` covers my own work in this repository. It does not cover the files below, which keep their own licenses.

## `lib/sky130_fd_sc_hd__tt_025C_1v80.lib` and `ppa/lib/sky130hd_tt.lib`

Both are Sky130 HD typical-corner liberty files, the standard-cell timing data of the SkyWater SKY130 PDK, Copyright 2020 The SkyWater PDK
Authors, licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0). `lib/` is the copy that was in my original
AXI2APB repository. `ppa/lib/` is a copy from the `test/sky130hd/` directory of the OpenROAD project (https://github.com/The-OpenROAD-Project/OpenROAD,
BSD 3-Clause License, Copyright (c) 2018-2025, The OpenROAD Authors), unchanged.

## Tools that are used but not included

Icarus Verilog, Verilator, Yosys and OpenSTA are run by the scripts here, but none of their code is in this repository.
