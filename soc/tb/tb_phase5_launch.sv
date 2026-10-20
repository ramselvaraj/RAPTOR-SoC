`timescale 1ns/1ps
module tb_phase5_launch;
    logic cpu_clk=0,gpu_clk=0,arst=1,boot_hold=1,boot_valid=0;
    always #10 cpu_clk=~cpu_clk;
    initial begin #0.317; forever #1 gpu_clk=~gpu_clk; end
    logic boot_ready,boot_done,boot_error,fault,gpu_start,gpu_busy,gpu_done,gpu_commit;
    logic [1:0] boot_sel=0;
    logic [14:0] boot_addr=0;
    logic [31:0] boot_wdata=0;
    logic retire_valid,retire_write;
    logic [4:0] retire_rd;
    logic [31:0] retire_data;
    logic [31:0] image[1024];
    int launches=0,completions=0;
    soc_phase5_top #(.FIFO_DEPTH(2)) dut(
        .cpu_clk,.gpu_clk,.arst,.boot_hold,.boot_valid,.boot_ready,.boot_done,.boot_error,.boot_sel,.boot_addr,.boot_wdata,
        .memory_service_enable(1'b1),.fault,.gpu_start,.gpu_busy,.gpu_done,.gpu_commit,
        .retire_valid,.retire_write,.retire_rd,.retire_data,
        .boot_rdata(),.gpu_commit_we(),.cpu_cycles(),.gpu_cycles(),.retired(),.icache_hits(),.icache_misses(),
        .dcache_hits(),.dcache_misses(),.dcache_writebacks(),.retire_pc(),.retire_instruction());
    always @(posedge cpu_clk) if(!arst) begin
        assert(!fault && !gpu_commit);
        if(gpu_start) launches++;
        if(gpu_done) completions++;
    end
    task automatic write_boot(input logic [1:0] sel,input int address,input logic [31:0] data,input logic expected_error=0);
        @(negedge cpu_clk);boot_sel=sel;boot_addr=15'(address);boot_wdata=data;boot_valid=1;
        do @(posedge cpu_clk);while(!boot_ready);
        @(negedge cpu_clk);boot_valid=0;
        while(!boot_done) @(negedge cpu_clk);
        assert(boot_error==expected_error);
    endtask
    initial begin
        for(int i=0;i<1024;i++) image[i]=32'h00000063;
        $readmemh("soc/build/phase5/launch.hex",image);
        #57;arst=0;wait(boot_ready);
        for(int i=0;i<1024;i++) write_boot(0,i,image[i]);
        write_boot(1,0,32'h5000); // GPU RET opcode
        write_boot(0,1024,32'hdeadbeef,1);
        write_boot(1,1024,32'hdeadbeef,1);
        write_boot(3,0,32'hdeadbeef,1);
        assert(dut.cpu_program.memdata[0]==image[0] && dut.gpu_program.mem[0]==16'h5000);
        @(negedge cpu_clk);boot_hold=0;
        wait(retire_valid && retire_write && retire_rd==22 && retire_data==123);
        @(negedge cpu_clk);
        assert(launches==32 && completions==32 && !gpu_busy)
            else $fatal(1,"short launch events lost: %0d/%0d",launches,completions);
        $display("PHASE5 LAUNCH PASS 32 zero-thread launches, 10:1 GPU/CPU clock ratio");
        $finish;
    end
    initial begin #10000000;$fatal(1,"short launch timeout");end
endmodule
