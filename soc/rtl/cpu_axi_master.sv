`timescale 1ns/1ps

module cpu_axi_master (
    input  logic        clk,
    input  logic        reset,
    input  logic        req,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        done,

    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    typedef enum logic [3:0] {
        A_IDLE, A_AR, A_R, A_AW, A_W, A_B, A_DONE
    } state_t;

    state_t state;
    logic [31:0] addr_q;
    logic [31:0] wdata_q;

    assign m_axi_awaddr  = addr_q;
    assign m_axi_awvalid = (state == A_AW);
    assign m_axi_wdata   = wdata_q;
    assign m_axi_wstrb   = 4'b1111;
    assign m_axi_wvalid  = (state == A_W);
    assign m_axi_bready  = (state == A_B);
    assign m_axi_araddr  = addr_q;
    assign m_axi_arvalid = (state == A_AR);
    assign m_axi_rready  = (state == A_R);
    assign done           = (state == A_DONE);

    // The CPU currently treats bus errors as completed accesses. The response
    // ports remain visible here for a future architectural fault mechanism.
    logic unused_response;
    assign unused_response = ^{m_axi_bresp, m_axi_rresp};

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state   <= A_IDLE;
            addr_q  <= 32'b0;
            wdata_q <= 32'b0;
            rdata   <= 32'b0;
        end else begin
            case (state)
                A_IDLE: if (req) begin
                    addr_q  <= addr;
                    wdata_q <= wdata;
                    state   <= we ? A_AW : A_AR;
                end
                A_AR: if (m_axi_arready)
                    state <= A_R;
                A_R: if (m_axi_rvalid) begin
                    rdata <= m_axi_rdata;
                    state <= A_DONE;
                end
                A_AW: if (m_axi_awready)
                    state <= A_W;
                A_W: if (m_axi_wready)
                    state <= A_B;
                A_B: if (m_axi_bvalid)
                    state <= A_DONE;
                A_DONE: state <= A_IDLE;
                default: state <= A_IDLE;
            endcase
        end
    end
endmodule
