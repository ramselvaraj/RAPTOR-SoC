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
// `ready` is high in W_FETCH/W_EXEC so the scheduler can pick this warp.
//
// Required instances (TODO Person B):
//   decoder  u_dec  (.instr(ir), .opcode, .rd, .rs1, .rs2, .imm8, .legal);
//   regfile  u_rf   (per-lane; write_data/write_mask from the execute logic);
//   alu      u_alu[LANES] (.a(read_data1[l]), .b(read_data2[l]), .op, .result);
//   mem_unit u_mem  (started on LDR/STR, driven by read_data1 (base),
//                    read_data2 (idx), read_data3 (store data));
//
// Register/field aliasing follows docs/GPU_ISA.md.
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

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= W_IDLE;
            pc    <= '0;
            ir    <= 16'b0;
        end
        // TODO(Person B): FSM update on `grant`
    end

    always_comb begin
        ready     = 1'b0;   // TODO(Person B)
        imem_addr = pc;
        mem_req   = 1'b0;   // TODO(Person B)
        mem_we    = 1'b0;   // TODO(Person B)
        mem_addr  = 32'b0;  // TODO(Person B)
        mem_wdata = 32'b0;  // TODO(Person B)
        halted    = (state == W_HALT);
        next_state = state;
        // TODO(Person B): decode + execute + transition logic
    end
endmodule
