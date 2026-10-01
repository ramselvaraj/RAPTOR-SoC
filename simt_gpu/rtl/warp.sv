`timescale 1ns/1ps
// warp.sv -- one SIMT warp: LANES lanes sharing a program counter.
//
// FSM (advance only when `grant` is high):
//
//   W_IDLE  --start_warp--> W_FETCH
//   W_FETCH --grant--> latch ir <= imem_rdata; -> W_EXEC
//   W_EXEC  --grant--> decode/execute:
//                         ADD/SUB/CONST: write rd, pc++, -> W_FETCH
//                         LDR/STR:       start mem_unit, -> W_MEM
//                         RET:           -> W_HALT
//   W_MEM   --mem_unit done--> LDR: write rd from load_data; pc++, -> W_FETCH
//   W_HALT  -- terminal, halted=1
//
// `ready` is high in W_FETCH/W_EXEC and also W_MEM, so a warp waiting on memory
// can still be granted the shared bus. mem_unit sees `mem_ready && grant` so it
// only advances on the cycle it actually owns the bus.
module warp #(parameter int LANES = 4, parameter int PC_W = 16)(
    input  logic              clk,
    input  logic              reset,
    input  logic              start_warp,
    input  logic [31:0]       tid_base,
    input  logic [31:0]       src_addr,
    input  logic [31:0]       dst_addr,
    input  logic [LANES-1:0]  lane_mask,
    input  logic              grant,
    output logic              ready,
    output logic [PC_W-1:0]   imem_addr,
    output logic              mem_req,
    output logic              mem_we,
    output logic [31:0]       mem_addr,
    output logic [31:0]       mem_wdata,
    input  logic [31:0]       mem_rdata,
    input  logic              mem_ready,
    input  logic [15:0]       imem_rdata,
    output logic              halted
);
    typedef enum logic [2:0] {W_IDLE, W_FETCH, W_EXEC, W_MEM, W_HALT} state_t;
    state_t      state, next_state;
    logic [PC_W-1:0] pc;
    logic [15:0]     ir;

    logic [3:0] opcode, rd, rs1, rs2;
    logic [7:0] imm8;
    logic       legal;

    logic [31:0] rd1 [LANES], rd2 [LANES], rd3 [LANES];
    logic [31:0] wdata [LANES];
    logic        w_en;
    logic [3:0]  waddr;

    logic [31:0] alu_res [LANES];
    logic [1:0]  alu_op;

    logic        mem_start, mem_done;
    logic [31:0] load_data [LANES];

    logic is_add, is_sub, is_const, is_ldr, is_str, is_ret, is_mem, is_alu;

    decoder u_dec(
        .instr(ir), .opcode(opcode), .rd(rd), .rs1(rs1), .rs2(rs2),
        .imm8(imm8), .legal(legal)
    );

    regfile #(.LANES(LANES)) u_rf(
        .clk(clk), .reset(reset),
        .write_enable(w_en), .write_mask(lane_mask), .write_addr(waddr),
        .write_data(wdata),
        .read_addr1(rs1), .read_addr2(rs2), .read_addr3(rd),
        .read_data1(rd1), .read_data2(rd2), .read_data3(rd3),
        .tid_base(tid_base), .src_addr(src_addr), .dst_addr(dst_addr)
    );

    generate
        for (genvar l = 0; l < LANES; l++) begin : g_alu
            alu u_alu(.a(rd1[l]), .b(rd2[l]), .op(alu_op), .result(alu_res[l]));
        end
    endgenerate

    mem_unit #(.LANES(LANES)) u_mem(
        .clk(clk), .reset(reset),
        .start(mem_start), .is_store(is_str), .lane_mask(lane_mask),
        .base_val(rd1), .idx_val(rd2), .data_val(rd3),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready && grant),
        .load_data(load_data), .done(mem_done)
    );

    always_comb begin
        is_add   = (opcode == 4'h0);
        is_sub   = (opcode == 4'h2);
        is_const = (opcode == 4'h1);
        is_ldr   = (opcode == 4'h3);
        is_str   = (opcode == 4'h4);
        is_ret   = (opcode == 4'h5);
        is_alu   = is_add || is_sub;
        is_mem   = is_ldr || is_str;
        alu_op   = is_sub ? 2'd1 : 2'd0;
    end

    always_comb begin
        imem_addr = pc;
        halted    = (state == W_HALT);
        ready     = (state == W_FETCH) || (state == W_EXEC) || (state == W_MEM);
        mem_start = (state == W_EXEC) && grant && legal && is_mem;

        w_en  = 1'b0;
        waddr = rd;
        for (int l = 0; l < LANES; l++) wdata[l] = 32'b0;

        if (state == W_EXEC && grant && legal) begin
            if (is_const) begin
                w_en = 1'b1;
                for (int l = 0; l < LANES; l++) wdata[l] = {24'b0, imm8};
            end else if (is_alu) begin
                w_en = 1'b1;
                for (int l = 0; l < LANES; l++) wdata[l] = alu_res[l];
            end
        end else if (state == W_MEM && mem_done && is_ldr) begin
            w_en = 1'b1;
            for (int l = 0; l < LANES; l++) wdata[l] = load_data[l];
        end

        next_state = state;
        if (start_warp) begin
            next_state = W_FETCH;          // (re)start from any state, incl. W_HALT
        end else begin
            case (state)
                W_IDLE:  next_state = W_IDLE;
                W_FETCH: if (grant)      next_state = W_EXEC;
                W_EXEC:  if (grant) begin
                             if (is_ret)               next_state = W_HALT;
                             else if (legal && is_mem) next_state = W_MEM;
                             else                      next_state = W_FETCH;
                         end
                W_MEM:   if (mem_done)   next_state = W_FETCH;
                W_HALT:                  next_state = W_HALT;
                default:                 next_state = state;
            endcase
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= W_IDLE;
            pc    <= '0;
            ir    <= 16'b0;
        end else begin
            state <= next_state;
            if (state == W_FETCH && grant)
                ir <= imem_rdata;
            if (start_warp)
                pc <= '0;                       // new wave restarts at pc 0
            else if ((state == W_EXEC && grant && !is_ret && !is_mem) ||
                     (state == W_MEM && mem_done))
                pc <= pc + 1'b1;
        end
    end
endmodule
