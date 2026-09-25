`timescale 1ns/1ps
// mem_unit.sv -- serialized per-lane memory access for one warp.
//
// Phase 1 has a single 32-bit word port, but a SIMT LDR/STR is per-lane, so
// this unit walks lanes one at a time:
//   lane_ptr 0..LANES-1; skip lanes whose mask bit is 0;
//   for each active lane issue one bus transfer at (base + idx);
//   for loads, capture mem_rdata into load_data[lane].
// On finishing all lanes it pulses `done` for one cycle.
//
// This is the *uncoalesced baseline*. Phase 2 replaces it with a coalescing
// unit that merges consecutive-lane accesses.
//
// TODO(Person A):
//   - on start: busy<=1, lane_ptr<=0, done<=0, clear load_data.
//   - while busy:
//       * advance lane_ptr past inactive lanes;
//       * assert mem_req, mem_we=is_store, mem_addr=base[idx]+idx[idx],
//         mem_wdata=data_val[lane_ptr];
//       * when mem_ready: for loads capture load_data[lane_ptr]<=mem_rdata;
//         lane_ptr++;
//       * when lane_ptr==LANES: busy<=0, done<=1.
module mem_unit #(parameter int LANES = 4)(
    input  logic             clk,
    input  logic             reset,
    input  logic             start,
    input  logic             is_store,
    input  logic [LANES-1:0] lane_mask,
    input  logic [31:0]      base_val [LANES],
    input  logic [31:0]      idx_val  [LANES],
    input  logic [31:0]      data_val [LANES],
    output logic             mem_req,
    output logic             mem_we,
    output logic [31:0]      mem_addr,
    output logic [31:0]      mem_wdata,
    input  logic [31:0]      mem_rdata,
    input  logic             mem_ready,
    output logic [31:0]      load_data [LANES],
    output logic             done
);
    always_comb begin
        mem_req   = 1'b0;   // TODO(Person A)
        mem_we    = 1'b0;   // TODO(Person A)
        mem_addr  = 32'b0;  // TODO(Person A)
        mem_wdata = 32'b0;  // TODO(Person A)
        done      = 1'b0;   // TODO(Person A)
        for (int l = 0; l < LANES; l++) load_data[l] = 32'b0;
    end
endmodule
