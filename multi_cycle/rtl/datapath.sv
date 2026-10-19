module mc_datapath(
    input logic clk, reset,
    input logic imem_we,
    input logic [9:0] imem_waddr,
    input logic [31:0] imem_wdata,
    input logic pc_write, ir_write, ab_write, aluout_write, mdr_write, reg_write,
    input logic alu_src_a_pc,
    input logic [2:0] alu_src_b,
    input logic [2:0] alu_operation,
    input logic writeback_from_memory, pc_next_from_aluout,
    input logic [31:0] mem_rdata,
    output logic [31:0] mem_addr, mem_wdata,
    output logic [6:0] opcode,
    output logic funct7_bit,
    output logic [2:0] funct3,
    output logic zero
);
    logic [31:0] pc, pc_next, instruction, ir, read_data1, read_data2;
    logic [31:0] a, b, alu_a, alu_b, alu_result, alu_out, mdr;
    logic [31:0] immediate_i_s, immediate_b, immediate_j, writeback_data;

    pc_sv pc_inst(.clk, .reset, .pc_ctrl(pc_write), .pc_next, .pc);
    mc_instruction_memory imem_inst(
        .clk, .write_enable(imem_we && reset),
        .write_addr(imem_waddr), .write_data(imem_wdata),
        .address(pc), .instruction
    );
    instr_reg ir_inst(.clk, .reset, .write_enable(ir_write), .instruction_in(instruction), .instruction_out(ir));
    mc_reg_file regfile_inst(.clk, .reset, .write_enable(reg_write), .read_addr1(ir[19:15]), .read_addr2(ir[24:20]), .write_addr(ir[11:7]), .write_data(writeback_data), .read_data1, .read_data2);
    data_reg a_reg(.clk, .reset, .write_enable(ab_write), .data_in(read_data1), .data_out(a));
    data_reg b_reg(.clk, .reset, .write_enable(ab_write), .data_in(read_data2), .data_out(b));
    data_reg aluout_reg(.clk, .reset, .write_enable(aluout_write), .data_in(alu_result), .data_out(alu_out));
    data_reg mdr_reg(.clk, .reset, .write_enable(mdr_write), .data_in(mem_rdata), .data_out(mdr));
    mc_alu alu_inst(.a(alu_a), .b(alu_b), .operation(alu_operation), .result(alu_result), .zero);

    assign immediate_i_s = (opcode == 7'b0100011) ? {{20{ir[31]}}, ir[31:25], ir[11:7]} : {{20{ir[31]}}, ir[31:20]};
    assign immediate_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
    assign immediate_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};
    assign alu_a = alu_src_a_pc ? pc : a;
    // Branch and JAL execute after FETCH has advanced PC by one instruction.
    always_comb begin
        case (alu_src_b)
            3'd1: alu_b = 32'd4;
            3'd2: alu_b = immediate_i_s;
            3'd3: alu_b = immediate_b - 32'd4;
            3'd4: alu_b = immediate_j - 32'd4;
            3'd5: alu_b = 32'd0;
            default: alu_b = b;
        endcase
    end
    assign pc_next = pc_next_from_aluout ? alu_out : alu_result;
    assign writeback_data = writeback_from_memory ? mdr : alu_out;
    assign mem_addr = alu_out;
    assign mem_wdata = b;
    assign opcode = ir[6:0];
    assign funct7_bit = ir[30];
    assign funct3 = ir[14:12];
endmodule
