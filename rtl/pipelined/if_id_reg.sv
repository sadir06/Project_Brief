module if_id_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        write_enable,  // IF_ID_Write from hazard_unit (1=update, 0=stall)
    input  logic        flush,         // IF_ID_Flush from hazard_unit (1=insert NOP)
    
    // Inputs from IF stage
    input  logic [31:0] pcF,           // PC in Fetch stage
    input  logic [31:0] instrF,        // Instruction from instruction memory
    input  logic        btb_hitF,      // BTB prediction from IF stage
    input  logic        btb_predict_takenF, // BTB prediction: 1=taken, 0=not taken
    input  logic [31:0] btb_targetF,   // Predicted target from IF stage
    
    // Outputs to ID stage
    output logic [31:0] pcD,           // PC in Decode stage
    output logic [31:0] instrD,        // Instruction in Decode stage
    output logic        btb_hitD,      // BTB prediction in Decode stage
    output logic        btb_predict_takenD, // BTB prediction in Decode stage
    output logic [31:0] btb_targetD   // Predicted target in Decode stage
);

    always_ff @(negedge clk or posedge rst) begin
        if (rst) begin
            // On reset, clear pipeline register
            pcD        <= 32'b0;
            instrD     <= 32'b0;
            btb_hitD   <= 1'b0;
            btb_predict_takenD <= 1'b0;
            btb_targetD <= 32'b0;
        end 
        else if (flush) begin
            // On flush, insert a NOP (all control bits zero)
            pcD        <= 32'b0;
            instrD     <= 32'b0;
            btb_hitD   <= 1'b0;
            btb_predict_takenD <= 1'b0;
            btb_targetD <= 32'b0;
        end 
        else if (write_enable) begin
            // Normal operation: pass values from IF to ID
            pcD        <= pcF;
            instrD     <= instrF;
            btb_hitD   <= btb_hitF;
            btb_predict_takenD <= btb_predict_takenF;
            btb_targetD <= btb_targetF;
        end
        // else: stall - values remain unchanged (hold current state)
    end

endmodule
