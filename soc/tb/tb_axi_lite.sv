`timescale 1ns/1ps

module tb_axi_lite;
    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;

    logic clk;
    logic reset = 1'b1;

    logic [31:0] m_awaddr [0:1];
    logic        m_awvalid[0:1];
    logic        m_awready[0:1];
    logic [31:0] m_wdata  [0:1];
    logic [3:0]  m_wstrb  [0:1];
    logic        m_wvalid [0:1];
    logic        m_wready [0:1];
    logic [1:0]  m_bresp  [0:1];
    logic        m_bvalid [0:1];
    logic        m_bready [0:1];
    logic [31:0] m_araddr [0:1];
    logic        m_arvalid[0:1];
    logic        m_arready[0:1];
    logic [31:0] m_rdata  [0:1];
    logic [1:0]  m_rresp  [0:1];
    logic        m_rvalid [0:1];
    logic        m_rready [0:1];

    logic [31:0] s_awaddr [0:1];
    logic        s_awvalid[0:1];
    logic        s_awready[0:1];
    logic [31:0] s_wdata  [0:1];
    logic [3:0]  s_wstrb  [0:1];
    logic        s_wvalid [0:1];
    logic        s_wready [0:1];
    logic [1:0]  s_bresp  [0:1];
    logic        s_bvalid [0:1];
    logic        s_bready [0:1];
    logic [31:0] s_araddr [0:1];
    logic        s_arvalid[0:1];
    logic        s_arready[0:1];
    logic [31:0] s_rdata  [0:1];
    logic [1:0]  s_rresp  [0:1];
    logic        s_rvalid [0:1];
    logic        s_rready [0:1];

    logic [14:0] host_addr;
    logic        host_we;
    logic [31:0] host_wdata;
    logic [31:0] host_rdata;
    logic [31:0] px_rdata;

    logic gpu_busy = 1'b0;
    logic gpu_done = 1'b0;
    logic start;
    logic [31:0] thread_count;
    logic [31:0] src_addr;
    logic [31:0] dst_addr;
    logic [31:0] prog_base;

    integer errors = 0;
    integer start_count;
    integer completed [0:1];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    axi_lite_interconnect dut (
        .clk(clk), .reset(reset),
        .m0_axi_awaddr(m_awaddr[0]), .m0_axi_awvalid(m_awvalid[0]), .m0_axi_awready(m_awready[0]),
        .m0_axi_wdata(m_wdata[0]), .m0_axi_wstrb(m_wstrb[0]), .m0_axi_wvalid(m_wvalid[0]), .m0_axi_wready(m_wready[0]),
        .m0_axi_bresp(m_bresp[0]), .m0_axi_bvalid(m_bvalid[0]), .m0_axi_bready(m_bready[0]),
        .m0_axi_araddr(m_araddr[0]), .m0_axi_arvalid(m_arvalid[0]), .m0_axi_arready(m_arready[0]),
        .m0_axi_rdata(m_rdata[0]), .m0_axi_rresp(m_rresp[0]), .m0_axi_rvalid(m_rvalid[0]), .m0_axi_rready(m_rready[0]),
        .m1_axi_awaddr(m_awaddr[1]), .m1_axi_awvalid(m_awvalid[1]), .m1_axi_awready(m_awready[1]),
        .m1_axi_wdata(m_wdata[1]), .m1_axi_wstrb(m_wstrb[1]), .m1_axi_wvalid(m_wvalid[1]), .m1_axi_wready(m_wready[1]),
        .m1_axi_bresp(m_bresp[1]), .m1_axi_bvalid(m_bvalid[1]), .m1_axi_bready(m_bready[1]),
        .m1_axi_araddr(m_araddr[1]), .m1_axi_arvalid(m_arvalid[1]), .m1_axi_arready(m_arready[1]),
        .m1_axi_rdata(m_rdata[1]), .m1_axi_rresp(m_rresp[1]), .m1_axi_rvalid(m_rvalid[1]), .m1_axi_rready(m_rready[1]),
        .s0_axi_awaddr(s_awaddr[0]), .s0_axi_awvalid(s_awvalid[0]), .s0_axi_awready(s_awready[0]),
        .s0_axi_wdata(s_wdata[0]), .s0_axi_wstrb(s_wstrb[0]), .s0_axi_wvalid(s_wvalid[0]), .s0_axi_wready(s_wready[0]),
        .s0_axi_bresp(s_bresp[0]), .s0_axi_bvalid(s_bvalid[0]), .s0_axi_bready(s_bready[0]),
        .s0_axi_araddr(s_araddr[0]), .s0_axi_arvalid(s_arvalid[0]), .s0_axi_arready(s_arready[0]),
        .s0_axi_rdata(s_rdata[0]), .s0_axi_rresp(s_rresp[0]), .s0_axi_rvalid(s_rvalid[0]), .s0_axi_rready(s_rready[0]),
        .s1_axi_awaddr(s_awaddr[1]), .s1_axi_awvalid(s_awvalid[1]), .s1_axi_awready(s_awready[1]),
        .s1_axi_wdata(s_wdata[1]), .s1_axi_wstrb(s_wstrb[1]), .s1_axi_wvalid(s_wvalid[1]), .s1_axi_wready(s_wready[1]),
        .s1_axi_bresp(s_bresp[1]), .s1_axi_bvalid(s_bvalid[1]), .s1_axi_bready(s_bready[1]),
        .s1_axi_araddr(s_araddr[1]), .s1_axi_arvalid(s_arvalid[1]), .s1_axi_arready(s_arready[1]),
        .s1_axi_rdata(s_rdata[1]), .s1_axi_rresp(s_rresp[1]), .s1_axi_rvalid(s_rvalid[1]), .s1_axi_rready(s_rready[1])
    );

    axi_lite_ram #(.RANDOM_BACKPRESSURE(1'b1)) ram_slave (
        .clk(clk), .reset(reset),
        .s_axi_awaddr(s_awaddr[0]), .s_axi_awvalid(s_awvalid[0]), .s_axi_awready(s_awready[0]),
        .s_axi_wdata(s_wdata[0]), .s_axi_wstrb(s_wstrb[0]), .s_axi_wvalid(s_wvalid[0]), .s_axi_wready(s_wready[0]),
        .s_axi_bresp(s_bresp[0]), .s_axi_bvalid(s_bvalid[0]), .s_axi_bready(s_bready[0]),
        .s_axi_araddr(s_araddr[0]), .s_axi_arvalid(s_arvalid[0]), .s_axi_arready(s_arready[0]),
        .s_axi_rdata(s_rdata[0]), .s_axi_rresp(s_rresp[0]), .s_axi_rvalid(s_rvalid[0]), .s_axi_rready(s_rready[0]),
        .host_addr(host_addr), .host_we(host_we), .host_wdata(host_wdata), .host_rdata(host_rdata)
    );

    shared_ram ram (
        .clk(clk), .px_addr(15'h2000), .px_we(1'b0), .px_wdata(32'b0), .px_rdata(px_rdata),
        .host_addr(host_addr), .host_we(host_we), .host_wdata(host_wdata), .host_rdata(host_rdata)
    );

    gpu_mmio #(.RANDOM_BACKPRESSURE(1'b1)) mmio_slave (
        .command_ready(1'b1),
        .clk(clk), .reset(reset),
        .s_axi_awaddr(s_awaddr[1]), .s_axi_awvalid(s_awvalid[1]), .s_axi_awready(s_awready[1]),
        .s_axi_wdata(s_wdata[1]), .s_axi_wstrb(s_wstrb[1]), .s_axi_wvalid(s_wvalid[1]), .s_axi_wready(s_wready[1]),
        .s_axi_bresp(s_bresp[1]), .s_axi_bvalid(s_bvalid[1]), .s_axi_bready(s_bready[1]),
        .s_axi_araddr(s_araddr[1]), .s_axi_arvalid(s_arvalid[1]), .s_axi_arready(s_arready[1]),
        .s_axi_rdata(s_rdata[1]), .s_axi_rresp(s_rresp[1]), .s_axi_rvalid(s_rvalid[1]), .s_axi_rready(s_rready[1]),
        .gpu_busy(gpu_busy), .gpu_done(gpu_done), .start(start),
        .thread_count(thread_count), .src_addr(src_addr), .dst_addr(dst_addr), .prog_base(prog_base)
    );

    always_ff @(posedge clk) begin
        if (reset)
            start_count <= 0;
        else if (start)
            start_count <= start_count + 1;
    end

    task automatic check_result(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            errors = errors + 1;
        end
    endtask

    task automatic axi_write(
        input logic master,
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0] strobe,
        input integer aw_delay,
        input integer w_delay,
        output logic [1:0] response
    );
        fork
            begin
                repeat (aw_delay) @(negedge clk);
                m_awaddr[master]  = address;
                m_awvalid[master] = 1'b1;
                do @(posedge clk); while (!m_awready[master]);
                @(negedge clk);
                m_awvalid[master] = 1'b0;
            end
            begin
                repeat (w_delay) @(negedge clk);
                m_wdata[master]  = data;
                m_wstrb[master]  = strobe;
                m_wvalid[master] = 1'b1;
                do @(posedge clk); while (!m_wready[master]);
                @(negedge clk);
                m_wvalid[master] = 1'b0;
            end
        join

        m_bready[master] = 1'b0;
        do begin
            @(negedge clk);
            m_bready[master] = ($urandom_range(0, 1) != 0);
            @(posedge clk);
        end while (!(m_bvalid[master] && m_bready[master]));
        response = m_bresp[master];
        completed[master] = completed[master] + 1;
        @(negedge clk);
        m_bready[master] = 1'b0;
    endtask

    task automatic axi_read(
        input logic master,
        input logic [31:0] address,
        input integer ar_delay,
        output logic [31:0] data,
        output logic [1:0] response
    );
        repeat (ar_delay) @(negedge clk);
        m_araddr[master]  = address;
        m_arvalid[master] = 1'b1;
        do @(posedge clk); while (!m_arready[master]);
        @(negedge clk);
        m_arvalid[master] = 1'b0;
        m_rready[master] = 1'b0;
        do begin
            @(negedge clk);
            m_rready[master] = ($urandom_range(0, 1) != 0);
            @(posedge clk);
        end while (!(m_rvalid[master] && m_rready[master]));
        data = m_rdata[master];
        response = m_rresp[master];
        completed[master] = completed[master] + 1;
        @(negedge clk);
        m_rready[master] = 1'b0;
    endtask

    initial begin : test_sequence
        logic [1:0] response;
        logic [31:0] data;
        integer i;

        for (i = 0; i < 2; i = i + 1) begin
            m_awaddr[i]  = 32'b0;
            m_awvalid[i] = 1'b0;
            m_wdata[i]   = 32'b0;
            m_wstrb[i]   = 4'b0;
            m_wvalid[i]  = 1'b0;
            m_bready[i]  = 1'b0;
            m_araddr[i]  = 32'b0;
            m_arvalid[i] = 1'b0;
            m_rready[i]  = 1'b0;
            completed[i] = 0;
        end

        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        axi_write(0, 32'h0000_8000, 32'haabb_ccdd, 4'b1111, 0, 3, response);
        check_result(response == AXI_OKAY, "RAM full-word write response");
        axi_write(0, 32'h0000_8000, 32'h1122_3344, 4'b0101, 3, 0, response);
        check_result(response == AXI_OKAY, "RAM byte-strobe write response");
        axi_read(0, 32'h0000_8000, 0, data, response);
        check_result(response == AXI_OKAY && data == 32'haa22_cc44,
               "RAM readback honors WSTRB");
        check_result(px_rdata == 32'haa22_cc44,
                     "AXI byte address maps to the GPU word address");

        axi_write(0, 32'h0000_3ffc, 32'h1, 4'hf, 0, 0, response);
        check_result(response == AXI_SLVERR, "RAM address below window returns SLVERR");
        axi_read(0, 32'h0001_c000, 0, data, response);
        check_result(response == AXI_SLVERR, "RAM address above window returns SLVERR");

        axi_write(0, 32'h4000_0008, 32'h1234_5678, 4'hf, 0, 2, response);
        check_result(response == AXI_OKAY && thread_count == 32'h1234_5678,
               "THREADS write");
        axi_write(0, 32'h4000_0008, 32'haabb_ccdd, 4'b0010, 2, 0, response);
        check_result(response == AXI_OKAY && thread_count == 32'h1234_cc78,
               "MMIO WSTRB update");
        axi_write(0, 32'h4000_000c, 32'h0000_2000, 4'hf, 1, 0, response);
        axi_write(0, 32'h4000_0010, 32'h0000_6000, 4'hf, 0, 1, response);
        axi_write(0, 32'h4000_0014, 32'h0000_0200, 4'hf, 1, 1, response);
        check_result(src_addr == 32'h2000 && dst_addr == 32'h6000 && prog_base == 32'h200,
               "GPU address registers");

        gpu_busy = 1'b1;
        @(negedge clk);
        gpu_done = 1'b1;
        @(negedge clk);
        gpu_done = 1'b0;
        axi_read(0, 32'h4000_0004, 1, data, response);
        check_result(response == AXI_OKAY && data[1:0] == 2'b11,
               "STATUS exposes busy and sticky done");
        axi_read(0, 32'h4000_0004, 0, data, response);
        check_result(data[1], "done remains sticky across reads");

        axi_write(0, 32'h4000_0000, 32'h1, 4'hf, 2, 0, response);
        axi_read(0, 32'h4000_0004, 0, data, response);
        check_result(response == AXI_OKAY && !data[1], "CTRL.start clears sticky done");
        check_result(start_count == 1, "CTRL.start emits exactly one pulse");
        gpu_busy = 1'b0;

        axi_write(0, 32'h4000_0004, 32'h1, 4'hf, 0, 0, response);
        check_result(response == AXI_SLVERR, "STATUS write is illegal");
        axi_read(0, 32'h4000_0008, 0, data, response);
        check_result(response == AXI_SLVERR, "write-only MMIO read is illegal");
        axi_read(0, 32'h4000_0018, 0, data, response);
        check_result(response == AXI_SLVERR, "unknown MMIO offset returns SLVERR");
        axi_write(0, 32'h4000_000b, 32'hdead_beef, 4'hf, 0, 1, response);
        check_result(response == AXI_OKAY && thread_count == 32'hdead_beef,
                     "MMIO ignores address bits [1:0]");

        // Both masters continuously request distinct RAM locations. Completion
        // of every operation under randomized response stalls demonstrates that
        // the held-grant round-robin arbiter does not starve either master.
        completed[0] = 0;
        completed[1] = 0;
        fork
            begin
                logic [1:0] local_response;
                logic [31:0] local_data;
                integer j;
                for (j = 0; j < 16; j = j + 1) begin
                    axi_write(0, 32'h0000_9000 + j*4, 32'h1000_0000 + j,
                              4'hf, $urandom_range(0, 2), $urandom_range(0, 2), local_response);
                    check_result(local_response == AXI_OKAY, "master 0 randomized write");
                    axi_read(0, 32'h0000_9000 + j*4, $urandom_range(0, 2),
                             local_data, local_response);
                    check_result(local_response == AXI_OKAY && local_data == (32'h1000_0000 + j),
                           "master 0 randomized readback");
                end
            end
            begin
                logic [1:0] local_response;
                logic [31:0] local_data;
                integer j;
                for (j = 0; j < 16; j = j + 1) begin
                    axi_write(1, 32'h0000_a000 + j*4, 32'h2000_0000 + j,
                              4'hf, $urandom_range(0, 2), $urandom_range(0, 2), local_response);
                    check_result(local_response == AXI_OKAY, "master 1 randomized write");
                    axi_read(1, 32'h0000_a000 + j*4, $urandom_range(0, 2),
                             local_data, local_response);
                    check_result(local_response == AXI_OKAY && local_data == (32'h2000_0000 + j),
                           "master 1 randomized readback");
                end
            end
        join
        check_result(completed[0] == 32 && completed[1] == 32,
               "both masters complete all contended transactions");

        if (errors == 0)
            $display("PASS: tb_axi_lite completed with no errors");
        else
            $fatal(1, "tb_axi_lite failed with %0d errors", errors);
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "tb_axi_lite timeout");
    end
endmodule
