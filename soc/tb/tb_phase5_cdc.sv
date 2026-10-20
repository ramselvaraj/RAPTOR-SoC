`timescale 1ns/1ps
module tb_phase5_cdc #(parameter int DEPTH=4);
    logic sclk=0,dclk=0,arst=1,srst,drst;
    logic pause_source=0,pause_dest=0;
    always #3.5 if(!pause_source) sclk=~sclk;
    initial begin #1.219; forever #5.5 if(!pause_dest) dclk=~dclk; end
    reset_release a(.clk(sclk), .arst, .reset(srst));
    reset_release b(.clk(dclk), .arst, .reset(drst));
    logic req_valid,req_ready,resp_valid,resp_ready,dreq_valid,dreq_ready,dresp_valid,dresp_ready;
    logic [31:0] req_data,resp_data,dreq_data,dresp_data;
    cdc_request_channel #(.DEPTH(DEPTH)) dut(.*);
    int sent=0,received=0,serviced=0;
    logic accepted=0;
    logic [31:0] srng=32'h12345,drng=32'h56789;
    assign req_data=32'(sent)^32'h1234abcd;
    assign dreq_ready=!dresp_valid && drng[0];
    always @(negedge sclk) begin
        if(srst) begin req_valid=0; resp_ready=0; srng=32'h12345; end
        else begin
            srng={srng[30:0],srng[31]^srng[21]^srng[1]^srng[0]};
            if(!req_valid || accepted) req_valid=sent<2000 && srng[0];
            resp_ready=srng[1] || srng[3];
        end
    end
    always @(posedge sclk) begin
        if(srst) begin sent<=0;received<=0;accepted<=0;end
        else begin
            accepted<=req_valid && req_ready;
            if(req_valid && req_ready) sent<=sent+1;
            if(resp_valid && resp_ready) begin
                assert(resp_data == ((32'(received)^32'h1234abcd)+32'h00420042))
                    else $fatal(1,"CDC response lost/reordered/duplicated at %0d",received);
                received<=received+1;
            end
        end
    end
    always @(posedge dclk) begin
        if(drst) begin serviced<=0;dresp_valid<=0;dresp_data<=0;drng<=32'h56789;end
        else begin
            drng<={drng[30:0],drng[31]^drng[21]^drng[1]^drng[0]};
            if(dresp_valid && dresp_ready) dresp_valid<=0;
            if(dreq_valid && dreq_ready) begin
                assert(dreq_data == (32'(serviced)^32'h1234abcd)) else $fatal(1,"CDC request corruption");
                serviced<=serviced+1;
                dresp_valid<=1;dresp_data<=dreq_data+32'h00420042;
            end
        end
    end
    initial begin
        req_valid=0;resp_ready=0;
        #51; arst=0;
        wait(sent>40); #0.217; arst=1;
        #39; arst=0;
        wait(sent>100); #23; pause_dest=1; #193; pause_dest=0;
        wait(received>200); #21; pause_source=1; #197; pause_source=0;
        wait(received==2000);
        assert(serviced==2000 && sent==2000);
        $display("PHASE5 CDC PASS depth=%0d requests=%0d",DEPTH,sent);
        $finish;
    end
    initial begin #2000000; $fatal(1,"CDC timeout"); end
endmodule
