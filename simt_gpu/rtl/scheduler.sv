`timescale 1ns/1ps
// scheduler.sv -- round-robin warp scheduler.
//
// Grants exactly one ready warp per cycle, rotating so no ready warp starves.
// When no warp is ready, grant == 0.
//
// TODO(Person A): implement round-robin.
//   Suggested: keep a `last` pointer (0..WARPS-1). Scan from `last` forward for
//   the first ready warp; grant it one-hot. Advance `last` past the granted
//   warp on the next edge.
module scheduler #(parameter int WARPS = 2)(
    input  logic             clk,
    input  logic             reset,
    input  logic [WARPS-1:0] ready,
    output logic [WARPS-1:0] grant
);
    always_comb begin
        grant = '0;  // TODO(Person A)
    end
endmodule
