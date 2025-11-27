



/*
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        RegWriteE   <= 0;
        MemWriteE   <= 0;
        MemReadE    <= 0;
        BranchE     <= 0;
        JumpE       <= 0;
        JalrE       <= 0;
        ALUSrcE     <= 0;
        ResultSrcE  <= 0;
        ALUControlE <= 0;
    end else if (flush) begin
        // Insert a bubble: zero **only** the control bits
        RegWriteE   <= 0;
        MemWriteE   <= 0;
        MemReadE    <= 0;
        BranchE     <= 0;
        JumpE       <= 0;
        JalrE       <= 0;
        ALUSrcE     <= 0;
        ResultSrcE  <= 0;
        ALUControlE <= 0;

    end else begin
        // Normal operation: pipeline registers copy values from D stage
        RegWriteE   <= RegWriteD;
        MemWriteE   <= MemWriteD;
        MemReadE    <= MemReadD;
        BranchE     <= BranchD;
        JumpE       <= JumpD;
        JalrE       <= JalrD;
        ALUSrcE     <= ALUSrcD;
        ResultSrcE  <= ResultSrcD;
        ALUControlE <= ALUControlD;

        pcE         <= pcD;
        rs1E_val    <= rs1D_val;
        rs2E_val    <= rs2D_val;
        ImmExtE     <= ImmExtD;
        rdE         <= rdD;
        rs1_addrE   <= rs1D_addr;
        rs2_addrE   <= rs2D_addr;
    end
end
*/
