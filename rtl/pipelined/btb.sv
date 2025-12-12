// Branch Target Buffer (BTB)
// Stores predicted branch targets to reduce control hazard penalties
// Simple design: 64 entries, direct-mapped, 1-bit prediction

module btb (
    input  logic        clk,
    input  logic        rst,
    
    // Lookup port (used in IF stage)
    input  logic [31:0] pc_lookup,           // PC to look up
    output logic        btb_hit,             // 1 if BTB has entry for this PC
    output logic [31:0] btb_target,          // Predicted target address
    
    // Update port (used in EX stage when branch resolves)
    input  logic        update_en,          // 1 to update BTB entry
    input  logic [31:0] pc_update,          // PC of branch that resolved
    input  logic [31:0] actual_target,      // Actual target (if taken)
    input  logic        actual_taken         // 1 if branch was actually taken
);

    // BTB parameters
    localparam BTB_SIZE = 64;               // 64 entries
    localparam INDEX_BITS = 6;              // log2(64) = 6 bits for index
    localparam TAG_BITS = 32 - INDEX_BITS - 2;  // Remaining bits for tag (PC[31:8])
    
    // BTB entry structure
    typedef struct packed {
        logic                valid;          // Entry is valid
        logic                prediction;     // 1 = predict taken, 0 = predict not taken
        logic [TAG_BITS-1:0] tag;           // Tag to verify PC match
        logic [31:0]         target;        // Predicted target address
    } btb_entry_t;
    
    // BTB storage array
    btb_entry_t btb_array [0:BTB_SIZE-1];
    
    // Extract index and tag from PC
    logic [INDEX_BITS-1:0] lookup_index;
    logic [TAG_BITS-1:0]   lookup_tag;
    logic [INDEX_BITS-1:0] update_index;
    logic [TAG_BITS-1:0]   update_tag;
    
    // Use PC[7:2] as index (bits 1:0 are always 00 for word-aligned addresses)
    assign lookup_index = pc_lookup[INDEX_BITS+1:2];
    assign lookup_tag   = pc_lookup[31:INDEX_BITS+2];
    assign update_index = pc_update[INDEX_BITS+1:2];
    assign update_tag   = pc_update[31:INDEX_BITS+2];
    
    // Lookup logic (combinational)
    always_comb begin
        btb_hit = 1'b0;
        btb_target = 32'b0;
        
        // Check if entry exists and tag matches
        if (btb_array[lookup_index].valid && 
            (btb_array[lookup_index].tag == lookup_tag)) begin
            btb_hit = 1'b1;
            btb_target = btb_array[lookup_index].target;
        end
    end
    
    // Update logic (sequential - on clock edge)
    always_ff @(posedge clk or posedge rst) begin
        integer i;
        
        if (rst) begin
            // Reset all entries
            for (i = 0; i < BTB_SIZE; i++) begin
                btb_array[i].valid <= 1'b0;
                btb_array[i].prediction <= 1'b0;
                btb_array[i].tag <= '0;
                btb_array[i].target <= 32'b0;
            end
        end
        else if (update_en) begin
            // Update BTB entry
            if (actual_taken) begin
                // Branch was taken: store target and predict taken next time
                btb_array[update_index].valid <= 1'b1;
                btb_array[update_index].prediction <= 1'b1;  // Predict taken
                btb_array[update_index].tag <= update_tag;
                btb_array[update_index].target <= actual_target;
            end
            else begin
                // Branch was not taken: update prediction to not taken
                // Keep entry valid but change prediction
                if (btb_array[update_index].valid && 
                    (btb_array[update_index].tag == update_tag)) begin
                    btb_array[update_index].prediction <= 1'b0;  // Predict not taken
                end
            end
        end
    end

endmodule

