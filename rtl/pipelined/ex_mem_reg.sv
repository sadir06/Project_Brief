module ex_mem_reg (
    input  logic        clk,
    input  logic        rst,

    // EX-stage data inputs
    input  logic [31:0] ALUResultE,
    input  logic [31:0] WriteDataE,
    input  logic [31:0] PCTargetE,
    input  logic [4:0]  rdE,

    // EX-stage control inputs
    input  logic        RegWriteE,
    input  logic        MemWriteE,
    input  logic        MemReadE,
    input  logic [1:0]  ResultSrcE,
    input  logic        BranchE,
    input  logic        JumpE,
    input  logic        JalrE,

    // MEM-stage data outputs
    output logic [31:0] ALUResultM,
    output logic [31:0] WriteDataM,
    output logic [31:0] PCTargetM,
    output logic [4:0]  rdM,

    // MEM-stage control outputs
    output logic        RegWriteM,
    output logic        MemWriteM,
    output logic        MemReadM,
    output logic [1:0]  ResultSrcM,
    output logic        BranchM,
    output logic        JumpM,
    output logic        JalrM
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Data
            ALUResultM <= 32'b0;
            WriteDataM <= 32'b0;
            PCTargetM  <= 32'b0;
            rdM        <= 5'b0;

            // Control
            RegWriteM  <= 1'b0;
            MemWriteM  <= 1'b0;
            MemReadM   <= 1'b0;
            ResultSrcM <= 2'b00;
            BranchM    <= 1'b0;
            JumpM      <= 1'b0;
            JalrM      <= 1'b0;
        end else begin
            // Normal pipeline transfer from EX to MEM
            ALUResultM <= ALUResultE;
            WriteDataM <= WriteDataE;
            PCTargetM  <= PCTargetE;
            rdM        <= rdE;

            RegWriteM  <= RegWriteE;
            MemWriteM  <= MemWriteE;
            MemReadM   <= MemReadE;
            ResultSrcM <= ResultSrcE;
            BranchM    <= BranchE;
            JumpM      <= JumpE;
            JalrM      <= JalrE;
        end
    end

endmodule
