
pc_reg pc_reg_inst (
    .clk(clk),
    .rst(rst),
    .en(PCWrite),
    .pc_next(pc_next),
    .pc(pcF)
);


always_comb begin
    if (JalrE)
        pc_next = PCJalrE;
    else if (BranchE && cond_trueE)
        pc_next = PCTargetE;
    else if (JumpE)
        pc_next = PCTargetE;
    else
        pc_next = PCPlus4F;  // PC+4 from fetch stage
end

