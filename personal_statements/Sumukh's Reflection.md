# Personal Statement — Sumukh Adiraju

## Contents

- [Overview](#overview)
- [Core Technical Contributions](#core-technical-contributions)
  1. [Single-Cycle Foundations](#1-single-cycle--datapath-foundations)
  2. [Pipelined Execution Stage](#2-pipelined-execution-stage)
  3. [L1 Data Cache Controller](#3-l1-data-cache-controller)
  4. [Full Instruction Set](#4-full-instruction-set)
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

* **Register File:** I implemented the dual-port asynchronous read / single-port synchronous write Register File, ensuring register `x0` was hardwired to zero to meet RISC-V specifications.

* **Top-Level Wiring:** I created the initial `top.sv` module, effectively wiring the Program Counter, Control Unit, and Data Path together to create our first working single-cycle CPU.

---

### 2. Pipelined Execution Stage
Commits - 
https://github.com/sadir06/Project_Brief/tree/e04c9ba1a96598dd20dc57ef96b10c49bcf1793f

https://github.com/sadir06/Project_Brief/tree/68df3b990a9faaf365582f349aaf293eeca79d0f

https://github.com/sadir06/Project_Brief/tree/23fcc3d9d235c4321cd25c924b09c0213aa239d0


The transition to a 5-stage pipeline required a complete re-architecture of the execution logic. I was responsible for the `execute.sv` module, which became the decision-making center of the pipeline.

* **Data Hazard Resolution (Forwarding):** To maximize IPC (Instructions Per Cycle), I avoided simple stalling for Read-After-Write (RAW) hazards. Instead, I implemented a "Forwarding Unit" logic within the Execute stage. I designed 3-way multiplexers (`ForwardAE`/`ForwardBE`) that intelligently select operands from the Memory or Writeback stages if they are more recent than the values in the Register File.

* **Control Flow Handling:** I moved the branch decision logic into the Execute stage to resolve control hazards earlier. I implemented the `cond_trueE` logic to evaluate all branch conditions (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) based on the `Funct3` field and ALU flags. I also had to add flush logic in the memory section for extra handling. (CPU is flushed if the "guess" is wrong)

* **Complex Jump Targets:** I implemented the specialized target calculation for `JALR`, ensuring the target address `(rs1 + imm)` had its least significant bit masked (`& ~1`) to enforce 16-bit instruction alignment, a critical requirement for RISC-V compliance.
 
* **Testing:** As forwarding logic needed to be functional, I created a short test script to check if the forwarding logic would work. 

---

### 3. L1 Data Cache Controller
Commit -
https://github.com/sadir06/Project_Brief/tree/61872e8eebac1d91bda756d8e84f17b8e2946e06

My most significant design contribution was the memory hierarchy. I engineered a **Write-Back, Write-Allocate, 2-Way Set-Associative Cache Controller**.

* **FSM Architecture:** I designed the Finite State Machine (`data_cache.sv`) with five distinct states (`IDLE`, `MISS_SELECT`, `WRITEBACK`, `REFILL`, `RESPOND`) to handle the variable latency of main memory.

* **Replacement Policy:** I implemented a Least Recently Used (LRU) policy using a "flip-bit" strategy per set. This efficiently tracks access patterns and evicts the least useful cache line during a collision.

* **Memory Interface Muxing:** I designed the logic to intercept the CPU's memory requests. During cache misses, the FSM takes control of the main memory interface, using a 2-bit internal counter (`refill_cnt`) to burst-read or write-back 16-byte cache lines automatically.

---

### 4. Full Instruction Set
Commit - 
https://github.com/sadir06/Project_Brief/tree/219c898983f3bf5ef259d9b0c7cdb8bb1d2b2e32

To finalize the processor, I extended the Execute stage (`execute.sv`) to support the complete RV32I instruction set, moving beyond basic arithmetic to handle complex control flow and addressing modes:

- **Comprehensive Branch Logic:** I implemented the full suite of branch comparisons (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) by decoding the `Funct3` field directly in the Execute stage. This allowed the processor to handle signed/unsigned control flow without adding latency in the Decode stage.

- **Absolute Jumps (JALR):** I engineered the specific target calculation logic for `JALR`, which requires masking the least significant bit `(rs1 + imm) & ~1`. This ensures 16-bit alignment compliance, which is critical for the RISC-V specification.

- **AUIPC & LUI Support:** To support position-independent code, I integrated the `AUIPC` instruction by extending the control unit with opcode `OPC_AUIPC = 7'b0010111` and a new `ALUSrcA` control signal. The control unit sets `ALUSrcA = 1'b1` for AUIPC instructions, which propagates through the ID/EX pipeline register to become `ALUSrcAE` in the execute stage. The execute stage uses this signal to select PC as ALU source A via a multiplexer: when `ALUSrcAE` is high, `SrcAE_final = PCE`; otherwise, `SrcAE_final = SrcAE_forwarded` (the normal forwarded rs1 value). With the U-type immediate (extracted from instruction bits [31:12] and shifted left by 12) as ALU source B and `ALUControl = ALU_ADD`, the instruction computes `rd = PC + (imm[31:12] << 12)` in a single cycle. This enables efficient PC-relative address calculations without requiring multiple instructions, which is essential for position-independent code and global offset table (GOT) access patterns.

---

## Key Design Decisions & Challenges

### The "Shadow Address" Stability Solution

**Challenge:** During cache stress testing, we noticed data corruption during refill sequences. I debugged this and realized that while the CPU pipeline was stalled, the address signals coming from the Execute stage were fluctuating, causing the cache to write incoming data to the wrong index.
**Solution:** I introduced a **Shadow Address Register** (`shadow_addr`) inside the cache controller. This register latches the exact faulting address the moment a miss is detected (transitioning from `IDLE` to `MISS_SELECT`). This ensures the FSM operates on a stable address throughout the multi-cycle refill process, regardless of pipeline noise.

### Preventing Infinite Loops in Write-Back

**Challenge:** Initially, my FSM logic would sometimes get stuck in the `WRITEBACK` state or overwrite dirty data incorrectly.
**Solution:** I refined the state transition logic to explicitly check the `Dirty` bit of the *victim* way (determined by LRU) during `MISS_SELECT`. If dirty, the FSM transitions to `WRITEBACK` to save the data; if clean, it skips directly to `REFILL`. This optimization reduced memory traffic and prevented data loss.

### Return Address Continuity

**Challenge:** When testing function calls with `JAL` in the pipeline, the processor would jump correctly but fail to return. I traced this to the return address (`PC+4`) being dropped after the Execute stage.
**Solution:** I coordinated with Lila (who managed pipeline registers) to modify the `ex_mem_reg` interface. We added a dedicated pass-through path for `PCPlus4`. This ensured the return address traveled safely from Execute, through Memory, to Writeback, where it could be correctly written to the link register (`ra`).

### Selection of Cache Replacement Policy (LRU vs. Random Replacement)

**Design Decision:** We debated whether to implement a Least Recently Used (LRU) or a Pseudo-Random replacement policy. Initially, I considered Random replacement to avoid the "thrashing" scenario where a sequential loop (like our F1 light sequence iterating 0x00-0xFF) strictly larger than the cache size would constantly evict the lines needed next, resulting in a 0% hit rate.
**Resolution:** After consulting with lecturers and researching standard cache hierarchies, I determined that for our 2-way set-associative design with typical workload locality, LRU offers superior performance. Random replacement, while simple, risks evicting hot data unpredictably. I proceeded with LRU, confident that our cache capacity was sufficient to hold the working set of our test kernels, providing a deterministic and optimized hit rate.

---

## Future Improvements

With more time, I would focus on architectural upgrades that meaningfully improve IPC (Instructions per Cycle) by reducing control-flow penalties and improving throughput:

* **Dynamic Branch Prediction (BTB):** Our current static “not taken” approach causes a 2-cycle flush on taken branches. Adding a small Branch Target Buffer in the Fetch stage would let the processor jump directly to predicted targets, eliminating the penalty for correctly predicted branches.

* **Dual-Issue Superscalar Design:** To exceed 1 IPC, I would widen the Fetch path to 64 bits and duplicate the Decode/Execute units. With dependency checks in the ID stage, the processor could issue two independent instructions per cycle, improving performance on parallelizable workloads.

* **Non-Blocking Cache with Write Buffering:** Right now, evicting a dirty line stalls the core. A write buffer between L1 and main memory would let the cache offload dirty lines instantly and continue execution while writes complete in the background.

* **Higher Associativity with PLRU:** Moving beyond 2-way associativity would reduce conflict misses. Instead of expensive true LRU tracking, I would use a Pseudo-LRU tree algorithm, which offers most of the benefits of LRU with far lower hardware overhead.

---

## Reflection

This project really deepened my understanding of processor design. The most valuable part for me was getting hands-on with data and control hazards, and learning how to implement forwarding and branch prediction to handle them. I also enjoyed building the 2-way set associative cache. Implementing the TLB with LRU replacement and dirty bits helped connect what I learned in both my instruction architecture and software systems lectures. I even had to approach both lecturers to figure out certain design details (for the LRU cache), which made the whole experience feel very real. Despite the complexity—especially the pipeline timing and FSM debugging—seeing the full processor run with forwarding, branching, and caching was incredibly rewarding. This project reinforced my interest in computer architecture and significantly improved my SystemVerilog skills.

As a team, we worked systematically through each goal. We split tasks clearly, and I learned the importance of coordinating dependencies—especially when I needed Ambre’s part finished before I could start mine. To manage this, I communicated timelines early and used the waiting time to research and plan my implementation. Once she finished, I fetched her branch and layered my changes on top.

As the repo master, I set up a clean Git structure with a single main branch and multiple feature branches (one for each of our implementations). I also created extra branches for each milestone (e.g., single-cycle CPU, pipelined CPU) to make future testing and rollback easy. Early on, I helped teammates with Git basics like creating PRs and reviewing merges. We made sure that every PR was reviewed by the whole team before merging to main.

Overall, this project was an invaluable introduction to hardware design. I gained a much deeper understanding of how modern CPUs handle instructions, especially with pipelining and caching. I also strengthened my Git workflow skills and learned what it feels like to work in an engineering team shipping real features. It was challenging at times, but figuring out the implementation details made it genuinely rewarding.

