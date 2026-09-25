`timescale 1ns/1ps
// dispatcher.sv -- maps a thread count onto warps and lanes.
//
// For warp w, lane l:
//   tid            = w*LANES + l
//   warp_tid_base[w] = w*LANES
//   warp_lane_mask[w][l] = (tid < thread_count)
//
// `warp_start` follows `start` (single-cycle launch pulse). `thread_count` is
// stable for the duration of a launch, so this block is purely combinational.
//
// TODO(Person A): fill in warp_start / warp_tid_base / warp_lane_mask.
module dispatcher #(parameter int WARPS = 2, parameter int LANES = 4)(
    input  logic                        start,
    input  logic [31:0]                 thread_count,
    output logic [WARPS-1:0]            warp_start,
    output logic [WARPS-1:0][31:0]      warp_tid_base,
    output logic [WARPS-1:0][LANES-1:0] warp_lane_mask
);
    always_comb begin
        warp_start     = '0;  // TODO(Person A)
        warp_tid_base  = '0;  // TODO(Person A)
        warp_lane_mask = '0;  // TODO(Person A)
    end
endmodule
