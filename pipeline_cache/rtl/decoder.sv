`timescale 1ns/1ps
module cache_cpu_decoder(
    input logic [31:0] instruction,
    output rv32_pkg::id_ex_t decoded
);
    import rv32_pkg::*;
    logic legal;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    always_comb begin
        decoded = '0;
        opcode = instruction[6:0];
        funct7 = instruction[31:25];
        funct3 = instruction[14:12];
        legal = 1'b0;
        decoded.instruction = instruction;
        decoded.rs1 = instruction[19:15];
        decoded.rs2 = instruction[24:20];
        decoded.rd = instruction[11:7];
        decoded.funct3 = funct3;
        decoded.imm = {{20{instruction[31]}}, instruction[31:20]};
        case (opcode)
            7'h33, 7'h13: begin
                decoded.immediate = opcode == 7'h13;
                decoded.use_rs1 = 1;
                decoded.use_rs2 = opcode == 7'h33;
                decoded.write_rd = 1;
                legal = opcode == 7'h13 || funct7 == 0;
                case (funct3)
                    0: begin
                        decoded.alu_op = (opcode == 7'h33 && funct7 == 7'h20) ? SUB : ADD;
                        if (opcode == 7'h33 && funct7 == 7'h20) legal = 1;
                    end
                    1: begin decoded.alu_op = SLL; legal = funct7 == 0; end
                    2: decoded.alu_op = SLT;
                    3: decoded.alu_op = SLTU;
                    4: decoded.alu_op = XOR_OP;
                    5: begin
                        decoded.alu_op = funct7 == 7'h20 ? SRA : SRL;
                        legal = funct7 == 0 || funct7 == 7'h20;
                    end
                    6: decoded.alu_op = OR_OP;
                    7: decoded.alu_op = AND_OP;
                    default: ;
                endcase
            end
            7'h03: begin
                legal = funct3 == 0 || funct3 == 1 || funct3 == 2 || funct3 == 4 || funct3 == 5;
                decoded.load = 1; decoded.write_rd = 1;
                decoded.use_rs1 = 1; decoded.immediate = 1;
            end
            7'h23: begin
                legal = funct3 <= 2;
                decoded.store = 1; decoded.use_rs1 = 1; decoded.use_rs2 = 1;
                decoded.immediate = 1;
                decoded.imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end
            7'h63: begin
                legal = funct3 == 0 || funct3 == 1 || funct3 >= 4;
                decoded.branch = 1; decoded.use_rs1 = 1; decoded.use_rs2 = 1;
                decoded.imm = {{19{instruction[31]}}, instruction[31], instruction[7],
                               instruction[30:25], instruction[11:8], 1'b0};
            end
            7'h6f: begin
                legal = 1; decoded.jal = 1; decoded.write_rd = 1;
                decoded.imm = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                               instruction[20], instruction[30:21], 1'b0};
            end
            7'h67: begin
                legal = funct3 == 0; decoded.jalr = 1;
                decoded.use_rs1 = 1; decoded.write_rd = 1;
            end
            7'h37, 7'h17: begin
                legal = 1; decoded.write_rd = 1;
                decoded.lui = opcode == 7'h37; decoded.auipc = opcode == 7'h17;
                decoded.imm = {instruction[31:12], 12'b0};
            end
            // FENCE is a no-op: this core has no outstanding store buffer.
            7'h0f: legal = funct3 == 0;
            default: ;
        endcase
        decoded.valid = legal;
        if (!legal) begin
            decoded.write_rd = 0; decoded.load = 0; decoded.store = 0;
            decoded.branch = 0; decoded.jal = 0; decoded.jalr = 0;
        end
    end
endmodule
