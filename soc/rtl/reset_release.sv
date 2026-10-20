`timescale 1ns/1ps
module reset_release(input logic clk, arst, output logic reset);
    (* ASYNC_REG = "TRUE" *) logic [1:0] stages;
    always_ff @(posedge clk or posedge arst)
        if (arst) stages <= 2'b11;
        else stages <= {stages[0], 1'b0};
    assign reset = stages[1];
endmodule
