`timescale 1ns/1ps

module axi_lite_ram #(
    parameter bit RANDOM_BACKPRESSURE = 1'b0
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    output logic [14:0] host_addr,
    output logic        host_we,
    output logic [31:0] host_wdata,
    input  logic [31:0] host_rdata
);
    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;

    logic [31:0] awaddr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        aw_held;
    logic        w_held;
    logic        write_commit;
    logic [7:0]  ready_lfsr;

    function automatic logic address_valid(input logic [31:0] addr);
        address_valid = (addr >= 32'h0000_4000) &&
                        (addr <= 32'h0001_bfff);
    endfunction

    assign s_axi_awready = !aw_held && !s_axi_bvalid &&
                           (!RANDOM_BACKPRESSURE || ready_lfsr[0]);
    assign s_axi_wready  = !w_held && !s_axi_bvalid &&
                           (!RANDOM_BACKPRESSURE || ready_lfsr[2]);
    assign s_axi_arready = !s_axi_rvalid && !write_commit &&
                           (!RANDOM_BACKPRESSURE || ready_lfsr[4]);
    assign write_commit  = aw_held && w_held && !s_axi_bvalid;

    assign host_addr = write_commit ? awaddr_q[16:2] : s_axi_araddr[16:2];
    assign host_we = write_commit && address_valid(awaddr_q);
    assign host_wdata = {
        wstrb_q[3] ? wdata_q[31:24] : host_rdata[31:24],
        wstrb_q[2] ? wdata_q[23:16] : host_rdata[23:16],
        wstrb_q[1] ? wdata_q[15:8]  : host_rdata[15:8],
        wstrb_q[0] ? wdata_q[7:0]   : host_rdata[7:0]
    };

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ready_lfsr   <= 8'h5a;
            awaddr_q    <= 32'b0;
            wdata_q     <= 32'b0;
            wstrb_q     <= 4'b0;
            aw_held     <= 1'b0;
            w_held      <= 1'b0;
            s_axi_bresp <= AXI_OKAY;
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= AXI_OKAY;
            s_axi_rvalid <= 1'b0;
        end else begin
            ready_lfsr <= {ready_lfsr[6:0], ready_lfsr[7] ^ ready_lfsr[5] ^ ready_lfsr[4] ^ ready_lfsr[3]};
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_q <= s_axi_awaddr;
                aw_held  <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                w_held  <= 1'b1;
            end

            if (write_commit) begin
                aw_held      <= 1'b0;
                w_held       <= 1'b0;
                s_axi_bresp  <= address_valid(awaddr_q) ? AXI_OKAY : AXI_SLVERR;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rdata  <= address_valid(s_axi_araddr) ? host_rdata : 32'b0;
                s_axi_rresp  <= address_valid(s_axi_araddr) ? AXI_OKAY : AXI_SLVERR;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
