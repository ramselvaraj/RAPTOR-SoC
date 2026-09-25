`timescale 1ns/1ps

// simt_gpu.sv
//
// Phase 0 skeleton. This is deliberately NOT the SIMT core yet: it is a
// single-lane scanner that walks `thread_count` pixels and writes each one
// back unchanged, exercising the external memory read/write port and the
// start/done handshake.
//
// Its only purpose is to prove the host <-> simulation <-> host file loop:
//   frame.hex -> [this] -> out.hex
// The SIMT core + real ISA replace the scanner in later phases.
module simt_gpu #(
    parameter int ADDR_W = 12
)(
    input  logic              clk,
    input  logic              reset,
    input  logic              start,
    input  logic [31:0]       thread_count,
    // External memory port (one access at a time). Reads are asynchronous:
    // mem_rdata must be valid in the same cycle mem_re is high.
    output logic              mem_re,
    output logic              mem_we,
    output logic [ADDR_W-1:0] mem_addr,
    output logic [31:0]       mem_wdata,
    input  logic [31:0]       mem_rdata,
    output logic              done
);
    typedef enum logic [2:0] {IDLE, REQ, WRITE, NEXT, DONE} state_t;

    state_t      state, next_state;
    logic [31:0] count, index, rdata_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state   <= IDLE;
            count   <= 32'b0;
            index   <= 32'b0;
            rdata_q <= 32'b0;
        end else begin
            state <= next_state;
            if (state == IDLE && start)
                count <= thread_count;
            if (state == REQ)
                rdata_q <= mem_rdata;
            if (state == NEXT)
                index <= index + 32'd1;
        end
    end

    always_comb begin
        next_state = state;
        mem_re     = 1'b0;
        mem_we     = 1'b0;
        mem_addr   = index[ADDR_W-1:0];
        mem_wdata  = rdata_q;
        done       = 1'b0;

        case (state)
            IDLE:  if (start) next_state = (thread_count == 32'b0) ? DONE : REQ;
            REQ:   begin mem_re = 1'b1; next_state = WRITE; end
            WRITE: begin mem_we = 1'b1; next_state = NEXT;  end
            NEXT:  next_state = (index + 32'd1 >= count) ? DONE : REQ;
            DONE:  begin done = 1'b1; if (!start) next_state = IDLE; end
            default: next_state = IDLE;
        endcase
    end
endmodule
