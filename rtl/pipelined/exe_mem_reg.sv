module exe_mem_reg (
    // 'E' after a term indicates that it is in the Execute stage
    // 'M  after a term indicates that it is in the Memory stage

    input logic clk, 
    input logic rst, 

    // Data inputs (from the execute stage)
    input logic [31:0] ALUResultE, 
    input logic [31:0] WriteDataE, 
    input logic [31:0] PCTargetE, 
    input logic [4:0] rdE, 
    input logic [31:0] PCPlus4E, // PC + 4 value from EX stage. We need to include this for JAL and JALR instructions. 
                                // If we don't, the value of the "Return Address" will be lost before it reaches the end. 

    // Control inputs (pass-through from ID/EX)
    input logic RegWriteE, 
    input logic [1:0] ResultSrcE, 
    input logic MemWriteE,

    // Data outputs (To Memory Stage)
    output logic [31:0] ALUResultM,
    output logic [31:0] WriteDataM,
    output logic [31:0] PCTargetM, 
    output logic [4:0] rdM,
    output logic [31:0] PCPlus4M,

    // Control Ouptuts (To Memory Stage)
    output logic RegWriteM,
    output logic [1:0] ResultSrcM,
    output logic MemWriteM
);

    // Ont he rising edge of the clock (transition from EX to MEM)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // On reset, clear all pipeline registers to 0 (because it is a reset)
            ALUResultM <= 32'b0;
            WriteDataM <= 32'b0; 
            PCTargetM  <= 32'b0;
            rdM        <= 5'b0;
            PCPlus4M   <= 32'b0;

            RegWriteM  <= 1'b0;
            ResultSrcM <= 2'b00;
            MemWriteM  <= 1'b0;
        end
        else begin
            // Normal operation: transfer data from EX stage to the MEM stage
            // We use the <= (non-blocking assignment) to ensure all registers update in parallel
            
            // Pass Data
            ALUResultM <= ALUResultE;
            WriteDataM <= WriteDataE;
            PCTargetM  <= PCTargetE;
            rdM        <= rdE;
            PCPlus4M   <= PCPlus4E;

            // Pass Control
            RegWriteM  <= RegWriteE;
            ResultSrcM <= ResultSrcE;
            MemWriteM  <= MemWriteE;
        end
    end

endmodule


