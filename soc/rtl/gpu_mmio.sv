`timescale 1ns/1ps

module gpu_mmio #(
    parameter bit RANDOM_BACKPRESSURE = 1'b0,
    parameter bit STRICT_START = 1'b0
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    input  logic        gpu_busy,
    input  logic        gpu_done,
    input  logic        command_ready,
    output logic        start,
    output logic [31:0] thread_count,
    output logic [31:0] src_addr,
    output logic [31:0] dst_addr,
    output logic [31:0] prog_base
);
    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;
    localparam logic [31:0] MMIO_BASE = 32'h4000_0000;

    logic [31:0] awaddr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        aw_held;
    logic        w_held;
    logic        write_commit;
    logic        done_sticky;
    logic [7:0]  ready_lfsr;

    function automatic logic legal_write(input logic [31:0] addr);
        case ({addr[31:2], 2'b00})
            MMIO_BASE + 32'h00,
            MMIO_BASE + 32'h08,
            MMIO_BASE + 32'h0c,
            MMIO_BASE + 32'h10,
            MMIO_BASE + 32'h14: legal_write = 1'b1;
            default: legal_write = 1'b0;
        endcase
    endfunction

    function automatic logic legal_read(input logic [31:0] addr);
        legal_read = ({addr[31:2], 2'b00} == (MMIO_BASE + 32'h04));
    endfunction

    assign s_axi_awready = !aw_held && !s_axi_bvalid &&
                           (!RANDOM_BACKPRESSURE || ready_lfsr[1]);
    assign s_axi_wready  = !w_held && !s_axi_bvalid &&
                           (!RANDOM_BACKPRESSURE || ready_lfsr[3]);
    assign s_axi_arready = !s_axi_rvalid &&
                           (!RANDOM_BACKPRESSURE || ready_lfsr[5]);
    logic start_write;
    assign start_write = legal_write(awaddr_q) && awaddr_q[5:2] == 0 && wstrb_q[0] && wdata_q[0];
    assign write_commit  = aw_held && w_held && !s_axi_bvalid &&
                          (!STRICT_START || !start_write || gpu_busy || command_ready);

    always_ff @(posedge clk or posedge reset) begin : mmio_registers
        integer byte_index;
        if (reset) begin
            ready_lfsr     <= 8'ha5;
            awaddr_q      <= 32'b0;
            wdata_q       <= 32'b0;
            wstrb_q       <= 4'b0;
            aw_held       <= 1'b0;
            w_held        <= 1'b0;
            s_axi_bresp   <= AXI_OKAY;
            s_axi_bvalid  <= 1'b0;
            s_axi_rdata   <= 32'b0;
            s_axi_rresp   <= AXI_OKAY;
            s_axi_rvalid  <= 1'b0;
            start          <= 1'b0;
            thread_count   <= 32'b0;
            src_addr       <= 32'b0;
            dst_addr       <= 32'b0;
            prog_base      <= 32'b0;
            done_sticky    <= 1'b0;
        end else begin
            ready_lfsr <= {ready_lfsr[6:0], ready_lfsr[7] ^ ready_lfsr[5] ^ ready_lfsr[4] ^ ready_lfsr[3]};
            start <= 1'b0;
            if (gpu_done)
                done_sticky <= 1'b1;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_q <= s_axi_awaddr;
                aw_held  <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                w_held  <= 1'b1;
            end

            if (write_commit) begin
                aw_held      <= 1'b0;
                w_held       <= 1'b0;
                s_axi_bresp  <= legal_write(awaddr_q) && !(STRICT_START && start_write && gpu_busy) ? AXI_OKAY : AXI_SLVERR;
                s_axi_bvalid <= 1'b1;

                if (legal_write(awaddr_q)) begin
                    case ({awaddr_q[31:2], 2'b00})
                        MMIO_BASE + 32'h00: begin
                            if (wstrb_q[0] && wdata_q[0] && !(STRICT_START && gpu_busy)) begin
                                start       <= 1'b1;
                                done_sticky <= 1'b0;
                            end
                        end
                        MMIO_BASE + 32'h08: begin
                            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                                if (wstrb_q[byte_index])
                                    thread_count[byte_index*8 +: 8] <= wdata_q[byte_index*8 +: 8];
                        end
                        MMIO_BASE + 32'h0c: begin
                            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                                if (wstrb_q[byte_index])
                                    src_addr[byte_index*8 +: 8] <= wdata_q[byte_index*8 +: 8];
                        end
                        MMIO_BASE + 32'h10: begin
                            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                                if (wstrb_q[byte_index])
                                    dst_addr[byte_index*8 +: 8] <= wdata_q[byte_index*8 +: 8];
                        end
                        MMIO_BASE + 32'h14: begin
                            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                                if (wstrb_q[byte_index])
                                    prog_base[byte_index*8 +: 8] <= wdata_q[byte_index*8 +: 8];
                        end
                        default: begin end
                    endcase
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rdata  <= legal_read(s_axi_araddr) ?
                                {30'b0, done_sticky, gpu_busy} : 32'b0;
                s_axi_rresp  <= legal_read(s_axi_araddr) ? AXI_OKAY : AXI_SLVERR;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
