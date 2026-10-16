`timescale 1ns/1ps

module tb_riscv_mc;
    logic clk = 0;
    logic reset = 1;
    logic mem_req, mem_we, mem_done;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [31:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
    logic [3:0] axi_wstrb;
    logic [1:0] axi_bresp, axi_rresp;
    logic axi_awvalid, axi_awready, axi_wvalid, axi_wready;
    logic axi_bvalid, axi_bready, axi_arvalid, axi_arready;
    logic axi_rvalid, axi_rready;
    logic [3:0] state;
    logic [31:0] memory [0:255];
    logic pending, aw_held, w_held;
    logic [31:0] awaddr_q, wdata_q;
    integer bus_cycle;
    integer transaction_count;
    integer errors = 0;
    integer cycles;
    integer i;
    logic jal_seen = 0;
    logic duplicate_request;

    riscv_mc dut(
        .clk, .reset,
        .mem_req, .mem_we, .mem_addr, .mem_wdata,
        .mem_rdata, .mem_done, .state
    );

    cpu_axi_master axi_master(
        .clk, .reset, .req(mem_req), .we(mem_we), .addr(mem_addr),
        .wdata(mem_wdata), .rdata(mem_rdata), .done(mem_done),
        .m_axi_awaddr(axi_awaddr), .m_axi_awvalid(axi_awvalid), .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata), .m_axi_wstrb(axi_wstrb),
        .m_axi_wvalid(axi_wvalid), .m_axi_wready(axi_wready),
        .m_axi_bresp(axi_bresp), .m_axi_bvalid(axi_bvalid), .m_axi_bready(axi_bready),
        .m_axi_araddr(axi_araddr), .m_axi_arvalid(axi_arvalid), .m_axi_arready(axi_arready),
        .m_axi_rdata(axi_rdata), .m_axi_rresp(axi_rresp),
        .m_axi_rvalid(axi_rvalid), .m_axi_rready(axi_rready)
    );

    always #5 clk = ~clk;

    function automatic [31:0] encode_i(
        input integer imm,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        encode_i = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] encode_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        encode_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    endfunction

    function automatic [31:0] encode_s(
        input integer imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1
    );
        encode_s = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] encode_b(
        input integer imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        encode_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                    imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic [31:0] encode_j(
        input integer imm,
        input logic [4:0] rd
    );
        encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    task automatic expect_equal(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string name
    );
        if (actual !== expected) begin
            $display("FAIL: %s: expected %h, got %h", name, expected, actual);
            errors = errors + 1;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    // Deterministic READY gaps inject stalls on every AXI request channel.
    assign axi_awready = !reset && !aw_held && !axi_bvalid && (bus_cycle[1:0] == 2'b01);
    assign axi_wready  = !reset && !w_held && !axi_bvalid && (bus_cycle[1:0] == 2'b10);
    assign axi_arready = !reset && !axi_rvalid && (bus_cycle[2:0] == 3'b011);
    assign axi_bresp = 2'b00;
    assign axi_rresp = 2'b00;

    always_ff @(posedge clk) begin
        if (reset) begin
            pending <= 1'b0;
            aw_held <= 1'b0;
            w_held <= 1'b0;
            axi_bvalid <= 1'b0;
            axi_rvalid <= 1'b0;
            axi_rdata <= 32'b0;
            bus_cycle <= 0;
            transaction_count <= 0;
            duplicate_request <= 1'b0;
        end else begin
            bus_cycle <= bus_cycle + 1;
            if (mem_req) begin
                if (pending) begin
                    $display("FAIL: duplicate request while transaction is pending");
                    duplicate_request <= 1'b1;
                end else begin
                    pending <= 1'b1;
                    transaction_count <= transaction_count + 1;
                end
            end
            if (mem_done)
                pending <= 1'b0;

            if (axi_awvalid && axi_awready) begin
                awaddr_q <= axi_awaddr;
                aw_held <= 1'b1;
            end
            if (axi_wvalid && axi_wready) begin
                wdata_q <= axi_wdata;
                w_held <= 1'b1;
            end
            if (aw_held && w_held && !axi_bvalid) begin
                if (axi_wstrb == 4'b1111)
                    memory[awaddr_q[9:2]] <= wdata_q;
                aw_held <= 1'b0;
                w_held <= 1'b0;
                axi_bvalid <= 1'b1;
            end else if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
            end

            if (axi_arvalid && axi_arready) begin
                axi_rdata <= memory[axi_araddr[9:2]];
                axi_rvalid <= 1'b1;
            end else if (axi_rvalid && axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!reset && state == 4'd10) begin
            #1;
            expect_equal(dut.datapath_inst.pc, 32'd68, "JAL target");
            expect_equal(dut.datapath_inst.regfile_inst.registers[10], 32'd60,
                         "JAL link is instruction PC+4");
            jal_seen = 1'b1;
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'b0;

        // Wait for the instruction memory's initialization before preloading it.
        #1;
        dut.datapath_inst.imem_inst.memdata[0]  = encode_i(10, 0, 3'b000, 1, 7'b0010011); // addi x1,x0,10
        dut.datapath_inst.imem_inst.memdata[1]  = encode_i(3, 0, 3'b000, 2, 7'b0010011);  // addi x2,x0,3
        dut.datapath_inst.imem_inst.memdata[2]  = encode_r(0, 2, 1, 3'b000, 3);            // add x3,x1,x2
        dut.datapath_inst.imem_inst.memdata[3]  = encode_r(7'b0100000, 2, 1, 3'b000, 5);   // sub x5,x1,x2
        dut.datapath_inst.imem_inst.memdata[4]  = encode_r(0, 2, 1, 3'b110, 6);            // or x6,x1,x2
        dut.datapath_inst.imem_inst.memdata[5]  = encode_r(0, 2, 1, 3'b111, 7);            // and x7,x1,x2
        dut.datapath_inst.imem_inst.memdata[6]  = encode_s(64, 3, 0);                      // sw x3,64(x0)
        dut.datapath_inst.imem_inst.memdata[7]  = encode_i(64, 0, 3'b010, 4, 7'b0000011); // lw x4,64(x0)
        dut.datapath_inst.imem_inst.memdata[8]  = encode_b(8, 4, 3, 3'b000);              // beq x3,x4,+8
        dut.datapath_inst.imem_inst.memdata[9]  = encode_i(1, 0, 3'b000, 14, 7'b0010011);// skipped
        dut.datapath_inst.imem_inst.memdata[10] = encode_b(8, 4, 3, 3'b001);              // bne not taken
        dut.datapath_inst.imem_inst.memdata[11] = encode_i(1, 0, 3'b000, 8, 7'b0010011); // executes
        dut.datapath_inst.imem_inst.memdata[12] = encode_b(8, 2, 1, 3'b001);              // bne taken
        dut.datapath_inst.imem_inst.memdata[13] = encode_i(1, 0, 3'b000, 9, 7'b0010011); // skipped
        dut.datapath_inst.imem_inst.memdata[14] = encode_j(12, 10);                       // jal x10,+12
        dut.datapath_inst.imem_inst.memdata[15] = encode_i(1, 0, 3'b000, 11, 7'b0010011);// skipped
        dut.datapath_inst.imem_inst.memdata[16] = encode_i(1, 0, 3'b000, 12, 7'b0010011);// skipped
        dut.datapath_inst.imem_inst.memdata[17] = encode_i(0, 10, 3'b000, 13, 7'b0010011);// addi x13,x10,0
        dut.datapath_inst.imem_inst.memdata[18] = encode_b(0, 0, 0, 3'b000);              // halt

        repeat (2) @(posedge clk);
        reset = 1'b0;

        cycles = 0;
        while ((dut.datapath_inst.regfile_inst.registers[13] !== 32'd60) &&
               (cycles < 250)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        repeat (5) @(posedge clk);

        expect_equal(dut.datapath_inst.regfile_inst.registers[1], 10, "ADDI");
        expect_equal(dut.datapath_inst.regfile_inst.registers[3], 13, "ADD");
        expect_equal(dut.datapath_inst.regfile_inst.registers[5], 7, "SUB");
        expect_equal(dut.datapath_inst.regfile_inst.registers[6], 11, "OR");
        expect_equal(dut.datapath_inst.regfile_inst.registers[7], 2, "AND");
        expect_equal(memory[16], 13, "AXI SW with stalls");
        expect_equal(dut.datapath_inst.regfile_inst.registers[4], 13, "AXI LW with stalls");
        expect_equal(dut.datapath_inst.regfile_inst.registers[14], 0, "BEQ taken");
        expect_equal(dut.datapath_inst.regfile_inst.registers[8], 1, "BNE not taken");
        expect_equal(dut.datapath_inst.regfile_inst.registers[9], 0, "BNE taken");
        expect_equal(dut.datapath_inst.regfile_inst.registers[11], 0, "JAL skips PC+4");
        expect_equal(dut.datapath_inst.regfile_inst.registers[12], 0, "JAL reaches target");
        expect_equal(transaction_count, 2, "one external request per LW/SW");
        expect_equal({31'b0, duplicate_request}, 0, "no duplicate external request");
        expect_equal({31'b0, cycles < 250}, 1, "program completed before timeout");
        expect_equal({31'b0, jal_seen}, 1, "JAL observed");

        if (errors == 0)
            $display("All multi-cycle processor tests passed.");
        else
            $fatal(1, "%0d multi-cycle processor tests failed.", errors);
        $finish;
    end
endmodule
