`timescale 1ns/1ps
module tb_soc_phase5 #(
    parameter bit CACHE_ENABLE=1,
    parameter int FIFO_DEPTH=4
);
    logic cpu_clk=0, gpu_clk=0, arst=1, boot_hold=1;
    int cpu_half_ps=3500, gpu_half_ps=5500, seed=1, stalls=0, reset_test=0;
    logic cpu_pause=0, gpu_pause=0;
    initial begin
        void'($value$plusargs("cpu_half_ps=%d", cpu_half_ps));
        void'($value$plusargs("gpu_half_ps=%d", gpu_half_ps));
        void'($value$plusargs("seed=%d",seed));
        void'($value$plusargs("stalls=%d",stalls));
        void'($value$plusargs("reset_test=%d",reset_test));
        assert(cpu_half_ps>0 && gpu_half_ps>0);
    end
    initial forever begin #(cpu_half_ps*1ps); if(!cpu_pause) cpu_clk=~cpu_clk; end
    initial begin
        // Equal-period runs deliberately exercise coincident clock edges.
        if(cpu_half_ps!=gpu_half_ps) #1.137;
        forever begin #(gpu_half_ps*1ps); if(!gpu_pause) gpu_clk=~gpu_clk; end
    end
    logic boot_valid=0,boot_ready,boot_done,boot_error;
    logic [1:0] boot_sel=0;
    logic [14:0] boot_addr=0;
    logic [31:0] boot_wdata=0,boot_rdata;
    logic memory_service_enable=1;
    logic fault,gpu_start,gpu_busy,gpu_done,gpu_commit,gpu_commit_we;
    logic [63:0] cpu_cycles,gpu_cycles,retired,icache_hits,icache_misses,dcache_hits,dcache_misses,dcache_writebacks;
    logic retire_valid,retire_write;
    logic [31:0] retire_pc,retire_instruction,retire_data;
    logic [4:0] retire_rd;
    soc_phase5_top #(.CACHE_ENABLE(CACHE_ENABLE), .FIFO_DEPTH(FIFO_DEPTH), .RANDOM_BACKPRESSURE(1)) dut(.*);
    string frame_path="frame.hex",cpu_path="cpu.hex",gpu1_path="gpu1.hex",gpu2_path="gpu2.hex",out_path="out.hex",trace_path="";
    int unsigned width=16,height=16,threads1=0,threads2=0;
    logic [31:0] ram_image[32768], cpu_image[1024];
    logic [15:0] gpu_image[1024];
    int starts=0,dones=0,reads=0,writes=0,tfd=0;
    logic firmware_done=0;
    logic [31:0] cpu_pixel,cpu_source,rng;
    logic [31:0] launched_base;
    always @(posedge cpu_clk) begin
        if(arst) begin starts=0; dones=0; reads=0; writes=0; firmware_done=0; rng=seed==0?32'd1:32'(seed); end
        else begin
            rng = {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(fault) $fatal(1,"Phase 5 CPU/AXI fault at PC %08x", retire_pc);
            if(gpu_start) begin
                starts++;
                launched_base=dut.prog_base;
                if(tfd!=0) $fdisplay(tfd,"GPU_START pass=%0s threads=%0d",dut.prog_base==0?"interior":"border",dut.threads);
            end
            if(gpu_done) begin
                dones++;
                if(tfd!=0) $fdisplay(tfd,"GPU_DONE pass=%0s",launched_base==0?"interior":"border");
            end
            if(gpu_commit) begin if(gpu_commit_we) writes++; else reads++; end
            if(retire_valid && retire_write) begin
                if(retire_rd==20) cpu_pixel=retire_data;
                if(retire_rd==21) cpu_source=retire_data;
                if(retire_rd==22 && retire_data==123) firmware_done=1;
            end
        end
    end
    always @(negedge cpu_clk) memory_service_enable = stalls==0 || rng[0] || rng[3];
    task automatic write_boot(input logic [1:0] sel, input int addr, input logic [31:0] data);
        @(negedge cpu_clk);
        boot_valid=1; boot_sel=sel; boot_addr=15'(addr); boot_wdata=data;
        do @(posedge cpu_clk); while(!boot_ready);
        @(negedge cpu_clk); boot_valid=0;
        // Immediate CPU writes completed on the acceptance edge; GPU writes return later.
        while(!boot_done) @(negedge cpu_clk);
        if(boot_error) $fatal(1,"boot write rejected sel=%0d addr=%0d",sel,addr);
    endtask
    task automatic load_images;
        for(int i=0;i<32768;i++) write_boot(2,i,ram_image[i]);
        for(int i=0;i<1024;i++) write_boot(0,i,cpu_image[i]);
        for(int i=0;i<1024;i++) write_boot(1,i,{16'b0,gpu_image[i]});
    endtask
    initial begin
        void'($value$plusargs("frame=%s",frame_path));
        void'($value$plusargs("cpu=%s",cpu_path));
        void'($value$plusargs("gpu1=%s",gpu1_path));
        void'($value$plusargs("gpu2=%s",gpu2_path));
        void'($value$plusargs("out=%s",out_path));
        void'($value$plusargs("trace=%s",trace_path));
        void'($value$plusargs("width=%d",width));
        void'($value$plusargs("height=%d",height));
        void'($value$plusargs("threads1=%d",threads1));
        void'($value$plusargs("threads2=%d",threads2));
        for(int i=0;i<32768;i++) ram_image[i]=0;
        for(int i=0;i<1024;i++) begin cpu_image[i]=0;gpu_image[i]=0;end
        $readmemh(frame_path,ram_image,8192,8192+width*height-1);
        $readmemh(cpu_path,cpu_image);
        $readmemh(gpu1_path,gpu_image,0);
        $readmemh(gpu2_path,gpu_image,512);
        if(trace_path!="") tfd=$fopen(trace_path,"w");
        #50; arst=0;
        wait(boot_ready);
        load_images();
        @(negedge cpu_clk); boot_hold=0;
        if(reset_test!=0) begin
            wait(gpu_commit);
            #0.217; arst=1; boot_hold=1;
            $display("PHASE5: abort old epoch with live pixel transaction, then reload");
            if(tfd!=0) begin $fclose(tfd);tfd=$fopen(trace_path,"w");end
            #71; arst=0;
            wait(boot_ready);
            load_images();
            @(negedge cpu_clk); boot_hold=0;
        end
        // Pause both clocks independently in a live launch, without changing resets.
        if(stalls!=0) begin
            wait(gpu_busy); #237; gpu_pause=1; #153; gpu_pause=0;
            #211; cpu_pause=1; #177; cpu_pause=0;
        end
        wait(firmware_done);
        @(negedge cpu_clk);
        if(starts!=2 || dones!=2 || reads!=width*height*9 || writes!=width*height)
            $fatal(1,"traffic mismatch starts=%0d dones=%0d reads=%0d writes=%0d",starts,dones,reads,writes);
        if(cpu_pixel!==dut.ram.mem[24576] || cpu_source!==dut.ram.mem[8192])
            $fatal(1,"uncached CPU readback did not observe GPU output/source");
        if(dut.ram.mem[4096]!==32'h007b7b7b) $fatal(1,"private dirty eviction/byte strobes incorrect");
        if(CACHE_ENABLE && (icache_hits==0 || dcache_hits==0 || dcache_writebacks==0))
            $fatal(1,"caches were not exercised");
        if(tfd!=0) begin
            $fdisplay(tfd,"SUMMARY cpu_cycles=%0d gpu_cycles=%0d retired=%0d reads=%0d writes=%0d starts=%0d dones=%0d ic_hits=%0d dc_hits=%0d dc_wb=%0d",cpu_cycles,gpu_cycles,retired,reads,writes,starts,dones,icache_hits,dcache_hits,dcache_writebacks);
            $fclose(tfd);
        end
        $writememh(out_path,dut.ram.mem);
        $display("PHASE5 PASS clocks=%0d/%0dps seed=%0d cpu_cycles=%0d gpu_cycles=%0d",cpu_half_ps*2,gpu_half_ps*2,seed,cpu_cycles,gpu_cycles);
        $finish;
    end
    initial begin #200000000; $fatal(1,"Phase 5 timeout"); end
endmodule
