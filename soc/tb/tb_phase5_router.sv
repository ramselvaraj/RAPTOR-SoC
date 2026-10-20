`timescale 1ns/1ps
module tb_phase5_router;
    logic clk=0,reset=1;
    always #5 clk=~clk;
    logic req_valid=0,req_ready,resp_valid,resp_ready=0,mem_req_valid,mem_req_ready,mem_resp_valid=0,mem_resp_ready;
    logic [31:0] req_addr=0,req_data=0,resp_data,mem_req_addr,mem_req_data,mem_resp_data=0;
    logic [3:0] req_strb=0,mem_req_strb;
    logic [63:0] hits,misses,writebacks;
    cache_data_router dut(.*);
    logic [31:0] memory[32768];
    int ticks=0,mmio_reads=0,mmio_writes=0,shared_ops=0;
    assign mem_req_ready=!reset && !mem_resp_valid && ticks%3!=0;
    always @(posedge clk) begin
        if(reset) begin ticks<=0;mem_resp_valid<=0;end
        else begin
            ticks<=ticks+1;
            if(mem_resp_valid && mem_resp_ready) mem_resp_valid<=0;
            if(mem_req_valid && mem_req_ready) begin
                mem_resp_valid<=1;
                if(mem_req_addr[31:28]==4'h4) begin
                    if(mem_req_strb!=0) begin mmio_writes++;mem_resp_data<=0;end
                    else begin mmio_reads++;mem_resp_data<=32'(mmio_reads);end
                    assert(mem_req_addr==32'h40000004) else $fatal(1,"speculative MMIO refill");
                end else begin
                    if(mem_req_addr>=32'h8000) shared_ops++;
                    mem_resp_data<=memory[mem_req_addr[16:2]];
                    for(int b=0;b<4;b++) if(mem_req_strb[b]) memory[mem_req_addr[16:2]][b*8+:8]<=mem_req_data[b*8+:8];
                end
            end
        end
    end
    task automatic access(input logic [31:0] addr,data,input logic [3:0] strb,output logic [31:0] value);
        @(negedge clk);req_valid=1;req_addr=addr;req_data=data;req_strb=strb;
        do @(posedge clk); while(!req_ready);
        @(negedge clk);req_valid=0;
        wait(resp_valid);
        value=resp_data;
        repeat(4) begin @(negedge clk);assert(resp_valid && resp_data==value && !req_ready);end
        resp_ready=1;
        @(negedge clk);resp_ready=0;
    endtask
    logic [31:0] result;
    initial begin
        for(int i=0;i<32768;i++) memory[i]=0;
        repeat(3) @(negedge clk);reset=0;
        access('h4000,'h12345678,15,result);
        access('h4000,0,0,result);assert(result=='h12345678);
        access('h4000,'h0000ab00,2,result);
        access('h4000,0,0,result);assert(result=='h1234ab78);
        for(int i=1;i<=4;i++) access(32'h4000+32'(i*64),32'(i),15,result);
        assert(memory[4096]=='h1234ab78 && writebacks>0);
        access('h8000,'h11223344,15,result);
        access('h8000,0,0,result);assert(result=='h11223344);
        @(negedge clk);memory[8192]='hdeadbeef;
        access('h8000,0,0,result);assert(result=='hdeadbeef && shared_ops==3);
        access('h40000004,0,0,result);assert(result==1);
        access('h40000004,0,0,result);assert(result==2 && mmio_reads==2);
        access('h40000004,'h5555,15,result);assert(mmio_writes==1);
        access('h4ffc,'haabbccdd,15,result);
        access('h4ffc,0,0,result);assert(result=='haabbccdd);
        access('h5000,'h13579bdf,15,result);
        access('h5000,0,0,result);assert(result=='h13579bdf);
        @(negedge clk);memory[5120]='h2468ace0;
        access('h5000,0,0,result);assert(result=='h2468ace0);
        assert(hits>0 && misses>0);
        $display("PHASE5 ROUTER PASS hits=%0d misses=%0d writebacks=%0d",hits,misses,writebacks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"router timeout");end
endmodule
