`timescale 1ns/1ps

module axi_lite_interconnect (
    input  logic        clk,
    input  logic        reset,

    input  logic [31:0] m0_axi_awaddr,
    input  logic        m0_axi_awvalid,
    output logic        m0_axi_awready,
    input  logic [31:0] m0_axi_wdata,
    input  logic [3:0]  m0_axi_wstrb,
    input  logic        m0_axi_wvalid,
    output logic        m0_axi_wready,
    output logic [1:0]  m0_axi_bresp,
    output logic        m0_axi_bvalid,
    input  logic        m0_axi_bready,
    input  logic [31:0] m0_axi_araddr,
    input  logic        m0_axi_arvalid,
    output logic        m0_axi_arready,
    output logic [31:0] m0_axi_rdata,
    output logic [1:0]  m0_axi_rresp,
    output logic        m0_axi_rvalid,
    input  logic        m0_axi_rready,

    input  logic [31:0] m1_axi_awaddr,
    input  logic        m1_axi_awvalid,
    output logic        m1_axi_awready,
    input  logic [31:0] m1_axi_wdata,
    input  logic [3:0]  m1_axi_wstrb,
    input  logic        m1_axi_wvalid,
    output logic        m1_axi_wready,
    output logic [1:0]  m1_axi_bresp,
    output logic        m1_axi_bvalid,
    input  logic        m1_axi_bready,
    input  logic [31:0] m1_axi_araddr,
    input  logic        m1_axi_arvalid,
    output logic        m1_axi_arready,
    output logic [31:0] m1_axi_rdata,
    output logic [1:0]  m1_axi_rresp,
    output logic        m1_axi_rvalid,
    input  logic        m1_axi_rready,

    output logic [31:0] s0_axi_awaddr,
    output logic        s0_axi_awvalid,
    input  logic        s0_axi_awready,
    output logic [31:0] s0_axi_wdata,
    output logic [3:0]  s0_axi_wstrb,
    output logic        s0_axi_wvalid,
    input  logic        s0_axi_wready,
    input  logic [1:0]  s0_axi_bresp,
    input  logic        s0_axi_bvalid,
    output logic        s0_axi_bready,
    output logic [31:0] s0_axi_araddr,
    output logic        s0_axi_arvalid,
    input  logic        s0_axi_arready,
    input  logic [31:0] s0_axi_rdata,
    input  logic [1:0]  s0_axi_rresp,
    input  logic        s0_axi_rvalid,
    output logic        s0_axi_rready,

    output logic [31:0] s1_axi_awaddr,
    output logic        s1_axi_awvalid,
    input  logic        s1_axi_awready,
    output logic [31:0] s1_axi_wdata,
    output logic [3:0]  s1_axi_wstrb,
    output logic        s1_axi_wvalid,
    input  logic        s1_axi_wready,
    input  logic [1:0]  s1_axi_bresp,
    input  logic        s1_axi_bvalid,
    output logic        s1_axi_bready,
    output logic [31:0] s1_axi_araddr,
    output logic        s1_axi_arvalid,
    input  logic        s1_axi_arready,
    input  logic [31:0] s1_axi_rdata,
    input  logic [1:0]  s1_axi_rresp,
    input  logic        s1_axi_rvalid,
    output logic        s1_axi_rready
);
    typedef enum logic [1:0] {IC_IDLE, IC_WRITE, IC_READ} state_t;
    state_t state;
    logic master_q;
    logic slave_q;
    logic next_master;
    logic m0_request;
    logic m1_request;
    logic selected_master;
    logic selected_write;
    logic [31:0] selected_addr;
    logic response_accepted;

    assign m0_request = m0_axi_awvalid || m0_axi_arvalid;
    assign m1_request = m1_axi_awvalid || m1_axi_arvalid;

    always_comb begin
        if (m0_request && m1_request)
            selected_master = next_master;
        else
            selected_master = m1_request;

        if (!selected_master) begin
            selected_write = m0_axi_awvalid;
            selected_addr  = selected_write ? m0_axi_awaddr : m0_axi_araddr;
        end else begin
            selected_write = m1_axi_awvalid;
            selected_addr  = selected_write ? m1_axi_awaddr : m1_axi_araddr;
        end
    end

    always_comb begin
        response_accepted = 1'b0;
        if (state == IC_WRITE) begin
            if (!master_q)
                response_accepted = m0_axi_bvalid && m0_axi_bready;
            else
                response_accepted = m1_axi_bvalid && m1_axi_bready;
        end else if (state == IC_READ) begin
            if (!master_q)
                response_accepted = m0_axi_rvalid && m0_axi_rready;
            else
                response_accepted = m1_axi_rvalid && m1_axi_rready;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IC_IDLE;
            master_q    <= 1'b0;
            slave_q     <= 1'b0;
            next_master <= 1'b0;
        end else begin
            if (state == IC_IDLE) begin
                if (m0_request || m1_request) begin
                    master_q <= selected_master;
                    slave_q  <= (selected_addr[31:28] == 4'h4);
                    state    <= selected_write ? IC_WRITE : IC_READ;
                end
            end else if (response_accepted) begin
                next_master <= ~master_q;
                state       <= IC_IDLE;
            end
        end
    end

    always_comb begin
        m0_axi_awready = 1'b0;
        m0_axi_wready  = 1'b0;
        m0_axi_bresp   = 2'b00;
        m0_axi_bvalid  = 1'b0;
        m0_axi_arready = 1'b0;
        m0_axi_rdata   = 32'b0;
        m0_axi_rresp   = 2'b00;
        m0_axi_rvalid  = 1'b0;

        m1_axi_awready = 1'b0;
        m1_axi_wready  = 1'b0;
        m1_axi_bresp   = 2'b00;
        m1_axi_bvalid  = 1'b0;
        m1_axi_arready = 1'b0;
        m1_axi_rdata   = 32'b0;
        m1_axi_rresp   = 2'b00;
        m1_axi_rvalid  = 1'b0;

        s0_axi_awaddr  = 32'b0;
        s0_axi_awvalid = 1'b0;
        s0_axi_wdata   = 32'b0;
        s0_axi_wstrb   = 4'b0;
        s0_axi_wvalid  = 1'b0;
        s0_axi_bready  = 1'b0;
        s0_axi_araddr  = 32'b0;
        s0_axi_arvalid = 1'b0;
        s0_axi_rready  = 1'b0;

        s1_axi_awaddr  = 32'b0;
        s1_axi_awvalid = 1'b0;
        s1_axi_wdata   = 32'b0;
        s1_axi_wstrb   = 4'b0;
        s1_axi_wvalid  = 1'b0;
        s1_axi_bready  = 1'b0;
        s1_axi_araddr  = 32'b0;
        s1_axi_arvalid = 1'b0;
        s1_axi_rready  = 1'b0;

        if (state == IC_WRITE) begin
            if (!master_q) begin
                if (!slave_q) begin
                    s0_axi_awaddr   = m0_axi_awaddr;
                    s0_axi_awvalid  = m0_axi_awvalid;
                    m0_axi_awready  = s0_axi_awready;
                    s0_axi_wdata    = m0_axi_wdata;
                    s0_axi_wstrb    = m0_axi_wstrb;
                    s0_axi_wvalid   = m0_axi_wvalid;
                    m0_axi_wready   = s0_axi_wready;
                    m0_axi_bresp    = s0_axi_bresp;
                    m0_axi_bvalid   = s0_axi_bvalid;
                    s0_axi_bready   = m0_axi_bready;
                end else begin
                    s1_axi_awaddr   = m0_axi_awaddr;
                    s1_axi_awvalid  = m0_axi_awvalid;
                    m0_axi_awready  = s1_axi_awready;
                    s1_axi_wdata    = m0_axi_wdata;
                    s1_axi_wstrb    = m0_axi_wstrb;
                    s1_axi_wvalid   = m0_axi_wvalid;
                    m0_axi_wready   = s1_axi_wready;
                    m0_axi_bresp    = s1_axi_bresp;
                    m0_axi_bvalid   = s1_axi_bvalid;
                    s1_axi_bready   = m0_axi_bready;
                end
            end else begin
                if (!slave_q) begin
                    s0_axi_awaddr   = m1_axi_awaddr;
                    s0_axi_awvalid  = m1_axi_awvalid;
                    m1_axi_awready  = s0_axi_awready;
                    s0_axi_wdata    = m1_axi_wdata;
                    s0_axi_wstrb    = m1_axi_wstrb;
                    s0_axi_wvalid   = m1_axi_wvalid;
                    m1_axi_wready   = s0_axi_wready;
                    m1_axi_bresp    = s0_axi_bresp;
                    m1_axi_bvalid   = s0_axi_bvalid;
                    s0_axi_bready   = m1_axi_bready;
                end else begin
                    s1_axi_awaddr   = m1_axi_awaddr;
                    s1_axi_awvalid  = m1_axi_awvalid;
                    m1_axi_awready  = s1_axi_awready;
                    s1_axi_wdata    = m1_axi_wdata;
                    s1_axi_wstrb    = m1_axi_wstrb;
                    s1_axi_wvalid   = m1_axi_wvalid;
                    m1_axi_wready   = s1_axi_wready;
                    m1_axi_bresp    = s1_axi_bresp;
                    m1_axi_bvalid   = s1_axi_bvalid;
                    s1_axi_bready   = m1_axi_bready;
                end
            end
        end else if (state == IC_READ) begin
            if (!master_q) begin
                if (!slave_q) begin
                    s0_axi_araddr   = m0_axi_araddr;
                    s0_axi_arvalid  = m0_axi_arvalid;
                    m0_axi_arready  = s0_axi_arready;
                    m0_axi_rdata    = s0_axi_rdata;
                    m0_axi_rresp    = s0_axi_rresp;
                    m0_axi_rvalid   = s0_axi_rvalid;
                    s0_axi_rready   = m0_axi_rready;
                end else begin
                    s1_axi_araddr   = m0_axi_araddr;
                    s1_axi_arvalid  = m0_axi_arvalid;
                    m0_axi_arready  = s1_axi_arready;
                    m0_axi_rdata    = s1_axi_rdata;
                    m0_axi_rresp    = s1_axi_rresp;
                    m0_axi_rvalid   = s1_axi_rvalid;
                    s1_axi_rready   = m0_axi_rready;
                end
            end else begin
                if (!slave_q) begin
                    s0_axi_araddr   = m1_axi_araddr;
                    s0_axi_arvalid  = m1_axi_arvalid;
                    m1_axi_arready  = s0_axi_arready;
                    m1_axi_rdata    = s0_axi_rdata;
                    m1_axi_rresp    = s0_axi_rresp;
                    m1_axi_rvalid   = s0_axi_rvalid;
                    s0_axi_rready   = m1_axi_rready;
                end else begin
                    s1_axi_araddr   = m1_axi_araddr;
                    s1_axi_arvalid  = m1_axi_arvalid;
                    m1_axi_arready  = s1_axi_arready;
                    m1_axi_rdata    = s1_axi_rdata;
                    m1_axi_rresp    = s1_axi_rresp;
                    m1_axi_rvalid   = s1_axi_rvalid;
                    s1_axi_rready   = m1_axi_rready;
                end
            end
        end
    end
endmodule
