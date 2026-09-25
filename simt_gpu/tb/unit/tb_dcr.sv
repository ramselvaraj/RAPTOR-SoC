`timescale 1ns/1ps
// tb_dcr.sv -- unit test for dcr.sv. Run: make unit TEST=tb_dcr
module tb_dcr;
    logic        clk = 0, reset = 1, start, all_halted;
    logic [31:0] thread_count, src_addr, dst_addr;
    logic [31:0] tc_q, src_q, dst_q;
    logic        busy, done;
    int errors = 0;

    dcr dut(
        .clk(clk), .reset(reset), .start(start),
        .thread_count(thread_count), .src_addr(src_addr), .dst_addr(dst_addr),
        .all_halted(all_halted),
        .busy(busy), .done(done),
        .thread_count_q(tc_q), .src_addr_q(src_q), .dst_addr_q(dst_q)
    );

    always #5 clk = ~clk;

    task automatic check(input logic got, exp, input string name);
        if (got !== exp) begin
            $display("FAIL %0s: got %0b expected %0b", name, got, exp);
            errors++;
        end else $display("PASS %0s", name);
    endtask

    initial begin
        start=0; all_halted=0;
        thread_count=32'd256; src_addr=32'h2000; dst_addr=32'h6000;

        repeat (2) @(posedge clk);
        reset = 0;

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        #1; check(busy, 1'b1, "busy after start");
        check(tc_q === 32'd256, 1'b1, "thread_count latched");
        check(src_q === 32'h2000, 1'b1, "src latched");
        check(dst_q === 32'h6000, 1'b1, "dst latched");

        @(negedge clk); all_halted = 1;
        @(posedge clk); #1;
        check(busy, 1'b0, "busy clears when halted");
        check(done, 1'b1, "done pulses");

        @(posedge clk); #1;
        check(done, 1'b0, "done is one cycle");

        if (errors == 0) $display("TB_DCR PASS");
        else $fatal(1, "TB_DCR FAIL: %0d errors", errors);
        $finish;
    end
endmodule
