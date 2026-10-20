`timescale 1ns/1ps
package rv32_pkg;
    typedef struct packed {
        logic valid;
        logic [31:0] pc, instruction;
    } if_id_t;
    typedef struct packed {
        logic valid;
        logic [31:0] pc, instruction, a, b, imm;
        logic [4:0] rs1, rs2, rd;
        logic write_rd, load, store, branch, jal, jalr, lui, auipc, immediate;
        logic use_rs1, use_rs2;
        logic [3:0] alu_op;
        logic [2:0] funct3;
    } id_ex_t;
    typedef struct packed {
        logic valid;
        logic [31:0] pc, instruction, result, store_data;
        logic [4:0] rd;
        logic write_rd, load, store;
        logic [2:0] funct3;
    } ex_mem_t;
    typedef struct packed {
        logic valid;
        logic [31:0] pc, instruction, result;
        logic [4:0] rd;
        logic write_rd;
    } mem_wb_t;
    localparam logic [3:0] ADD=0, SUB=1, AND_OP=2, OR_OP=3, XOR_OP=4,
                          SLT=5, SLTU=6, SLL=7, SRL=8, SRA=9;
endpackage
