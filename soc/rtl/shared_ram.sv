`timescale 1ns/1ps

module shared_ram #(
    parameter int WORDS = 32768
) (
    input  logic        clk,
    input  logic [14:0] px_addr,
    input  logic        px_we,
    input  logic [31:0] px_wdata,
    output logic [31:0] px_rdata,
    input  logic [14:0] host_addr,
    input  logic        host_we,
    input  logic [31:0] host_wdata,
    output logic [31:0] host_rdata
);
    logic [31:0] mem [0:WORDS-1];

    always_ff @(posedge clk) begin
        // If both ports write the same word, the host write wins.
        // Preserve this priority when replacing the array with a memory macro.
        if (px_we)
            mem[px_addr] <= px_wdata;
        if (host_we)
            mem[host_addr] <= host_wdata;
    end

    assign px_rdata   = mem[px_addr];
    assign host_rdata = mem[host_addr];
endmodule
