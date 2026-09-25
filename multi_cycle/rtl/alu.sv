module mc_alu(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [2:0] operation,
    output logic [31:0] result,
    output logic zero
);
    localparam logic [2:0] ALU_SUB = 3'd1;
    localparam logic [2:0] ALU_AND = 3'd2;
    localparam logic [2:0] ALU_OR  = 3'd3;

    always_comb begin
        case (operation)
            ALU_SUB: result = a - b;
            ALU_AND: result = a & b;
            ALU_OR:  result = a | b;
            default: result = a + b;
        endcase
        zero = (result == 32'b0);
    end
endmodule
