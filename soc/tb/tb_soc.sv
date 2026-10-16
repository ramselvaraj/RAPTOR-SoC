`timescale 1ns/1ps

module tb_soc;
    localparam int WORDS = 32768;
    localparam int SRC = 32'h0000_2000;
    localparam int DST = 32'h0000_6000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [3:0] cpu_state;
    logic gpu_start, gpu_busy, gpu_done;
    logic gpu_mem_req, gpu_mem_we;
    logic [31:0] gpu_mem_addr, gpu_mem_wdata;

    string frame_path = "frame.hex";
    string cpu_path = "cpu.hex";
    string gpu1_path = "gpu1.hex";
    string gpu2_path = "gpu2.hex";
    string out_path = "out.hex";
    string trace_path = "";
    int unsigned width = 64, height = 64, threads1 = 0, threads2 = 0;
    int unsigned cycles = 0, reads = 0, writes = 0, starts = 0, dones = 0;
    integer i, tfd;
    bit trace_on;

    soc_top dut (.*);

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            cycles <= 0;
            reads <= 0;
            writes <= 0;
            starts <= 0;
            dones <= 0;
        end else begin
            cycles <= cycles + 1;
            if (gpu_mem_req) begin
                if (gpu_mem_we) writes <= writes + 1;
                else reads <= reads + 1;
                if (trace_on)
                    $fdisplay(tfd, "BUS cycle=%0d op=%0s addr=%0d data=%08x",
                              cycles, gpu_mem_we ? "write" : "read",
                              gpu_mem_addr, gpu_mem_wdata);
            end
            if (dut.mmio.write_commit && dut.mmio.legal_write(dut.mmio.awaddr_q) && trace_on)
                $fdisplay(tfd, "MMIO_WRITE cycle=%0d addr=%08x data=%08x",
                          cycles, dut.mmio.awaddr_q, dut.mmio.wdata_q);
            if (gpu_start) begin
                starts <= starts + 1;
                if (trace_on)
                    $fdisplay(tfd, "GPU_START cycle=%0d pass=%0s threads=%0d prog_base=%0d",
                              cycles, dut.gpu_prog_base == 0 ? "interior" : "border",
                              dut.gpu_threads, dut.gpu_prog_base);
            end
            if (gpu_done) begin
                dones <= dones + 1;
                if (trace_on)
                    $fdisplay(tfd, "GPU_DONE cycle=%0d pass=%0s",
                              cycles, dut.gpu_prog_base == 0 ? "interior" : "border");
            end
        end
    end

    initial begin
        void'($value$plusargs("frame=%s", frame_path));
        void'($value$plusargs("cpu=%s", cpu_path));
        void'($value$plusargs("gpu1=%s", gpu1_path));
        void'($value$plusargs("gpu2=%s", gpu2_path));
        void'($value$plusargs("out=%s", out_path));
        void'($value$plusargs("trace=%s", trace_path));
        void'($value$plusargs("width=%d", width));
        void'($value$plusargs("height=%d", height));
        void'($value$plusargs("threads1=%d", threads1));
        void'($value$plusargs("threads2=%d", threads2));

        trace_on = (trace_path != "");
        if (trace_on) begin
            tfd = $fopen(trace_path, "w");
            $fdisplay(tfd, "CONFIG width=%0d height=%0d src=%0d dst=%0d", width, height, SRC, DST);
        end

        #1;
        for (i = 0; i < WORDS; i = i + 1) dut.ram.mem[i] = 32'b0;
        for (i = 0; i < 1024; i = i + 1) begin
            dut.cpu.datapath_inst.imem_inst.memdata[i] = 32'b0;
            dut.program_mem.mem[i] = 16'b0;
        end
        $readmemh(frame_path, dut.ram.mem, SRC, SRC + width*height - 1);
        $readmemh(cpu_path, dut.cpu.datapath_inst.imem_inst.memdata);
        $readmemh(gpu1_path, dut.program_mem.mem, 0);
        $readmemh(gpu2_path, dut.program_mem.mem, 512);

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        dut.cpu.datapath_inst.regfile_inst.registers[5]  = 32'h4000_0000;
        dut.cpu.datapath_inst.regfile_inst.registers[6]  = SRC;
        dut.cpu.datapath_inst.regfile_inst.registers[7]  = DST;
        dut.cpu.datapath_inst.regfile_inst.registers[8]  = threads1;
        dut.cpu.datapath_inst.regfile_inst.registers[9]  = threads2;
        dut.cpu.datapath_inst.regfile_inst.registers[10] = 0;
        dut.cpu.datapath_inst.regfile_inst.registers[11] = 512;
        dut.cpu.datapath_inst.regfile_inst.registers[14] = 2;

        wait (dones == 2);
        repeat (50) @(posedge clk);
        if (starts != 2 || dones != 2)
            $fatal(1, "expected two GPU passes, saw starts=%0d dones=%0d", starts, dones);
        $writememh(out_path, dut.ram.mem);
        if (trace_on) begin
            $fdisplay(tfd, "SUMMARY cycles=%0d reads=%0d writes=%0d starts=%0d dones=%0d",
                      cycles, reads, writes, starts, dones);
            $fclose(tfd);
        end
        $display("tb_soc: two CPU-driven GPU passes completed in %0d cycles", cycles);
        $finish;
    end

    initial begin
        repeat (50000000) @(posedge clk);
        $fatal(1, "tb_soc: TIMEOUT waiting for two GPU passes");
    end
endmodule
