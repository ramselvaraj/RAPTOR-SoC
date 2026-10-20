`timescale 1ns/1ps
module cache_pipeline_core(
    input logic clk, reset,
    output logic i_req_valid,
    input logic i_req_ready,
    output logic [31:0] i_req_addr,
    input logic i_resp_valid,
    output logic i_resp_ready,
    input logic [31:0] i_resp_data,
    output logic d_req_valid,
    input logic d_req_ready,
    output logic [31:0] d_req_addr, d_req_data,
    output logic [3:0] d_req_strb,
    input logic d_resp_valid,
    output logic d_resp_ready,
    input logic [31:0] d_resp_data,
    output logic retire_valid,
    output logic [31:0] retire_pc, retire_instruction, retire_data,
    output logic [4:0] retire_rd,
    output logic retire_write,
    output logic [63:0] cycles, retired, load_stalls, memory_stalls, fetch_stalls, redirects, branch_misses,
    output logic fault
);
    import rv32_pkg::*;
    if_id_t if_id;
    id_ex_t id_ex, decoded, decode_next;
    ex_mem_t ex_mem, execute_next;
    mem_wb_t mem_wb;
    logic [31:0] registers [0:31];
    logic [31:0] pc, fetch_pc, a, b, alu_b, result, target, load_data, shifted_load;
    logic fetch_pending, fetch_discard, data_pending;
    logic request_held, held_discard;
    logic [31:0] held_address;
    logic mem_wait, load_hazard, redirect, branch_taken, decode_fault, execute_fault;
    logic [31:0] offset_data;
    integer n;

    cache_cpu_decoder decoder(.instruction(if_id.instruction), .decoded);

    always_comb begin
        decode_next = decoded;
        decode_next.valid = if_id.valid && decoded.valid;
        decode_next.pc = if_id.pc;
        decode_next.a = decoded.rs1 == 0 ? 0 : registers[decoded.rs1];
        decode_next.b = decoded.rs2 == 0 ? 0 : registers[decoded.rs2];
        if (mem_wb.valid && mem_wb.write_rd && mem_wb.rd != 0) begin
            if (mem_wb.rd == decoded.rs1) decode_next.a = mem_wb.result;
            if (mem_wb.rd == decoded.rs2) decode_next.b = mem_wb.result;
        end
        a = id_ex.a;
        b = id_ex.b;
        if (mem_wb.valid && mem_wb.write_rd && mem_wb.rd != 0) begin
            if (mem_wb.rd == id_ex.rs1) a = mem_wb.result;
            if (mem_wb.rd == id_ex.rs2) b = mem_wb.result;
        end
        if (ex_mem.valid && ex_mem.write_rd && !ex_mem.load && ex_mem.rd != 0) begin
            if (ex_mem.rd == id_ex.rs1) a = ex_mem.result;
            if (ex_mem.rd == id_ex.rs2) b = ex_mem.result;
        end
        if (id_ex.rs1 == 0) a = 0;
        if (id_ex.rs2 == 0) b = 0;
        alu_b = id_ex.immediate ? id_ex.imm : b;
        case (id_ex.alu_op)
            SUB: result = a - alu_b;
            AND_OP: result = a & alu_b;
            OR_OP: result = a | alu_b;
            XOR_OP: result = a ^ alu_b;
            SLT: result = {31'b0, $signed(a) < $signed(alu_b)};
            SLTU: result = {31'b0, a < alu_b};
            SLL: result = a << alu_b[4:0];
            SRL: result = a >> alu_b[4:0];
            SRA: result = $signed(a) >>> alu_b[4:0];
            default: result = a + alu_b;
        endcase
        if (id_ex.lui) result = id_ex.imm;
        if (id_ex.auipc) result = id_ex.pc + id_ex.imm;
        if (id_ex.jal || id_ex.jalr) result = id_ex.pc + 4;
        case (id_ex.funct3)
            0: branch_taken = a == b;
            1: branch_taken = a != b;
            4: branch_taken = $signed(a) < $signed(b);
            5: branch_taken = $signed(a) >= $signed(b);
            6: branch_taken = a < b;
            7: branch_taken = a >= b;
            default: branch_taken = 0;
        endcase
        target = id_ex.jalr ? ((a + id_ex.imm) & 32'hffff_fffe) : id_ex.pc + id_ex.imm;
        execute_next = '0;
        execute_next.valid = id_ex.valid;
        execute_next.pc = id_ex.pc;
        execute_next.instruction = id_ex.instruction;
        execute_next.result = result;
        execute_next.store_data = b;
        execute_next.rd = id_ex.rd;
        execute_next.write_rd = id_ex.write_rd;
        execute_next.load = id_ex.load;
        execute_next.store = id_ex.store;
        execute_next.funct3 = id_ex.funct3;
    end

    assign mem_wait = ex_mem.valid && (ex_mem.load || ex_mem.store) && !d_resp_valid;
    assign load_hazard = if_id.valid && id_ex.valid && id_ex.load && id_ex.rd != 0 &&
                         ((decoded.use_rs1 && decoded.rs1 == id_ex.rd) ||
                          (decoded.use_rs2 && decoded.rs2 == id_ex.rd));
    assign redirect = !mem_wait && id_ex.valid &&
                      (id_ex.jal || id_ex.jalr || (id_ex.branch && branch_taken));
    // Decode faults are suppressed for younger wrong-path instructions.
    assign decode_fault = !mem_wait && !redirect && if_id.valid && !decoded.valid;
    assign execute_fault = !mem_wait && id_ex.valid &&
                           (((id_ex.load || id_ex.store) &&
                             ((id_ex.funct3[1:0] == 2 && result[1:0] != 0) ||
                              (id_ex.funct3[1:0] == 1 && result[0]))) ||
                            (redirect && target[1:0] != 0));

    assign i_req_valid = !reset && !fault && (request_held || (!redirect &&
                         (!fetch_pending || (i_resp_valid && i_resp_ready)) &&
                         (!if_id.valid || (!mem_wait && !load_hazard))));
    assign i_req_addr = request_held ? held_address : pc;
    assign i_resp_ready = fetch_pending && (fetch_discard || redirect || !if_id.valid ||
                                           (!mem_wait && !load_hazard));
    assign d_req_valid = !reset && !fault && ex_mem.valid && (ex_mem.load || ex_mem.store) && !data_pending;
    assign d_req_addr = {ex_mem.result[31:2], 2'b0};
    assign d_req_data = ex_mem.store_data << {ex_mem.result[1:0], 3'b0};
    always_comb begin
        d_req_strb = 0;
        if (ex_mem.store) begin
            case (ex_mem.funct3)
                0: d_req_strb = 4'b0001 << ex_mem.result[1:0];
                1: d_req_strb = 4'b0011 << ex_mem.result[1:0];
                default: d_req_strb = 4'b1111;
            endcase
        end
        shifted_load = d_resp_data >> {ex_mem.result[1:0], 3'b0};
        offset_data = shifted_load;
        case (ex_mem.funct3)
            0: load_data = {{24{offset_data[7]}}, offset_data[7:0]};
            1: load_data = {{16{offset_data[15]}}, offset_data[15:0]};
            4: load_data = {24'b0, offset_data[7:0]};
            5: load_data = {16'b0, offset_data[15:0]};
            default: load_data = offset_data;
        endcase
    end
    assign d_resp_ready = !reset && !fault && data_pending;
    assign retire_valid = mem_wb.valid && !fault && !reset;
    assign retire_pc = mem_wb.pc;
    assign retire_instruction = mem_wb.instruction;
    assign retire_data = mem_wb.result;
    assign retire_rd = mem_wb.rd;
    assign retire_write = mem_wb.write_rd && mem_wb.rd != 0;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 0; fetch_pc <= 0;
            fetch_pending <= 0; fetch_discard <= 0; data_pending <= 0;
            request_held <= 0; held_discard <= 0; held_address <= 0;
            if_id <= '0; id_ex <= '0; ex_mem <= '0; mem_wb <= '0;
            fault <= 0;
            cycles <= 0; retired <= 0; load_stalls <= 0;
            memory_stalls <= 0; fetch_stalls <= 0; redirects <= 0; branch_misses <= 0;
            for (n = 0; n < 32; n = n + 1) registers[n] <= 0;
        end else if (!fault) begin
            cycles <= cycles + 1;
            if (retire_valid) begin
                retired <= retired + 1;
                if (retire_write) registers[mem_wb.rd] <= mem_wb.result;
            end
            mem_wb.valid <= 0;
            if (mem_wait) memory_stalls <= memory_stalls + 1;
            if (!if_id.valid) fetch_stalls <= fetch_stalls + 1;
            if (load_hazard && !mem_wait) load_stalls <= load_stalls + 1;
            if (d_req_valid && d_req_ready) data_pending <= 1;
            if (d_resp_valid && d_resp_ready) data_pending <= 0;

            if (i_resp_valid && i_resp_ready) begin
                fetch_pending <= 0;
                fetch_discard <= 0;
                if (!fetch_discard && !redirect) begin
                    if_id <= '{valid:1'b1, pc:fetch_pc, instruction:i_resp_data};
                end
            end
            if (i_req_valid && i_req_ready) begin
                fetch_pending <= 1;
                fetch_pc <= i_req_addr;
                fetch_discard <= (request_held && held_discard) || redirect;
                request_held <= 0;
                held_discard <= 0;
                if (!(request_held && held_discard) && !redirect) pc <= i_req_addr + 4;
            end else if (i_req_valid && !i_req_ready) begin
                request_held <= 1;
                held_address <= i_req_addr;
                if (redirect) held_discard <= 1;
            end
            if (!mem_wait) begin
                mem_wb <= '{valid:ex_mem.valid, pc:ex_mem.pc, instruction:ex_mem.instruction,
                            result:ex_mem.load ? load_data : ex_mem.result,
                            rd:ex_mem.rd, write_rd:ex_mem.write_rd};
                ex_mem <= execute_next;
                if (redirect) begin
                    pc <= target;
                    redirects <= redirects + 1;
                    if (id_ex.branch) branch_misses <= branch_misses + 1;
                    if_id <= '0;
                    id_ex <= '0;
                    if (fetch_pending && !(i_resp_valid && i_resp_ready)) fetch_discard <= 1;
                end else if (load_hazard) begin
                    id_ex <= '0;
                end else begin
                    id_ex <= decode_next;
                    // A returning instruction can populate the empty IF/ID slot.
                    if (!(i_resp_valid && i_resp_ready && !fetch_discard)) if_id.valid <= 0;
                end
            end else begin
                // Persist forwarded operands while EX waits behind a memory miss.
                id_ex.a <= a;
                id_ex.b <= b;
            end
            if (decode_fault || execute_fault) fault <= 1;
`ifndef SYNTHESIS
            assert (registers[0] == 0) else $fatal(1, "x0 changed");
            assert (!(d_resp_valid && !data_pending)) else $fatal(1, "unsolicited data response");
`endif
        end
    end
`ifndef SYNTHESIS
    assert property (@(posedge clk) disable iff (reset || fault)
        mem_wait |=> $stable(ex_mem));
    assert property (@(posedge clk) disable iff (reset || fault)
        load_hazard && !mem_wait && !redirect |=> !id_ex.valid && $stable(if_id));
    assert property (@(posedge clk) disable iff (reset || fault)
        redirect |=> !id_ex.valid && !if_id.valid);
    assert property (@(posedge clk) disable iff (reset || fault)
        i_req_valid && !i_req_ready |=> i_req_valid && $stable(i_req_addr));
    assert property (@(posedge clk) disable iff (reset || fault)
        d_req_valid && !d_req_ready |=> d_req_valid && $stable({d_req_addr, d_req_data, d_req_strb}));
`endif
endmodule
