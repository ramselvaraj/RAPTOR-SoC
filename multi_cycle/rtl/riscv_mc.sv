module riscv_mc(
    input logic clk,
    input logic reset,
    output logic [3:0] state
);
    logic pc_write, ir_write, ab_write, aluout_write, mdr_write, reg_write, mem_write, mem_read;
    logic alu_src_a_pc, writeback_from_memory, pc_next_from_aluout, funct7_bit, zero;
    logic [1:0] alu_src_b;
    logic [2:0] alu_operation, funct3;
    logic [6:0] opcode;

    mc_controller controller_inst(.*);
    mc_datapath datapath_inst(.*);
endmodule
