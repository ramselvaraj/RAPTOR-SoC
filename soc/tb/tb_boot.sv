`timescale 1ns/1ps

module tb_boot;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic boot_we = 1'b0;
    logic [1:0] boot_sel = 2'd0;
    logic [14:0] boot_addr = '0;
    logic [31:0] boot_wdata = '0;
    logic [31:0] boot_rdata;
    logic [3:0] cpu_state;
    logic gpu_start, gpu_busy, gpu_done, gpu_mem_req, gpu_mem_we;
    logic [31:0] gpu_mem_addr, gpu_mem_wdata;

    soc_top dut (.*);
    always #5 clk = ~clk;

    task automatic boot_write(
        input logic [1:0] sel,
        input logic [14:0] addr,
        input logic [31:0] data
    );
        @(negedge clk);
        boot_we = 1'b1;
        boot_sel = sel;
        boot_addr = addr;
        boot_wdata = data;
        @(negedge clk);
        boot_we = 1'b0;
    endtask

    task automatic expect_equal(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string name
    );
        if (actual !== expected)
            $fatal(1, "%s: got %08x, expected %08x", name, actual, expected);
    endtask

    task automatic check_images;
        // Hierarchical observation is test-only. All writes use the real pins.
        expect_equal(dut.cpu.datapath_inst.imem_inst.memdata[0],
                     32'h0000_0063, "CPU first word");
        expect_equal(dut.cpu.datapath_inst.imem_inst.memdata[1023],
                     32'h1234_5678, "CPU last word");
        expect_equal({16'b0, dut.program_mem.mem[0]}, 32'h0000_c000, "GPU first word");
        expect_equal({16'b0, dut.program_mem.mem[1023]}, 32'h0000_abcd, "GPU last word");
        expect_equal(dut.ram.mem[0], 32'h1122_3344, "RAM first word");
        expect_equal(dut.ram.mem[32767], 32'h5566_7788, "RAM last word");
    endtask

    initial begin
        boot_write(2'd0, 15'd0, 32'h0000_0063); // beq x0,x0,0
        boot_write(2'd0, 15'd1023, 32'h1234_5678);
        boot_write(2'd1, 15'd0, 32'hffff_c000); // upper bits must be ignored
        boot_write(2'd1, 15'd1023, 32'hffff_abcd);
        boot_write(2'd2, 15'd0, 32'h1122_3344);
        boot_write(2'd2, 15'd32767, 32'h5566_7788);
        check_images();

        // Invalid instruction addresses must not wrap into either program.
        boot_write(2'd0, 15'd1024, 32'hdead_beef);
        boot_write(2'd1, 15'd1024, 32'hdead_beef);
        boot_write(2'd3, 15'd0, 32'hdead_beef);
        check_images();
        #1;
        expect_equal(boot_rdata, 32'b0, "reserved readback");

        boot_sel = 2'd2;
        boot_addr = 15'd0;
        #1;
        expect_equal(boot_rdata, 32'h1122_3344, "RAM first readback");
        boot_addr = 15'd32767;
        #1;
        expect_equal(boot_rdata, 32'h5566_7788, "RAM last readback");
        boot_sel = 2'd0;
        #1;
        expect_equal(boot_rdata, 32'b0, "instruction readback disabled");

        @(negedge clk);
        reset = 1'b0;
        boot_write(2'd0, 15'd0, 32'hdead_beef);
        boot_write(2'd1, 15'd0, 32'hdead_beef);
        boot_write(2'd2, 15'd0, 32'hdead_beef);
        check_images();
        expect_equal(boot_rdata, 32'b0, "running readback disabled");

        // A subsequent reset must preserve the images.
        @(negedge clk);
        reset = 1'b1;
        repeat (2) @(negedge clk);
        check_images();
        expect_equal(boot_rdata, 32'h1122_3344, "RAM survives reset");
        $display("tb_boot: programming, bounds, write protection, and reset retention passed");
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk);
        $fatal(1, "tb_boot: TIMEOUT");
    end
endmodule
