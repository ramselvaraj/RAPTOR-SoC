`timescale 1ns/1ps

module axi_lite_checker (
    input logic        clk,
    input logic        reset,
    input logic [31:0] awaddr,
    input logic        awvalid,
    input logic        awready,
    input logic [31:0] wdata,
    input logic [3:0]  wstrb,
    input logic        wvalid,
    input logic        wready,
    input logic [1:0]  bresp,
    input logic        bvalid,
    input logic        bready,
    input logic [31:0] araddr,
    input logic        arvalid,
    input logic        arready,
    input logic [31:0] rdata,
    input logic [1:0]  rresp,
    input logic        rvalid,
    input logic        rready
);
    logic aw_accepted;
    logic w_accepted;
    logic ar_accepted;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            aw_accepted <= 1'b0;
            w_accepted  <= 1'b0;
            ar_accepted <= 1'b0;
        end else begin
            if (bvalid && bready) begin
                aw_accepted <= 1'b0;
                w_accepted  <= 1'b0;
            end
            if (rvalid && rready)
                ar_accepted <= 1'b0;
            if (awvalid && awready)
                aw_accepted <= 1'b1;
            if (wvalid && wready)
                w_accepted <= 1'b1;
            if (arvalid && arready)
                ar_accepted <= 1'b1;
        end
    end

    assert property (@(posedge clk) disable iff (reset)
        awvalid && !awready |=> awvalid && $stable(awaddr));
    assert property (@(posedge clk) disable iff (reset)
        wvalid && !wready |=> wvalid && $stable({wdata, wstrb}));
    assert property (@(posedge clk) disable iff (reset)
        arvalid && !arready |=> arvalid && $stable(araddr));
    assert property (@(posedge clk) disable iff (reset)
        bvalid && !bready |=> bvalid && $stable(bresp));
    assert property (@(posedge clk) disable iff (reset)
        rvalid && !rready |=> rvalid && $stable({rdata, rresp}));

    assert property (@(posedge clk) disable iff (reset)
        bvalid |-> (aw_accepted && w_accepted));
    assert property (@(posedge clk) disable iff (reset)
        rvalid |-> ar_accepted);
    assert property (@(posedge clk) disable iff (reset)
        !$isunknown({awready, wready, bvalid, arready, rvalid}));
endmodule

bind axi_lite_ram axi_lite_checker ram_axi_protocol (
    .clk(clk), .reset(reset),
    .awaddr(s_axi_awaddr), .awvalid(s_axi_awvalid), .awready(s_axi_awready),
    .wdata(s_axi_wdata), .wstrb(s_axi_wstrb),
    .wvalid(s_axi_wvalid), .wready(s_axi_wready),
    .bresp(s_axi_bresp), .bvalid(s_axi_bvalid), .bready(s_axi_bready),
    .araddr(s_axi_araddr), .arvalid(s_axi_arvalid), .arready(s_axi_arready),
    .rdata(s_axi_rdata), .rresp(s_axi_rresp),
    .rvalid(s_axi_rvalid), .rready(s_axi_rready)
);

bind gpu_mmio axi_lite_checker mmio_axi_protocol (
    .clk(clk), .reset(reset),
    .awaddr(s_axi_awaddr), .awvalid(s_axi_awvalid), .awready(s_axi_awready),
    .wdata(s_axi_wdata), .wstrb(s_axi_wstrb),
    .wvalid(s_axi_wvalid), .wready(s_axi_wready),
    .bresp(s_axi_bresp), .bvalid(s_axi_bvalid), .bready(s_axi_bready),
    .araddr(s_axi_araddr), .arvalid(s_axi_arvalid), .arready(s_axi_arready),
    .rdata(s_axi_rdata), .rresp(s_axi_rresp),
    .rvalid(s_axi_rvalid), .rready(s_axi_rready)
);

bind axi_lite_interconnect axi_lite_checker master0_axi_protocol (
    .clk(clk), .reset(reset),
    .awaddr(m0_axi_awaddr), .awvalid(m0_axi_awvalid), .awready(m0_axi_awready),
    .wdata(m0_axi_wdata), .wstrb(m0_axi_wstrb),
    .wvalid(m0_axi_wvalid), .wready(m0_axi_wready),
    .bresp(m0_axi_bresp), .bvalid(m0_axi_bvalid), .bready(m0_axi_bready),
    .araddr(m0_axi_araddr), .arvalid(m0_axi_arvalid), .arready(m0_axi_arready),
    .rdata(m0_axi_rdata), .rresp(m0_axi_rresp),
    .rvalid(m0_axi_rvalid), .rready(m0_axi_rready)
);

bind axi_lite_interconnect axi_lite_checker master1_axi_protocol (
    .clk(clk), .reset(reset),
    .awaddr(m1_axi_awaddr), .awvalid(m1_axi_awvalid), .awready(m1_axi_awready),
    .wdata(m1_axi_wdata), .wstrb(m1_axi_wstrb),
    .wvalid(m1_axi_wvalid), .wready(m1_axi_wready),
    .bresp(m1_axi_bresp), .bvalid(m1_axi_bvalid), .bready(m1_axi_bready),
    .araddr(m1_axi_araddr), .arvalid(m1_axi_arvalid), .arready(m1_axi_arready),
    .rdata(m1_axi_rdata), .rresp(m1_axi_rresp),
    .rvalid(m1_axi_rvalid), .rready(m1_axi_rready)
);
