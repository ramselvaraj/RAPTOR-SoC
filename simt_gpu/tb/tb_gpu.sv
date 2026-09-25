// tb_gpu.sv
//
// Phase 0 testbench. Owns the global memory model (like a host attached to
// GPU global memory), loads it from files passed as plusargs, drives the
// device's start/done handshake, then dumps the result back to a file.
//
// Plusargs (all optional):
//   +frame=<path>  input framebuffer hex (one 32-bit word per line)
//   +prog=<path>   program memory hex (loaded, not executed yet)
//   +out=<path>    where to write the resulting framebuffer
//   +count=<n>     number of pixels to process
//
// Run: ./Vtb_gpu +frame=... +prog=... +out=... +count=256
`timescale 1ns/1ps

module tb_gpu;
    parameter int ADDR_W      = 12;
    parameter int WORDS       = 1 << ADDR_W;
    parameter int PROG_WORDS  = 1024;

    logic              clk = 1'b0;
    logic              reset = 1'b1;
    logic              start = 1'b0;
    logic [31:0]       thread_count = 32'b0;
    logic              mem_re, mem_we, done;
    logic [ADDR_W-1:0] mem_addr;
    logic [31:0]       mem_wdata, mem_rdata;

    logic [31:0] data_mem [0:WORDS-1];
    logic [15:0] prog_mem [0:PROG_WORDS-1];

    string frame_path, prog_path, out_path;
    int unsigned count;
    integer i;

    simt_gpu #(.ADDR_W(ADDR_W)) dut (
        .clk, .reset, .start, .thread_count,
        .mem_re, .mem_we, .mem_addr, .mem_wdata, .mem_rdata, .done
    );

    always #5 clk = ~clk;

    // Asynchronous-read / synchronous-write memory model.
    assign mem_rdata = data_mem[mem_addr];

    always_ff @(posedge clk) begin
        if (mem_we)
            data_mem[mem_addr] <= mem_wdata;
    end

    initial begin
        for (i = 0; i < WORDS; i = i + 1)      data_mem[i] = 32'b0;
        for (i = 0; i < PROG_WORDS; i = i + 1) prog_mem[i] = 16'b0;

        if (!$value$plusargs("frame=%s", frame_path)) frame_path = "frame.hex";
        if (!$value$plusargs("prog=%s",  prog_path))  prog_path  = "prog.hex";
        if (!$value$plusargs("out=%s",   out_path))   out_path   = "out.hex";
        if (!$value$plusargs("count=%d", count))      count      = WORDS;

        $readmemh(frame_path, data_mem);
        $readmemh(prog_path,  prog_mem);
        $display("tb_gpu: frame=%0s prog=%0s out=%0s count=%0d",
                 frame_path, prog_path, out_path, count);
        $display("tb_gpu: prog[0]=%04h", prog_mem[0]);

        thread_count = count;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait (done);
        repeat (2) @(posedge clk);

        $writememh(out_path, data_mem);
        $display("tb_gpu: wrote %0s", out_path);
        $finish;
    end
endmodule
