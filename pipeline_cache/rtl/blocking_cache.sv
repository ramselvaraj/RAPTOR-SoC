`timescale 1ns/1ps
// Direct-mapped, one outstanding CPU transaction. All addresses are byte addresses.
// READ_ONLY selects the I-cache. WRITE_BACK=0 selects write-through/no-allocate;
// WRITE_BACK=1 selects write-back/write-allocate. Responses remain valid until ready.
module blocking_cache #(
    parameter int LINES = 4,
    parameter int WORDS_PER_LINE = 4,
    parameter bit READ_ONLY = 0,
    parameter bit WRITE_BACK = 1
)(
    input logic clk, reset,
    input logic req_valid,
    output logic req_ready,
    input logic [31:0] req_addr, req_data,
    input logic [3:0] req_strb,
    output logic resp_valid,
    input logic resp_ready,
    output logic [31:0] resp_data,
    output logic mem_req_valid,
    input logic mem_req_ready,
    output logic [31:0] mem_req_addr, mem_req_data,
    output logic [3:0] mem_req_strb,
    input logic mem_resp_valid,
    output logic mem_resp_ready,
    input logic [31:0] mem_resp_data,
    output logic [63:0] hits, misses, writebacks
);
    localparam int WORD_BITS = $clog2(WORDS_PER_LINE);
    localparam int INDEX_BITS = $clog2(LINES);
    localparam int TAG_BITS = 32 - 2 - WORD_BITS - INDEX_BITS;
    typedef enum logic [3:0] {IDLE, LOOKUP, EVICT_REQ, EVICT_WAIT,
                              REFILL_REQ, REFILL_WAIT, WT_REQ, WT_WAIT, RESPOND} state_t;
    state_t state;
    logic [31:0] data [0:LINES-1][0:WORDS_PER_LINE-1];
    logic [TAG_BITS-1:0] tags [0:LINES-1];
    logic valid [0:LINES-1], dirty [0:LINES-1];
    logic [31:0] address_q, data_q;
    logic [3:0] strb_q;
    logic [INDEX_BITS-1:0] index;
    logic [WORD_BITS-1:0] word_index, transfer_word;
    logic [TAG_BITS-1:0] tag;
    logic hit;
    integer i, j;

`ifndef SYNTHESIS
    initial begin
        assert (LINES >= 2 && (LINES & (LINES - 1)) == 0)
            else $fatal(1, "LINES must be a power of two >= 2");
        assert (WORDS_PER_LINE >= 2 && (WORDS_PER_LINE & (WORDS_PER_LINE - 1)) == 0)
            else $fatal(1, "WORDS_PER_LINE must be a power of two >= 2");
    end
`endif
    assign word_index = address_q[2 +: WORD_BITS];
    assign index = address_q[2 + WORD_BITS +: INDEX_BITS];
    assign tag = address_q[31 -: TAG_BITS];
    assign hit = valid[index] && tags[index] == tag;
    assign req_ready = state == IDLE && !reset;
    assign resp_valid = state == RESPOND;
    assign mem_req_valid = state == EVICT_REQ || state == REFILL_REQ || state == WT_REQ;
    assign mem_resp_ready = state == EVICT_WAIT || state == REFILL_WAIT || state == WT_WAIT;
    always_comb begin
        mem_req_addr = {address_q[31:2+WORD_BITS], transfer_word, 2'b0};
        mem_req_data = 0;
        mem_req_strb = 0;
        if (state == EVICT_REQ) begin
            mem_req_addr = {tags[index], index, transfer_word, 2'b0};
            mem_req_data = data[index][transfer_word];
            mem_req_strb = 4'b1111;
        end else if (state == WT_REQ) begin
            mem_req_addr = address_q;
            mem_req_data = data_q;
            mem_req_strb = strb_q;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            address_q <= 0; data_q <= 0; strb_q <= 0; transfer_word <= 0;
            resp_data <= 0; hits <= 0; misses <= 0; writebacks <= 0;
            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 0; dirty[i] <= 0; tags[i] <= 0;
                for (j = 0; j < WORDS_PER_LINE; j = j + 1) data[i][j] <= 0;
            end
        end else begin
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    address_q <= req_addr; data_q <= req_data; strb_q <= req_strb;
                    state <= LOOKUP;
`ifndef SYNTHESIS
                    assert (!READ_ONLY || req_strb == 0) else $fatal(1, "store to I-cache");
                    assert (req_addr[1:0] == 0) else $fatal(1, "unaligned cache request");
`endif
                end
                LOOKUP: begin
                    if (hit) begin
                        hits <= hits + 1;
                        resp_data <= data[index][word_index];
                        if (strb_q != 0) begin
                            for (j = 0; j < 4; j = j + 1)
                                if (strb_q[j]) data[index][word_index][j*8 +: 8] <= data_q[j*8 +: 8];
                            dirty[index] <= WRITE_BACK;
                        end
                        state <= strb_q != 0 && !WRITE_BACK ? WT_REQ : RESPOND;
                    end else begin
                        misses <= misses + 1;
                        transfer_word <= 0;
                        if (strb_q != 0 && !WRITE_BACK) state <= WT_REQ;
                        else if (valid[index] && dirty[index]) begin
                            writebacks <= writebacks + 1;
                            state <= EVICT_REQ;
                        end else state <= REFILL_REQ;
                    end
                end
                EVICT_REQ: if (mem_req_ready) state <= EVICT_WAIT;
                EVICT_WAIT: if (mem_resp_valid) begin
                    if (transfer_word == WORD_BITS'(WORDS_PER_LINE - 1)) begin
                        transfer_word <= 0;
                        dirty[index] <= 0;
                        valid[index] <= 0;
                        state <= REFILL_REQ;
                    end else begin
                        transfer_word <= transfer_word + 1'b1;
                        state <= EVICT_REQ;
                    end
                end
                REFILL_REQ: if (mem_req_ready) state <= REFILL_WAIT;
                REFILL_WAIT: if (mem_resp_valid) begin
                    data[index][transfer_word] <= mem_resp_data;
                    if (transfer_word == WORD_BITS'(WORDS_PER_LINE - 1)) begin
                        tags[index] <= tag; valid[index] <= 1; dirty[index] <= 0;
                        // Replay without counting this refill as another CPU hit.
                        state <= RESPOND;
                        if (word_index == transfer_word) resp_data <= mem_resp_data;
                        else resp_data <= data[index][word_index];
                        if (strb_q != 0) begin
                            dirty[index] <= WRITE_BACK;
                            for (j = 0; j < 4; j = j + 1)
                                if (strb_q[j]) data[index][word_index][j*8 +: 8] <= data_q[j*8 +: 8];
                        end
                    end else begin
                        transfer_word <= transfer_word + 1'b1;
                        state <= REFILL_REQ;
                    end
                end
                WT_REQ: if (mem_req_ready) state <= WT_WAIT;
                WT_WAIT: if (mem_resp_valid) begin resp_data <= 0; state <= RESPOND; end
                RESPOND: if (resp_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk) disable iff (reset)
        resp_valid && !resp_ready |=> resp_valid && $stable(resp_data));
    assert property (@(posedge clk) disable iff (reset)
        mem_req_valid && !mem_req_ready |=> mem_req_valid &&
        $stable({mem_req_addr, mem_req_data, mem_req_strb}));
`endif
endmodule
