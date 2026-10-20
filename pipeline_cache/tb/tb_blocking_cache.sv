`timescale 1ns/1ps
module tb_blocking_cache #(
    parameter bit WRITE_BACK = 1,
    parameter int LINES = 4,
    parameter int LINE_WORDS = 4
);
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;
    logic req_valid = 0, req_ready, resp_valid, resp_ready = 0;
    logic [31:0] req_addr = 0, req_data = 0, resp_data;
    logic [3:0] req_strb = 0;
    logic mv, mr, rv, rr;
    logic [31:0] ma, md, rd;
    logic [3:0] ms;
    logic [63:0] hits, misses, writebacks;
    logic [31:0] reference_words [0:4095];
    logic [31:0] rng = 32'hc0ffee42;
    logic [31:0] value, address, data;
    logic [3:0] strb;
    integer transactions = 0;
    integer i, j;
    localparam int CONFLICT = LINES * LINE_WORDS * 4;
    blocking_cache #(.LINES(LINES), .WORDS_PER_LINE(LINE_WORDS), .WRITE_BACK(WRITE_BACK)) dut(
        .clk, .reset, .req_valid, .req_ready, .req_addr, .req_data, .req_strb,
        .resp_valid, .resp_ready, .resp_data,
        .mem_req_valid(mv), .mem_req_ready(mr), .mem_req_addr(ma), .mem_req_data(md), .mem_req_strb(ms),
        .mem_resp_valid(rv), .mem_resp_ready(rr), .mem_resp_data(rd), .hits, .misses, .writebacks
    );
    delayed_memory #(.MAX_DELAY(11), .SEED(71)) memory_model(
        .clk, .reset, .req_valid(mv), .req_ready(mr), .req_addr(ma), .req_data(md), .req_strb(ms),
        .resp_valid(rv), .resp_ready(rr), .resp_data(rd)
    );
    task automatic access_word(input logic [31:0] addr, wd, input logic [3:0] mask);
        @(negedge clk);
        req_valid = 1; req_addr = addr; req_data = wd; req_strb = mask;
        do @(posedge clk); while (!req_ready);
        @(negedge clk); req_valid = 0;
        // Apply response backpressure on every transaction.
        wait (resp_valid);
        repeat (3) @(negedge clk);
        if (mask == 0 && resp_data !== reference_words[addr >> 2])
            $fatal(1, "cache mismatch addr=%h expected=%h got=%h", addr, reference_words[addr >> 2], resp_data);
        if (mask != 0)
            for (int k = 0; k < 4; k++) if (mask[k]) reference_words[addr >> 2][8*k +: 8] = wd[8*k +: 8];
        resp_ready = 1;
        @(negedge clk); resp_ready = 0;
        transactions++;
    endtask
    initial begin
        for (i = 0; i < 4096; i++) begin
            reference_words[i] = 32'(i) ^ 32'h12345678;
            memory_model.words[i] = reference_words[i];
        end
        repeat (3) @(negedge clk); reset = 0;
        // Compulsory miss, hit, partial update, and dirty conflicting line.
        access_word(0, 0, 0);
        access_word(0, 32'h00ab0000, 4'b0100);
        access_word(0, 0, 0);
        access_word(32'(CONFLICT), 0, 0);
        access_word(0, 0, 0);
        // Store-miss to final refill word must preserve the untouched bytes.
        access_word(32'(CONFLICT + (LINE_WORDS-1)*4), 32'h990000aa, 4'b1001);
        access_word(32'(CONFLICT + (LINE_WORDS-1)*4), 0, 0);
        access_word(32'(2*CONFLICT), 0, 0);
        access_word(32'(CONFLICT + (LINE_WORDS-1)*4), 0, 0);
        for (i = 0; i < 160; i++) begin
            rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            address = (rng % 128) * 4;
            data = rng ^ 32'h87654321;
            strb = rng[7:4];
            access_word(address, data, strb);
            access_word(address, 0, 0);
        end
        // Evict every modified line to an untouched address range, then compare RAM.
        for (j = 0; j < LINES; j++) access_word(32'(4096 + j*LINE_WORDS*4), 0, 0);
        for (i = 0; i < 128; i++)
            if (memory_model.words[i] !== reference_words[i])
                $fatal(1, "writeback mismatch word=%0d expected=%h got=%h", i, reference_words[i], memory_model.words[i]);
        if (hits == 0 || misses == 0 || (WRITE_BACK && writebacks == 0)) $fatal(1, "cache coverage missing");
        if (!WRITE_BACK && writebacks != 0) $fatal(1, "write-through dirty eviction");
        // Reset invalidates the cache but leaves external RAM intact.
        @(negedge clk); reset = 1;
        repeat (2) @(negedge clk); reset = 0;
        access_word(0, 0, 0);
        if (misses != 1 || hits != 0) $fatal(1, "reset failed to invalidate cache");
        $display("PASS: %0d cache transactions, byte masks, response backpressure, evictions, reset; WB=%0d", transactions, WRITE_BACK);
        $finish;
    end
    initial begin #2000000; $fatal(1, "cache test timeout"); end
endmodule
