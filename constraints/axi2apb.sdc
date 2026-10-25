# axi2apb.sdc - pre-layout constraints (period from the environment: CLK_PERIOD_NS).
# Boundary model (assumptions, not measurements): inputs arrive 0.35 ns after the clock edge, outputs must be stable 0.15 ns before the next edge,
# inputs driven by a buf_2, outputs load 0.02 pF. The synchronous reset is an ordinary data input here.
set period $::env(CLK_PERIOD_NS)
create_clock -name clk -period $period [get_ports clk]
set data_in {}
foreach p [all_inputs] { if {[get_property $p name] ne "clk"} { lappend data_in $p } }
set_input_delay 0.35 -clock clk $data_in
set_output_delay 0.15 -clock clk [all_outputs]
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $data_in
set_load 0.02 [all_outputs]
