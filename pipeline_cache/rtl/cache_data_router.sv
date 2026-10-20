`timescale 1ns/1ps
// Serialize CPU data operations. Only complete private-RAM lines are cached.
module cache_data_router #(
    parameter int LINES=4, WORDS_PER_LINE=4,
    parameter bit BYPASS=0, WRITE_BACK=1
)(
    input logic clk, reset, req_valid,
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
    typedef enum logic [1:0] {IDLE, SEND, WAIT_RESPONSE} state_t;
    state_t state;
    logic cached;
    logic [31:0] addr_q, data_q;
    logic [3:0] strb_q;
    logic cv, cr, rv, rr, mv, mr, mrv, mrr;
    logic [31:0] rd, ma, md;
    logic [3:0] ms;
    assign req_ready = state == IDLE && !reset;
    assign cv = state == SEND && cached;
    assign rr = state == WAIT_RESPONSE && cached && resp_ready;
    assign mr = cached && mem_req_ready;
    assign mrv = cached && mem_resp_valid;
    assign mem_req_valid = cached ? mv : state == SEND;
    assign mem_req_addr = cached ? ma : addr_q;
    assign mem_req_data = cached ? md : data_q;
    assign mem_req_strb = cached ? ms : strb_q;
    assign mem_resp_ready = cached ? mrr : (state == WAIT_RESPONSE && resp_ready);
    assign resp_valid = state == WAIT_RESPONSE && (cached ? rv : mem_resp_valid);
    assign resp_data = cached ? rd : mem_resp_data;
    generate if (!BYPASS) begin : cache_enabled
        blocking_cache #(.LINES(LINES), .WORDS_PER_LINE(WORDS_PER_LINE), .WRITE_BACK(WRITE_BACK)) cache(
            .clk, .reset, .req_valid(cv), .req_ready(cr), .req_addr(addr_q),
            .req_data(data_q), .req_strb(strb_q), .resp_valid(rv), .resp_ready(rr), .resp_data(rd),
            .mem_req_valid(mv), .mem_req_ready(mr), .mem_req_addr(ma), .mem_req_data(md),
            .mem_req_strb(ms), .mem_resp_valid(mrv), .mem_resp_ready(mrr), .mem_resp_data,
            .hits, .misses, .writebacks);
    end else begin : bypass_cache
        assign {cr, rv, mv, mrr} = '0;
        assign {rd, ma, md, ms} = '0;
        assign {hits, misses, writebacks} = '0;
    end endgenerate
    always_ff @(posedge clk or posedge reset) begin
        if(reset) begin state<=IDLE; cached<=0; addr_q<=0; data_q<=0; strb_q<=0; end
        else case(state)
            IDLE: if(req_valid && req_ready) begin
                addr_q<=req_addr; data_q<=req_data; strb_q<=req_strb;
                cached <= !BYPASS && req_addr >= 32'h4000 &&
                    ((req_addr | (32'(WORDS_PER_LINE*4)-1)) <= 32'h4fff);
                state<=SEND;
            end
            SEND: if(cached ? cr : mem_req_ready) state<=WAIT_RESPONSE;
            WAIT_RESPONSE: if(resp_valid && resp_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
