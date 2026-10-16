`timescale 1ns/1ps

module soc_top (
    input  logic        clk,
    input  logic        reset,
    output logic [3:0]  cpu_state,
    output logic        gpu_start,
    output logic        gpu_busy,
    output logic        gpu_done,
    output logic        gpu_mem_req,
    output logic        gpu_mem_we,
    output logic [31:0] gpu_mem_addr,
    output logic [31:0] gpu_mem_wdata
);
    logic cpu_mem_req, cpu_mem_we, cpu_mem_done;
    logic [31:0] cpu_mem_addr, cpu_mem_wdata, cpu_mem_rdata;

    logic [31:0] m0_awaddr, m0_wdata, m0_araddr, m0_rdata;
    logic [3:0]  m0_wstrb;
    logic [1:0]  m0_bresp, m0_rresp;
    logic m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    logic m0_bvalid, m0_bready, m0_arvalid, m0_arready, m0_rvalid, m0_rready;

    logic [31:0] s0_awaddr, s0_wdata, s0_araddr, s0_rdata;
    logic [3:0]  s0_wstrb;
    logic [1:0]  s0_bresp, s0_rresp;
    logic s0_awvalid, s0_awready, s0_wvalid, s0_wready;
    logic s0_bvalid, s0_bready, s0_arvalid, s0_arready, s0_rvalid, s0_rready;

    logic [31:0] s1_awaddr, s1_wdata, s1_araddr, s1_rdata;
    logic [3:0]  s1_wstrb;
    logic [1:0]  s1_bresp, s1_rresp;
    logic s1_awvalid, s1_awready, s1_wvalid, s1_wready;
    logic s1_bvalid, s1_bready, s1_arvalid, s1_arready, s1_rvalid, s1_rready;

    logic [14:0] host_addr;
    logic host_we;
    logic [31:0] host_wdata, host_rdata;
    logic [31:0] gpu_mem_rdata;
    logic gpu_mem_ready;

    logic [31:0] gpu_threads, gpu_src, gpu_dst, gpu_prog_base;
    logic [15:0] gpu_imem_addr, gpu_imem_rdata;

    riscv_mc cpu (
        .clk(clk), .reset(reset),
        .mem_req(cpu_mem_req), .mem_we(cpu_mem_we),
        .mem_addr(cpu_mem_addr), .mem_wdata(cpu_mem_wdata),
        .mem_rdata(cpu_mem_rdata), .mem_done(cpu_mem_done), .state(cpu_state)
    );

    cpu_axi_master cpu_master (
        .clk(clk), .reset(reset),
        .req(cpu_mem_req), .we(cpu_mem_we), .addr(cpu_mem_addr),
        .wdata(cpu_mem_wdata), .rdata(cpu_mem_rdata), .done(cpu_mem_done),
        .m_axi_awaddr(m0_awaddr), .m_axi_awvalid(m0_awvalid), .m_axi_awready(m0_awready),
        .m_axi_wdata(m0_wdata), .m_axi_wstrb(m0_wstrb),
        .m_axi_wvalid(m0_wvalid), .m_axi_wready(m0_wready),
        .m_axi_bresp(m0_bresp), .m_axi_bvalid(m0_bvalid), .m_axi_bready(m0_bready),
        .m_axi_araddr(m0_araddr), .m_axi_arvalid(m0_arvalid), .m_axi_arready(m0_arready),
        .m_axi_rdata(m0_rdata), .m_axi_rresp(m0_rresp),
        .m_axi_rvalid(m0_rvalid), .m_axi_rready(m0_rready)
    );

    axi_lite_interconnect u_interconnect (
        .clk(clk), .reset(reset),
        .m0_axi_awaddr(m0_awaddr), .m0_axi_awvalid(m0_awvalid), .m0_axi_awready(m0_awready),
        .m0_axi_wdata(m0_wdata), .m0_axi_wstrb(m0_wstrb), .m0_axi_wvalid(m0_wvalid), .m0_axi_wready(m0_wready),
        .m0_axi_bresp(m0_bresp), .m0_axi_bvalid(m0_bvalid), .m0_axi_bready(m0_bready),
        .m0_axi_araddr(m0_araddr), .m0_axi_arvalid(m0_arvalid), .m0_axi_arready(m0_arready),
        .m0_axi_rdata(m0_rdata), .m0_axi_rresp(m0_rresp), .m0_axi_rvalid(m0_rvalid), .m0_axi_rready(m0_rready),
        .m1_axi_awaddr(32'b0), .m1_axi_awvalid(1'b0), .m1_axi_awready(),
        .m1_axi_wdata(32'b0), .m1_axi_wstrb(4'b0), .m1_axi_wvalid(1'b0), .m1_axi_wready(),
        .m1_axi_bresp(), .m1_axi_bvalid(), .m1_axi_bready(1'b0),
        .m1_axi_araddr(32'b0), .m1_axi_arvalid(1'b0), .m1_axi_arready(),
        .m1_axi_rdata(), .m1_axi_rresp(), .m1_axi_rvalid(), .m1_axi_rready(1'b0),
        .s0_axi_awaddr(s0_awaddr), .s0_axi_awvalid(s0_awvalid), .s0_axi_awready(s0_awready),
        .s0_axi_wdata(s0_wdata), .s0_axi_wstrb(s0_wstrb), .s0_axi_wvalid(s0_wvalid), .s0_axi_wready(s0_wready),
        .s0_axi_bresp(s0_bresp), .s0_axi_bvalid(s0_bvalid), .s0_axi_bready(s0_bready),
        .s0_axi_araddr(s0_araddr), .s0_axi_arvalid(s0_arvalid), .s0_axi_arready(s0_arready),
        .s0_axi_rdata(s0_rdata), .s0_axi_rresp(s0_rresp), .s0_axi_rvalid(s0_rvalid), .s0_axi_rready(s0_rready),
        .s1_axi_awaddr(s1_awaddr), .s1_axi_awvalid(s1_awvalid), .s1_axi_awready(s1_awready),
        .s1_axi_wdata(s1_wdata), .s1_axi_wstrb(s1_wstrb), .s1_axi_wvalid(s1_wvalid), .s1_axi_wready(s1_wready),
        .s1_axi_bresp(s1_bresp), .s1_axi_bvalid(s1_bvalid), .s1_axi_bready(s1_bready),
        .s1_axi_araddr(s1_araddr), .s1_axi_arvalid(s1_arvalid), .s1_axi_arready(s1_arready),
        .s1_axi_rdata(s1_rdata), .s1_axi_rresp(s1_rresp), .s1_axi_rvalid(s1_rvalid), .s1_axi_rready(s1_rready)
    );

    axi_lite_ram ram_slave (
        .clk(clk), .reset(reset),
        .s_axi_awaddr(s0_awaddr), .s_axi_awvalid(s0_awvalid), .s_axi_awready(s0_awready),
        .s_axi_wdata(s0_wdata), .s_axi_wstrb(s0_wstrb), .s_axi_wvalid(s0_wvalid), .s_axi_wready(s0_wready),
        .s_axi_bresp(s0_bresp), .s_axi_bvalid(s0_bvalid), .s_axi_bready(s0_bready),
        .s_axi_araddr(s0_araddr), .s_axi_arvalid(s0_arvalid), .s_axi_arready(s0_arready),
        .s_axi_rdata(s0_rdata), .s_axi_rresp(s0_rresp), .s_axi_rvalid(s0_rvalid), .s_axi_rready(s0_rready),
        .host_addr(host_addr), .host_we(host_we), .host_wdata(host_wdata), .host_rdata(host_rdata)
    );

    gpu_mmio mmio (
        .clk(clk), .reset(reset),
        .s_axi_awaddr(s1_awaddr), .s_axi_awvalid(s1_awvalid), .s_axi_awready(s1_awready),
        .s_axi_wdata(s1_wdata), .s_axi_wstrb(s1_wstrb), .s_axi_wvalid(s1_wvalid), .s_axi_wready(s1_wready),
        .s_axi_bresp(s1_bresp), .s_axi_bvalid(s1_bvalid), .s_axi_bready(s1_bready),
        .s_axi_araddr(s1_araddr), .s_axi_arvalid(s1_arvalid), .s_axi_arready(s1_arready),
        .s_axi_rdata(s1_rdata), .s_axi_rresp(s1_rresp), .s_axi_rvalid(s1_rvalid), .s_axi_rready(s1_rready),
        .gpu_busy(gpu_busy), .gpu_done(gpu_done), .start(gpu_start),
        .thread_count(gpu_threads), .src_addr(gpu_src), .dst_addr(gpu_dst),
        .prog_base(gpu_prog_base)
    );

    shared_ram ram (
        .clk(clk),
        .px_addr(gpu_mem_addr[14:0]),
        .px_we(gpu_mem_req && gpu_mem_we && gpu_mem_ready),
        .px_wdata(gpu_mem_wdata), .px_rdata(gpu_mem_rdata),
        .host_addr(host_addr), .host_we(host_we),
        .host_wdata(host_wdata), .host_rdata(host_rdata)
    );

    program_memory program_mem (
        .prog_base(gpu_prog_base), .imem_addr(gpu_imem_addr), .imem_rdata(gpu_imem_rdata)
    );

    assign gpu_mem_ready = 1'b1;

    simt_gpu gpu (
        .clk(clk), .reset(reset), .start(gpu_start),
        .thread_count(gpu_threads), .src_addr(gpu_src), .dst_addr(gpu_dst),
        .busy(gpu_busy), .done(gpu_done),
        .imem_addr(gpu_imem_addr), .imem_rdata(gpu_imem_rdata),
        .mem_req(gpu_mem_req), .mem_we(gpu_mem_we),
        .mem_addr(gpu_mem_addr), .mem_wdata(gpu_mem_wdata),
        .mem_rdata(gpu_mem_rdata), .mem_ready(gpu_mem_ready)
    );
endmodule
