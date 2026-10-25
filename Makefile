# Makefile - axi2apb_bridge (portfolio copy). The as-found Makefile is kept as Makefile.original (make -f Makefile.original synth sta sim).
PYTHON ?= python3
.DEFAULT_GOAL := help
.PHONY: help
help:
	@echo "make lint      Verilator -Wall on the bridge"
	@echo "make seeds     self-checking testbench over 8 seeds (bound assertions on)       -> results/regression.txt"
	@echo "make baseline  the as-found RTL against the same testbench: shows the PSLVERR bug -> results/baseline_original.txt"
	@echo "make cov       merged coverage (named cover points + lines)                       -> results/coverage_summary.txt"
	@echo "make mutants   15 injected bugs, with and without the assertions                  -> results/mutants.txt"
	@echo "make check     lint seeds cov"
	@echo "make clean"

.PHONY: lint
lint:
	@verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE src/axi2apb.v --top-module axi2apb && echo "[LINT] clean except two known, documented warnings (unused sampled_wdata register; output-decode case without default)"

.PHONY: seeds baseline cov mutants
seeds:
	@$(PYTHON) scripts/campaign.py seeds
baseline:
	@$(PYTHON) scripts/campaign.py baseline
cov:
	@$(PYTHON) scripts/campaign.py cov
mutants:
	@$(PYTHON) scripts/campaign.py mutants --jobs 3

.PHONY: check
check: lint seeds cov
	@echo "[CHECK] all gates passed"

.PHONY: clean
clean:
	rm -rf build
