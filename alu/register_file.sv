module register_file(
    input logic        clk,
    input logic        WE3,
    input logic [4:0]  A1, 
    input logic [4:0]  A2,
    input logic [4:0]  A3,
    input logic [31:0] WD3,
    output logic [31:0] RD1,
    output logic [31:0] RD2
);

    logic [31:0] rf[31:0]; // 32 registers of 32 bits each (These are the internal registers stored inside the regfile)

    //Asynchronous reads, register x0 is always 0
    assign RD1 = (A1 != 0) ? rf[A1] : 32'b0; // Read the first register, return 0 if A1 is 0
    assign RD2 = (A2 != 0) ? rf[A2] : 32'b0; //Read the second register, return 0 if A2 is 0


    //Synchronous write, only write on clock edge, never write to x0
    always_ff @(posedge clk) begin
        if (WE3 && (A3 != 0)) begin
            rf[A3] <= WD3; // Write data to the register specified by A3
        end
    end

endmodule
