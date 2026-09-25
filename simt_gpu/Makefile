VERILATOR ?= verilator
OBJ       := build/obj
BIN       := $(OBJ)/Vtb_gpu
SOURCES   := $(shell cat files.txt)

# Prefer the local venv (Pillow/numpy) when present, else system python3.
PY := $(shell if [ -x .venv/bin/python ]; then echo .venv/bin/python; else echo python3; fi)

.PHONY: all build run test venv clean inputs

all: build

inputs:
	$(PY) tools/prepare_inputs.py

build: $(BIN)

$(BIN): $(SOURCES) files.txt
	mkdir -p $(OBJ)
	$(VERILATOR) --binary --timing --top-module tb_gpu -f files.txt --Mdir $(OBJ)

# Full Phase 0 loop: generate frame -> simulate -> verify echo -> render.
run: build
	$(PY) tools/run_sim.py

test: run

venv:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt

clean:
	rm -rf build
