`timescale 1ns/1ps
// Request/response channel. A write needs an explicit destination response too.
module cdc_request_channel #(
    parameter int REQUEST_WIDTH=32, RESPONSE_WIDTH=32, DEPTH=4
)(
    input logic sclk, srst, req_valid,
    output logic req_ready,
    input logic [REQUEST_WIDTH-1:0] req_data,
    output logic resp_valid,
    input logic resp_ready,
    output logic [RESPONSE_WIDTH-1:0] resp_data,
    input logic dclk, drst,
    output logic dreq_valid,
    input logic dreq_ready,
    output logic [REQUEST_WIDTH-1:0] dreq_data,
    input logic dresp_valid,
    output logic dresp_ready,
    input logic [RESPONSE_WIDTH-1:0] dresp_data
);
    async_fifo #(.WIDTH(REQUEST_WIDTH), .DEPTH(DEPTH)) requests(
        .wclk(sclk), .wrst(srst), .wvalid(req_valid), .wready(req_ready), .wdata(req_data),
        .rclk(dclk), .rrst(drst), .rvalid(dreq_valid), .rready(dreq_ready), .rdata(dreq_data));
    async_fifo #(.WIDTH(RESPONSE_WIDTH), .DEPTH(DEPTH)) responses(
        .wclk(dclk), .wrst(drst), .wvalid(dresp_valid), .wready(dresp_ready), .wdata(dresp_data),
        .rclk(sclk), .rrst(srst), .rvalid(resp_valid), .rready(resp_ready), .rdata(resp_data));
endmodule
