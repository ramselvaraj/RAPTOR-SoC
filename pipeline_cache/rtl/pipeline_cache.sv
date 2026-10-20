`timescale 1ns/1ps
module pipeline_cache #(
    parameter int CACHE_LINES = 4,
    parameter int WORDS_PER_LINE = 4,
    parameter bit DATA_WRITE_BACK = 1,
    parameter bit BYPASS_ICACHE = 0,
    parameter bit REGION_BYPASS = 0,
    parameter bit BYPASS_DCACHE = 0
)(
    input logic clk, reset,
    output logic imem_req_valid,
    input logic imem_req_ready,
    output logic [31:0] imem_req_addr, imem_req_data,
    output logic [3:0] imem_req_strb,
    input logic imem_resp_valid,
    output logic imem_resp_ready,
    input logic [31:0] imem_resp_data,
    output logic dmem_req_valid,
    input logic dmem_req_ready,
    output logic [31:0] dmem_req_addr, dmem_req_data,
    output logic [3:0] dmem_req_strb,
    input logic dmem_resp_valid,
    output logic dmem_resp_ready,
    input logic [31:0] dmem_resp_data,
    output logic retire_valid, retire_write,
    output logic [31:0] retire_pc, retire_instruction, retire_data,
    output logic [4:0] retire_rd,
    output logic [63:0] cycles, retired, load_stalls, memory_stalls, fetch_stalls, redirects, branch_misses,
    output logic [63:0] icache_hits, icache_misses, dcache_hits, dcache_misses, dcache_writebacks,
    output logic fault
);
    logic iv, ir, irv, irr, dv, dr, drv, drr;
    logic [31:0] ia, idata, da, dw, dread;
    logic [3:0] ds;
    logic [63:0] unused_i_writebacks;
    cache_pipeline_core core(
        .clk, .reset,
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia),
        .i_resp_valid(irv), .i_resp_ready(irr), .i_resp_data(idata),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_data(dw), .d_req_strb(ds),
        .d_resp_valid(drv), .d_resp_ready(drr), .d_resp_data(dread),
        .retire_valid, .retire_write, .retire_pc, .retire_instruction, .retire_data, .retire_rd,
        .cycles, .retired, .load_stalls, .memory_stalls, .fetch_stalls, .redirects, .branch_misses, .fault
    );
    generate if (BYPASS_ICACHE) begin : uncached_fetch
        assign imem_req_valid = iv;
        assign ir = imem_req_ready;
        assign imem_req_addr = ia;
        assign imem_req_data = 0;
        assign imem_req_strb = 0;
        assign irv = imem_resp_valid;
        assign imem_resp_ready = irr;
        assign idata = imem_resp_data;
        assign icache_hits = 0;
        assign icache_misses = 0;
        assign unused_i_writebacks = 0;
    end else begin : cached_fetch
    blocking_cache #(.LINES(CACHE_LINES), .WORDS_PER_LINE(WORDS_PER_LINE), .READ_ONLY(1)) icache(
        .clk, .reset, .req_valid(iv), .req_ready(ir), .req_addr(ia), .req_data(32'b0), .req_strb(4'b0),
        .resp_valid(irv), .resp_ready(irr), .resp_data(idata),
        .mem_req_valid(imem_req_valid), .mem_req_ready(imem_req_ready),
        .mem_req_addr(imem_req_addr), .mem_req_data(imem_req_data), .mem_req_strb(imem_req_strb),
        .mem_resp_valid(imem_resp_valid), .mem_resp_ready(imem_resp_ready), .mem_resp_data(imem_resp_data),
        .hits(icache_hits), .misses(icache_misses), .writebacks(unused_i_writebacks)
    );
    end endgenerate
    generate if (REGION_BYPASS || BYPASS_DCACHE) begin : routed_data
    cache_data_router #(.LINES(CACHE_LINES), .WORDS_PER_LINE(WORDS_PER_LINE), .BYPASS(BYPASS_DCACHE), .WRITE_BACK(DATA_WRITE_BACK)) router(
        .clk, .reset, .req_valid(dv), .req_ready(dr), .req_addr(da), .req_data(dw), .req_strb(ds),
        .resp_valid(drv), .resp_ready(drr), .resp_data(dread),
        .mem_req_valid(dmem_req_valid), .mem_req_ready(dmem_req_ready),
        .mem_req_addr(dmem_req_addr), .mem_req_data(dmem_req_data), .mem_req_strb(dmem_req_strb),
        .mem_resp_valid(dmem_resp_valid), .mem_resp_ready(dmem_resp_ready), .mem_resp_data(dmem_resp_data),
        .hits(dcache_hits), .misses(dcache_misses), .writebacks(dcache_writebacks));
    end else begin : original_data
    blocking_cache #(.LINES(CACHE_LINES), .WORDS_PER_LINE(WORDS_PER_LINE), .WRITE_BACK(DATA_WRITE_BACK)) dcache(
        .clk, .reset, .req_valid(dv), .req_ready(dr), .req_addr(da), .req_data(dw), .req_strb(ds),
        .resp_valid(drv), .resp_ready(drr), .resp_data(dread),
        .mem_req_valid(dmem_req_valid), .mem_req_ready(dmem_req_ready),
        .mem_req_addr(dmem_req_addr), .mem_req_data(dmem_req_data), .mem_req_strb(dmem_req_strb),
        .mem_resp_valid(dmem_resp_valid), .mem_resp_ready(dmem_resp_ready), .mem_resp_data(dmem_resp_data),
        .hits(dcache_hits), .misses(dcache_misses), .writebacks(dcache_writebacks)
    );
    end endgenerate
endmodule
