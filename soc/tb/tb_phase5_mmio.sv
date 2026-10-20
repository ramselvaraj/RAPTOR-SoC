`timescale 1ns/1ps
module tb_phase5_mmio;
    logic clk=0,reset=1;
    always #5 clk=~clk;
    logic [31:0] s_axi_awaddr=0,s_axi_wdata=0,s_axi_araddr=0,s_axi_rdata;
    logic [3:0] s_axi_wstrb=15;
    logic [1:0] s_axi_bresp,s_axi_rresp;
    logic s_axi_awvalid=0,s_axi_awready,s_axi_wvalid=0,s_axi_wready,s_axi_bvalid,s_axi_bready=0;
    logic s_axi_arvalid=0,s_axi_arready,s_axi_rvalid,s_axi_rready=0;
    logic gpu_busy=0,gpu_done=0,command_ready=0,start;
    logic [31:0] thread_count,src_addr,dst_addr,prog_base;
    int starts=0;
    gpu_mmio #(.STRICT_START(1)) dut(.*);
    always @(posedge clk) if(!reset && start) starts++;
    task automatic begin_write(input int offset,input logic [31:0] value);
        @(negedge clk);s_axi_awaddr=32'h40000000+32'(offset);s_axi_awvalid=1;
        do @(posedge clk);while(!s_axi_awready);
        @(negedge clk);s_axi_awvalid=0;
        repeat(3) @(negedge clk);
        s_axi_wdata=value;s_axi_wvalid=1;
        do @(posedge clk);while(!s_axi_wready);
        @(negedge clk);s_axi_wvalid=0;
    endtask
    task automatic end_write(input logic [1:0] expected_response);
        wait(s_axi_bvalid);
        @(negedge clk);assert(s_axi_bresp==expected_response);
        s_axi_bready=1;
        @(negedge clk);s_axi_bready=0;
    endtask
    task automatic read_status(output logic [31:0] value);
        @(negedge clk);s_axi_araddr=32'h40000004;s_axi_arvalid=1;
        do @(posedge clk);while(!s_axi_arready);
        @(negedge clk);s_axi_arvalid=0;
        wait(s_axi_rvalid);value=s_axi_rdata;
        @(negedge clk);s_axi_rready=1;
        @(negedge clk);s_axi_rready=0;
    endtask
    logic [31:0] result;
    initial begin
        repeat(3) @(negedge clk);reset=0;
        begin_write(8,17);end_write(0);
        begin_write(12,'h2000);end_write(0);
        begin_write(0,1);
        repeat(8) begin @(negedge clk);assert(!start && !s_axi_bvalid);end
        command_ready=1;end_write(0);
        @(negedge clk);gpu_busy=1;
        assert(starts==1 && thread_count==17 && src_addr=='h2000);
        begin_write(8,99);end_write(0);assert(thread_count==99);
        begin_write(0,1);end_write(2);assert(starts==1);
        gpu_done=1;gpu_busy=0;@(negedge clk);gpu_done=0;
        read_status(result);assert(result==2);
        read_status(result);assert(result==2);
        begin_write(0,1);end_write(0);
        @(negedge clk);assert(starts==2);
        read_status(result);assert(result==0);
        $display("PHASE5 MMIO PASS command backpressure, busy rejection, shadow config, sticky done");
        $finish;
    end
    initial begin #1000000;$fatal(1,"MMIO timeout");end
endmodule
