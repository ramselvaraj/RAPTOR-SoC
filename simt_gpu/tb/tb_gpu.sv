`timescale 1ns/1ps
// tb_gpu.sv -- Phase 1 integration testbench.
//
// Owns the memory system (data + program), loads files via plusargs, drives the
// DCR launch, then dumps data memory. The Python driver (run_sim.py) checks the
// result against the isa_sim golden model and renders a PNG.
//
// Plusargs:
//   +frame=<path>  input framebuffer hex (one 32-bit word per line)
//   +prog=<path>   GPU program hex (one 16-bit instruction per line)
//   +out=<path>    where to dump the resulting data memory
//   +count=<n>     number of threads
//   +src=<n>       source framebuffer word address
//   +dst=<n>       destination framebuffer word address
module tb_gpu;
    parameter int WARPS      = 2;
    parameter int LANES      = 4;
    parameter int PC_W       = 16;
    parameter int ADDR_W     = 15;              // 32768 data words
    parameter int WORDS      = 1 << ADDR_W;
    parameter int PROG_WORDS = 1024;

    logic              clk = 1'b0;
    logic              reset = 1'b1;
    logic              start = 1'b0;
    logic [31:0]       thread_count = 32'b0;
    logic [31:0]       src_addr = 32'b0, dst_addr = 32'b0;
    logic              busy, done;
    logic [PC_W-1:0]   imem_addr;
    logic [15:0]       imem_rdata;
    logic              mem_req, mem_we, mem_ready;
    logic [31:0]       mem_addr, mem_wdata, mem_rdata;

    logic [31:0] data_mem [0:WORDS-1];
    logic [15:0] prog_mem [0:PROG_WORDS-1];

    string frame_path, prog_path, out_path;
    int unsigned count, src, dst;
    integer i;
    int unsigned cycles;

    simt_gpu #(.WARPS(WARPS), .LANES(LANES), .PC_W(PC_W)) dut(
        .clk(clk), .reset(reset), .start(start),
        .thread_count(thread_count), .src_addr(src_addr), .dst_addr(dst_addr),
        .busy(busy), .done(done),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    // Instruction memory: combinational read.
    assign imem_rdata = prog_mem[imem_addr[9:0]];

    // Data memory: combinational read, synchronous write.
    assign mem_rdata = data_mem[mem_addr[ADDR_W-1:0]];
    assign mem_ready = 1'b1;

    always_ff @(posedge clk) begin
        if (mem_req && mem_we)
            data_mem[mem_addr[ADDR_W-1:0]] <= mem_wdata;
    end

    always_ff @(posedge clk) begin
        if (reset) cycles <= 0;
        else       cycles <= cycles + 1;
    end

    initial begin
        for (i = 0; i < WORDS; i = i + 1)      data_mem[i] = 32'b0;
        for (i = 0; i < PROG_WORDS; i = i + 1) prog_mem[i] = 16'b0;

        if (!$value$plusargs("frame=%s", frame_path)) frame_path = "frame.hex";
        if (!$value$plusargs("prog=%s",  prog_path))  prog_path  = "prog.hex";
        if (!$value$plusargs("out=%s",   out_path))   out_path   = "out.hex";
        if (!$value$plusargs("count=%d", count))      count      = WORDS;
        if (!$value$plusargs("src=%d",   src))        src        = 0;
        if (!$value$plusargs("dst=%d",   dst))        dst        = 0;

        $readmemh(frame_path, data_mem, src, src + count - 1);
        $readmemh(prog_path,  prog_mem);
        $display("tb_gpu: frame=%0s prog=%0s out=%0s count=%0d src=%0d dst=%0d",
                 frame_path, prog_path, out_path, count, src, dst);
        $display("tb_gpu: prog[0]=%04h prog[1]=%04h", prog_mem[0], prog_mem[1]);

        thread_count = count;
        src_addr     = src;
        dst_addr     = dst;

        repeat (2) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait (done);
        repeat (2) @(posedge clk);

        $writememh(out_path, data_mem);
        $display("tb_gpu: wrote %0s after %0d cycles", out_path, cycles);
        $finish;
    end

    // Watchdog: fail loudly instead of hanging if the GPU never finishes.
    // The unrolled interior blur runs ~481 waves x ~125 instructions, so this
    // is generous (a stuck design still fails quickly in wall-clock terms).
    initial begin
        repeat (20000000) @(posedge clk);
        $fatal(1, "tb_gpu: TIMEOUT - GPU never asserted done");
    end
endmodule
