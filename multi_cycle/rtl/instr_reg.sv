module instr_reg(
    input logic clk,
    input logic reset,
    input logic write_enable,
    input logic [31:0] instruction_in,
    output logic [31:0] instruction_out
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            instruction_out <= 32'b0;
        else if (write_enable)
            instruction_out <= instruction_in;
    end
endmodule
