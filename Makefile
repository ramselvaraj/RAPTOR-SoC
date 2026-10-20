VERILATOR ?= verilator
DC_SHELL ?= dc_shell
SOC_RTL := $(shell cat soc/rtl/files.txt)
CORE_RTL := $(filter-out soc/rtl/shared_ram.sv soc/rtl/program_memory.sv multi_cycle/rtl/instruction_memory.sv,$(SOC_RTL))
.DEFAULT_GOAL := axi
PY := $(shell if [ -x simt_gpu/.venv/bin/python ]; then echo simt_gpu/.venv/bin/python; else echo python3; fi)

.PHONY: axi cpu boot lint lint-core dc dc-elab dc-core dc-core-elab dc-core-report core-test soc soc16 soc32 soc64 phase4 run blur blur16 blur32 blur64 golden branch trace phase3 unit clean

# Reset also gates the programming port, so synchronous and asynchronous uses
# are intentional. Keep undriven signals, latches, and width warnings fatal.
lint:
	$(VERILATOR) --lint-only -Wall -DSYNTHESIS --top-module soc_top \
		-Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
		-Wno-SYNCASYNCNET -f soc/rtl/files.txt

dc:
	$(DC_SHELL) -f synth/dc.tcl

dc-elab:
	DC_ELAB_ONLY=1 $(DC_SHELL) -f synth/dc.tcl

dc-core:
	DC_MODE=core $(DC_SHELL) -f synth/dc.tcl

dc-core-elab:
	DC_MODE=core DC_ELAB_ONLY=1 $(DC_SHELL) -f synth/dc.tcl

dc-core-report:
	DC_MODE=core DC_REPORT_ONLY=1 $(DC_SHELL) -f synth/dc.tcl

lint-core:
	$(VERILATOR) --lint-only -Wall -DSYNTHESIS -DRAPTOR_EXTERNAL_MEMORIES \
		--top-module soc_top -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY \
		-Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET $(CORE_RTL)

soc/build/core/Vtb_soc: soc/files.txt soc/rtl/files.txt $(SOC_RTL) soc/tb/tb_soc.sv
	mkdir -p soc/build/core
	$(VERILATOR) --binary --timing -Wno-fatal -DRAPTOR_EXTERNAL_MEMORIES \
		--top-module tb_soc -f soc/files.txt --Mdir soc/build/core

core-test: lint-core soc/build/core/Vtb_soc
	$(PY) soc/tools/run_soc.py --width 16 --height 16 --binary soc/build/core/Vtb_soc --workdir soc/build/run/core16
	$(PY) soc/tools/run_soc.py --width 32 --height 32 --binary soc/build/core/Vtb_soc --workdir soc/build/run/core32
	$(PY) soc/tools/run_soc.py --width 64 --height 64 --binary soc/build/core/Vtb_soc --workdir soc/build/run/core64

soc/build/boot/Vtb_boot: soc/rtl/files.txt $(SOC_RTL) soc/tb/tb_boot.sv
	mkdir -p soc/build/boot
	$(VERILATOR) --binary --timing -Wno-fatal --top-module tb_boot \
		-f soc/rtl/files.txt soc/tb/tb_boot.sv --Mdir soc/build/boot

boot: soc/build/boot/Vtb_boot
	soc/build/boot/Vtb_boot

axi:
	mkdir -p soc/build/axi
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_axi_lite \
		soc/rtl/shared_ram.sv soc/rtl/axi_lite_ram.sv soc/rtl/gpu_mmio.sv \
		soc/rtl/axi_lite_interconnect.sv soc/tb/axi_lite_checker.sv \
		soc/tb/tb_axi_lite.sv --Mdir soc/build/axi
	soc/build/axi/Vtb_axi_lite

cpu:
	mkdir -p soc/build/cpu
	$(VERILATOR) --binary --timing -Wno-fatal --top-module tb_riscv_mc \
		soc/rtl/cpu_axi_master.sv -f multi_cycle/files.txt --Mdir soc/build/cpu
	soc/build/cpu/Vtb_riscv_mc

soc/build/obj/Vtb_soc: soc/files.txt soc/rtl/files.txt $(SOC_RTL) soc/tb/tb_soc.sv
	mkdir -p soc/build/obj
	$(VERILATOR) --binary --timing -Wno-fatal --top-module tb_soc \
		-f soc/files.txt --Mdir soc/build/obj

soc16: soc/build/obj/Vtb_soc
	$(PY) soc/tools/run_soc.py --width 16 --height 16

soc32: soc/build/obj/Vtb_soc
	$(PY) soc/tools/run_soc.py --width 32 --height 32

soc64: soc/build/obj/Vtb_soc
	$(PY) soc/tools/run_soc.py --width 64 --height 64

soc: soc64

phase4: lint core-test boot axi cpu phase3 soc16 soc32 soc64

run blur blur16 blur32 blur64 golden branch phase3:
	$(MAKE) -C simt_gpu $@

trace:
	$(MAKE) -C simt_gpu trace SIZE=$(SIZE)

unit:
	$(MAKE) -C simt_gpu unit TEST=$(TEST)

clean:
	rm -rf soc/build
	$(MAKE) -C simt_gpu clean
