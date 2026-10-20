VERILATOR ?= verilator
DC_SHELL ?= dc_shell
SOC_RTL := $(shell cat soc/rtl/files.txt)
CORE_RTL := $(filter-out soc/rtl/shared_ram.sv soc/rtl/program_memory.sv multi_cycle/rtl/instruction_memory.sv,$(SOC_RTL))
.DEFAULT_GOAL := axi
PHASE5_RTL := $(shell cat soc/phase5_files.txt)
PY := $(shell if [ -x simt_gpu/.venv/bin/python ]; then echo simt_gpu/.venv/bin/python; else echo python3; fi)

.PHONY: axi cpu boot lint lint-core dc dc-elab dc-core dc-core-elab dc-core-report dc-core-sweep core-test soc soc16 soc32 soc64 phase4 run blur blur16 blur32 blur64 golden branch trace phase3 unit clean
.PHONY: phase5 phase5-cpu phase5-bus phase5-cdc phase5-soc phase5-lint
.PHONY: dc-phase5-core dc-phase5-elab dc-phase5-sweep dc-phase5-cpu-check dc-phase5-boot-check

dc-phase5-boot-check:
	DC_MODE=phase5 DC_PHASE5_CPU_CHECK=1 DC_BOOT_CONTRACT=1 $(DC_SHELL) -f synth/dc.tcl

dc-phase5-cpu-check:
	DC_MODE=phase5 DC_PHASE5_CPU_CHECK=1 $(DC_SHELL) -f synth/dc.tcl

dc-phase5-sweep:
	DC_MODE=phase5 DC_PHASE5_SWEEP=1 $(DC_SHELL) -f synth/dc.tcl

dc-phase5-core:
	DC_MODE=phase5 $(DC_SHELL) -f synth/dc.tcl

dc-phase5-elab:
	DC_MODE=phase5 DC_ELAB_ONLY=1 $(DC_SHELL) -f synth/dc.tcl

phase5-cpu:
	$(MAKE) -f pipeline_cache/Makefile test

phase5-lint:
	$(VERILATOR) --lint-only --timing --assert -Wall --top-module soc_phase5_top \
		-Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET -f soc/phase5_files.txt
	$(VERILATOR) --lint-only -Wall -DSYNTHESIS -DRAPTOR_EXTERNAL_MEMORIES --top-module soc_phase5_top \
		-Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-SYNCASYNCNET -f soc/phase5_files.txt

soc/build/phase5/obj/Vtb_soc_phase5: $(PHASE5_RTL) soc/phase5_files.txt soc/tb/tb_soc_phase5.sv
	mkdir -p soc/build/phase5/obj
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_soc_phase5 \
		-f soc/phase5_files.txt soc/tb/tb_soc_phase5.sv --Mdir soc/build/phase5/obj

soc/build/phase5/nocache/Vtb_soc_phase5: $(PHASE5_RTL) soc/phase5_files.txt soc/tb/tb_soc_phase5.sv
	mkdir -p soc/build/phase5/nocache
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_soc_phase5 -GCACHE_ENABLE=0 \
		-f soc/phase5_files.txt soc/tb/tb_soc_phase5.sv --Mdir soc/build/phase5/nocache

soc/build/phase5/shallow/Vtb_soc_phase5: $(PHASE5_RTL) soc/phase5_files.txt soc/tb/tb_soc_phase5.sv
	mkdir -p soc/build/phase5/shallow
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_soc_phase5 -GFIFO_DEPTH=2 \
		-f soc/phase5_files.txt soc/tb/tb_soc_phase5.sv --Mdir soc/build/phase5/shallow

phase5-soc: soc/build/phase5/obj/Vtb_soc_phase5 soc/build/phase5/nocache/Vtb_soc_phase5 soc/build/phase5/shallow/Vtb_soc_phase5
	$(PY) soc/tools/run_phase5.py

phase5-bus:
	mkdir -p soc/build/phase5/router
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_phase5_router \
		pipeline_cache/rtl/blocking_cache.sv pipeline_cache/rtl/cache_data_router.sv soc/tb/tb_phase5_router.sv --Mdir soc/build/phase5/router
	soc/build/phase5/router/Vtb_phase5_router
	mkdir -p soc/build/phase5/axi
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_phase5_axi \
		soc/rtl/cpu_request_axi.sv soc/tb/tb_phase5_axi.sv --Mdir soc/build/phase5/axi
	soc/build/phase5/axi/Vtb_phase5_axi
	mkdir -p soc/build/phase5/mmio
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_phase5_mmio \
		soc/rtl/gpu_mmio.sv soc/tb/tb_phase5_mmio.sv --Mdir soc/build/phase5/mmio
	soc/build/phase5/mmio/Vtb_phase5_mmio

phase5-cdc:
	@for depth in 2 4 8; do \
		mkdir -p soc/build/phase5/cdc$$depth; \
		$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_phase5_cdc -GDEPTH=$$depth \
			soc/rtl/reset_release.sv soc/rtl/async_fifo.sv soc/rtl/cdc_request_channel.sv soc/tb/tb_phase5_cdc.sv \
			--Mdir soc/build/phase5/cdc$$depth && soc/build/phase5/cdc$$depth/Vtb_phase5_cdc || exit 1; \
	done
	mkdir -p soc/build/phase5/launch
	$(PY) soc/tools/riscv_asm.py soc/tb/programs/launch_stress.asm -o soc/build/phase5/launch.hex
	$(VERILATOR) --binary --timing --assert -Wno-fatal --top-module tb_phase5_launch \
		-f soc/phase5_files.txt soc/tb/tb_phase5_launch.sv --Mdir soc/build/phase5/launch
	soc/build/phase5/launch/Vtb_phase5_launch

phase5: phase5-lint phase5-cpu phase5-bus phase5-cdc phase5-soc phase4

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

dc-core-sweep:
	DC_MODE=core DC_CONSTRAINT_SWEEP=1 $(DC_SHELL) -f synth/dc.tcl

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
