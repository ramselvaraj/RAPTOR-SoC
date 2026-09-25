module mc_controller(
    input logic clk, reset,
    input logic [6:0] opcode,
    input logic funct7_bit,
    input logic [2:0] funct3,
    input logic zero,
    output logic pc_write, ir_write, ab_write, aluout_write, mdr_write, reg_write, mem_write, mem_read,
    output logic alu_src_a_pc,
    output logic [1:0] alu_src_b,
    output logic [2:0] alu_operation,
    output logic writeback_from_memory, pc_next_from_aluout,
    output logic [3:0] state
);
    localparam logic [3:0] FETCH = 0, DECODE = 1, EXEC_R = 2, WB_ALU = 3, MEM_ADDR = 4,
                           MEM_READ = 5, WB_MEM = 6, MEM_WRITE = 7, BRANCH = 8;
    localparam logic [6:0] OP_RTYPE = 7'b0110011, OP_LW = 7'b0000011,
                           OP_SW = 7'b0100011, OP_BEQ = 7'b1100011;
    localparam logic [2:0] ALU_ADD = 0, ALU_SUB = 1, ALU_AND = 2, ALU_OR = 3;
    logic [3:0] next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= FETCH;
        else state <= next_state;
    end

    always_comb begin
        next_state = FETCH;
        case (state)
            FETCH: next_state = DECODE;
            DECODE: case (opcode)
                OP_RTYPE: next_state = EXEC_R;
                OP_LW, OP_SW: next_state = MEM_ADDR;
                OP_BEQ: next_state = BRANCH;
                default: next_state = FETCH;
            endcase
            EXEC_R: next_state = WB_ALU;
            WB_ALU: next_state = FETCH;
            MEM_ADDR: next_state = (opcode == OP_LW) ? MEM_READ : MEM_WRITE;
            MEM_READ: next_state = WB_MEM;
            WB_MEM, MEM_WRITE, BRANCH: next_state = FETCH;
            default: next_state = FETCH;
        endcase
    end

    always_comb begin
        pc_write = 0; ir_write = 0; ab_write = 0; aluout_write = 0; mdr_write = 0;
        reg_write = 0; mem_write = 0; mem_read = 0; alu_src_a_pc = 0; alu_src_b = 0;
        alu_operation = ALU_ADD; writeback_from_memory = 0; pc_next_from_aluout = 0;
        case (state)
            FETCH: begin
                pc_write = 1; ir_write = 1; alu_src_a_pc = 1; alu_src_b = 1;
            end
            DECODE: begin
                ab_write = 1;
                if (opcode == OP_BEQ) begin
                    // PC already points to the sequential instruction after fetch.
                    aluout_write = 1; alu_src_a_pc = 1; alu_src_b = 3;
                end
            end
            EXEC_R: begin
                aluout_write = 1;
                case (funct3)
                    3'b111: alu_operation = ALU_AND;
                    3'b110: alu_operation = ALU_OR;
                    default: alu_operation = funct7_bit ? ALU_SUB : ALU_ADD;
                endcase
            end
            WB_ALU: reg_write = 1;
            MEM_ADDR: begin aluout_write = 1; alu_src_b = 2; end
            MEM_READ: begin mem_read = 1; mdr_write = 1; end
            WB_MEM: begin reg_write = 1; writeback_from_memory = 1; end
            MEM_WRITE: mem_write = 1;
            BRANCH: begin pc_write = zero; alu_operation = ALU_SUB; pc_next_from_aluout = 1; end
            default: ;
        endcase
    end
endmodule
