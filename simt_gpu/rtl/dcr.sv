`timescale 1ns/1ps
// dcr.sv -- Device Control Registers (Phase 1: direct signals, Phase 4: MMIO).
//
// Behaviour:
//   - On `start` high: latch thread_count/src_addr/dst_addr, assert busy.
//   - While busy and all_halted: deassert busy and pulse `done` for one cycle.
//   - `done` is a single-cycle pulse.
//
// TODO(Person A): implement the register update + busy/done handshake.
//   Suggested:
//     done <= 0 each cycle;
//     if (start) begin busy<=1; q<=inputs; end
//     else if (busy && all_halted) begin busy<=0; done<=1; end
module dcr(
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [31:0] thread_count,
    input  logic [31:0] src_addr,
    input  logic [31:0] dst_addr,
    input  logic        all_halted,
    output logic        busy,
    output logic        done,
    output logic [31:0] thread_count_q,
    output logic [31:0] src_addr_q,
    output logic [31:0] dst_addr_q
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy          <= 1'b0;
            done          <= 1'b0;
            thread_count_q <= 32'b0;
            src_addr_q     <= 32'b0;
            dst_addr_q     <= 32'b0;
        end
        // TODO(Person A): start / busy / done logic
    end
endmodule
