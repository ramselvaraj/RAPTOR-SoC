`timescale 1ns/1ps
module delayed_memory #(
    parameter int WORDS = 4096,
    parameter int MAX_DELAY = 7,
    parameter int SEED = 1
)(
    input logic clk, reset,
    input logic req_valid,
    output logic req_ready,
    input logic [31:0] req_addr, req_data,
    input logic [3:0] req_strb,
    output logic resp_valid,
    input logic resp_ready,
    output logic [31:0] resp_data
);
    logic [31:0] words [0:WORDS-1];
    logic busy;
    logic [31:0] address_q, data_q, random_state;
    logic [3:0] strb_q;
    integer countdown;
    integer j;
    assign req_ready = !busy && !resp_valid && random_state[1:0] != 0 && !reset;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 0; resp_valid <= 0; resp_data <= 0;
            address_q <= 0; data_q <= 0; strb_q <= 0; countdown <= 0;
            random_state <= 32'(SEED);
        end else begin
            random_state <= {random_state[30:0], random_state[31] ^ random_state[21] ^ random_state[1] ^ random_state[0]};
            if (req_valid && req_ready) begin
                assert (req_addr[1:0] == 0 && req_addr < WORDS * 4)
                    else $fatal(1, "memory address out of range: %h", req_addr);
                busy <= 1; address_q <= req_addr; data_q <= req_data; strb_q <= req_strb;
                countdown <= int'(random_state % (MAX_DELAY + 1));
            end
            if (busy) begin
                if (countdown == 0) begin
                    for (j = 0; j < 4; j = j + 1)
                        if (strb_q[j]) words[address_q >> 2][j*8 +: 8] <= data_q[j*8 +: 8];
                    resp_data <= words[address_q >> 2];
                    resp_valid <= 1; busy <= 0;
                end else countdown <= countdown - 1;
            end
            if (resp_valid && resp_ready) resp_valid <= 0;
        end
    end
    assert property (@(posedge clk) disable iff (reset)
        req_valid && !req_ready |=> req_valid && $stable({req_addr, req_data, req_strb}));
    assert property (@(posedge clk) disable iff (reset)
        resp_valid && !resp_ready |=> resp_valid && $stable(resp_data));
endmodule
