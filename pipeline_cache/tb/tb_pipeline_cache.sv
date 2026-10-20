`timescale 1ns/1ps
module tb_pipeline_cache #(
    parameter bit WRITE_BACK = 1,
    parameter int MAX_DELAY = 7,
    parameter int SEED = 13,
    parameter int CACHE_LINES = 4,
    parameter int LINE_WORDS = 4,
    parameter bit FAST_FETCH = 0
);
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;
    logic iv, ir, irv, irr, dv, dr, drv, drr;
    logic [31:0] ia, iw, idata, da, dw, dread;
    logic [3:0] istrb, ds;
    logic retire_valid, retire_write, fault;
    logic [31:0] retire_pc, retire_instruction, retire_data;
    logic [4:0] retire_rd;
    logic [63:0] cycles, retired, load_stalls, memory_stalls, fetch_stalls, redirects, branch_misses;
    logic [63:0] icache_hits, icache_misses, dcache_hits, dcache_misses, dcache_writebacks;
    logic [31:0] reference_regs [0:31];
    byte unsigned reference_mem [0:16383];
    logic [31:0] expected_pc = 0;
    integer cursor = 0, checked = 0, end_pc;
    integer branch_mask = 0, opcode_mask = 0;
    integer expected_redirects = 0, expected_branch_misses = 0;
    integer ex_forwarded = 0, wb_forwarded = 0, priority_forwarded = 0;
    integer i;
    logic [31:0] rng;

    always @(posedge clk) if (!reset && dut.core.id_ex.valid && !dut.core.mem_wait) begin
        if (dut.core.ex_mem.valid && dut.core.ex_mem.write_rd && !dut.core.ex_mem.load &&
            dut.core.ex_mem.rd != 0 && dut.core.ex_mem.rd == dut.core.id_ex.rs1)
            ex_forwarded++;
        if (dut.core.mem_wb.valid && dut.core.mem_wb.write_rd && dut.core.mem_wb.rd != 0 &&
            dut.core.mem_wb.rd == dut.core.id_ex.rs1) begin
            wb_forwarded++;
            if (dut.core.ex_mem.valid && dut.core.ex_mem.write_rd && !dut.core.ex_mem.load &&
                dut.core.ex_mem.rd == dut.core.mem_wb.rd) priority_forwarded++;
        end
    end

    pipeline_cache #(.DATA_WRITE_BACK(WRITE_BACK), .CACHE_LINES(CACHE_LINES), .BYPASS_ICACHE(FAST_FETCH),
                     .WORDS_PER_LINE(LINE_WORDS)) dut(
        .clk, .reset,
        .imem_req_valid(iv), .imem_req_ready(ir), .imem_req_addr(ia), .imem_req_data(iw), .imem_req_strb(istrb),
        .imem_resp_valid(irv), .imem_resp_ready(irr), .imem_resp_data(idata),
        .dmem_req_valid(dv), .dmem_req_ready(dr), .dmem_req_addr(da), .dmem_req_data(dw), .dmem_req_strb(ds),
        .dmem_resp_valid(drv), .dmem_resp_ready(drr), .dmem_resp_data(dread),
        .retire_valid, .retire_write, .retire_pc, .retire_instruction, .retire_data, .retire_rd,
        .cycles, .retired, .load_stalls, .memory_stalls, .fetch_stalls, .redirects, .branch_misses,
        .icache_hits, .icache_misses, .dcache_hits, .dcache_misses, .dcache_writebacks, .fault
    );
    logic slow_ir, slow_irv, slow_irr;
    logic [31:0] slow_idata;
    delayed_memory #(.MAX_DELAY(MAX_DELAY), .SEED(SEED)) imem(
        .clk, .reset, .req_valid(iv && !FAST_FETCH), .req_ready(slow_ir), .req_addr(ia), .req_data(iw), .req_strb(istrb),
        .resp_valid(slow_irv), .resp_ready(slow_irr), .resp_data(slow_idata)
    );
    generate if (FAST_FETCH) begin : fast_rom
        assign ir = !irv || irr;
        assign slow_irr = 0;
        always_ff @(posedge clk or posedge reset) begin
            if (reset) begin irv <= 0; idata <= 0; end
            else if (ir) begin
                irv <= iv;
                if (iv) idata <= imem.words[ia >> 2];
            end
        end
    end else begin : slow_rom
        assign ir = slow_ir;
        assign irv = slow_irv;
        assign idata = slow_idata;
        assign slow_irr = irr;
    end endgenerate
    delayed_memory #(.MAX_DELAY(MAX_DELAY), .SEED(SEED+29)) dmem(
        .clk, .reset, .req_valid(dv), .req_ready(dr), .req_addr(da), .req_data(dw), .req_strb(ds),
        .resp_valid(drv), .resp_ready(drr), .resp_data(dread)
    );

    function automatic [31:0] ri(input integer imm, rs1, f3, rd, op = 'h13);
        return {12'(imm), 5'(rs1), 3'(f3), 5'(rd), 7'(op)};
    endfunction
    function automatic [31:0] rr(input integer f7, rs2, rs1, f3, rd);
        return {7'(f7), 5'(rs2), 5'(rs1), 3'(f3), 5'(rd), 7'h33};
    endfunction
    function automatic [31:0] st(input integer imm, rs2, rs1, f3);
        return {imm[11:5], 5'(rs2), 5'(rs1), 3'(f3), imm[4:0], 7'h23};
    endfunction
    function automatic [31:0] br(input integer imm, rs2, rs1, f3);
        return {imm[12], imm[10:5], 5'(rs2), 5'(rs1), 3'(f3), imm[4:1], imm[11], 7'h63};
    endfunction
    function automatic [31:0] jal(input integer imm, rd);
        return {imm[20], imm[10:1], imm[11], imm[19:12], 5'(rd), 7'h6f};
    endfunction
    task automatic emit(input logic [31:0] instruction);
        imem.words[cursor] = instruction;
        cursor++;
    endtask

    // Independent architectural interpreter, invoked once per DUT retirement.
    // Byte-addressed memory and instruction decoding are separate from the RTL.
    task automatic check_retirement;
        logic [31:0] ins, x, y, value, next_pc, address, imm;
        integer rs1, rs2, rd, funct3, opcode, size;
        logic write_rd, take;
        ins = imem.words[expected_pc >> 2];
        if (retire_pc !== expected_pc || retire_instruction !== ins)
            $fatal(1, "retirement mismatch #%0d: expected PC=%h ins=%h got PC=%h ins=%h",
                   checked, expected_pc, ins, retire_pc, retire_instruction);
        rs1 = int'({27'b0, ins[19:15]}); rs2 = int'({27'b0, ins[24:20]});
        rd = int'({27'b0, ins[11:7]}); funct3 = int'({29'b0, ins[14:12]});
        opcode = int'({25'b0, ins[6:0]});
        x = reference_regs[rs1]; y = reference_regs[rs2];
        next_pc = expected_pc + 4; value = 0; write_rd = 0; take = 0;
        imm = {{20{ins[31]}}, ins[31:20]};
        case (opcode)
            'h13, 'h33: begin
                opcode_mask |= 1;
                write_rd = 1;
                if (opcode == 'h13) y = imm;
                case (funct3)
                    0: value = opcode == 'h33 && ins[30] ? x-y : x+y;
                    1: value = x << y[4:0];
                    2: value = {31'b0, $signed(x) < $signed(y)};
                    3: value = {31'b0, x < y};
                    4: value = x ^ y;
                    5: value = ins[30] ? $unsigned($signed(x) >>> y[4:0]) : x >> y[4:0];
                    6: value = x | y;
                    7: value = x & y;
                    default: $fatal(1, "invalid reference ALU");
                endcase
            end
            'h37: begin value = {ins[31:12], 12'b0}; write_rd = 1; opcode_mask |= 2; end
            'h17: begin value = expected_pc + {ins[31:12], 12'b0}; write_rd = 1; opcode_mask |= 4; end
            'h03: begin
                opcode_mask |= 8;
                write_rd = 1; address = x + imm;
                case (funct3)
                    0: value = {{24{reference_mem[address][7]}}, reference_mem[address]};
                    1: value = {{16{reference_mem[address+1][7]}}, reference_mem[address+1], reference_mem[address]};
                    2: value = {reference_mem[address+3], reference_mem[address+2], reference_mem[address+1], reference_mem[address]};
                    4: value = {24'b0, reference_mem[address]};
                    5: value = {16'b0, reference_mem[address+1], reference_mem[address]};
                    default: $fatal(1, "invalid reference load");
                endcase
            end
            'h23: begin
                opcode_mask |= 16;
                imm = {{20{ins[31]}}, ins[31:25], ins[11:7]};
                address = x + imm; size = 1 << funct3;
                for (int k = 0; k < size; k++) reference_mem[address+32'(k)] = 8'(y >> (k*8));
            end
            'h63: begin
                opcode_mask |= 32; branch_mask |= 1 << funct3;
                case (funct3)
                    0: take = x == y;
                    1: take = x != y;
                    4: take = $signed(x) < $signed(y);
                    5: take = $signed(x) >= $signed(y);
                    6: take = x < y;
                    7: take = x >= y;
                    default: $fatal(1, "invalid reference branch");
                endcase
                imm = {{19{ins[31]}}, ins[31], ins[7], ins[30:25], ins[11:8], 1'b0};
                if (take) begin
                    next_pc = expected_pc + imm;
                    expected_redirects++;
                    expected_branch_misses++;
                end
            end
            'h6f: begin
                expected_redirects++;
                opcode_mask |= 64; value = next_pc; write_rd = 1;
                imm = {{11{ins[31]}}, ins[31], ins[19:12], ins[20], ins[30:21], 1'b0};
                next_pc = expected_pc + imm;
            end
            'h67: begin
                expected_redirects++;
                opcode_mask |= 128; value = next_pc; write_rd = 1; next_pc = (x + imm) & 32'hffff_fffe;
            end
            'h0f: opcode_mask |= 256;
            default: $fatal(1, "unsupported reference instruction %h", ins);
        endcase
        if (retire_write !== (write_rd && rd != 0)) $fatal(1, "write enable mismatch at %h", expected_pc);
        if (write_rd && rd != 0) begin
            if (retire_rd !== 5'(rd) || retire_data !== value)
                $fatal(1, "register mismatch PC=%h x%0d expected=%h actual=%h", expected_pc, rd, value, retire_data);
            reference_regs[rd] = value;
        end
        expected_pc = next_pc;
        checked++;
    endtask

    initial begin
        for (i = 0; i < 4096; i++) begin imem.words[i] = 32'h00000013; dmem.words[i] = 0; end
        for (i = 0; i < 32; i++) reference_regs[i] = 0;
        for (i = 0; i < 16384; i++) reference_mem[i] = 0;
        emit(ri(-16, 0, 0, 1)); emit(ri(3, 0, 0, 2));
        emit(ri(99, 0, 0, 0)); // attempted x0 write
        emit(32'h123451b7); // lui x3,0x12345
        emit(32'h00001217); // auipc x4,0x1
        // Every register ALU operation, including both comparison signs and shifts.
        for (i = 0; i < 8; i++) emit(rr(0, 2, 1, i, 5+i));
        emit(rr('h20, 2, 1, 0, 13)); emit(rr('h20, 2, 1, 5, 14));
        for (i = 0; i < 8; i++) emit(ri(i == 1 || i == 5 ? 3 : -7, 1, i, 15+i));
        emit(ri('h403, 1, 5, 23));
        // Immediate stores, signed/unsigned loads, and load->store dependency.
        emit(st(0, 1, 0, 2));
        emit(ri(0, 0, 0, 24, 'h03)); emit(ri(0, 0, 4, 25, 'h03));
        emit(ri(0, 0, 1, 26, 'h03)); emit(ri(0, 0, 5, 27, 'h03));
        emit(st(3, 2, 0, 0)); emit(st(2, 1, 0, 1));
        emit(ri(0, 0, 2, 28, 'h03)); emit(st(4, 28, 0, 2));
        emit(ri(0, 28, 0, 29));
        // Same-index conflicts force dirty eviction, refill, and data preservation.
        emit(st(256, 3, 0, 2)); emit(st(512, 2, 0, 2));
        emit(ri(0, 0, 2, 28, 'h03)); emit(ri(256, 0, 2, 29, 'h03));
        emit(ri(512, 0, 2, 30, 'h03));
        // Negative address offset and accesses at the last word of a cache line.
        emit(ri(64, 0, 0, 10)); emit(st(-4, 1, 10, 2));
        emit(ri(-4, 10, 2, 11, 'h03)); emit(st(63, 2, 0, 0));
        emit(ri(63, 0, 4, 12, 'h03));
        // Six branch predicates, each taken and untaken. Wrong paths store poison.
        for (i = 0; i < 8; i++) begin
            if (i == 2 || i == 3) continue;
            case (i)
                0: begin emit(br(12, 1, 1, i)); end
                1: begin emit(br(12, 2, 1, i)); end
                4: begin emit(br(12, 2, 1, i)); end
                5: begin emit(br(12, 1, 2, i)); end
                6: begin emit(br(12, 1, 2, i)); end
                7: begin emit(br(12, 2, 1, i)); end
                default: ;
            endcase
            emit(st(1024, 1, 0, 2)); emit(32'hffffffff); // wrong-path illegal instruction
            // Reverse the operands (or use unequal operands for BEQ).
            case (i)
                0: emit(br(8, 2, 1, i));
                1: emit(br(8, 1, 1, i));
                4, 7: emit(br(8, 1, 2, i));
                5, 6: emit(br(8, 2, 1, i));
                default: ;
            endcase
            emit(ri(1, 31, 0, 31));
        end
        // Backward branch loop.
        emit(ri(4, 0, 0, 6)); emit(ri(-1, 6, 0, 6)); emit(br(-4, 0, 6, 1));
        emit(jal(12, 7)); emit(st(1024, 1, 0, 2)); emit(ri(99, 0, 0, 31));
        emit(ri(1, 7, 0, 8));
        emit(ri((cursor+4)*4 + 1, 0, 0, 9)); // odd target tests JALR bit-zero clearing
        emit(ri(0, 9, 0, 10, 'h67)); emit(st(1024, 1, 0, 2)); emit(ri(99, 0, 0, 31));
        emit(ri(1, 10, 0, 11));
        emit(32'h0000000f); // fence
        // Both producers target the same register: newest forwarding must win.
        emit(ri(11, 0, 0, 5)); emit(ri(22, 0, 0, 5)); emit(ri(1, 5, 0, 6));
        // Load-to-branch and load-to-JALR dependencies.
        emit(ri(0, 0, 2, 6, 'h03)); emit(br(12, 6, 6, 0));
        emit(st(1024, 1, 0, 2)); emit(ri(99, 0, 0, 31));
        emit(ri((cursor+6)*4 + 1, 0, 0, 6));
        emit(st(128, 6, 0, 2)); emit(ri(128, 0, 2, 7, 'h03));
        emit(ri(0, 7, 0, 8, 'h67)); emit(st(1024, 1, 0, 2)); emit(ri(99, 0, 0, 31));
        emit(ri(3, 0, 0, 6)); emit(ri(-1, 6, 0, 6));
        emit(br(8, 0, 6, 0)); emit(jal(-8, 0));
        // Deterministic pseudo-random dependent ALU stream.
        rng = 32'hbeef1234;
        for (i = 0; i < 128; i++) begin
            rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            emit(rr(0, int'({27'b0, rng[4:0]}), int'({27'b0, rng[9:5]}),
                    int'({29'b0, rng[12:10]}), 1 + int'(rng % 31)));
        end
        // Read back all modified words and the wrong-path poison location.
        emit(ri(0, 0, 2, 1, 'h03)); emit(ri(4, 0, 2, 2, 'h03));
        emit(ri(60, 0, 2, 3, 'h03)); emit(ri(1024, 0, 2, 4, 'h03));
        end_pc = cursor*4;
        emit(jal(0, 0));
        repeat (4) @(negedge clk);
        reset = 0;
    end

    always @(negedge clk) if (!reset) begin
        if (fault) $fatal(1, "DUT fault, next expected PC=%h", expected_pc);
        if (retire_valid) begin
            check_retirement();
            if (retire_pc == 32'(end_pc)) begin
                if (opcode_mask != 511 || branch_mask != 243) $fatal(1, "instruction coverage incomplete");
                if ((!FAST_FETCH && (icache_hits == 0 || icache_misses == 0)) || dcache_hits == 0 || dcache_misses == 0)
                    $fatal(1, "cache coverage incomplete");
                if (FAST_FETCH && load_stalls == 0) $fatal(1, "no load-use hazard exercised");
                if (FAST_FETCH && (ex_forwarded == 0 || wb_forwarded == 0 || priority_forwarded == 0))
                    $fatal(1, "forwarding coverage incomplete: EX=%0d WB=%0d priority=%0d",
                           ex_forwarded, wb_forwarded, priority_forwarded);
                if (WRITE_BACK && dcache_writebacks == 0) $fatal(1, "no dirty eviction");
                if (dmem.words[256] !== 0) $fatal(1, "wrong-path store escaped");
                @(posedge clk); #1;
                if (retired != 64'(checked)) $fatal(1, "retirement counter mismatch");
                // The terminal JAL has already redirected by its retirement.
                // A repeated terminal JAL can also reach EX in the fast front end.
                if (branch_misses != 64'(expected_branch_misses)) $fatal(1, "branch-miss counter mismatch");
                if (redirects < 64'(expected_redirects) || redirects > 64'(expected_redirects + 1))
                    $fatal(1, "redirect counter mismatch");
                $display("PASS: %0d retirements matched reference; WB=%0d delay=%0d seed=%0d fast=%0d", checked, WRITE_BACK, MAX_DELAY, SEED, FAST_FETCH);
                $display("cycles=%0d retired=%0d load_stalls=%0d memory_stalls=%0d fetch_stalls=%0d redirects=%0d branch_misses=%0d",
                         cycles, retired, load_stalls, memory_stalls, fetch_stalls, redirects, branch_misses);
                $display("I hit/miss=%0d/%0d D hit/miss=%0d/%0d writebacks=%0d",
                         icache_hits, icache_misses, dcache_hits, dcache_misses, dcache_writebacks);
                $finish;
            end
        end
        if (cycles > 100000) $fatal(1, "test timeout");
    end
endmodule
