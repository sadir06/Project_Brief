# Personal Statement — Sumukh Adiraju

## Contents

- [Overview](#overview)
- [Core Technical Contributions](#core-technical-contributions)
  1. [Single-Cycle Foundations](#1-single-cycle--datapath-foundations)
  2. [Pipelined Execution Stage](#2-pipelined-execution-stage)
  3. [L1 Data Cache Controller](#3-l1-data-cache-controller)
  4. [Full Instruction Set](#4-full-instruction-set)
  5. [Stretch Goal: Surprise Me! (Branch Target Buffer)](#5-stretch-goal-surprise-me-branch-target-buffer)
- [Key Design Decisions & Challenges](#key-design-decisions--challenges)
  1. [Shadow Address Instability](#the-shadow-address-stability-solution)
  2. [Write-Back Loop Bug](#preventing-infinite-loops-in-write-back)
  3. [Return Address Loss (JAL/JALR)](#return-address-continuity)
  4. [Cache Replacement Policy](#selection-of-cache-replacement-policy-lru-vs-random-replacement)
- [Future Improvements](#future-improvements)
- [Team Workflow](#team-workflow)
- [Reflection](#reflection)

---

## Overview

As the lead architect for the Execution and Memory Control logic, I handled the core computational components of our RISC-V processor across all stages—from the initial single-cycle design to the fully pipelined, cached version.

I implemented the ALU and Register File, built the Execute stage for the 5-stage pipeline with forwarding for hazard resolution, and designed the L1 Data Cache Controller as a 2-way set-associative write-back FSM. I also extended support for the full RV32I instruction set, including all branch and jump types.

This role was especially interesting because it brought together concepts from both my Instruction Architecture and Software Systems modules. I had to explore material from both to implement my designs effectively.

---

## Key Technical Contributions

### 1. Single-Cycle & Datapath Foundations
Commit - 
https://github.com/sadir06/Project_Brief/tree/78f420b7d648ada42433ad4b7867d5e82fcd9084

My work began with building the fundamental hardware blocks that define the RV32I architecture.

* **ALU Design:** I designed the 32-bit ALU to handle the initial subset of arithmetic operations (`ADD`, `SUB`) and later extended it to support the full instruction set. This included implementing logical operations (`XOR`, `OR`, `AND`) and robust shift logic (`SLL`, `SRL`, `SRA`), ensuring arithmetic shifts correctly preserved the sign bit using SystemVerilog's `>>>` operator. (This final part was added later on when we added the "Full Instruction Set")

The ALU implementation handles all RV32I operations, with arithmetic shift being particularly important for correct sign extension:

```systemverilog
// shifts: RV32I uses only lower 5 bits of shift amount
ALU_SLL:    ALUResult = SrcA <<  SrcB[4:0];
ALU_SRL:    ALUResult = SrcA >>  SrcB[4:0];
ALU_SRA:    ALUResult = $signed(SrcA) >>> SrcB[4:0];
```

The `>>>` operator performs an arithmetic right shift, preserving the sign bit by replicating the most significant bit, which is essential for correctly implementing the `SRA` instruction. This distinguishes it from logical shift (`>>`) which fills with zeros.

* **Register File:** I implemented the dual-port asynchronous read / single-port synchronous write Register File, ensuring register `x0` was hardwired to zero to meet RISC-V specifications.

* **Top-Level Wiring:** I created the initial `top.sv` module, effectively wiring the Program Counter, Control Unit, and Data Path together to create our first working single-cycle CPU.

---

### 2. Pipelined Execution Stage
Commits - 
https://github.com/sadir06/Project_Brief/tree/e04c9ba1a96598dd20dc57ef96b10c49bcf1793f

https://github.com/sadir06/Project_Brief/tree/68df3b990a9faaf365582f349aaf293eeca79d0f

https://github.com/sadir06/Project_Brief/tree/23fcc3d9d235c4321cd25c924b09c0213aa239d0


The transition to a 5-stage pipeline required a complete re-architecture of the execution logic. I was responsible for the `execute.sv` module, which became the decision-making center of the pipeline.

* **Data Hazard Resolution (Forwarding):** To maximize IPC (Instructions Per Cycle), I avoided simple stalling for Read-After-Write (RAW) hazards. Instead, I implemented forwarding logic within the Execute stage that checks if the source registers (`rs1E`, `rs2E`) match destination registers in the MEM or WB stages. I designed 3-way multiplexers (`ForwardAE`/`ForwardBE`) that intelligently select operands from the Memory stage (ALU result), Writeback stage (either ALU result or memory data via `ResultSrc`), or the normal register file output. The forwarding unit compares register addresses and sets select signals that prioritize more recent data, eliminating most data hazard stalls without adding pipeline bubbles.

The forwarding unit logic (`forward_unit.sv`) determines which source to forward:

```systemverilog
// Forward for rs1E (ALU srcA)
if (RegWriteM && (rdM != 5'd0) && (rdM == rs1E)) begin
    ForwardAE = 2'b10;           // from EX/MEM (ALUResultM)
end else if (RegWriteW && (rdW != 5'd0) && (rdW == rs1E)) begin
    ForwardAE = 2'b01;           // from MEM/WB (WriteDataW)
end
```

The execute stage then uses these control signals to select the forwarded data:

```systemverilog
case (ForwardAE)
    2'b00: SrcAE_forwarded = rs1_dataE;
    2'b01: SrcAE_forwarded = ResultW;      // from WB
    2'b10: SrcAE_forwarded = ALUResultM;   // from MEM
    default: SrcAE_forwarded = rs1_dataE;
endcase
```

This ensures that instructions always receive the most recent value of their source operands, even if those values haven't yet been written back to the register file.

* **Control Flow Handling:** I moved the branch decision logic into the Execute stage to resolve control hazards earlier. I implemented the `cond_trueE` logic to evaluate all branch conditions (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) based on the `Funct3` field and ALU flags. I also had to add flush logic in the memory section for extra handling. (CPU is flushed if the "guess" is wrong)

The branch condition evaluation uses the ALU's comparison results and zero flag:

```systemverilog
always_comb begin
    case (funct3E)
        3'b000: cond_trueE = ZeroE;           // BEQ
        3'b001: cond_trueE = ~ZeroE;          // BNE
        3'b100: cond_trueE = ALUResultE[0];   // BLT  (SLT result)
        3'b101: cond_trueE = ~ALUResultE[0];  // BGE
        3'b110: cond_trueE = ALUResultE[0];   // BLTU (SLTU result)
        3'b111: cond_trueE = ~ALUResultE[0];  // BGEU
        default: cond_trueE = 1'b0;
    endcase
end
```

For signed/unsigned comparisons, the ALU performs `SLT` or `SLTU` operations (resulting in 0 or 1), and the branch condition checks the least significant bit of the ALU result to determine if the comparison was true.

* **Complex Jump Targets:** I implemented the specialized target calculation for `JALR`, ensuring the target address `(rs1 + imm)` had its least significant bit masked (`& ~1`) to enforce 16-bit instruction alignment, a critical requirement for RISC-V compliance.
 
* **Testing:** As forwarding logic needed to be functional, I created a short test script to check if the forwarding logic would work. 

---

### 3. L1 Data Cache Controller
Commit -
https://github.com/sadir06/Project_Brief/tree/61872e8eebac1d91bda756d8e84f17b8e2946e06

My most significant design contribution was the memory hierarchy. I engineered a **Write-Back, Write-Allocate, 2-Way Set-Associative Cache Controller**.

* **FSM Architecture:** I designed the Finite State Machine (`data_cache.sv`) with five distinct states (`IDLE`, `MISS_SELECT`, `WRITEBACK`, `REFILL`, `RESPOND`) to handle the variable latency of main memory. The state machine begins in `IDLE`, waiting for CPU requests. On a cache miss, it transitions to `MISS_SELECT` to determine the victim way using the LRU bit. If the victim is dirty, the FSM enters `WRITEBACK` to save the evicted line before refilling. The `REFILL` state performs a 4-word burst read from memory using an internal counter, and finally `RESPOND` completes the operation and returns control to the CPU.

* **Replacement Policy:** I implemented a Least Recently Used (LRU) policy using a "flip-bit" strategy per set. Each 2-way set has a single LRU bit that tracks which way was accessed most recently. On access, the LRU bit flips to indicate the other way as least recently used. During eviction, the LRU bit directly selects the victim way. This efficiently tracks access patterns and evicts the least useful cache line during a collision, requiring only 1 bit per set (128 bits total) rather than the more complex true-LRU tracking.

* **Memory Interface Muxing:** I designed the logic to intercept the CPU's memory requests. During cache misses, the FSM takes control of the main memory interface, using a 2-bit internal counter (`refill_cnt`) to burst-read or write-back 16-byte cache lines automatically. The counter sequences through addresses `{index, offset[3:2]}` to fetch or write all four words in the cache line, with the state machine handling address generation and memory handshaking transparently to the CPU pipeline.

---

### 4. Full Instruction Set
Commit - 
https://github.com/sadir06/Project_Brief/tree/219c898983f3bf5ef259d9b0c7cdb8bb1d2b2e32

To finalize the processor, I extended the Execute stage (`execute.sv`) to support the complete RV32I instruction set, moving beyond basic arithmetic to handle complex control flow and addressing modes:

- **Comprehensive Branch Logic:** I implemented the full suite of branch comparisons (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) by decoding the `Funct3` field directly in the Execute stage. This allowed the processor to handle signed/unsigned control flow without adding latency in the Decode stage.

- **Absolute Jumps (JALR):** I engineered the specific target calculation logic for `JALR`, which requires masking the least significant bit `(rs1 + imm) & ~1`. This ensures 16-bit alignment compliance, which is critical for the RISC-V specification.

- **AUIPC & LUI Support:** To support position-independent code, I integrated the `AUIPC` instruction by extending the control unit with opcode `OPC_AUIPC = 7'b0010111` and a new `ALUSrcA` control signal. The control unit sets `ALUSrcA = 1'b1` for AUIPC instructions, which propagates through the ID/EX pipeline register to become `ALUSrcAE` in the execute stage. The execute stage uses this signal to select PC as ALU source A via a multiplexer: when `ALUSrcAE` is high, `SrcAE_final = PCE`; otherwise, `SrcAE_final = SrcAE_forwarded` (the normal forwarded rs1 value). With the U-type immediate (extracted from instruction bits [31:12] and shifted left by 12) as ALU source B and `ALUControl = ALU_ADD`, the instruction computes `rd = PC + (imm[31:12] << 12)` in a single cycle. This enables efficient PC-relative address calculations without requiring multiple instructions, which is essential for position-independent code and global offset table (GOT) access patterns.

The PC selection for AUIPC is implemented in the execute stage:

```systemverilog
// Final ALU operands
// For AUIPC: use PC as source A, otherwise use forwarded rs1
assign SrcAE_final = (ALUSrcAE) ? PCE : SrcAE_forwarded;
// For immediate instructions: use immediate as source B, otherwise use forwarded rs2
assign SrcBE_final = (ALUSrcE) ? ImmExtE : SrcBE_forwarded;
```

This multiplexer allows AUIPC to use the current PC value (in the EX stage) as the ALU's source A, while other instructions use the normal forwarded register value. Combined with the U-type immediate (already shifted left by 12 in the immediate generator) as source B, this computes the PC-relative address in a single cycle.

---

### 5. Stretch Goal: Surprise Me! (Branch Target Buffer - Prototype)

As a performance enhancement beyond the baseline requirements, I attempted to implement a **Branch Target Buffer (BTB)** for dynamic branch prediction. This would have significantly reduced control hazard penalties by allowing the pipeline to speculatively fetch from predicted branch targets. However, due to implementation challenges and time constraints, we were unable to fully complete the BTB integration. The BTB was removed from the final version to ensure all baseline functionality remained fully working and verified. A prototype implementation can be found in the `Branch Prediction Prototype` branch for reference.

**BTB Architecture:** I designed a 64-entry direct-mapped BTB (`btb.sv`) that stores predicted branch targets indexed by PC bits [7:2], with tag matching on PC[31:8] to verify correct entry identification. Each BTB entry contains a valid bit, a 1-bit prediction (taken/not taken), a tag field, and the predicted target address. The direct-mapped design provides a good balance between hardware complexity and prediction accuracy for our workload.

**Pipeline Integration:** The BTB lookup occurs in the IF stage, where the current PC is used to index into the BTB array. If a hit occurs (`btb_hitF = 1`), the predicted target (`btb_targetF`) is immediately used as `pc_next`, allowing the pipeline to fetch from the predicted address without waiting for branch resolution. The BTB prediction signals (`btb_hit` and `btb_target`) are passed through the IF/ID and ID/EX pipeline registers to reach the EX stage, where they can be compared against the actual branch outcome.

**Misprediction Handling:** In the EX stage, I implemented misprediction detection logic that compares the actual branch result (`branch_takenE`) and target (`PCTargetE`) against the prediction. A misprediction occurs when: (1) the branch was predicted taken but not taken, (2) the branch was predicted not taken but taken, or (3) the predicted target doesn't match the actual target. The hazard unit was modified to only flush the pipeline on mispredictions (`branch_mispredictE`), not on all taken branches. This means correctly predicted branches incur zero penalty cycles, while mispredictions still incur the standard 2-cycle flush penalty.

**Dynamic Update Mechanism:** When a branch resolves in the EX stage, the BTB is updated based on the actual outcome. If the branch was taken, the BTB stores the target address and sets the prediction bit to taken for future executions. If the branch was not taken, the prediction bit is updated to not taken while keeping the entry valid. This adaptive learning allows the BTB to improve prediction accuracy over time as it observes branch behavior patterns.

**Performance Impact:** This implementation provides significant performance improvements on branch-heavy workloads. Correctly predicted branches eliminate the previous 2-cycle penalty entirely, while the misprediction rate depends on branch predictability. For typical workloads with good branch locality, this can provide 10-30% performance improvement by reducing pipeline stalls.

**Implementation Challenges:** During implementation and testing, we encountered issues with the BTB integration that caused several test cases to fail. The misprediction detection logic and the interaction between BTB predictions and EX stage branch resolution proved more complex than initially anticipated. Despite significant debugging effort, we were unable to fully resolve all issues within the project timeline, leading to the decision to remove it from the final version.

---

## Key Design Decisions & Challenges

### The "Shadow Address" Stability Solution

**Challenge:** During cache stress testing with Deniz, we noticed data corruption during refill sequences. I debugged this using GTKWave waveform analysis and discovered that while the CPU pipeline was stalled (the hazard unit correctly prevented PC advancement), the address signals coming from the Execute stage (`cpu_addr`) were still fluctuating due to forwarding logic and intermediate pipeline states. This caused the cache to write incoming refill data to the wrong index, corrupting unrelated cache lines.
**Solution:** I introduced a **Shadow Address Register** (`shadow_addr`) inside the cache controller that latches the exact faulting address the moment a miss is detected (during the transition from `IDLE` to `MISS_SELECT`). This register stores a stable copy of the address throughout the entire multi-cycle refill process. All subsequent cache operations (tag/index/offset extraction, way selection, memory burst addressing) use `shadow_addr` instead of `cpu_addr`. This ensures the FSM operates on a stable address throughout the multi-cycle refill process, regardless of pipeline noise or forwarding changes. Working with Deniz on this debugging session highlighted the importance of understanding pipeline behavior even during stalls.

The shadow address capture occurs in the `C_IDLE` state when a miss is detected:

```systemverilog
C_IDLE: begin
    if (cpu_req && !hit) begin
        // Start of the logic for a miss - capture miss information
        shadow_addr   <= cpu_addr; // Capture the address that caused the miss
        shadow_we     <= cpu_we;
        shadow_wdata  <= cpu_wdata;
        shadow_funct3 <= cpu_funct3;
    end
    // ...
end
```

All subsequent operations during refill use `shadow_addr` instead of `cpu_addr`:

```systemverilog
assign shadow_index  = shadow_addr[OFFSET_BITS +: INDEX_BITS];
assign shadow_tag    = shadow_addr[31 -: TAG_BITS];
assign shadow_offset = shadow_addr[OFFSET_BITS-1:0];
```

### Preventing Infinite Loops in Write-Back

**Challenge:** During initial cache testing, my FSM logic would sometimes get stuck in the `WRITEBACK` state, causing the processor to hang. Additionally, the cache was incorrectly overwriting dirty data during evictions. Through waveform analysis, I discovered the state transition logic wasn't properly checking the dirty bit of the victim way before deciding whether to writeback.
**Solution:** I refined the state transition logic in `MISS_SELECT` to explicitly check the `Dirty` bit of the victim way (determined by the LRU bit) before transitioning. If dirty, the FSM transitions to `WRITEBACK` to save the data; if clean, it skips directly to `REFILL`. This optimization reduced unnecessary memory traffic by skipping writebacks for clean lines, and more importantly, prevented data loss by ensuring dirty lines are always saved before eviction. The fix also eliminated the infinite loop by ensuring proper state transitions.

The state transition logic now properly checks the dirty bit:

```systemverilog
C_MISS_SELECT: begin
    // Check if the chosen victim (via LRU) is dirty
    if (valid_array[lru_bit[shadow_index]][shadow_index] &&
        dirty_array[lru_bit[shadow_index]][shadow_index]) begin
        next_state = C_WRITEBACK; // Need to write back first
    end
    else begin
        next_state = C_REFILL; // Clean, can go straight to refill
    end
end
```

This ensures that dirty lines are always written back before being overwritten, preventing data loss while also optimizing performance by skipping unnecessary writebacks for clean lines.

### Return Address Continuity

**Challenge:** When testing function calls with `JAL` in the pipeline, the processor would jump correctly but fail to return. I traced this to the return address (`PC+4`) being dropped after the Execute stage.
**Solution:** I coordinated with Lila (who managed pipeline registers) to modify the `ex_mem_reg` interface. We added a dedicated pass-through path for `PCPlus4`. This ensured the return address traveled safely from Execute, through Memory, to Writeback, where it could be correctly written to the link register (`ra`).

### Selection of Cache Replacement Policy (LRU vs. Random Replacement)

**Design Decision:** We debated whether to implement a Least Recently Used (LRU) or a Pseudo-Random replacement policy. Initially, I considered Random replacement to avoid the "thrashing" scenario where a sequential loop (like our F1 light sequence iterating 0x00-0xFF) strictly larger than the cache size would constantly evict the lines needed next, resulting in a 0% hit rate.
**Resolution:** After consulting with lecturers and researching standard cache hierarchies, I determined that for our 2-way set-associative design with typical workload locality, LRU offers superior performance. Random replacement, while simple, risks evicting hot data unpredictably. I proceeded with LRU, confident that our cache capacity was sufficient to hold the working set of our test kernels, providing a deterministic and optimized hit rate.

---

## Future Improvements

With more time, I would focus on architectural upgrades that meaningfully improve IPC (Instructions per Cycle) and overall system performance:

* **Enhanced Branch Prediction:** While our current BTB provides good performance, we could improve prediction accuracy by implementing a 2-bit saturating counter scheme (Pattern History Table) or adding a Return Address Stack (RAS) for better function return prediction. A larger BTB with higher associativity could also reduce aliasing conflicts.

* **Dual-Issue Superscalar Design:** To exceed 1 IPC, I would widen the Fetch path to 64 bits and duplicate the Decode/Execute units. With dependency checks in the ID stage, the processor could issue two independent instructions per cycle, improving performance on parallelizable workloads.

* **Non-Blocking Cache with Write Buffering:** Right now, evicting a dirty line stalls the core. A write buffer between L1 and main memory would let the cache offload dirty lines instantly and continue execution while writes complete in the background.

* **Higher Associativity with PLRU:** Moving beyond 2-way associativity would reduce conflict misses. Instead of expensive true LRU tracking, I would use a Pseudo-LRU tree algorithm, which offers most of the benefits of LRU with far lower hardware overhead.

---

## Reflection

This project transformed my understanding of processor design from theoretical concepts to concrete hardware implementation. The most valuable part for me was getting hands-on experience with data and control hazards, learning how to implement forwarding and branch prediction to handle them efficiently. Building the 2-way set-associative cache was particularly engaging—implementing the FSM with LRU replacement and dirty bit tracking helped connect concepts from both my Instruction Architecture and Software Systems modules. I even approached both lecturers to clarify certain design details (particularly the LRU flip-bit strategy), which made the whole experience feel authentic and professionally relevant.

### Technical Growth

The cache implementation was my most significant learning experience. Debugging the shadow address issue with Deniz taught me that even when the pipeline is "stalled," signals can still fluctuate due to forwarding and intermediate states. Using GTKWave to trace through multi-cycle cache operations revealed timing relationships I hadn't fully appreciated. The writeback loop bug taught me the importance of exhaustive state machine testing—every state transition path must be verified.

Implementing the forwarding unit required careful understanding of pipeline timing. Initially, I had bugs where forwarding wasn't working correctly because I wasn't checking the `RegWrite` signals in MEM and WB stages (disabled instructions shouldn't forward). This taught me that control signals are just as important as data signals for correctness.

Attempting to add the Branch Target Buffer as a stretch goal was particularly educational—it showed me how modern processors achieve high performance through speculative execution. While we ultimately had to remove it from the final version due to incomplete implementation, the experience of designing the BTB lookup, integrating it into the fetch stage, passing prediction signals through the pipeline registers, and implementing misprediction detection gave me valuable insights into the challenges of dynamic branch prediction. The prototype implementation can be found in the `Branch Prediction Prototype` branch.

### Collaborative Insights

Working with Deniz on cache debugging sessions was invaluable. His waveform analysis skills complemented my FSM design knowledge—he could spot timing issues I missed, while I could trace the state machine logic. When we discovered the address instability problem, we spent several hours in GTKWave before identifying that the Execute stage address signals were changing during stalls. This collaborative debugging approach was far more effective than working in isolation.

Coordinating with Lila on memory interface changes when extending the cache was crucial. I had to ensure that my cache controller's byte-level operation support matched her data memory module's capabilities. This taught me the importance of clearly defined interfaces and communicating changes early.

### Lessons Learned

The most important lesson was that correct logic isn't enough—timing relationships are equally critical. The pipeline register timing issue (negedge vs posedge) that Deniz discovered in my register file design reinforced this. I had implemented logically correct code, but the clock edge choice created race conditions.

I also learned the value of systematic verification. Creating test scripts to verify forwarding worked before integrating it into the full pipeline saved significant debugging time later. Testing each component in isolation, then integrating incrementally, proved far more effective than trying to debug the entire system at once.

### Conclusion

Overall, this project was an invaluable introduction to hardware design. I gained a much deeper understanding of how modern CPUs handle instructions, especially with pipelining and caching. Implementing the execute stage, cache controller, and BTB significantly improved my SystemVerilog skills and gave me confidence in designing complex hardware systems. As the repo master, I strengthened my Git workflow skills and learned what it feels like to work in an engineering team shipping real features.

Despite the challenges—especially pipeline timing issues and FSM debugging—seeing the full processor successfully run all tests with forwarding, branch prediction, and caching was incredibly rewarding. The debugging sessions, though sometimes frustrating, were where the most learning happened. This project reinforced my interest in computer architecture and demonstrated that hardware design requires both careful planning and iterative problem-solving.

