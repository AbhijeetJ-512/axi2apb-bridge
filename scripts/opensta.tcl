# opensta.tcl

read_liberty ./lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog build/synth.v

link_design axi2apb

read_sdc ./scripts/axi2apb.sdc

report_power >  build/reports/power_report.txt
report_checks > build/reports/timing.txt
exit
