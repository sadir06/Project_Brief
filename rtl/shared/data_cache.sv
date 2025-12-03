//CPU → data_cache → data_mem → CPU
// still needs implementation of cache and stall logic

module data_cache (
    input  logic        clk,
    input  logic        rst,

    input  logic        cpu_req,      // 1 when MEM stage has a valid load/store
    input  logic        cpu_we,       // 1 = store/write, 0 = load/read
    input  logic [31:0] cpu_addr,     // byte address - ALUResultM
    input  logic [31:0] cpu_wdata,    // store data - WriteDataM
    input  logic [2:0]  cpu_funct3,   // funct3M (byte/half/word)
    output logic [31:0] cpu_rdata,    // load result to MEM/WB
    output logic        cpu_stall     // 1 = cache busy (miss, stall pipeline)
);

// Cache configuration (4 KiB, 2-way, 16-byte lines)
    localparam CACHE_BYTES = 4096;
    localparam LINE_BYTES  = 16;
    localparam WAYS        = 2;

    localparam LINE_WORDS  = LINE_BYTES / 4;       // 4 words per line
    localparam NUM_LINES   = CACHE_BYTES / LINE_BYTES;
    localparam NUM_SETS    = NUM_LINES / WAYS;     // 4096 / (16*2) = 128
    localparam INDEX_BITS  = 7;                    // log2(128)
    localparam OFFSET_BITS = 4;                    // log2(16)
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;

    // Address breakdown
    logic [TAG_BITS-1:0]    addr_tag;
    logic [INDEX_BITS-1:0]  addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;
    logic [1:0]             word_offset;

    assign addr_offset = cpu_addr[OFFSET_BITS-1:0];             // [3:0]
    assign addr_index  = cpu_addr[OFFSET_BITS +: INDEX_BITS];   // [10:4]
    assign addr_tag    = cpu_addr[31           -: TAG_BITS];    // top bits
    assign word_offset = addr_offset[3:2];

// Cache arrays (tags[way][set], valid[way][set], dirty[way][set])
    logic [TAG_BITS-1:0] tag_array   [0:WAYS-1][0:NUM_SETS-1];
    logic                valid_array [0:WAYS-1][0:NUM_SETS-1];
    logic                dirty_array [0:WAYS-1][0:NUM_SETS-1];

    // data[way][set][word]
    logic [31:0]         data_array  [0:WAYS-1][0:NUM_SETS-1][0:LINE_WORDS-1];

    logic                lru_bit     [0:NUM_SETS-1];

    logic miss_load;
    logic [1:0] refill_cnt;


    // Hit detection:
    logic hit_way0, hit_way1;
    logic hit;
    logic [0:0] hit_way_idx;   // 1 bit since WAYS=2
    logic [31:0] hit_data;
    always_comb begin
        hit_way0 = valid_array[0][addr_index] &&
                   (tag_array[0][addr_index] == addr_tag);
        hit_way1 = valid_array[1][addr_index] &&
                   (tag_array[1][addr_index] == addr_tag);
        hit = hit_way0 | hit_way1;
        if (hit_way1)      hit_way_idx = 1;
        else               hit_way_idx = 0;
        hit_data = data_array[hit_way_idx][addr_index][word_offset];
    end



// Cache controller FSM (skeleton - needs to be done)
    typedef enum logic [2:0] {
        C_IDLE,
        C_MISS_SELECT,
        C_WRITEBACK,
        C_REFILL,
        C_RESPOND
    } cache_state_t;

    cache_state_t state, next_state;

    // State register + reset of cache arrays
    always_ff @(negedge clk or posedge rst) begin
        integer w;
        integer s;
        integer word;

        if (rst) begin
            state <= C_IDLE;
            refill_cnt <= 2'd0;

            // Clear all tags/valid/dirty and data arrays
            for (w = 0; w < WAYS; w++) begin
                for (s = 0; s < NUM_SETS; s++) begin
                    valid_array[w][s] <= 1'b0;
                    dirty_array[w][s] <= 1'b0;
                    tag_array[w][s]   <= '0;

                    for (word = 0; word < LINE_WORDS; word++) begin
                        data_array[w][s][word] <= 32'b0;
                    end
                end
            end

            // Reset LRU bits
            for (s = 0; s < NUM_SETS; s++) begin
                lru_bit[s] <= 1'b0;
            end
        end
        else begin
            state <= next_state;
            // refill_counter : reset to 0 when we leave IDLE (start of a miss), count 0..3 while in REFILL, reset when leaving REFILL
            case (state)
                C_IDLE: begin
                    if (next_state == C_REFILL)
                        refill_cnt <= 2'd0;
                end
                C_REFILL: begin
                    if (next_state == C_REFILL)
                        refill_cnt <= refill_cnt + 2'd1;
                    else
                        refill_cnt <= 2'd0;
                end
                default: begin
                    refill_cnt <= 2'd0;
                end
            endcase
            // still needs to update valid_array, tag_array, dirty_array and data_array during REFILL/WRITEBACK
        end
    end

    assign miss_load = cpu_req && !cpu_we && !hit;  // load + miss

    // Next-state logic for cache controller
    always_comb begin
        next_state = state;
        unique case (state)
            C_IDLE: begin
                // On a load miss, start a "refill" sequence.
                // For now we just wait a few cycles
                if (miss_load)
                    next_state = C_REFILL;
                // Later: if (cpu_req && miss) next_state = C_MISS_SELECT;
            end
            C_MISS_SELECT: begin
                // choose victim via LRU, inspect dirty -> WRITEBACK/REFILL, when doing 2-way selection
                next_state = C_MISS_SELECT;
            end
            C_WRITEBACK: begin
                // needs to be done (used to evict dirty lines)
                next_state = C_WRITEBACK;
            end
            C_REFILL: begin
                // Stay in REFILL while we "fetch" a 16B line (4 words) then  when counter reaches 3, move to RESPOND
                if (refill_cnt == 2'd3)
                    next_state = C_RESPOND;
                else
                    next_state = C_REFILL;
            end
            C_RESPOND: begin
                // 1 cycle where filled data is available to the CPU then IDLE
                next_state = C_IDLE;
            end
            default: next_state = C_IDLE;
        endcase
    end


    logic [31:0] mem_rdata;

    data_mem data_mem_inst (
        .clk          (clk),
        .addr_i       (cpu_addr),
        .write_data_i (cpu_wdata),
        .write_en_i   (cpu_we & cpu_req),
        .funct3_i     (cpu_funct3),
        .read_data_o  (mem_rdata)
    );

        always_comb begin
            cpu_stall = 1'b0; // default: no stall
            cpu_rdata = mem_rdata;
        //on hit, use hit_data; on miss, use refill buffer

        // miss-handling state: stall the CPU
            if (state == C_REFILL || state == C_RESPOND) begin
                cpu_stall = 1'b1;
            end

            if (state == C_IDLE) begin
                // LOAD (read) path
                if (cpu_req && !cpu_we) begin
                    if (hit)
                        cpu_rdata = hit_data;   // cache hit
                    else
                        cpu_rdata = mem_rdata;  // miss, but we will then go to REFILL
                end
                else begin
                    // STORE or no request: write-through, read_data_o from memory is don't-care
                    cpu_rdata = mem_rdata;
                end
            end
            else begin
                // During REFILL/RESPOND we keep cpu_rdata = mem_rdata (cpu_stall=1 so the pipeline does not consume it yet)
            end
        end

endmodule
