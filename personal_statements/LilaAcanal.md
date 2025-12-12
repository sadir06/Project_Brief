# Personal Statement - Lila Acanal

## Contents
- [Overview](#overview)
- [Key Technical Contributions](#key-technical-contributions)
  - [1. Single-Cycle CPU: Memory Systems and I/O](#1-single-cycle-cpu-memory-systems-and-io)
    - [1.1 Instruction Memory Implementation](#11-instruction-memory-implementation)
    - [1.2 Data Memory with Byte-Level Operations](#12-data-memory-with-byte-level-operations)
    - [1.3 F1 Starting Lights Assembly Program](#13-f1-starting-lights-assembly-program)
  - [2. Pipelined CPU: Pipeline Registers and Integration](#2-pipelined-cpu-pipeline-registers-and-integration)
    - [2.1 Pipeline Register Implementation](#21-pipeline-register-implementation)
    - [2.2 Top-Level Integration](#22-top-level-integration)
  - [3. Cache-Enabled CPU: Memory Hierarchy Extension](#3-cache-enabled-cpu-memory-hierarchy-extension)
    - [3.1 Data Memory Enhancement for Cache Support](#31-data-memory-enhancement-for-cache-support)
    - [3.2 Cache Byte Operation Support](#32-cache-byte-operation-support)
    - [3.3 Cache Controller Debugging and Verification](#33-cache-controller-debugging-and-verification)
  - [4. Complete RV32I Load/Store Instruction Set](#4-complete-rv32i-loadstore-instruction-set)
    - [4.1 Control Unit Extension](#41-control-unit-extension)
    - [4.2 Data Memory Complete Implementation](#42-data-memory-complete-implementation)
    - [4.3 Cache Integration for All Instruction Sizes](#43-cache-integration-for-all-instruction-sizes)
- [Reflection](#reflection)

---

## Overview

As the Memory Systems and I/O engineer for the team, my primary responsibility was designing and implementing the memory hierarchy that forms the foundation of our RISC-V processor. I built the instruction memory (`instr_mem.sv`) and data memory (`data_mem.sv`) modules, building up on the data memory module as we went forward with each section of the project from single cycle, pipelined, cached and full instruction set. Otherwise, for each section of the project, if additional memory implementation was not needed, I contributed by implementing other modules, such as the pipeline registers in the pipelined cpu.

I additionally partially contributed to the verification process for both the single cycle and cache implementation. Thus, my role extended beyond hardware design to also include partial verification through assembly programming. This dual focus on hardware implementation and software verification provided valuable insights into the processor's behavior from both perspectives.

Working on the memory subsystem was especially engaging because it required deep understanding of the RISC-V memory model, byte ordering conventions, and the critical timing relationships between memory and the CPU. The collaborative debugging sessions, especially when resolving byte addressing issues, were essential learning experiences.

---

# Key Technical Contributions

## 1. Single-Cycle CPU: Memory Systems and I/O

### 1.1 Instruction Memory Implementation

I initially implemented the instruction memory module (`rtl/instr_mem.sv`) as word-addressable storage, which seemed logical since RISC-V instructions are 32-bit aligned. However, during testing with Deniz, we discovered instructions weren't being fetched correctly—the root cause was a fundamental misunderstanding of RISC-V's byte addressing model.

**Critical Debugging with Deniz:**

While instructions are 32-bit aligned, the PC uses byte addresses, not word addresses. Our implementation conflicted with the expected base address of `0xBFC00000`. The solution required a complete redesign to byte-addressable memory. [Commit: 21f8a12](https://github.com/sadir06/Project_Brief/commit/21f8a127ad04035d4e50985b3c6fb5fd8e44380b)

**Key changes implemented:**
- Changed memory array from 32-bit words to 8-bit bytes
- Added base address offset calculation (`addr_i - 32'hBFC00000`)
- Implemented byte assembly logic for 32-bit instructions in little-endian order:
```systemverilog
instr_o = {rom_array[offset_addr+3], rom_array[offset_addr+2], 
           rom_array[offset_addr+1], rom_array[offset_addr+0]};
```

This experience taught me the critical difference between logical organization (word-aligned instructions) and physical implementation (byte-addressable memory), and the importance of thoroughly understanding addressing specifications. It also taught me to read the project brief more carefully :D

---

### 1.2 Data Memory with Byte-Level Operations

The data memory module required supporting load and store operations for the F1 starting lights program. Initially, I implemented only the operations needed for the single-cycle CPU: LBU (load byte unsigned) and SB (store byte).

**Initial Implementation:**

I created a byte-addressable memory array with proper memory layout:
- `0x00000000-0x000000FF`: Reserved (256 bytes)
- `0x00000100-0x000001FF`: pdf_array for reference program (256 bytes)
- `0x00010000-0x0001FFFF`: General data array (64KB)

The implementation supported only two operations:

```systemverilog
// Synchronous write - SB only
always_ff @(posedge clk) begin
    if (write_en_i && funct3_i == 3'b000) begin  // SB
        ram_array[byte_addr] <= write_data_i[7:0];
    end
end

// Asynchronous read - LBU only
always_comb begin
    if (funct3_i == 3'b100) begin  // LBU
        read_data_o = {24'b0, ram_array[byte_addr]};  // Zero-extend
    end else begin
        read_data_o = 32'b0;
    end
end
```

**Key Design Choices:**
- **Byte-addressable from the start:** Even though we only needed LBU/SB, using an 8-bit array foundation made future expansion straightforward
- **Synchronous writes, asynchronous reads:** Writes occur on clock edges while reads are combinational, essential for single-cycle timing
- **Zero extension for LBU:** Properly implements unsigned byte loads by padding with zeros

This minimal implementation was sufficient for the F1 starting lights program and established the memory interface that would later be extended for the complete RV32I instruction set and cache integration.

---

### 1.3 F1 Starting Lights Assembly Program

I developed the F1 starting lights program to verify processor functionality and provide visual demonstration. The program implements the Lab 3 sequence (pattern: 0x01 → 0x03 → 0x07 → 0x0F → ... → 0xFF).

**Initial Implementations:**

I created two versions—a fast test version for verification and a VBuddy demo version with trigger input and visual delays. We ended up discarding the demo version due to it not working at all (zero lights were lighting up) most likely due to complications arising with the trigger input, the test version at least was working partially, so we built on that. 

The test version comprehensively verified:
- Subroutine calls (`JAL`, `JALR`)
- Memory operations (`SB`, `LBU`)
- Branch instructions (`BNE`)
- Arithmetic operations (`ADD`, `ADDI`)

**Critical Bug Discovery and Fix (with Deniz):**

During VBuddy testing, we observed the first LED blinking instead of staying on. Deniz added hex display debugging, revealing the pattern value was flickering. The root cause was our increment logic:
```assembly
ADD  a0, a0, a0         # a0 = a0 * 2
ADDI a0, a0, 1          # a0 = a0 + 1
```

This two-instruction sequence created a visible intermediate state. The solution was to use a temporary register for atomic updates:
```assembly
add     t2, a0, a0      # t2 = a0 * 2
addi    t2, t2, 1       # t2 = t2 + 1
add     a0, t2, zero    # a0 = t2 (instant update!)
```

This fixed the blinking by computing the pattern in `t2` before copying to `a0` in a single instruction, eliminating the visible intermediate state. This experience reinforced the importance of understanding instruction-level timing and visibility of intermediate states in hardware.

The fixed assembly code can be found in (`tb/asm/f1_lights_other.s`)
We found then a simpler way to implement this assembly code and saved it in (`tb/asm/f1_lights.s`) , this was the file used for all future testing.

---

## 2. Pipelined CPU: Pipeline Registers and Integration

My primary responsibility for the pipelined CPU was implementing the pipeline registers that separate each stage and integrating all components into the top-level module. This work required careful attention to control signal propagation, hazard handling, and timing relationships.

### 2.1 Pipeline Register Implementation

With Ambre's help, me and her worked out the stall/flush logic needed in each pipeline register and then we collaboratively implemented 3 out of 4 pipeline registers (IF/ID, ID/EX, MEM/WB) that segment the datapath:

**IF/ID Register (`if_id_reg.sv`):**
This register required special control logic for hazard handling. With Ambre, we implemented both `write_enable` (for stalling) and `flush` (for inserting NOPs) signals:
```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pcD <= 32'b0;
        instrD <= 32'b0;
    end 
    else if (flush) begin
        // Insert NOP on branch/jump misprediction
        pcD <= 32'b0;
        instrD <= 32'b0;
    end 
    else if (write_enable) begin
        // Normal operation
        pcD <= pcF;
        instrD <= instrF;
    end
    // else: stall - hold current values
end
```

The key insight was understanding that stalling (holding values) and flushing (inserting bubbles) serve different purposes in hazard resolution.

**ID/EX Register (`id_ex_reg.sv`):**
This was the most complex pipeline register, carrying both control signals (9 signals) and data (7 signals including register addresses for forwarding). We put more thought into this module with Ambre. The flush logic only zeroes control bits while preserving data:
```systemverilog
else if (flush) begin
    // Insert bubble: zero control bits to create NOP
    RegWriteE <= 1'b0;
    MemWriteE <= 1'b0;
    MemReadE <= 1'b0;
    BranchE <= 1'b0;
    JumpE <= 1'b0;
    // ... other control signals
    
    // Keep data values (won't be used since controls are zero)
    pcE <= pcD;
    rs1_dataE <= rs1_dataD;
    // ... other data signals
end
```

**MEM/WB Register:**
These were more straightforward, passing ALU results, memory data, PC values, and control signals through the pipeline stages.

Note: the EX/MEM register was implemented by another team member.

**PC Register with Enable (`pc_reg_pipe.sv`):**
I modified the single-cycle PC register to add an enable signal for stalling. The key change was minimal:
```systemverilog
else if (en)
    pc <= pc_next;
// else: stall (hold current value)
```

### 2.2 Top-Level Integration

I built the initial `top_pipe.sv` module that instantiated all pipeline components and wired them together. This included:
- All five pipeline stages (IF, ID, EX, MEM, WB)
- Four pipeline registers
- Hazard detection unit and forwarding unit
- PC control logic for branches, jumps, and JALR

**Critical Bug - Register File Timing:**

During testing, Deniz discovered timing issues with register writeback. I had implemented the register file to write on `posedge clk`, which created a race condition—the register file would update at the same time the ID stage was trying to read from it, causing data corruption. Deniz identified this issue and changed it to `negedge clk`, ensuring writes complete before the next cycle's reads. [Commit: 8b3e842](https://github.com/sadir06/Project_Brief/commit/8b3e84254f92aa9bc0ff7e8e50e1e0f8f58fb4c6)

**Missing Signal - funct3 Pipelining:**

In my initial top module implementation, I hardcoded `funct3` as `3'b100` for the data memory module. This broke store operations—while LBU loads worked (funct3=3'b100), SB stores failed because they require funct3=3'b000. Deniz identified this issue and added `funct3` to the pipeline registers, properly propagating it through ID/EX/MEM stages so the actual instruction's funct3 field would reach the memory module. This taught me the importance of carefully tracing which instruction fields each pipeline stage requires, rather than making assumptions about constant values.

Finding out where my designs were failing in Deniz's debugging process was invaluable —while I handled the structural implementation of pipeline registers and initial integration, Deniz's timing analysis and signal propagation insights were critical to getting the pipelined CPU functioning correctly.

---

## 3. Cache-Enabled CPU: Memory Hierarchy Extension

For the cache extension, my responsibility was ensuring the data memory and cache modules properly supported byte-level operations required by the cache controller's refill and writeback mechanisms.

### 3.1 Data Memory Enhancement for Cache Support

The existing data memory module only supported LBU (load byte unsigned) and SB (store byte) operations, which was insufficient for cache line transfers. I extended it to support word operations for cache refills and writebacks:

**Key additions:**
- **LW (Load Word):** Required for cache refills - reading 4-word cache lines from memory
- **SW (Store Word):** Required for cache writebacks - writing dirty cache lines back to memory
- **Little-endian handling:** Proper byte ordering for multi-byte transfers

```systemverilog
3'b010: begin // LW - Load Word (little-endian)
    read_data_o = {ram_array[byte_addr + 3], ram_array[byte_addr + 2],
                   ram_array[byte_addr + 1], ram_array[byte_addr]};
end

3'b010: begin // SW - Store Word (little-endian)
    ram_array[byte_addr]     <= write_data_i[7:0];
    ram_array[byte_addr + 1] <= write_data_i[15:8];
    ram_array[byte_addr + 2] <= write_data_i[23:16];
    ram_array[byte_addr + 3] <= write_data_i[31:24];
end
```

Without these operations, the cache couldn't efficiently transfer entire cache lines (4 words = 16 bytes) between cache and main memory.

### 3.2 Cache Byte Operation Support

I implemented byte-level load and store support within the data cache module to handle sub-word operations correctly:

**Load Data Sizing:**
The cache needed to extract the correct byte from a 32-bit word and zero-extend it for LBU operations:
```systemverilog
if (cpu_funct3 == 3'b100) begin // LBU
    case (addr_offset[1:0])
        2'b00: load_data_sized = {24'b0, hit_data[7:0]};
        2'b01: load_data_sized = {24'b0, hit_data[15:8]};
        2'b10: load_data_sized = {24'b0, hit_data[23:16]};
        2'b11: load_data_sized = {24'b0, hit_data[31:24]};
    endcase
end
```

**Write Data Masking:**
For byte stores (SB), only the target byte should change while preserving the other 3 bytes in the word:
```systemverilog
if (cpu_funct3 == 3'b000) begin // SB
    case (addr_offset[1:0])
        2'b00: write_data_masked = {current_data[31:8],  cpu_wdata[7:0]};
        2'b01: write_data_masked = {current_data[31:16], cpu_wdata[7:0], current_data[7:0]};
        // ... other cases
    endcase
end
```

### 3.3 Cache Controller Debugging and Verification

Working with Deniz on cache verification revealed several timing and state management issues:

**Clock Edge Mismatch:**
I initially implemented the cache FSM on `negedge clk`, but this caused timing conflicts with the memory module which operated on `posedge clk`. The cache would try to read memory data before it was available. We changed the entire cache to `posedge clk` for consistency. [Commit: Co-authored with Deniz]

**Write Miss Handling:**
During a multi-cycle cache refill, the CPU pipeline continues to advance (while stalled), and new instructions enter the decode stage. The original `cpu_addr` and `cpu_wdata` signals would change, causing the cache to lose the original write data for a write miss.

Thus, the initial cache design only handled read misses correctly. For write misses, the cache would refill the line but then lose the write data. We added shadow registers to capture miss information:
```systemverilog
if (cpu_req && !hit) begin
    shadow_addr   <= cpu_addr;   // Capture address
    shadow_we     <= cpu_we;      // Was this a write?
    shadow_wdata  <= cpu_wdata;   // Store write data
    shadow_funct3 <= cpu_funct3;  // Store operation type
end
```

Then in the `C_RESPOND` state, after refill completes, we performed the delayed write:
```systemverilog
C_RESPOND: begin
    if (shadow_we) begin
        // Now that line is valid, perform the write
        data_array[victim_way][shadow_index][shadow_word_offset] <= resp_write_data;
        dirty_array[victim_way][shadow_index] <= 1'b1;
    end
end
```

**LRU Update Timing:**
Initially, the LRU bit wasn't updated after cache refills, causing poor replacement decisions. We added LRU updates at the end of refills to properly track which way was most recently used.

The cache work demonstrated the complexity of memory hierarchy design—proper timing coordination, state management for multi-cycle operations, and careful handling of edge cases like write misses are all critical for correctness.

---

## 4. Complete RV32I Load/Store Instruction Set

After implementing the cache, we needed to extend our processor to support the complete RV32I  instruction set beyond the basic operations initially implemented. I implemented all the load/store instructions.

### 4.1 Control Unit Extension

I extended the control unit to decode all load and store variants:

**Load Operations (5 variants):**
- `LB` / `LH` / `LW`: Signed loads with sign extension
- `LBU` / `LHU`: Unsigned loads with zero extension

**Store Operations (3 variants):**
- `SB` / `SH` / `SW`: Byte, halfword, and word stores

All operations use `ALU_ADD` for address calculation (rs1 + offset) and are differentiated by their `funct3` field. The control unit sets appropriate `ImmSrc`, `ResultSrc`, and memory control signals for each operation.

### 4.2 Data Memory Complete Implementation

I extended the data memory module to handle all load/store sizes with proper sign and zero extension:

**Load Operations:**
```systemverilog
3'b000: begin // LB - Load Byte (sign-extended)
    read_data_o = {{24{ram_array[byte_addr][7]}}, ram_array[byte_addr]};
end

3'b001: begin // LH - Load Halfword (sign-extended, little-endian)
    read_data_o = {{16{ram_array[byte_addr + 1][7]}}, 
                  ram_array[byte_addr + 1], ram_array[byte_addr]};
end

3'b101: begin // LHU - Load Halfword Unsigned
    read_data_o = {16'b0, ram_array[byte_addr + 1], ram_array[byte_addr]};
end
```

**Store Operations:**
```systemverilog
3'b001: begin // SH - Store Halfword (little-endian)
    ram_array[byte_addr]     <= write_data_i[7:0];
    ram_array[byte_addr + 1] <= write_data_i[15:8];
end
```

The key challenge was maintaining little-endian byte ordering across all sizes while properly handling sign extension for signed loads.

### 4.3 Cache Integration for All Instruction Sizes

The cache module required significant updates to handle sub-word operations correctly:

**Load Data Sizing in Cache:**
The cache needed to extract and properly extend the correct bytes based on both the address offset and operation size:
```systemverilog
3'b000: begin // LB - Load Byte (sign-extended)
    case (addr_offset[1:0])
        2'b00: load_data_sized = {{24{hit_data[7]}}, hit_data[7:0]};
        2'b01: load_data_sized = {{24{hit_data[15]}}, hit_data[15:8]};
        2'b10: load_data_sized = {{24{hit_data[23]}}, hit_data[23:16]};
        2'b11: load_data_sized = {{24{hit_data[31]}}, hit_data[31:24]};
    endcase
end

3'b001: begin // LH - Load Halfword (sign-extended)
    case (addr_offset[1])
        1'b0: load_data_sized = {{16{hit_data[15]}}, hit_data[15:0]};
        1'b1: load_data_sized = {{16{hit_data[31]}}, hit_data[31:16]};
    endcase
end
```

**Write Data Masking in Cache:**
For sub-word stores, the cache must preserve unmodified bytes within the 32-bit word:
```systemverilog
3'b001: begin // SH - Store Halfword
    case (addr_offset[1])
        1'b0: write_data_masked = {current_data[31:16], cpu_wdata[15:0]};
        1'b1: write_data_masked = {cpu_wdata[15:0], current_data[15:0]};
    endcase
end
```

This implementation was particularly intricate because it had to work correctly in three contexts:
1. **Hit path:** Immediate cache reads/writes during `C_IDLE`
2. **Writeback path:** Full-word transfers to memory (always uses `funct3 = 3'b010`)
3. **Response path:** Delayed loads/stores after cache miss refill using shadow registers

Implementing the complete instruction set reinforced the importance of understanding how higher-level ISA specifications (RISC-V instruction formats) translate into low-level hardware details (byte extraction, masking, extension logic).

---

## Reflection

This project transformed my understanding of computer architecture from abstract concepts to concrete hardware implementation. Working on the memory subsystem (the foundation that each instruction depends on) taught me that seemingly simple operations like "load a byte" actually require careful orchestration of addressing, byte extraction, extension logic, and timing.

### Technical Growth

The most valuable learning came from debugging. When our initial word-addressable instruction memory failed, Deniz and I spent a lot of time tracing through address calculations before realizing our fundamental misunderstanding of byte vs. word addressing. It was silly we spent so much time since this specific detail was mentioned in the project brief, however, realising this on our own made it more memorable as a learning moment. That moment of clarity—seeing that RISC-V's architectural decisions have specific hardware implications—was transformative. Similarly, discovering the register file timing issue (posedge conflicts) taught me that correct logic isn't enough; timing relationships between components are just as critical.

The cache implementation was particularly challenging. Managing a five-state FSM while coordinating with main memory, handling dirty writebacks, and preserving write data through multi-cycle operations required thinking several cycles ahead. The shadow register solution felt elegant once implemented, but discovering the need for it demonstrated how hardware bugs can be subtle and state-dependent.

### Collaborative Insights

Working with Deniz on debugging was invaluable. I learned that two people examining the same waveform often see different things, sometimes I focused on data values while he noticed timing relationships I'd missed. Having two perspectives accelerated debugging significantly. When I implemented pipeline registers and he added the missing `funct3` signal propagation, I realized that hardware integration requires careful attention to what every downstream stage needs, not just the immediately obvious connections.

The F1 program debugging session, where we discovered the LED blinking issue, taught me about instruction-level visibility. The solution (using a temporary register for atomic updates) seems obvious in retrospect, but discovering it required understanding that hardware executes instructions sequentially, making every intermediate state potentially visible.

### Project Management Reflections

As someone focused on memory systems, I needed to coordinate with all teammates since every component interacts with memory. This taught me the importance of clearly defined interfaces (control signals, timing requirements, data formats). When I changed the data memory interface to support word operations for cache, I had to communicate this to ensure no one's assumptions broke.

It was important that the logic didn't only work but was also correct. 

### Future Improvements

Given more time, I would:

- **Implement write buffers**: Currently, cache writebacks stall the pipeline for 4 cycles. A write buffer would allow the cache to queue dirty evictions and continue serving hits, improving performance.

- **Add memory protection**: Real processors check for misaligned accesses (e.g., loading a word from address 0x103). Adding alignment exception detection would make our processor more robust.

- **Create a memory hierarchy visualizer**: A tool that shows cache state (tags, valid bits, dirty bits, LRU) alongside memory contents would have accelerated debugging significantly.

### Conclusion

This project made computer architecture tangible. I understand now why processors use caches (experiencing the 4-cycle memory latency firsthand), why pipelining is hard (timing hazards are everywhere), and why standards like RISC-V specify byte addressing (to support sub-word operations cleanly).

Most importantly, I learned that hardware design is iterative debugging. Nothing works the first time. The key is systematic verification—testing edge cases, examining waveforms, and maintaining clear communication with teammates. Seeing our processor successfully run the PDF reference program, with its complex memory access patterns operating correctly through our cache hierarchy was incredibly rewarding. It validated weeks of work debugging addressing modes, fixing timing issues, and refining our memory subsystem implementation.
