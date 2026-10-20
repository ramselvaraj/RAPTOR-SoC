module riscv_mc(
    input logic clk,
    input logic reset,
    input logic imem_we,
    input logic [9:0] imem_waddr,
    input logic [31:0] imem_wdata,
`ifdef RAPTOR_EXTERNAL_MEMORIES
    output logic [31:0] imem_addr,
    input logic [31:0] imem_rdata,
`endif
    output logic mem_req,
    output logic mem_we,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input logic [31:0] mem_rdata,
    input logic mem_done,
    output logic [3:0] state
);
    logic pc_write, ir_write, ab_write, aluout_write, mdr_write, reg_write;
    logic mem_start, mem_write, mem_rd_done, mem_wr_done, branch_ne;
    logic alu_src_a_pc, writeback_from_memory, pc_next_from_aluout, funct7_bit, zero;
    logic [2:0] alu_src_b;
    logic [2:0] alu_operation, funct3;
    logic [6:0] opcode;

    assign mem_req = mem_start;
    assign mem_we = mem_write;
    assign mem_rd_done = mem_done;
    assign mem_wr_done = mem_done;

    mc_controller controller_inst(.*);
    mc_datapath datapath_inst(.*);
endmodule
