`timescale 1ns/1ps
module tb_phase5_axi;
    logic clk=0,reset=1,req_valid=0,req_ready,resp_valid,resp_ready=0,fault;
    logic [31:0] req_addr=0,req_data=0,resp_data;
    logic [3:0] req_strb=0;
    logic [31:0] m_axi_awaddr,m_axi_wdata,m_axi_araddr,m_axi_rdata;
    logic [3:0] m_axi_wstrb;
    logic m_axi_awvalid,m_axi_awready,m_axi_wvalid,m_axi_wready,m_axi_bready,m_axi_arvalid,m_axi_arready,m_axi_rready;
    logic m_axi_bvalid=0,m_axi_rvalid=0;
    logic [1:0] m_axi_bresp=0,m_axi_rresp=0;
    cpu_request_axi dut(.*);
    always #5 clk=~clk;
    int cycle=0,reads=0,writes=0;
    logic aw_seen=0,bad=0;
    logic [31:0] address,word_value=32'h11223344;
    assign m_axi_awready=!aw_seen && !m_axi_bvalid && cycle%3==1;
    assign m_axi_wready=aw_seen && !m_axi_bvalid && cycle%4==2;
    assign m_axi_arready=!m_axi_rvalid && cycle%5==3;
    always @(posedge clk) begin
        if(reset) begin cycle<=0;m_axi_bvalid<=0;m_axi_rvalid<=0;aw_seen<=0;end
        else begin
            cycle<=cycle+1;
            if(m_axi_awvalid && m_axi_awready) begin aw_seen<=1;address<=m_axi_awaddr;end
            if(m_axi_wvalid && m_axi_wready) begin
                assert(address=='h4000);
                for(int b=0;b<4;b++) if(m_axi_wstrb[b]) word_value[b*8+:8]<=m_axi_wdata[b*8+:8];
                writes++;aw_seen<=0;m_axi_bvalid<=1;m_axi_bresp<=bad?2'b10:0;
            end else if(m_axi_bvalid && m_axi_bready) m_axi_bvalid<=0;
            if(m_axi_arvalid && m_axi_arready) begin
                reads++;m_axi_rvalid<=1;m_axi_rdata<=word_value;m_axi_rresp<=bad?2'b10:0;
            end else if(m_axi_rvalid && m_axi_rready) m_axi_rvalid<=0;
        end
    end
    task automatic request(input logic [3:0] mask,input logic [31:0] data);
        @(negedge clk);req_valid=1;req_addr='h4000;req_strb=mask;req_data=data;
        do @(posedge clk);while(!req_ready);
        // Deliberately hold VALID after acceptance: no duplicate must be issued.
        repeat(3) @(negedge clk);
        req_valid=0;
        wait(resp_valid);
        repeat(7) begin @(negedge clk); assert(resp_valid && !req_ready); end
        resp_ready=1;
        @(negedge clk);resp_ready=0;
    endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;
        request(2,32'h0000ab00);
        assert(word_value==32'h1122ab44 && writes==1);
        request(12,32'hcdef0000);
        assert(word_value==32'hcdefab44 && writes==2);
        request(0,0);
        assert(resp_data==32'hcdefab44 && reads==1);
        @(negedge clk);bad=1;req_valid=1;req_strb=0;
        do @(posedge clk);while(!req_ready);
        @(negedge clk);req_valid=0;
        wait(fault);
        repeat(4) @(negedge clk);
        assert(!req_ready && !resp_valid && reads==2);
        reset=1;repeat(2) @(negedge clk);reset=0;bad=0;
        @(negedge clk);assert(!fault && req_ready);
        $display("PHASE5 AXI PASS stalls, strobes, no duplicates, response hold, errors/reset");
        $finish;
    end
    initial begin #1000000;$fatal(1,"AXI adapter timeout");end
endmodule
