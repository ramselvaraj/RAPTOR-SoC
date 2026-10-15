VERILATOR ?= verilator
OBJ       := build/obj
BIN       := $(OBJ)/Vtb_gpu
SOURCES   := $(shell cat files.txt)

# Prefer the local venv (Pillow/numpy) when present, else system python3.
PY := $(shell if [ -x .venv/bin/python ]; then echo .venv/bin/python; else echo python3; fi)

# Unit tests: DUT + its testbench. Build/run one with `make unit TEST=<name>`.
RTL := rtl/simt_gpu.sv rtl/warp.sv rtl/regfile.sv rtl/alu.sv rtl/decoder.sv \
       rtl/dcr.sv rtl/dispatcher.sv rtl/scheduler.sv rtl/mem_unit.sv

UNIT_SRC_tb_alu        := rtl/alu.sv        tb/unit/tb_alu.sv
UNIT_SRC_tb_decoder    := rtl/decoder.sv    tb/unit/tb_decoder.sv
UNIT_SRC_tb_regfile    := rtl/regfile.sv    tb/unit/tb_regfile.sv
UNIT_SRC_tb_dcr        := rtl/dcr.sv        tb/unit/tb_dcr.sv
UNIT_SRC_tb_dispatcher := rtl/dispatcher.sv tb/unit/tb_dispatcher.sv
UNIT_SRC_tb_scheduler  := rtl/scheduler.sv  tb/unit/tb_scheduler.sv
UNIT_SRC_tb_branch     := $(RTL)            tb/unit/tb_branch.sv

.PHONY: all build unit run test check prog inputs venv clean blur golden branch \
        blur16 blur32 blur64 trace phase3 py-test

SIZE ?= 64

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
	@test -n "$(TEST)" || (echo "usage: make unit TEST=tb_alu|tb_decoder|tb_regfile|tb_dcr|tb_dispatcher|tb_scheduler|tb_branch"; exit 1)
	mkdir -p build/unit/$(TEST)
	$(VERILATOR) --binary --timing --top-module $(TEST) $(UNIT_SRC_$(TEST)) --Mdir build/unit/$(TEST)
	build/unit/$(TEST)/V$(TEST)

# CMP + uniform BRnzp regression (counted loop).
branch:
	$(MAKE) unit TEST=tb_branch

# Full Phase 1 loop: assemble -> golden model -> RTL -> compare -> render.
run: build
	$(PY) tools/run_sim.py

# Phase 2 interior blur (uses .gen_blur in sw/kernels/blur.asm).
blur: build
	$(PY) tools/run_sim.py --kernel sw/kernels/blur.asm

# Golden model + reference only, no RTL.
golden:
	$(PY) tools/run_sim.py --kernel sw/kernels/blur.asm --golden-only

# Phase 3: clamped full-frame blur (interior pass + border pass).
blur16: build
	$(PY) tools/run_sim.py --full --width 16 --height 16

blur32: build
	$(PY) tools/run_sim.py --full --width 32 --height 32

blur64: build
	$(PY) tools/run_sim.py --full --width 64 --height 64

# Phase 3 trace: run an RTL sim with +trace and validate it.
trace: build
	$(PY) tools/run_sim.py --full --width $(SIZE) --height $(SIZE) --trace \
	    --workdir build/run/trace$(SIZE)
	$(PY) tools/check_trace.py --trace build/run/trace$(SIZE)/trace.txt

# Python generator/reference unit tests.
py-test:
	$(PY) tools/tests/test_blur_ref.py
	$(PY) tools/tests/test_blur_border.py

# Full Phase 3 regression.
phase3: build
	$(MAKE) unit TEST=tb_alu
	$(MAKE) unit TEST=tb_decoder
	$(MAKE) unit TEST=tb_regfile
	$(MAKE) unit TEST=tb_dcr
	$(MAKE) unit TEST=tb_dispatcher
	$(MAKE) unit TEST=tb_scheduler
	$(MAKE) branch
	$(MAKE) py-test
	$(MAKE) run
	$(MAKE) blur
	$(MAKE) blur16
	$(MAKE) blur32
	$(MAKE) blur64
	$(MAKE) trace SIZE=64

test: run

venv:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt

clean:
	rm -rf build
