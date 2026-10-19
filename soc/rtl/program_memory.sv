`timescale 1ns/1ps

module program_memory (
    input  logic        clk,
    input  logic        write_enable,
    input  logic [9:0]  write_addr,
    input  logic [15:0] write_data,
    input  logic [31:0] prog_base,
    input  logic [15:0] imem_addr,
    output logic [15:0] imem_rdata
);
    logic [15:0] mem [0:1023];

    always_ff @(posedge clk) begin
        if (write_enable)
            mem[write_addr] <= write_data;
    end

    assign imem_rdata = mem[(prog_base[9:0] + imem_addr[9:0]) & 10'h3ff];
endmodule
