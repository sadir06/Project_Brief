module instr_mem #(
    parameter DATA_WIDTH = 32,  // Instruction width in bits
    parameter ADDR_WIDTH = 10   // Address width for word indexing (1024 words)
)(
    input  logic [31:0]           addr_i,   // Byte address from PC
    output logic [DATA_WIDTH-1:0] instr_o   // Instruction output
);

    // Memory array: 2^ADDR_WIDTH words of DATA_WIDTH bits each
    logic [DATA_WIDTH-1:0] rom_array [0:2**ADDR_WIDTH-1];
    
    initial begin
        $readmemh("program.hex", rom_array);
    end

    // Convert byte address to word address
    logic [ADDR_WIDTH-1:0] word_addr;
    assign word_addr = addr_i[ADDR_WIDTH+1:2]; //drop 2 LSB [11:2]
    
    assign instr_o = rom_array[word_addr];

endmodule
