`timescale 1ns/1ps

module tb_riscv_mc;
    logic clk, reset;
    logic [3:0] state;
    integer errors = 0;
    riscv_mc dut(.clk, .reset, .state);

    initial begin
        clk = 0;
        reset = 1;
    end

    always #5 clk = ~clk;

    initial begin
        wait (state == 8);
        @(posedge clk);
        #1 expect_equal(dut.datapath_inst.pc, 20, "taken branch target");
    end

    task expect_equal(input [31:0] actual, expected, input [255:0] name);
        if (actual !== expected) begin
            $display("FAIL: %0s: expected %h, got %h", name, expected, actual);
            errors = errors + 1;
        end else $display("PASS: %0s", name);
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset = 0;
        // add, store, load, taken branch, skipped sub, or, and
        dut.datapath_inst.imem_inst.memdata[0] = 32'h002081b3; // add x3, x1, x2
        dut.datapath_inst.imem_inst.memdata[1] = 32'h00302023; // sw x3, 0(x0)
        dut.datapath_inst.imem_inst.memdata[2] = 32'h00002203; // lw x4, 0(x0)
        dut.datapath_inst.imem_inst.memdata[3] = 32'h00418463; // beq x3, x4, 8
        dut.datapath_inst.imem_inst.memdata[4] = 32'h402082b3; // sub x5, x1, x2 (skipped)
        dut.datapath_inst.imem_inst.memdata[5] = 32'h0020e333; // or x6, x1, x2
        dut.datapath_inst.imem_inst.memdata[6] = 32'h0020f3b3; // and x7, x1, x2
        dut.datapath_inst.regfile_inst.registers[1] = 10;
        dut.datapath_inst.regfile_inst.registers[2] = 3;

        repeat (40) @(posedge clk);

        expect_equal(dut.datapath_inst.regfile_inst.registers[3], 13, "ADD write-back");
        expect_equal(dut.datapath_inst.dmem_inst.memdata[0], 13, "SW memory write");
        expect_equal(dut.datapath_inst.regfile_inst.registers[4], 13, "LW write-back");
        expect_equal(dut.datapath_inst.regfile_inst.registers[5], 0, "BEQ skips SUB");
        expect_equal(dut.datapath_inst.regfile_inst.registers[6], 11, "OR write-back");
        expect_equal(dut.datapath_inst.regfile_inst.registers[7], 2, "AND write-back");
        if (errors == 0) $display("All multi-cycle processor tests passed.");
        else $fatal(1, "%0d multi-cycle processor tests failed.", errors);
        $finish;
    end
endmodule
