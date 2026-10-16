`timescale 1ns/1ps

module program_memory (
    input  logic [31:0] prog_base,
    input  logic [15:0] imem_addr,
    output logic [15:0] imem_rdata
);
    logic [15:0] mem [0:1023];

    assign imem_rdata = mem[(prog_base[9:0] + imem_addr[9:0]) & 10'h3ff];
endmodule
