`timescale 1ns/1ps
// alu.sv -- per-lane integer ALU.
//
// Phase 1: ADD, SUB. Phase 2 adds MUL, DIV, AND, OR, XOR, SLL, SRL.
//
// op encoding (from warp.sv):
//   0 ADD   1 SUB   2 MUL   3 DIV   4 AND   5 OR   6 XOR   7 SLL   8 SRL
//
// TODO(Person B): implement the Phase 2 ops. Shifts use b[4:0] as the amount.
//   MUL: a * b          DIV: a / b (unsigned; b==0 -> 0)
//   AND: a & b          OR:  a | b          XOR: a ^ b
//   SLL: a << b[4:0]    SRL: a >> b[4:0]
module alu(
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  op,
    output logic [31:0] result
);
    always_comb begin
        case (op)
            4'd0: result = a + b;             // ADD
            4'd1: result = a - b;             // SUB
            // TODO(Person B): 4'd2..4'd8 (MUL/DIV/AND/OR/XOR/SLL/SRL)
            default: result = 32'b0;          // illegal op
        endcase
    end
endmodule
