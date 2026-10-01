`timescale 1ns/1ps
// alu.sv -- per-lane integer ALU.
//
// Phase 1 scope: ADD, SUB. Phase 2 extends with MUL/DIV/AND/OR/XOR/SLL/SRL.
//
// TODO(Person B): implement `result` combinationally.
//   op == 2'd0 -> a + b
//   op == 2'd1 -> a - b
//   default    -> 32'b0 (illegal op)
module alu(
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [1:0]  op,
    output logic [31:0] result
);
    always_comb begin
      case (op)
        2'd0: result = a + b;
        2'd1: result = a - b;
        default: result = 32'b0; //illegal op
    endcase
    end
endmodule
