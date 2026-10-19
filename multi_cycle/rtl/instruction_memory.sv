module mc_instruction_memory(
    input logic clk,
    input logic write_enable,
    input logic [9:0] write_addr,
    input logic [31:0] write_data,
    input logic [31:0] address,
    output logic [31:0] instruction
);
    logic [31:0] memdata [0:1023];

    // Program while the CPU is held in reset. Contents survive reset.
    always_ff @(posedge clk) begin
        if (write_enable)
            memdata[write_addr] <= write_data;
    end

    assign instruction = memdata[address[11:2]];
endmodule
