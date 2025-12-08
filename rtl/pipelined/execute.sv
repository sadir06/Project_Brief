module execute (
    input logic              clk,

    // Control Signals (From ID/EX Register)
    input logic             ALUSrcE,
    input logic             ALUSrcAE, // Selects SrcA (PC vs Reg) for AUIPC
    input logic [3:0]       ALUControlE,
    input logic [2:0]       Funct3E, //Needed for Branch Type (BEQ vs BNE)
    input logic             JalrE, // Needed for JALR target calc

    // Data Inputs (From ID/EX Register)
    input logic [31:0]    rs1_dataE, //Data read from Reg[rs1]
    input logic [31:0]    rs2_dataE, //Data read from Reg[rs2]
    input logic [31:0]    ImmExtE, //Extended Immediate
    input logic [31:0]      PCE,  //Program Counter at this stage

    // Forwarding Inputs
    input logic [1:0]    ForwardAE, // Select logic for SrcA
    input logic [1:0]    ForwardBE, // Select logic for SrcB

    // Forwarding Data 
    input logic [31:0]    ALUResultM, // Data forwarded from Memory Stage
    input logic [31:0]    ResultW,    // Data forwarded from Writeback Stage

    // Outputs to Ex/MEM Register
    output logic [31:0]   ALUResultE, // The calculation result
    output logic [31:0]   WriteDataE, // The data to store in memory (forwarded rs2)
    output logic [31:0]   PCTargetE, // Calulated Branch Target

    // Output to Hazard Unit
    output logic         cond_trueE // High if branch condition is met
);


    // Internal wires for the "Forwarding Mux" results
    logic [31:0] SrcAE_forwarded;
    logic [31:0] SrcBE_forwarded;
    logic [31:0] SrcAE_final;
    logic [31:0] SrcBE_final; // The actual input to the ALU
    logic       ZeroE; // Zero flag from ALU

    //Forwarding Logic for Source A
    always_comb begin
        case (ForwardAE)
            2'b00: SrcAE_forwarded = rs1_dataE; // No forwarding
            2'b01: SrcAE_forwarded = ResultW; // Forward from WB stage
            2'b10: SrcAE_forwarded = ALUResultM; // Forward from MEM stage
            default: SrcAE_forwarded = rs1_dataE;
        endcase
    end

    //Forwarding logic for Source B
    always_comb begin
        case (ForwardBE)
            2'b00: SrcBE_forwarded = rs2_dataE; // No forwarding
            2'b01: SrcBE_forwarded = ResultW; // Forward from WB stage
            2'b10: SrcBE_forwarded = ALUResultM; // Forward from MEM stage
            default: SrcBE_forwarded = rs2_dataE;
        endcase
    end


    //ALU Source A Mux (For AUIPC)
    assign SrcAE_final = (ALUSrcAE) ? PCE : SrcAE_forwarded;

    // This selects between the (potentially forwarded) rs2 and the Immediate
    // If ALUSrcE is 1, we use the Immediate. If it is 0, we use rs2.
    assign SrcBE_final = (ALUSrcE) ? ImmExtE : SrcBE_forwarded;

    // You reuse your ALU from the single cycle
    alu alu_inst (
        .SrcA(SrcAE_final),
        .SrcB(SrcBE_final),
        .ALUControl(ALUControlE),
        .ALUResult(ALUResultE),
        .Zero(ZeroE)
    );

    // JALR requires setting the LSB to 0
    always_comb begin
        if (JalrE)
            PCTargetE = (SrcAE_forwarded + ImmExtE) & ~32'd1;
        else
            //Calculate Branch Target (PC + Immediate)
            PCTargetE = PCE + ImmExtE;
    end

    // Full Branch Support
    // We use Funct3 to determine which condition to check
    // Relies on ALU performing SUB (for EQ/NE) or SLT (for LT/GE)
    always_comb begin
        case (Funct3E)
            3'b000: cond_trueE = ZeroE;          // BEQ (Zero=1)
            3'b001: cond_trueE = ~ZeroE;         // BNE (Zero=0)
            3'b100: cond_trueE = ALUResultE[0];  // BLT (Result=1 from SLT)
            3'b101: cond_trueE = ~ALUResultE[0]; // BGE (Result=0 from SLT)
            3'b110: cond_trueE = ALUResultE[0];  // BLTU (Result=1 from SLTU)
            3'b111: cond_trueE = ~ALUResultE[0]; // BGEU (Result=0 from SLTU)
        endcase
    end

    // Write Data Output
    // If we are doing a STORE instruction, the data we write to memory comes from rs2. 
    // However, rs2 may have been forwarded, so we output 'SrcBE_forwarded' as 'WriteDataE'.
    assign WriteDataE = SrcBE_forwarded;

endmodule
