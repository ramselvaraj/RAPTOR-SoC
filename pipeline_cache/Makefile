ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD ?= $(ROOT)/soc/build/phase5/cpu
VERILATOR ?= verilator

.PHONY: test cpu-test cache-test fault-test
test: cpu-test cache-test fault-test

cpu-test:
	mkdir -p $(BUILD)/wb $(BUILD)/wt $(BUILD)/large $(BUILD)/fast
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_pipeline_cache -f pipeline_cache/files.txt --Mdir $(BUILD)/wb
	$(BUILD)/wb/Vtb_pipeline_cache
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_pipeline_cache -f pipeline_cache/files.txt -GWRITE_BACK=0 -GMAX_DELAY=0 -GSEED=47 --Mdir $(BUILD)/wt
	$(BUILD)/wt/Vtb_pipeline_cache
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_pipeline_cache -f pipeline_cache/files.txt -GCACHE_LINES=8 -GLINE_WORDS=8 -GMAX_DELAY=13 -GSEED=91 --Mdir $(BUILD)/large
	$(BUILD)/large/Vtb_pipeline_cache
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_pipeline_cache -f pipeline_cache/files.txt -GFAST_FETCH=1 --Mdir $(BUILD)/fast
	$(BUILD)/fast/Vtb_pipeline_cache

cache-test:
	mkdir -p $(BUILD)/cache_wb $(BUILD)/cache_wt
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_blocking_cache -f pipeline_cache/cache_files.txt --Mdir $(BUILD)/cache_wb
	$(BUILD)/cache_wb/Vtb_blocking_cache
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_blocking_cache -f pipeline_cache/cache_files.txt -GWRITE_BACK=0 -GLINES=8 -GLINE_WORDS=8 --Mdir $(BUILD)/cache_wt
	$(BUILD)/cache_wt/Vtb_blocking_cache

fault-test:
	mkdir -p $(BUILD)/faults
	cd $(ROOT) && $(VERILATOR) --binary --timing --assert --top-module tb_core_faults -f pipeline_cache/fault_files.txt --Mdir $(BUILD)/faults
	$(BUILD)/faults/Vtb_core_faults
