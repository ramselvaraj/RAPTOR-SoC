`timescale 1ns/1ps

module tb_soc;
    localparam int WORDS = 32768;
    localparam int SRC = 32'h0000_2000;
    localparam int DST = 32'h0000_6000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic boot_we = 1'b0;
    logic [1:0] boot_sel = 2'd0;
    logic [14:0] boot_addr = '0;
    logic [31:0] boot_wdata = '0;
    logic [31:0] boot_rdata;
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
    logic [31:0] ram_image [0:WORDS-1];
    logic [31:0] cpu_image [0:1023];
    logic [15:0] gpu_image [0:1023];

    soc_top dut (.*);

    always #5 clk = ~clk;

    task automatic boot_write(
        input logic [1:0] sel,
        input logic [14:0] addr,
        input logic [31:0] data
    );
        @(negedge clk);
        boot_we = 1'b1;
        boot_sel = sel;
        boot_addr = addr;
        boot_wdata = data;
    endtask

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
        for (i = 0; i < WORDS; i = i + 1) ram_image[i] = 32'b0;
        for (i = 0; i < 1024; i = i + 1) begin
            cpu_image[i] = 32'b0;
            gpu_image[i] = 16'b0;
        end
        $readmemh(frame_path, ram_image, SRC, SRC + width*height - 1);
        $readmemh(cpu_path, cpu_image);
        $readmemh(gpu1_path, gpu_image, 0);
        $readmemh(gpu2_path, gpu_image, 512);

        for (i = 0; i < WORDS; i = i + 1)
            boot_write(2'd2, 15'(i), ram_image[i]);
        for (i = 0; i < 1024; i = i + 1)
            boot_write(2'd0, 15'(i), cpu_image[i]);
        for (i = 0; i < 1024; i = i + 1)
            boot_write(2'd1, 15'(i), {16'b0, gpu_image[i]});
        @(negedge clk);
        boot_we = 1'b0;
        reset = 1'b0;

        // Programming requests during execution must not corrupt any memory.
        boot_write(2'd0, 15'd0, 32'b0);
        boot_write(2'd1, 15'd0, 32'h0000_c000);
        boot_write(2'd2, 15'(SRC), 32'hdead_beef);
        @(negedge clk);
        boot_we = 1'b0;

        wait (dones == 2);
        repeat (50) @(posedge clk);
        if (starts != 2 || dones != 2)
            $fatal(1, "expected two GPU passes, saw starts=%0d dones=%0d", starts, dones);
        if (trace_on) begin
            $fdisplay(tfd, "SUMMARY cycles=%0d reads=%0d writes=%0d starts=%0d dones=%0d",
                      cycles, reads, writes, starts, dones);
            $fclose(tfd);
        end
        $display("tb_soc: two CPU-driven GPU passes completed in %0d cycles", cycles);

        // Reset the processors, not the memories, and read back through the pins.
        @(negedge clk);
        reset = 1'b1;
        boot_sel = 2'd2;
        for (i = 0; i < WORDS; i = i + 1) begin
            boot_addr = 15'(i);
            #1;
            ram_image[i] = boot_rdata;
        end
        $writememh(out_path, ram_image);
        $finish;
    end

    initial begin
        repeat (50000000) @(posedge clk);
        $fatal(1, "tb_soc: TIMEOUT waiting for two GPU passes");
    end
endmodule
