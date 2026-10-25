# Makefile

include config.mk

SRC := $(wildcard $(SRC_DIR)/*.v)
SYNTH_OUT := $(BUILD_DIR)/synth.json
REPORT_DIR := $(BUILD_DIR)/reports

.PHONY: all synth sta clean

all: synth sta sim

synth:
	@echo "Running synthesis for top module: $(TOP)"
	mkdir -p $(BUILD_DIR)
	mkdir -p $(REPORT_DIR)
	yosys -s scripts/run.ys

sta:
	@echo "Running STA on synthesized netlist"
	sta scripts/opensta.tcl

sim :
	@echo "Running Simulation"
	iverilog tb/axi2apb_tb.v -o a.out && ./a.out && gtkwave tb_axi2apb.vcd

clean:
	rm -rf $(BUILD_DIR)
