module data_mem #(
    parameter DATA_WIDTH = 32,  // Data width
    parameter ADDR_WIDTH = 17   // 128KB data memory (2^17 bytes)
)(
    input  logic                     clk,
    input  logic [DATA_WIDTH-1:0]    addr_i,
    input  logic [DATA_WIDTH-1:0]    write_data_i,
    input  logic                     write_en_i,
    input  logic [2:0]               funct3_i,
    output logic [DATA_WIDTH-1:0]    read_data_o
);

    // Memory array: byte-addressable
    // Memory layout:
    // 0x00000000-0x000000FF: Reserved (256 bytes)
    // 0x00000100-0x000001FF: pdf_array (256 bytes)  
    // 0x00010000-0x0001FFFF: data_array (64KB)
    logic [7:0] ram_array [0:2**ADDR_WIDTH-1];
    
    initial begin
        // Arrays initialize to 0 by default, no need for explicit loop
        $readmemh("data.hex", ram_array, 17'h10000);
    end
    
    // Extract byte address (lower ADDR_WIDTH bits)
    logic [ADDR_WIDTH-1:0] byte_addr;
    assign byte_addr = addr_i[ADDR_WIDTH-1:0];
    
    //===========================================
    // SYNCHRONOUS WRITE LOGIC
    //===========================================
    always_ff @(posedge clk) begin
        if (write_en_i) begin
            unique case (funct3_i)
                3'b000: begin  // SB - Store Byte
                    ram_array[byte_addr] <= write_data_i[7:0];
                end
                
                3'b001: begin  // SH - Store Halfword (little-endian)
                    ram_array[byte_addr]     <= write_data_i[7:0];
                    ram_array[byte_addr + 1] <= write_data_i[15:8];
                end
                
                3'b010: begin  // SW - Store Word (little-endian)
                    ram_array[byte_addr]     <= write_data_i[7:0];
                    ram_array[byte_addr + 1] <= write_data_i[15:8];
                    ram_array[byte_addr + 2] <= write_data_i[23:16];
                    ram_array[byte_addr + 3] <= write_data_i[31:24];
                end
                
                default: begin
                    // Invalid store - do nothing
                end
            endcase
        end
    end
    
    //===========================================
    // ASYNCHRONOUS READ LOGIC
    //===========================================
    logic [7:0]  read_byte;
    logic [15:0] read_half;
    logic [31:0] read_word;
    
    // Reconstruct multi-byte values (little-endian)
    assign read_byte = ram_array[byte_addr];
    assign read_half = {ram_array[byte_addr + 1], ram_array[byte_addr]};
    assign read_word = {ram_array[byte_addr + 3], ram_array[byte_addr + 2],
                        ram_array[byte_addr + 1], ram_array[byte_addr]};
    
    // Format output based on load operation
    always_comb begin
        unique case (funct3_i)
            3'b000: read_data_o = {{24{read_byte[7]}}, read_byte};  // LB (sign-extend)
            3'b001: read_data_o = {{16{read_half[15]}}, read_half}; // LH (sign-extend)
            3'b010: read_data_o = read_word;                        // LW
            3'b100: read_data_o = {24'b0, read_byte};               // LBU (zero-extend)
            3'b101: read_data_o = {16'b0, read_half};               // LHU (zero-extend)
            default: read_data_o = 32'b0;
        endcase
    end

endmodule
