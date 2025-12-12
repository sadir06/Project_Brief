# Personal Statement - Ambre Carrier


## Table of Contents
- [Overview](#overview)
- [Single-Cycle RV32I Design](#single-cycle-rv32i-design)
- [Stretch Goal 1: Pipelined RV32I Design](#stretch-goal-1-pipelined-rv32i-design)
- [Stretch Goal 2: Adding Data Memory Cache](#stretch-goal-2-adding-data-memory-cache)
- [Stretch Goal 3: Full RV32I Design](#stretch-goal-3-full-rv32i-design)
    - [Final Fixes Required to Pass All Pipelined RV32I Tests:](#final-fixes-required-to-pass-all-pipelined-rv32i-tests)
- [Extension: 2-Wide Superscalar Front-End Prototype](#extension-2-wide-superscalar-front-end-prototype)
- [Design decisions](#design-decisions)
- [Mistakes and how I or the team fixed them](#mistakes-and-how-i-or-the-team-fixed-them)
- [What I learned](#what-i-learned)
- [Reflection](#reflection)
- [What I would do differently with more time](#what-i-would-do-differently-with-more-time)
- [Appendix](#appendix)
    - [Replacement Policy: Justification for Using LRU](#replacement-policy-justification-for-using-lru)
    - [Observation: Why the Pipelined CPU Appears Slower in Simulation](#observation-why-the-pipelined-cpu-appears-slower-in-simulation)


---
## Overview

#### Across the project I contributed to several core architectural components of our RV32I processor amongst the single-cycle CPU, the pipelined design, the data cache, full RV32I ISA support, and attempted a 2-Wide Superscalar front-end prototype as an extension.

## Single-Cycle RV32I Design

**Modules authored:**  
`control_unit.sv`, `extend.sv`, `pc_reg.sv`, branch condition logic (Diagram 1\)

**Key commits:**

* [https://github.com/EIE2-IAC-Labs/Project\_Brief/commit/93a72b4178bc2a3b6c9de97ddb596a2cc30427c5](https://github.com/EIE2-IAC-Labs/Project_Brief/commit/93a72b4178bc2a3b6c9de97ddb596a2cc30427c5)  
* [https://github.com/EIE2-IAC-Labs/Project\_Brief/commit/cf7143ee081abfaa137075884f5581764f9d4577](https://github.com/EIE2-IAC-Labs/Project_Brief/commit/cf7143ee081abfaa137075884f5581764f9d4577)  
* [https://github.com/EIE2-IAC-Labs/Project\_Brief/commit/bff6d2646b5cd1b8032bbcdcd190e5e4fabd08dc](https://github.com/EIE2-IAC-Labs/Project_Brief/commit/bff6d2646b5cd1b8032bbcdcd190e5e4fabd08dc)

### 1. Control Unit Design

I implemented the full RV32I control path by designing a combinational **control\_unit.sv** module to decode each instruction’s opcode/funct fields and generate the control signals that drive every part of the datapath.

Instruction classes supported: R-type, I-type arithmetic, Load, Store, Branch, JAL / JALR, LUI / AUIPC

**![](images/1.png)**  
(taken from lecture slides)

### 2. Immediate Generator

I designed and implemented the extend.sv module to handle immediate encodings which require reconstructing scattered fields before sign-extension.

My implementation reconstructs:

- B-type branch (rearranging and sign-extending non-contiguous immediate)  
- J-type immediate (shifted and sign-extended)  
- U-type immediate  
- Standard I- and S-type

I implemented an ImmSrc-driven immediate decoder that extracts sign bits to then correctly re-assembles scattered B- and J-type immediate fields whilst handling sign-extension.

### 3. Program Counter Behaviour

I developed the PC update mechanism for the single-cycle processor (in pc\_reg.sv). This module determines the address of the next instruction on every clock cycle, intentionally simple to later reuse it unchanged in pipelined and cached designs:

- Sequential execution: PC \+ 4  
- Branch and JAL instructions: PC \+ immediate  
- JALR instructions: (rs1 \+ imm) & \~1

On reset, the PC loads the instruction memory base address 0xBFC0\_0000. 

### 4. Branch Condition Logic

I also implemented the basic branch semantics tied to the ALU flags, coordinated with Sumukh’s ALU implementation: BEQ branch if Zero \= 1, BNE branch if Zero \= 0 and BGEU branch based on an unsigned SLTU result.


### 5. Summary

My work in this section of the project established the single-cycle CPU’s full control behaviour and served as architectural foundation on which the rest of my teammates built the datapath, and that we later reused for the pipelined and cached designs.

![](images/2.png)

Diagram 1


## Stretch Goal 1: Pipelined RV32I Design

To transform our working single-cycle RV32I processor into a fully pipelined 5-stage design, I implemented the control-path behaviour required for pipelining: stage-partitioned decode logic, forwarding, load-use and branch hazard handling, PC update and flush/stall behaviour, and the bubble semantics for correct execution. (See Diagram 2)

**Modules authored:**  
 `hazard_unit.sv`, `forward_unit.sv`, pipeline control behaviour inside  
 `if_id_reg.sv`, `id_ex_reg.sv`, `exe_mem_reg.sv`, `mem_wb_reg.sv`, and PC logic in `top_pipelined.sv`.

**Key commit evidence:** [https://github.com/sadir06/Project\_Brief/pull/4/commits/930a6b7149615257b044adb26cef792a92e8d165](https://github.com/sadir06/Project_Brief/pull/4/commits/930a6b7149615257b044adb26cef792a92e8d165)

### 1. Pipeline control

Our pipelined RV32I processor follows a 5-stage structure (IF, ID, EX, MEM, WB) based on Harris & Harris seen in lectures. 

The single-cycle control signals are still generated in Decode (ID) but are now partitioned into EX, MEM and WB and carried through the pipeline registers.

### 2. Control signal, partitioning by stage

Our control\_unit module is unchanged from the single-cycle design, with MemRead added to distinguish loads now.

On each clock cycle, the ID/EX pipeline register captures the control signals which then propagate to EX/MEM and MEM/WB.

When flushing, a pipeline register forces the control bits to zero but leaves data fields as don’t-cares.

### 3. Data forwarding

To resolve most RAW data hazards without stalling, I implemented an EX-stage forwarding unit that compares EX-stage source registers with destination registers in MEM and WB and produces:

- 00 : use register values from ID/EX  
- 10 : forward from EX/MEM  
- 01 : forward from MEM/WB

The EX-stage ALU operand muxes use these signals to choose between the original register file outputs and forwarded results. 

### 4. Load–use hazard detection and stalling

As seen during lectures, forwarding cannot resolve the load-use hazard, where a load instruction is immediately followed by an instruction that uses its result, for example:

lbu x1, 0(x2)      \# in EX/MEM  
add x3, x1, x4     \# in ID/EX (next cycle)

The loaded data is only available at the end of the MEM stage, but the dependent instruction needs it at the beginning of EX. 

To solve this issue our hazard unit detects:

``` verilog
if (MemReadE && (rdE != 5'd0) &&
   ((rdE == rs1D) || (rdE == rs2D))) begin
    load_use_hazard = 1'b1;
end
```


When true:

- PCWrite \= 0 → freeze PC  
- IF\_ID\_Write \= 0 → stall IF/ID  
- ID\_EX\_Flush \= 1 → insert bubble in EX  
- IF\_ID\_Flush \= 1 → inject NOP

Now the dependent instruction waits one cycle in ID, while a NOP moves through EX, giving the load time to complete.

**PC update and control hazards**

In my design choices, branches and jumps are resolved in EX. On a taken branch, JAL, or JALR, the hazard unit asserts:

- IF\_ID\_Flush \= 1 → convert the instruction in ID into NOP  
- ID\_EX\_Flush \= 1 → convert EX instruction into bubble

and in top\_pipelined.sv:

- PCPlus4E \= pcE \+ 4  
- PCTargetE \= pcE \+ ImmExtE (branch/JAL target)  
- PCJalrE \= (ALUResultE & 32'hFFFF\_FFFE) (JALR target)

the PCWrite signal then selects whether to advance the PC or hold it (during load–use stalls)

![](images/3.png)

Diagram 2

## Stretch Goal 2: Adding Data Memory Cache

Next, with my teammates, we designed and implemented a 4 KiB, 2-way set-associative write-back data cache placed between the MEM stage of our pipelined RV32I and our data\_mem module. 

Initially I wrote a  “pass-through” cache wrapper that decodes addresses and generates a stall, but did not yet store or refill any lines. My initial contributions:

- definition of the cache (4 KiB, 2-way, 16-byte lines)  
- address breakdown into tag / index / offset  
- simple hit detection  
- forwarded data directly from data\_mem  
- load-size handling (LBU/LW)  
- a first draft of the miss-handling FSM and stall interface

At that stage the cache still behaved as a pass-through but it already provided correct hit detection, byte extraction and CPU signaling. Sumukh and Lila later extended my work into a fully functional write-back cache.

**Modules authored:**  
`data_cache.sv` (architectural scaffold: address decomposition, metadata arrays, hit logic, load-size logic, LRU, stall interface)  
Integration into `top_pipelined.sv` (I replaced the direct data\_mem instance with data\_cache) and `hazard_unit.sv (`I added a CacheStall input as a highest priority stall so that a miss freezes IF/ID without flushing the pipeline).

**Key commits:**

* [https://github.com/sadir06/Project\_Brief/pull/7/commits/ff1066ca6e34bac1d75a127f2da48eee5109abfa](https://github.com/sadir06/Project_Brief/pull/7/commits/ff1066ca6e34bac1d75a127f2da48eee5109abfa)  
* [https://github.com/sadir06/Project\_Brief/pull/7/commits/2b7123bf651888aa65247296a971ef8287929a99](https://github.com/sadir06/Project_Brief/pull/7/commits/2b7123bf651888aa65247296a971ef8287929a99)

### 1. Cache organisation and address breakdown

Our cache configuration:

- Total capacity: CACHE\_BYTES \= 4096  
- Line size: LINE\_BYTES \= 16 bytes (4× 32-bit words)  
- Associativity: WAYS \= 2 (2-way set-associative)  
- Number of sets: 4096 / (16 × 2\) \= 128

Each 32-bit byte address is split into tag, index, and offset fields:

![](images/4.png)

For each way and set the cache stores: tag bits, valid flag, dirty flag, four 32-bit words and implements the replacement policy.

The cache checks both ways in the selected set:

``` verilog
always_comb begin
    hit_way0 = valid_array[0][addr_index] &&
               (tag_array[0][addr_index] == addr_tag);

    hit_way1 = valid_array[1][addr_index] &&
               (tag_array[1][addr_index] == addr_tag);

    hit = hit_way0 | hit_way1;
end
```

In my design hit detection compares tag+valid for both ways and selects the word using word\_offset. This mechanism was fully implemented in my initial version and allowed us to validate address mapping before adding miss handling (data\_cache could tell “hit or miss” when miss handling wasn’t done yet).

![](images/5.png)

Diagram 3

### 2. Load/store size handling

I implemented the load-size logic supporting:

- LBU (funct3 \= 3'b100)  
- LW (funct3 \= 3'b010)  
- SB (funct3 \= 3'b000)  
- SW (funct3 \= 3'b010) for cache write-back

For loads, I implemented a sizing block that converts the 32-bit hit\_data into either a full word or a zero-extended byte:

``` verilog
if (cpu_funct3 == 3'b100) begin  // LBU
    case (addr_offset[1:0])
        2'b00: load_data_sized = {24'b0, hit_data[7:0]};
        2'b01: load_data_sized = {24'b0, hit_data[15:8]};
        2'b10: load_data_sized = {24'b0, hit_data[23:16]};
        2'b11: load_data_sized = {24'b0, hit_data[31:24]};
    endcase
end else begin
    load_data_sized = hit_data;
end

```

For stores, my teammates extended my byte-masking logic to fully support SB and SW. In parallel, we upgraded data\_mem.sv to support correct little-endian byte/word accesses needed for refills and write-backs.

### 3. Replacement policy and miss handling FSM

For replacement policy we agreed on using LRU method (see appendix for justification) with single bit per sheet:

- lru\_bit\[set\] \= 0 means way 0 is least recently used  
- lru\_bit\[set\] \= 1 means way 1 is least recently used.

On every hit the LRU bit is flipped so that the other way becomes the victim next time:

``` verilog
if (cpu_req && hit) begin
    lru_bit[addr_index] <= ~hit_way_idx;
end
```

I then designed the initial version of the five-state cache controller: 

![](images/6.png)

Diagram 4

(C\_RESPOND was present in my original design then was removed by Sumukh who proposed an approach where it was no longer required: the design returns to C\_IDLE once the last word is refilled. However whilst Deniz was testing the final version he found that tests failed so we added it back so that for read misses, the cache returns the correctly sized word to the CPU and for write misses, it applies the byte or word write to the refilled line and marks it dirty.)

My original version only contained a skeleton with basic transitions and key state variable, Sumukh and Lila then completed the write-back and refill behaviour:

- C\_MISS\_SELECT: choose victim\_way and inspect valid/dirty  
- C\_WRITEBACK: write out four words using the victim’s tag and index  
- C\_REFILL: fetch four words from memory into the selected way

and I had sketched the idea of assembling write-back addresses from (victim\_tag | index | offset), but Sumukh formalised the correct bit-width computations

Compared to my earlier version, which only stalled for a few cycles and then bypassed memory, the addition of their tasks now performs a genuine write-back/allocate sequence per miss (See Diagram 5 for full logic of implementation).

### 4. Stall signalling and integration with the pipeline

From the CPU’s perspective, the cache exposes a memory interface and cpu\_stall. I wired this into hazard\_unit.sv so that:

- when CacheStall \= 1 the hazard unit sets PCWrite \= 0 and IF\_ID\_Write \= 0, freezing the front of the pipeline while the cache is busy, but without flushing any pipeline registers  
- once the cache completes its write-back/refill and returns to C\_IDLE, CacheStall drops to zero and the pipeline resumes  
- normal load-use and branch hazards are only applied when there is no cache stall

In my first implementation I made several mistakes:

- Store masking handled incorrectly, fixed after integration testing  
- cpu\_stall was asserted too often (including on hits), which my teammates corrected by gating it on “miss / non-IDLE” only, ensuring that a cache miss simply pauses the pipeline until the line has been written back and refilled

![](images/7.png)

Diagram 5

### 5. Reflection

To me this stretch goal was one of the most challenging but also the most rewarding part of the project.  My initial cache wrapper established the architectural foundation: address breakdown, tag/valid/dirty structures, hit detection, and the CPU–cache interface. However, it lacked a full miss-handling path and contained early design mistakes, such as overly aggressive stalling and inconsistent data updates. 

In hindsight, I recognise areas where my early version was incomplete or overly optimistic, especially regarding write-back address construction and updating. However, establishing the entire architectural scaffold and through collaboration with my teammates, these issues were resolved and the cache evolved into a coherent 4 KiB, 2-way set-associative subsystem with correct LRU behaviour, write-back and stall signalling.

This part of the project taught me how important modular, readable designs and team feedback are: my architecture made it possible for others to fill in the complex FSM, while their testing forced me to tighten the stall and data logic.

From a technical perspective, I found that implementing hit detection was the most challenging as it required correctly comparing tags and valid bits across both ways and selecting the appropriate word for the CPU. But in the end this work strengthened my understanding of realistic memory hierarchy design and the systems-level thinking needed to integrate multi-cycle modules into a pipelined CPU without disrupting existing logic.

## Stretch Goal 3: Full RV32I Design

As part of Stretch Goal 3, my task was to extend our processor from our partial RV32I to a full RV32I base instruction set (excluding ECALL/EBREAK, CSR and FENCE). This required changes to the control path, the ALU interface, and the decoder, and re-checking the pipeline core.

Because I had previously implemented much of the control-path and hazard behaviour for the pipeline, this work naturally built on my understanding of how instructions propagate through each stage and how timing, forwarding, and stalls interact.

**Modules modified:**  
 `control_unit.sv`, `alu.sv`, `extend.sv`, `execute.sv`

**Key commits:**

* [https://github.com/sadir06/Project\_Brief/pull/11/commits/0339ee61b1db538705de6f7147cd8913bb966d1f](https://github.com/sadir06/Project_Brief/pull/11/commits/0339ee61b1db538705de6f7147cd8913bb966d1f)  
* [https://github.com/sadir06/Project\_Brief/pull/15/commits/e4f9375124d9d30c6797b267c24c53d6fcc7fd65](https://github.com/sadir06/Project_Brief/pull/15/commits/e4f9375124d9d30c6797b267c24c53d6fcc7fd65)  
* [https://github.com/sadir06/Project\_Brief/pull/16/commits/c8f3ac6ba05b69df4697ffbdf92e368eb76be551](https://github.com/sadir06/Project_Brief/pull/16/commits/c8f3ac6ba05b69df4697ffbdf92e368eb76be551)

### 1. Control Unit Extension

I first started redesigning and extending control\_unit.sv to decode all RV32I arithmetic, logical, and shift instructions. I expanded it to include the full RV32I ALU R-type (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND) and I-type (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SR) instruction set using the lecture slides:

![](images/8.png)![](images/9.png)

To support these instructions, I restructured the control block around a complete case-analysis of opcode, funct3, and when necessary funct7. A key part of this was defining a 4-bit ALUControl code rather than the earlier 3-bit encoding like before to account for the extra instructions.

One of the subtle challenges concerned I-type shift operations, which encode the shift amount in imm\[4:0\] but require funct7 to distinguish between SRLI and SRAI. Implementing this correctly required careful matching of exactly the bit patterns from the RISC-V manual.

I also added explicit default fallbacks so that illegal encodings safely degrade to NOP-like behaviour.

### 2. ALU Extension

I updated the ALU to accept the new 4-bit ALUControl input and implemented:

- Arithmetic: ADD, SUB  
- Comparison: SLT, SLTU  
- Logical: XOR, OR, AND  
- Shifts: SLL, SRL, SRA  
- Pass-B (for LUI and address calculations)

I found that the shift operations were the most subtle to do as SRA requires explicit arithmetic shift behaviour, whereas SRL must avoid sign replication.

### 3. Immediate Generator

The existing extend.sv already supported I/S/B/U/J immediates in our single cycle design, but I still verified that the immediate formats remained correct . The only modification needed was ensuring that the sign-extended I-type immediate remained valid for shift instructions, even though imm\[11:5\] encodes funct7 information. Because the ALU shift amount uses only imm\[4:0\], the immediate generator’s behaviour remained correct.

### 4. Pipeline Integration

Once my teammates finished their components (especially the cache and refined pipeline registers), I revisited my ISA-extension code and discovered several inconsistencies that needed to be addressed before full RV32I programs would run in the pipelined design.

Most of these centred around execute.sv, which still reflected assumptions from the earlier single-cycle version. I fixed the following issues:

- Removed unused or incorrect control signals  
- Ensured branch decisions use the funct3 encoded in ID/EX, not inferred behaviour  
- Implemented full RV32I branch semantics (BEQ, BNE, BLT, BGE, BLTU, BGEU)  
- Repaired forwarding logic so the correct ALU/MEM/WB results are selected for both operands  
- Fixed store-data forwarding so MEM receives the properly forwarded rs2 value  
- Ensured ALUControlE is consistently 4-bit throughout the pipeline


### 5. Reflection

This stretch goal confronted me with the details of ISA encoding and how they interact with a real pipeline. I learned that:

-  Small mismatches (e.g. wrong funct3 usage, inconsistent ALUControl width) can silently break complex instruction sequences. So i used a 4-bit ALUControl encoding ensured that each RV32I ALU instruction had a unique and unambiguous control signal

- A modular, well-designed pipeline pays off: we doubled the number of supported instructions without needing to redesign hazard or forwarding logic.

- Revisiting my own code after teammates finished their modules was essential as several of the final fixes only became obvious once everything was integrated and tested end-to-end.

--- 
## Final Fixes Required to Pass All Pipelined RV32I Tests
In the final debugging stage, several subtle issues needed correction to make our pipelined and cached full instruction set RV32I succeed on every test case written by Deniz (including TestAddiBne, TestBranches, TestJalRet and the long TestPdf were the ones failing). 

- First, I fixed a PC+4 propagation bug: the processor originally forwarded PCPlus4F into the ID/EX register, meaning JAL/JALR wrote an incorrect return address. I introduced a proper PCPlus4D = pcD + 4 computed after the IF/ID stage, ensuring the WB stage now writes the correct link address. 

- Next, I repaired the 2-way cache hit detection, requiring both tag and valid bit to match, eliminating false hits/misses.  

- Finally, I fixed LRU updates so that the LRU bit flips on every hit and repaired the 2-way cache hit detection, fixing incorrect results in TestPdf.

Github commits for fixes:
https://github.com/sadir06/Project_Brief/commit/e9aa85fedf5f72a0c76f820d2d04a925151b32d8
https://github.com/sadir06/Project_Brief/commit/9d7c360e19ec7e73158c5808c82c056d4319cec3




## Extension: 2-Wide Superscalar Front-End Prototype

**visible inside my branch: ambre \> rtl \> superscalar**

(https://github.com/sadir06/Project_Brief/tree/ambre/rtl/superscalar)

**Modules added:** `instr_mem_dual.sv`, `if_id_reg_dual.sv`, `dual_issue_unit.sv`

As a team we had the idea of making a superscalar extension but ran out of time.

As an additional stretch goal, I had already began exploring a simple 2-wide in-order superscalar front end built on top of our pipelined RV32I. I extended the fetch and decode stages to operate in parallel by introducing a dual-port instruction memory (instr\_mem\_dual) that fetches both PC and PC+4 each cycle, along with a dual IF/ID pipeline register (if\_id\_reg\_dual) that carries both instructions into the decode stage.

To analyse whether a pair of instructions could safely work together, I implemented a custom dual\_issue\_unit. This unit performs lightweight hazard detection, checking RAW and WAW dependencies between the two fetched instructions, as well as simple restrictions such as preventing dual issue when either instruction is a branch/jump or when both are memory operations. When none of these conditions are present, the unit marks the second instruction as “dual-issuable”.

In my prototype, only Slot 0 (the first instruction) enters the existing pipeline and executes. Slot 1 is fetched, decoded, classified, and validated by the issue logic, but is not yet sent to a second execution lane. 

### Limitations and Future Work:

Throughput remains single-issue because no second execution pipeline exists yet; supporting true dual issue would require duplicating EX/MEM/WB stages, adding multi-ported register file access, extending forwarding and hazard detection across both lanes, and introducing an in-order commit mechanism. I believe the next work I could try is to add a second execution lane and extend the hazard/forwarding logic.



---

# Overall:

### Design decisions

I made several deliberate design choices that shaped the architecture:

* 4-bit ALUControl: Unique encoding for all RV32I ALU ops for clarity and safety  
* Stage-partitioned control: Reused single-cycle control but propagate via ID/EX → EX/MEM → MEM/WB  
* One-bit LRU per set for good locality performance (seen in software system lecture)  
* CacheStall as highest priority to prevents accidental flush of the miss-causing instruction  
* I structured the cache wrapper and diagrams to help teammates complete the FSM
* I think another useful choice I made for my teamates and I was separting our tasks clearly in files with clear interfaces and names (same as in the Harris & Harris block names from the lectures) and inserting them into repsective folders that separates clearly our implementation progress (see team report for the directory and branch structure). That meant that anyone on the team could open a file and understand roughly what it was responsible for. That made it easier for others to extend my cache scaffold, and for me to go back and fix issues in execute.sv or the hazard unit once the rest of the pipeline was in place.

### Mistakes and how I/team fixed them

I made several mistakes along the way, the most challenging section of the project for me was implementing the cache and I had to revisit my own code, especially after my teammates modules were integrated:

* In the cache, my first version did not correctly mask byte stores in all cases and asserted cpu\_stall too aggressively (sometimes even on hits). After integration and testing, we fixed this by tightening the stall condition to “miss and not IDLE” and cleaning up the write-masking path.  
* My early write-back address construction for C\_WRITEBACK/C\_REFILL in data\_cache.sv was incomplete; I had the conceptual idea of reconstructing {victim\_tag, index, offset}, but my teammates later corrected the exact bit-width handling and we reinstated a C\_RESPOND state after testing showed subtle bugs.  
* When we first moved from the single-cycle core to the pipelined core, execute.sv still reflected the old interface and incorrectly handled some branch conditions and forwarding. After others finished their pipeline work, I went back and refactored execute.sv so it used the pipelined funct3 correctly, matched the 4-bit ALUControl, and produced the branch result used by hazard\_unit.sv.  
* At repository level, we delayed creating clean feature branches until late in the project. This made it harder to recover the exact versions when assembling final branches for single-cycle and stretch-goals



### What I learned

* How hazards, forwarding, and control interact in a real pipeline  
* That a single bad control signal can silently break branch or load behaviour  
* Why a cache subsystem needs careful coordination between FSM design, (tag/valid/dirty/LRU) and pipeline stalls, rather than just acting as a “faster memory” (RAM)  
* The subtleties of RV32I instruction encodings (especially shift and comparison instructions where immediate bits double as part of funct7)  
* The value of modularity and clarity when working in a team: my cache scaffold and diagrams (address breakdown, FSM state diagram) made it much easier for others to plug in their logic, and their later fixes made it clear where my design was too optimistic

### Reflection

Working on this project in a team of 4 made a difference to how far we could push the design. My work was mainly on the control path, pipeline structure and cache architecture, but none of it would have converged without Deniz’s systematic testbenches or Lila and Sumukh’s datapath and memory work. Many of the hardest bugs – especially in the cache and final PC+4/JALR behaviour – were only found once our modules were integrated and run through Deniz’s assembly tests. 

Overall, I learnt a lot during this project and working in a team made it more enjoyable. Getting the final green test output after chasing subtle bugs was extremely satisfying, and it gave me a much clearer picture of what day-to-day work in hardware design or computer architecture might feel like.


### What I would do differently with more time

* Introduce clean feature branches much earlier to avoid going through git history  
* Add more systematic tests and self-checking assembly specifically targeting new instructions and cache corner cases  
* Finish the 2-wide superscalar  
* Spend more time on assertions and internal checking (e.g. verifying LRU invariants and cache state) so mistakes like over-stalling or incorrect masking are caught earlier



---

# Appendix:


## Replacement Policy: Justification for Using LRU

Our 4 KiB data cache is 2-way set associative, which means each set contains two possible locations for storing a cache line. When a miss occurs and both ways are valid, the cache must choose which existing line to evict. 

Our workload exhibits temporal locality (as seen in detail on software system lectures): data accessed recently is more likely to be accessed again. LRU directly captures this behaviour by preferentially retaining the most recently used line and evicting the least recently used one. This yields a better hit rate than random replacement.
The implementation cost is minimal and simple: for each set I store a single LRU bit.

- If lru_bit = 0, way 0 is considered least recently used (so evict way 0 on miss)
- If lru_bit = 1, way 1 is considered least recently used (so evict way 1 on miss)

On every cache hit, I simply flip the bit so that the other way becomes the next eviction victim (ex: hit in way 0 we go to access way 0 but also updates LRU bit to 1 so that way 1 now becomes LRU for next time). On a miss, the FSM reads this bit to immediately select the correct way for replacement. This requires only one flip-flop per set and a small amount of combinational logic.

So this is why we thought LRU was the most appropriate policy for our design, offering strong locality performance with negligible hardware overhead.


## Observation: Why the Pipelined CPU Appears Slower in Simulation
In Verilator, our pipelined RV32I design takes more cycles than the single-cycle CPU, eventhough we expected the pipelining to improve the processor throughput. We believe it is a normal observation in the scope of our project as both models run with the same simulated clock period, so the pipeline does not benefit from the higher clock frequency it would have in real hardware. What we do see are the pipeline penalties:

- Branch flushes: every taken branch or jump in our design flushes IF/ID stage, ID/EX stage. This costs 2 lost cycles. Our F1 tests contain many tight loops, so these penalties accumulate.
- Load–use hazards: a dependent instruction after a load causes a mandatory 1-cycle stall. 
for example: 
```
lw x1, 0(x2)
add x3, x1, x4  ← must stall 1 cycle + bubble inserted 
```
(single-cycle CPU pays no penalty)

- Pipeline fill/drain: our short programs (most of them are 20–40 instructions) loses ~4–5 cycles to fill/drain the pipeline whereas the single-cycle CPU produces results immediately

