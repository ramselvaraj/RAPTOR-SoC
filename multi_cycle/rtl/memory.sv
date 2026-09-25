module memory(
    input clk,
    input reset,
    input w_enable,
    input r_enable,
    input [31:0] adr,
    input [31:0] wd,
    output logic [31:0] rd
);


    logic [31:0] memdata [0:63];
integer k;

    always_ff @(posedge clk or posedge reset) begin
        
        if (reset) begin
            for (k = 0; k < 64; k = k + 1) begin
                memdata[k] <= 0;
            end
        end

        else if (w_enable) begin
            memdata[adr[7:2]] <= wd;
        end

    end

    assign rd = r_enable ? memdata[adr[7:2]] : 32'b0;
endmodule //memory
