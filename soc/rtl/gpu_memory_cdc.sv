`timescale 1ns/1ps
// GPU owns its request until a response returns. RAM service is CPU-clocked.
module gpu_memory_cdc #(parameter int DEPTH=4)(
    input logic gpu_clk, gpu_reset, mem_req, mem_we,
    input logic [31:0] mem_addr, mem_wdata,
    output logic mem_ready,
    output logic [31:0] mem_rdata,
    input logic cpu_clk, cpu_reset, service_enable,
    output logic [14:0] ram_addr,
    output logic ram_we,
    output logic [31:0] ram_wdata,
    input logic [31:0] ram_rdata,
    output logic commit_valid, commit_we
);
    logic outstanding, qready, qvalid, qtake, rvalid, rready, reply;
    logic [64:0] request;
    logic [31:0] response;
    assign mem_ready = outstanding && rvalid;
    assign ram_addr = request[46:32];
    assign ram_wdata = request[31:0];
    assign qtake = !reply && service_enable;
    assign ram_we = qvalid && qtake && request[64];
    assign commit_valid = qvalid && qtake;
    assign commit_we = request[64];
    cdc_request_channel #(.REQUEST_WIDTH(65), .DEPTH(DEPTH)) channel(
        .sclk(gpu_clk), .srst(gpu_reset), .req_valid(mem_req && !outstanding),
        .req_ready(qready), .req_data({mem_we, mem_addr, mem_wdata}),
        .resp_valid(rvalid), .resp_ready(outstanding && mem_req), .resp_data(mem_rdata),
        .dclk(cpu_clk), .drst(cpu_reset), .dreq_valid(qvalid), .dreq_ready(qtake), .dreq_data(request),
        .dresp_valid(reply), .dresp_ready(rready), .dresp_data(response));
    always_ff @(posedge gpu_clk or posedge gpu_reset)
        if(gpu_reset) outstanding<=0;
        else begin
            if(mem_req && !outstanding && qready) outstanding<=1;
            if(mem_req && mem_ready) outstanding<=0;
        end
    always_ff @(posedge cpu_clk or posedge cpu_reset)
        if(cpu_reset) begin reply<=0; response<=0; end
        else begin
            if(reply && rready) reply<=0;
            if(qvalid && qtake) begin reply<=1; response<=request[64] ? 0 : ram_rdata; end
        end
endmodule
