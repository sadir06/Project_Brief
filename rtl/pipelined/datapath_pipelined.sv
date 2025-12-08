

//for the forward_unit.sv 
/*
logic [31:0] rs1E_val, rs2E_val;
logic [1:0]  ForwardAE, ForwardBE;
logic [31:0] srcA_E, srcB_E;

always_comb begin
    case (ForwardAE)
        2'b00: srcA_E = rs1E_val;
        2'b10: srcA_E = ALUResultM;
        2'b01: srcA_E = WriteDataW;
        default: srcA_E = rs1E_val;
    endcase

    case (ForwardBE)
        2'b00: srcB_E = rs2E_val;
        2'b10: srcB_E = ALUResultM;
        2'b01: srcB_E = WriteDataW;
        default: srcB_E = rs2E_val;
    endcase
end

logic [31:0] ALU_B_E;
assign ALU_B_E = (ALUSrcE) ? ImmExtE : srcB_E;
*/


//for the hazard_unit.sv and pc control:
/*
PCPlus4E = pcE + 4;

PCTargetE = pcE + ImmExtE; // for branch + jal

PCJalrE = { (ALUResultE[31:1]), 1'b0 }; // jalr target (rs1+imm)&~1

cond_trueE:

If BranchE and ALUControlE==SUB (bne): cond_trueE = ~ZeroE;

If BranchE and ALUControlE==SLTU (bgeu): cond_trueE = ZeroE; (since result==0 → rs1>=rs2)
*/