`timescale 1ns/1ps
module cpu_request_axi(
    input logic clk, reset, req_valid,
    output logic req_ready,
    input logic [31:0] req_addr, req_data,
    input logic [3:0] req_strb,
    output logic resp_valid,
    input logic resp_ready,
    output logic [31:0] resp_data,
    output logic fault,
    output logic [31:0] m_axi_awaddr, m_axi_wdata, m_axi_araddr,
    output logic [3:0] m_axi_wstrb,
    output logic m_axi_awvalid, m_axi_wvalid, m_axi_bready, m_axi_arvalid, m_axi_rready,
    input logic m_axi_awready, m_axi_wready, m_axi_bvalid, m_axi_arready, m_axi_rvalid,
    input logic [1:0] m_axi_bresp, m_axi_rresp,
    input logic [31:0] m_axi_rdata
);
    typedef enum logic [2:0] {IDLE, AR, R, AW, W, B, RESPONSE, FAILED} state_t;
    state_t state;
    logic [31:0] address_q, data_q;
    logic [3:0] strb_q;
    assign req_ready = state == IDLE && !reset && !fault;
    assign resp_valid = state == RESPONSE;
    assign m_axi_awaddr=address_q;
    assign m_axi_araddr=address_q;
    assign m_axi_wdata=data_q;
    assign m_axi_wstrb=strb_q;
    assign m_axi_arvalid=state==AR;
    assign m_axi_rready=state==R;
    assign m_axi_awvalid=state==AW;
    assign m_axi_wvalid=state==W;
    assign m_axi_bready=state==B;
    always_ff @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE; address_q<=0; data_q<=0; strb_q<=0; resp_data<=0; fault<=0;
        end else case(state)
            IDLE: if(req_valid && req_ready) begin
                address_q<=req_addr; data_q<=req_data; strb_q<=req_strb;
                state<=|req_strb ? AW : AR;
            end
            AR: if(m_axi_arready) state<=R;
            R: if(m_axi_rvalid) begin
                if(m_axi_rresp != 0) begin fault<=1; state<=FAILED; end
                else begin resp_data<=m_axi_rdata; state<=RESPONSE; end
            end
            AW: if(m_axi_awready) state<=W;
            W: if(m_axi_wready) state<=B;
            B: if(m_axi_bvalid) begin
                if(m_axi_bresp != 0) begin fault<=1; state<=FAILED; end
                else begin resp_data<=0; state<=RESPONSE; end
            end
            RESPONSE: if(resp_ready) state<=IDLE;
            FAILED: state<=FAILED;
            default: state<=FAILED;
        endcase
    end
`ifndef SYNTHESIS
    assert property (@(posedge clk) disable iff(reset)
        resp_valid && !resp_ready |=> resp_valid && $stable(resp_data));
`endif
endmodule
