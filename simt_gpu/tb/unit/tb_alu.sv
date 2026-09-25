`timescale 1ns/1ps
// tb_alu.sv -- unit test for alu.sv. Run: make unit TEST=tb_alu
module tb_alu;
    logic [31:0] a, b, result;
    logic [1:0]  op;
    int errors = 0;

    alu dut(.a(a), .b(b), .op(op), .result(result));

    task automatic check(input [31:0] exp, input string name);
        if (result !== exp) begin
            $display("FAIL %0s: got %0d expected %0d", name, result, exp);
            errors++;
        end else $display("PASS %0s", name);
    endtask

    initial begin
        op = 2'd0; a = 32'd10; b = 32'd3; #1; check(32'd13,  "add basic");
        op = 2'd0; a = 32'd0;  b = 32'd0; #1; check(32'd0,   "add zero");
        op = 2'd1; a = 32'd10; b = 32'd3; #1; check(32'd7,   "sub basic");
        op = 2'd1; a = 32'd3;  b = 32'd10;#1; check(32'hFFFFFFF9, "sub negative wraps");
        op = 2'd0; a = 32'hFFFFFFFF; b = 32'd1; #1; check(32'd0, "add overflow wraps");
        if (errors == 0) $display("TB_ALU PASS");
        else $fatal(1, "TB_ALU FAIL: %0d errors", errors);
        $finish;
    end
endmodule
