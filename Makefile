VERILATOR ?= verilator
PY := $(shell if [ -x simt_gpu/.venv/bin/python ]; then echo simt_gpu/.venv/bin/python; else echo python3; fi)

.PHONY: axi cpu soc soc16 soc32 soc64 phase4 run blur blur16 blur32 blur64 golden branch trace phase3 unit clean

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

soc/build/obj/Vtb_soc: soc/files.txt $(shell cat soc/files.txt)
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

phase4: axi cpu phase3 soc16 soc32 soc64

run blur blur16 blur32 blur64 golden branch phase3:
	$(MAKE) -C simt_gpu $@

trace:
	$(MAKE) -C simt_gpu trace SIZE=$(SIZE)

unit:
	$(MAKE) -C simt_gpu unit TEST=$(TEST)

clean:
	rm -rf soc/build
	$(MAKE) -C simt_gpu clean
