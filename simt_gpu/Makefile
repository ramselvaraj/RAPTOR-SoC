VERILATOR ?= verilator
OBJ       := build/obj
BIN       := $(OBJ)/Vtb_gpu
SOURCES   := $(shell cat files.txt)

# Prefer the local venv (Pillow/numpy) when present, else system python3.
PY := $(shell if [ -x .venv/bin/python ]; then echo .venv/bin/python; else echo python3; fi)

# Unit tests: DUT + its testbench. Build/run one with `make unit TEST=<name>`.
UNIT_SRC_tb_alu        := rtl/alu.sv        tb/unit/tb_alu.sv
UNIT_SRC_tb_decoder    := rtl/decoder.sv    tb/unit/tb_decoder.sv
UNIT_SRC_tb_regfile    := rtl/regfile.sv    tb/unit/tb_regfile.sv
UNIT_SRC_tb_dcr        := rtl/dcr.sv        tb/unit/tb_dcr.sv
UNIT_SRC_tb_dispatcher := rtl/dispatcher.sv tb/unit/tb_dispatcher.sv
UNIT_SRC_tb_scheduler  := rtl/scheduler.sv  tb/unit/tb_scheduler.sv

.PHONY: all build unit run test check prog inputs venv clean blur golden

all: build

inputs:
	$(PY) tools/prepare_inputs.py

prog:
	mkdir -p build/prog
	$(PY) tools/assemble.py sw/kernels/brighten.asm --out build/prog/brighten.hex --meta build/prog/brighten.json

build: $(BIN)

$(BIN): $(SOURCES) files.txt
	mkdir -p $(OBJ)
	$(VERILATOR) --binary --timing --top-module tb_gpu -f files.txt --Mdir $(OBJ)

unit:
	@test -n "$(TEST)" || (echo "usage: make unit TEST=tb_alu|tb_decoder|tb_regfile|tb_dcr|tb_dispatcher|tb_scheduler"; exit 1)
	mkdir -p build/unit/$(TEST)
	$(VERILATOR) --binary --timing --top-module $(TEST) $(UNIT_SRC_$(TEST)) --Mdir build/unit/$(TEST)
	build/unit/$(TEST)/V$(TEST)

# Full Phase 1 loop: assemble -> golden model -> RTL -> compare -> render.
run: build
	$(PY) tools/run_sim.py

# Phase 2 interior blur (uses .gen_blur in sw/kernels/blur.asm).
blur: build
	$(PY) tools/run_sim.py --kernel sw/kernels/blur.asm

# Golden model + reference only, no RTL.
golden:
	$(PY) tools/run_sim.py --kernel sw/kernels/blur.asm --golden-only

test: run

venv:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt

clean:
	rm -rf build
