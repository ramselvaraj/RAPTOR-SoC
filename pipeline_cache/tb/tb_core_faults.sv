`timescale 1ns/1ps
module tb_core_faults;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;
    logic iv, irv = 0, irr, dv, drr, fault;
    logic [31:0] ia, idata = 0, da, dw;
    logic [3:0] ds;
    logic retire_valid, retire_write;
    logic [31:0] retire_pc, retire_instruction, retire_data;
    logic [4:0] retire_rd;
    logic [63:0] cycles, retired, load_stalls, memory_stalls, fetch_stalls, redirects, branch_misses;
    logic [31:0] program_word;
    integer tests = 0;
    cache_pipeline_core dut(
        .clk, .reset, .i_req_valid(iv), .i_req_ready(!irv || irr), .i_req_addr(ia),
        .i_resp_valid(irv), .i_resp_ready(irr), .i_resp_data(idata),
        .d_req_valid(dv), .d_req_ready(1'b1), .d_req_addr(da), .d_req_data(dw), .d_req_strb(ds),
        .d_resp_valid(1'b0), .d_resp_ready(drr), .d_resp_data(32'b0),
        .retire_valid, .retire_write, .retire_pc, .retire_instruction, .retire_data, .retire_rd,
        .cycles, .retired, .load_stalls, .memory_stalls, .fetch_stalls, .redirects, .branch_misses, .fault
    );
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin irv <= 0; idata <= 0; end
        else if (!irv || irr) begin
            irv <= iv;
            if (iv) idata <= ia == 0 ? program_word : 32'h00000013;
        end
        if (!reset && dv) $fatal(1, "faulting memory operation reached external memory");
    end
    task automatic expect_fault(input logic [31:0] instruction, input string name);
        @(negedge clk); reset = 1; program_word = instruction;
        repeat (2) @(negedge clk); reset = 0;
        wait (fault);
        repeat (3) @(negedge clk);
        if (retire_valid || dv) $fatal(1, "fault did not halt core");
        $display("PASS: fault on %s", name);
        tests++;
    endtask
    initial begin
        program_word = 0;
        expect_fault(32'hffffffff, "illegal opcode");
        expect_fault(32'h02001093, "illegal SLLI encoding");
        expect_fault(32'h020000b3, "unsupported MUL");
        expect_fault(32'h00102083, "misaligned LW");
        expect_fault(32'h00101083, "misaligned LH");
        expect_fault(32'h00002123, "misaligned SW");
        expect_fault(32'h0020006f, "misaligned JAL target");
        expect_fault(32'h00000073, "ECALL without trap support");
        $display("PASS: %0d fail-stop and reset tests", tests);
        $finish;
    end
    initial begin #20000; $fatal(1, "fault-test timeout"); end
endmodule
