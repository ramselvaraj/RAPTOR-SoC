`timescale 1ns/1ps
// Dual-clock storage; only Gray pointers cross through synchronizer chains.
// Coordinated reset is required. The read side is first-word fall-through.
module async_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 4,
    localparam int A = $clog2(DEPTH)
)(
    input logic wclk, wrst, wvalid,
    output logic wready,
    input logic [WIDTH-1:0] wdata,
    input logic rclk, rrst,
    output logic rvalid,
    input logic rready,
    output logic [WIDTH-1:0] rdata
);
    logic [WIDTH-1:0] storage [DEPTH];
    logic [A:0] wb, wg, rb, rg;
    (* ASYNC_REG = "TRUE" *) logic [A:0] rg1, rg2, wg1, wg2;
    logic full, empty;
    logic [A:0] full_compare;
    assign full_compare = rg2 ^ ((A+1)'(3) << (A-1));
    assign full = wg == full_compare;
    assign empty = rg == wg2;
    assign wready = !wrst && !full;
    assign rvalid = !rrst && !empty;
    assign rdata = storage[rb[A-1:0]];
    always_ff @(posedge wclk or posedge wrst) begin
        if (wrst) begin wb <= 0; wg <= 0; rg1 <= 0; rg2 <= 0; end
        else begin
            rg1 <= rg; rg2 <= rg1;
            if (wvalid && wready) begin
                storage[wb[A-1:0]] <= wdata;
                wb <= wb + 1'b1;
                wg <= ((wb + 1'b1) >> 1) ^ (wb + 1'b1);
            end
        end
    end
    always_ff @(posedge rclk or posedge rrst) begin
        if (rrst) begin rb <= 0; rg <= 0; wg1 <= 0; wg2 <= 0; end
        else begin
            wg1 <= wg; wg2 <= wg1;
            if (rvalid && rready) begin
                rb <= rb + 1'b1;
                rg <= ((rb + 1'b1) >> 1) ^ (rb + 1'b1);
            end
        end
    end
`ifndef SYNTHESIS
    initial assert (DEPTH >= 2 && (DEPTH & (DEPTH-1)) == 0)
        else $fatal(1, "async_fifo requires power-of-two DEPTH >= 2");
    assert property (@(posedge wclk) disable iff(wrst)
        wvalid && !wready |=> wvalid && $stable(wdata));
    assert property (@(posedge rclk) disable iff(rrst)
        rvalid && !rready |=> rvalid && $stable(rdata));
    assert property (@(posedge wclk) disable iff(wrst) $onehot0(wg ^ $past(wg)));
    assert property (@(posedge rclk) disable iff(rrst) $onehot0(rg ^ $past(rg)));
`endif
endmodule
