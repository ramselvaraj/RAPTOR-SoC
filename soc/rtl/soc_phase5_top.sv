`timescale 1ns/1ps
module soc_phase5_top #(
    parameter bit CACHE_ENABLE=1,
    parameter int FIFO_DEPTH=4,
    parameter bit RANDOM_BACKPRESSURE=0
)(
    input logic cpu_clk, gpu_clk, arst, boot_hold,
    input logic boot_valid,
    output logic boot_ready, boot_done, boot_error,
    input logic [1:0] boot_sel,
    input logic [14:0] boot_addr,
    input logic [31:0] boot_wdata,
    output logic [31:0] boot_rdata,
    input logic memory_service_enable,
    output logic fault, gpu_start, gpu_busy, gpu_done,
    output logic gpu_commit, gpu_commit_we,
    output logic [63:0] cpu_cycles, gpu_cycles, retired, icache_hits, icache_misses,
                         dcache_hits, dcache_misses, dcache_writebacks,
    output logic retire_valid,
    output logic [31:0] retire_pc, retire_instruction, retire_data,
    output logic [4:0] retire_rd,
    output logic retire_write
`ifdef RAPTOR_EXTERNAL_MEMORIES
    ,output logic [31:0] cpu_imem_addr,
    input logic [31:0] cpu_imem_rdata,
    output logic cpu_imem_we,
    output logic [9:0] cpu_imem_waddr,
    output logic [31:0] cpu_imem_wdata,
    output logic [9:0] gpu_program_addr,
    input logic [15:0] gpu_program_rdata,
    output logic gpu_program_we,
    output logic [9:0] gpu_program_waddr,
    output logic [15:0] gpu_program_wdata,
    output logic [14:0] ram_px_addr, ram_host_addr,
    output logic ram_px_we, ram_host_we,
    output logic [31:0] ram_px_wdata, ram_host_wdata,
    input logic [31:0] ram_px_rdata, ram_host_rdata
`endif
);
    logic cpu_reset, gpu_reset, cpu_exec_reset, gpu_exec_reset;
    (* ASYNC_REG="TRUE" *) logic [1:0] gpu_up_cpu, cpu_up_gpu;
    logic cpu_online, gpu_online, core_fault, bus_fault;
    logic iv, ir, irv, irr, dv, dr, drv, drr;
    logic [31:0] ia, iw, idata, da, dw, dread;
    logic [3:0] istrb, ds;
    reset_release cpu_rst(.clk(cpu_clk), .arst, .reset(cpu_reset));
    reset_release gpu_rst(.clk(gpu_clk), .arst, .reset(gpu_reset));
    reset_release cpu_hold(.clk(cpu_clk), .arst(cpu_reset || boot_hold || fault), .reset(cpu_exec_reset));
    reset_release gpu_hold(.clk(gpu_clk), .arst(gpu_reset || boot_hold), .reset(gpu_exec_reset));
    always_ff @(posedge cpu_clk or posedge cpu_reset)
        if(cpu_reset) gpu_up_cpu<=0; else gpu_up_cpu<={gpu_up_cpu[0], !gpu_reset};
    always_ff @(posedge gpu_clk or posedge gpu_reset)
        if(gpu_reset) cpu_up_gpu<=0; else cpu_up_gpu<={cpu_up_gpu[0], !cpu_reset};
    assign cpu_online = !cpu_reset && gpu_up_cpu[1];
    assign gpu_online = !gpu_reset && cpu_up_gpu[1];
    // Fault is sticky at SoC level; resetting execution must not clear it.
    always_ff @(posedge cpu_clk or posedge cpu_reset)
        if(cpu_reset) fault<=0;
        else if(core_fault || bus_fault || (iv && ir && (ia>=4096 || istrb!=0))) fault<=1;

    pipeline_cache #(.REGION_BYPASS(1), .BYPASS_ICACHE(!CACHE_ENABLE), .BYPASS_DCACHE(!CACHE_ENABLE)) cpu(
        .clk(cpu_clk), .reset(cpu_exec_reset),
        .imem_req_valid(iv), .imem_req_ready(ir), .imem_req_addr(ia), .imem_req_data(iw), .imem_req_strb(istrb),
        .imem_resp_valid(irv), .imem_resp_ready(irr), .imem_resp_data(idata),
        .dmem_req_valid(dv), .dmem_req_ready(dr), .dmem_req_addr(da), .dmem_req_data(dw), .dmem_req_strb(ds),
        .dmem_resp_valid(drv), .dmem_resp_ready(drr), .dmem_resp_data(dread),
        .retire_valid, .retire_pc, .retire_instruction, .retire_write, .retire_rd, .retire_data,
        .cycles(cpu_cycles), .retired, .load_stalls(), .memory_stalls(), .fetch_stalls(),
        .redirects(), .branch_misses(), .icache_hits, .icache_misses,
        .dcache_hits, .dcache_misses, .dcache_writebacks, .fault(core_fault));
    logic [31:0] instruction;
    assign ir = !cpu_exec_reset && (!irv || irr);
    always_ff @(posedge cpu_clk or posedge cpu_exec_reset)
        if(cpu_exec_reset) begin irv<=0; idata<=0; end
        else if(ir) begin irv<=iv; if(iv) idata<=instruction; end

    logic [31:0] m0_awaddr, m0_wdata, m0_araddr, m0_rdata;
    logic [3:0] m0_wstrb;
    logic [1:0] m0_bresp, m0_rresp;
    logic m0_awvalid,m0_awready,m0_wvalid,m0_wready,m0_bvalid,m0_bready;
    logic m0_arvalid,m0_arready,m0_rvalid,m0_rready;
    logic [31:0] s0_awaddr,s0_wdata,s0_araddr,s0_rdata,s1_awaddr,s1_wdata,s1_araddr,s1_rdata;
    logic [3:0] s0_wstrb,s1_wstrb;
    logic [1:0] s0_bresp,s0_rresp,s1_bresp,s1_rresp;
    logic s0_awvalid,s0_awready,s0_wvalid,s0_wready,s0_bvalid,s0_bready,s0_arvalid,s0_arready,s0_rvalid,s0_rready;
    logic s1_awvalid,s1_awready,s1_wvalid,s1_wready,s1_bvalid,s1_bready,s1_arvalid,s1_arready,s1_rvalid,s1_rready;
    cpu_request_axi cpu_master(
        .clk(cpu_clk), .reset(cpu_reset), .req_valid(dv && !fault), .req_ready(dr),
        .req_addr(da), .req_data(dw), .req_strb(ds), .resp_valid(drv), .resp_ready(drr), .resp_data(dread), .fault(bus_fault),
        .m_axi_awaddr(m0_awaddr), .m_axi_awvalid(m0_awvalid), .m_axi_awready(m0_awready),
        .m_axi_wdata(m0_wdata), .m_axi_wstrb(m0_wstrb), .m_axi_wvalid(m0_wvalid), .m_axi_wready(m0_wready),
        .m_axi_bresp(m0_bresp), .m_axi_bvalid(m0_bvalid), .m_axi_bready(m0_bready),
        .m_axi_araddr(m0_araddr), .m_axi_arvalid(m0_arvalid), .m_axi_arready(m0_arready),
        .m_axi_rdata(m0_rdata), .m_axi_rresp(m0_rresp), .m_axi_rvalid(m0_rvalid), .m_axi_rready(m0_rready));
    axi_lite_interconnect u_interconnect(
        .clk(cpu_clk), .reset(cpu_reset),
        .m0_axi_awaddr(m0_awaddr), .m0_axi_awvalid(m0_awvalid), .m0_axi_awready(m0_awready),
        .m0_axi_wdata(m0_wdata), .m0_axi_wstrb(m0_wstrb), .m0_axi_wvalid(m0_wvalid), .m0_axi_wready(m0_wready),
        .m0_axi_bresp(m0_bresp), .m0_axi_bvalid(m0_bvalid), .m0_axi_bready(m0_bready),
        .m0_axi_araddr(m0_araddr), .m0_axi_arvalid(m0_arvalid), .m0_axi_arready(m0_arready),
        .m0_axi_rdata(m0_rdata), .m0_axi_rresp(m0_rresp), .m0_axi_rvalid(m0_rvalid), .m0_axi_rready(m0_rready),
        .m1_axi_awaddr(32'b0), .m1_axi_awvalid(1'b0), .m1_axi_awready(), .m1_axi_wdata(32'b0), .m1_axi_wstrb(4'b0),
        .m1_axi_wvalid(1'b0), .m1_axi_wready(), .m1_axi_bresp(), .m1_axi_bvalid(), .m1_axi_bready(1'b0),
        .m1_axi_araddr(32'b0), .m1_axi_arvalid(1'b0), .m1_axi_arready(), .m1_axi_rdata(), .m1_axi_rresp(),
        .m1_axi_rvalid(), .m1_axi_rready(1'b0),
        .s0_axi_awaddr(s0_awaddr), .s0_axi_awvalid(s0_awvalid), .s0_axi_awready(s0_awready),
        .s0_axi_wdata(s0_wdata), .s0_axi_wstrb(s0_wstrb), .s0_axi_wvalid(s0_wvalid), .s0_axi_wready(s0_wready),
        .s0_axi_bresp(s0_bresp), .s0_axi_bvalid(s0_bvalid), .s0_axi_bready(s0_bready),
        .s0_axi_araddr(s0_araddr), .s0_axi_arvalid(s0_arvalid), .s0_axi_arready(s0_arready),
        .s0_axi_rdata(s0_rdata), .s0_axi_rresp(s0_rresp), .s0_axi_rvalid(s0_rvalid), .s0_axi_rready(s0_rready),
        .s1_axi_awaddr(s1_awaddr), .s1_axi_awvalid(s1_awvalid), .s1_axi_awready(s1_awready),
        .s1_axi_wdata(s1_wdata), .s1_axi_wstrb(s1_wstrb), .s1_axi_wvalid(s1_wvalid), .s1_axi_wready(s1_wready),
        .s1_axi_bresp(s1_bresp), .s1_axi_bvalid(s1_bvalid), .s1_axi_bready(s1_bready),
        .s1_axi_araddr(s1_araddr), .s1_axi_arvalid(s1_arvalid), .s1_axi_arready(s1_arready),
        .s1_axi_rdata(s1_rdata), .s1_axi_rresp(s1_rresp), .s1_axi_rvalid(s1_rvalid), .s1_axi_rready(s1_rready));
    logic [14:0] host_addr, pixel_addr;
    logic host_we, pixel_we;
    logic [31:0] host_wdata,host_rdata,pixel_wdata,pixel_rdata;
    axi_lite_ram #(.RANDOM_BACKPRESSURE(RANDOM_BACKPRESSURE)) ram_slave(
        .clk(cpu_clk), .reset(cpu_reset),
        .s_axi_awaddr(s0_awaddr), .s_axi_awvalid(s0_awvalid), .s_axi_awready(s0_awready),
        .s_axi_wdata(s0_wdata), .s_axi_wstrb(s0_wstrb), .s_axi_wvalid(s0_wvalid), .s_axi_wready(s0_wready),
        .s_axi_bresp(s0_bresp), .s_axi_bvalid(s0_bvalid), .s_axi_bready(s0_bready),
        .s_axi_araddr(s0_araddr), .s_axi_arvalid(s0_arvalid), .s_axi_arready(s0_arready),
        .s_axi_rdata(s0_rdata), .s_axi_rresp(s0_rresp), .s_axi_rvalid(s0_rvalid), .s_axi_rready(s0_rready),
        .host_addr, .host_we, .host_wdata, .host_rdata);

    logic [31:0] threads, src, dst, prog_base;
    logic command_ready, command_valid, command_take;
    logic [127:0] command;
    logic reserved_busy;
    assign gpu_busy=reserved_busy || gpu_start;
    gpu_mmio #(.RANDOM_BACKPRESSURE(RANDOM_BACKPRESSURE), .STRICT_START(1)) mmio(
        .clk(cpu_clk), .reset(cpu_reset), .command_ready(command_ready && cpu_online),
        .s_axi_awaddr(s1_awaddr), .s_axi_awvalid(s1_awvalid), .s_axi_awready(s1_awready),
        .s_axi_wdata(s1_wdata), .s_axi_wstrb(s1_wstrb), .s_axi_wvalid(s1_wvalid), .s_axi_wready(s1_wready),
        .s_axi_bresp(s1_bresp), .s_axi_bvalid(s1_bvalid), .s_axi_bready(s1_bready),
        .s_axi_araddr(s1_araddr), .s_axi_arvalid(s1_arvalid), .s_axi_arready(s1_arready),
        .s_axi_rdata(s1_rdata), .s_axi_rresp(s1_rresp), .s_axi_rvalid(s1_rvalid), .s_axi_rready(s1_rready),
        .gpu_busy, .gpu_done, .start(gpu_start), .thread_count(threads), .src_addr(src), .dst_addr(dst), .prog_base);
    async_fifo #(.WIDTH(128), .DEPTH(FIFO_DEPTH)) commands(
        .wclk(cpu_clk), .wrst(cpu_reset), .wvalid(gpu_start), .wready(command_ready), .wdata({threads,src,dst,prog_base}),
        .rclk(gpu_clk), .rrst(gpu_reset), .rvalid(command_valid), .rready(command_take), .rdata(command));
    logic launch_gpu, busy_gpu, done_gpu, event_pending, event_ready, event_valid;
    logic [31:0] active_threads,active_src,active_dst,active_base;
    logic unused_event;
    assign command_take=gpu_online && !gpu_exec_reset && !busy_gpu && !launch_gpu && !event_pending;
    async_fifo #(.WIDTH(1), .DEPTH(FIFO_DEPTH)) completions(
        .wclk(gpu_clk), .wrst(gpu_reset), .wvalid(event_pending), .wready(event_ready), .wdata(1'b1),
        .rclk(cpu_clk), .rrst(cpu_reset), .rvalid(event_valid), .rready(1'b1), .rdata(unused_event));
    assign gpu_done=event_valid;
    always_ff @(posedge cpu_clk or posedge cpu_reset)
        if(cpu_reset) reserved_busy<=0;
        else begin if(gpu_start) reserved_busy<=1; if(gpu_done) reserved_busy<=0; end
    always_ff @(posedge gpu_clk or posedge gpu_reset) begin
        if(gpu_reset) begin
            launch_gpu<=0; active_threads<=0; active_src<=0; active_dst<=0; active_base<=0; event_pending<=0; gpu_cycles<=0;
        end else begin
            launch_gpu<=0;
            if(!gpu_exec_reset) gpu_cycles<=gpu_cycles+1'b1;
            if(command_valid && command_take) begin
                {active_threads,active_src,active_dst,active_base}<=command;
                launch_gpu<=1;
            end
            if(event_pending && event_ready) event_pending<=0;
            if(done_gpu) event_pending<=1;
        end
    end
    logic mem_req,mem_we,mem_ready;
    logic [31:0] mem_addr,mem_wdata,mem_rdata;
    logic [15:0] gpu_pc,gpu_instruction;
    simt_gpu #(.LOCK_MEMORY_OWNER(1)) gpu(
        .clk(gpu_clk), .reset(gpu_exec_reset), .start(launch_gpu),
        .thread_count(active_threads), .src_addr(active_src), .dst_addr(active_dst), .busy(busy_gpu), .done(done_gpu),
        .imem_addr(gpu_pc), .imem_rdata(gpu_instruction), .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_rdata, .mem_ready);
    gpu_memory_cdc #(.DEPTH(FIFO_DEPTH)) memory_bridge(
        .gpu_clk, .gpu_reset, .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_ready, .mem_rdata,
        .cpu_clk, .cpu_reset, .service_enable(memory_service_enable && cpu_online && !boot_hold),
        .ram_addr(pixel_addr), .ram_we(pixel_we), .ram_wdata(pixel_wdata), .ram_rdata(pixel_rdata),
        .commit_valid(gpu_commit), .commit_we(gpu_commit_we));

    // Boot programming transport stays active while the execution cores reset.
    logic boot_pending, prog_req_ready, prog_ack, prog_valid, prog_ready, prog_reply, prog_reply_ready;
    logic [25:0] prog_request;
    logic unused_ack;
    logic boot_accept, cpu_write, ram_write;
    assign boot_ready=cpu_online && boot_hold && !boot_pending && (boot_sel != 1 || prog_req_ready);
    assign boot_accept=boot_valid && boot_ready;
    assign cpu_write=boot_accept && boot_sel==0 && boot_addr<1024;
    assign ram_write=boot_accept && boot_sel==2;
    assign boot_rdata=boot_hold && boot_sel==2 ? host_rdata : 0;
    cdc_request_channel #(.REQUEST_WIDTH(26), .RESPONSE_WIDTH(1), .DEPTH(FIFO_DEPTH)) program_loader(
        .sclk(cpu_clk), .srst(cpu_reset), .req_valid(boot_valid && boot_ready && boot_sel==1 && boot_addr<1024),
        .req_ready(prog_req_ready), .req_data({boot_addr[9:0],boot_wdata[15:0]}),
        .resp_valid(prog_ack), .resp_ready(1'b1), .resp_data(unused_ack),
        .dclk(gpu_clk), .drst(gpu_reset), .dreq_valid(prog_valid), .dreq_ready(prog_ready), .dreq_data(prog_request),
        .dresp_valid(prog_reply), .dresp_ready(prog_reply_ready), .dresp_data(1'b1));
    assign prog_ready=gpu_online && gpu_exec_reset && !prog_reply;
    always_ff @(posedge gpu_clk or posedge gpu_reset)
        if(gpu_reset) prog_reply<=0;
        else begin
            if(prog_reply && prog_reply_ready) prog_reply<=0;
            if(prog_valid && prog_ready) prog_reply<=1;
        end
    always_ff @(posedge cpu_clk or posedge cpu_reset)
        if(cpu_reset) begin boot_pending<=0; boot_done<=0; boot_error<=0; end
        else begin
            boot_done<=0; boot_error<=0;
            if(boot_accept) begin
                if(boot_sel==3 || (boot_sel<2 && boot_addr>=1024)) begin boot_error<=1; boot_done<=1; end
                else if(boot_sel==1) boot_pending<=1;
                else boot_done<=1;
            end
            if(prog_ack) begin boot_pending<=0; boot_done<=1; end
        end
`ifdef RAPTOR_EXTERNAL_MEMORIES
    assign cpu_imem_addr=ia;
    assign instruction=cpu_imem_rdata;
    assign cpu_imem_we=cpu_write;
    assign cpu_imem_waddr=boot_addr[9:0];
    assign cpu_imem_wdata=boot_wdata;
    assign gpu_program_addr=active_base[9:0]+gpu_pc[9:0];
    assign gpu_instruction=gpu_program_rdata;
    assign gpu_program_we=prog_valid && prog_ready;
    assign gpu_program_waddr=prog_request[25:16];
    assign gpu_program_wdata=prog_request[15:0];
    assign ram_host_addr=boot_hold ? boot_addr : host_addr;
    assign ram_host_we=boot_hold ? ram_write : host_we;
    assign ram_host_wdata=boot_hold ? boot_wdata : host_wdata;
    assign host_rdata=ram_host_rdata;
    assign ram_px_addr=pixel_addr;
    assign ram_px_we=pixel_we;
    assign ram_px_wdata=pixel_wdata;
    assign pixel_rdata=ram_px_rdata;
`else
    mc_instruction_memory cpu_program(
        .clk(cpu_clk), .write_enable(cpu_write), .write_addr(boot_addr[9:0]), .write_data(boot_wdata), .address(ia), .instruction);
    program_memory gpu_program(
        .clk(gpu_clk), .write_enable(prog_valid && prog_ready), .write_addr(prog_request[25:16]), .write_data(prog_request[15:0]),
        .prog_base(active_base), .imem_addr(gpu_pc), .imem_rdata(gpu_instruction));
    shared_ram ram(
        .clk(cpu_clk), .px_addr(pixel_addr), .px_we(pixel_we), .px_wdata(pixel_wdata), .px_rdata(pixel_rdata),
        .host_addr(boot_hold ? boot_addr : host_addr), .host_we(boot_hold ? ram_write : host_we),
        .host_wdata(boot_hold ? boot_wdata : host_wdata), .host_rdata);
`endif
`ifndef SYNTHESIS
    assert property (@(posedge gpu_clk) disable iff(gpu_reset)
        busy_gpu && !launch_gpu |=> $stable({active_threads,active_src,active_dst,active_base}));
    assert property (@(posedge gpu_clk) disable iff(gpu_reset)
        done_gpu |-> !memory_bridge.outstanding);
    assert property (@(posedge cpu_clk) disable iff(cpu_reset)
        !boot_hold |-> !boot_pending);
    always @(posedge cpu_clk) if(!cpu_exec_reset && iv && ir)
        assert(ia < 4096) else $fatal(1,"instruction fetch outside boot allocation");
`endif
endmodule
