# mips32-5stage-pipelined-processor
A 32-bit MIPS32 processor implemented in Verilog featuring a classic 5-stage pipeline architecture (IF, ID, EX, MEM, WB), forwarding logic, load-use hazard detection, and branch hazard mitigation to improve instruction throughput.

## Features Implemented
* 32-bit MIPS32-like processor implemented in Verilog HDL.
* Classic 5-stage pipelined architecture:
  * Instruction Fetch (IF)
  * Instruction Decode (ID)
  * Execute (EX)
  * Memory Access (MEM)
  * Write Back (WB)
* Two-phase clocking scheme separating odd and even pipeline stages.
* Pipeline register implementation between all stages (IF/ID, ID/EX, EX/MEM, MEM/WB).
* 32 × 32-bit general-purpose register file.
* 1024 × 32-bit unified instruction/data memory.
* Support for arithmetic, logical, immediate, memory-access, and branch instructions.
* Dedicated **forwarding logic** for resolving read-after-write (RAW) data hazards.
* EX-to-EX and MEM-to-EX operand forwarding paths.
* **Load-use hazard detection** with automatic pipeline stalling and bubble insertion.
* **Early branch resolution in the Decode stage** to reduce branch penalty.
* Pipeline flushing and PC redirection for taken branches.
* Register write-back protection and branch-flush gating mechanisms.
* HALT instruction support for controlled pipeline termination.
* Fully synthesizable RTL design with simulation-based verification.

## Processor Specifications

| Specification                 | Details                                              |
| ----------------------------- | ---------------------------------------------------- |
| Processor Type                | MIPS32-like RISC Processor                           |
| Data Width                    | 32-bit                                               |
| Architecture                  | 5-Stage Pipelined                                    |
| Implementation Language       | Verilog HDL                                          |
| Pipeline Stages               | IF, ID, EX, MEM, WB                                  |
| Clocking Scheme               | Two-Phase Clocking (clk1, clk2)                      |
| Register File                 | 32 General-Purpose Registers (32-bit each)           |
| Memory Organization           | Unified Instruction and Data Memory                  |
| Memory Size                   | 1024 × 32-bit Words                                  |
| Supported Instruction Classes | R-Type, Immediate, Memory Access, Branch             |
| Arithmetic Operations         | ADD, SUB, MUL                                        |
| Logical Operations            | AND, OR                                              |
| Comparison Operations         | SLT, SLTI                                            |
| Immediate Operations          | ADDI, SUBI, SLTI                                     |
| Memory Operations             | LW, SW                                               |
| Branch Instructions           | BEQZ, BNEQZ                                          |
| Program Termination           | HLT                                                  |
| Data Hazard Handling          | Forwarding + Load-Use Stall Detection                |
| Control Hazard Handling       | Early Branch Resolution with Pipeline Flush          |
| Structural Hazard Handling    | Two-Phase Clocking with Resource Conflict Mitigation |
| Pipeline Registers            | IF/ID, ID/EX, EX/MEM, MEM/WB                         |
| Register Zero Support         | R0 Hardwired to Zero                                 |

## Instruction Set Architecture (ISA)
The processor implements a simplified MIPS32-like instruction set using a fixed 32-bit instruction format. Instructions are categorized into Register (R-type), Immediate (I-type), and Control/Jump (J-type) formats.
<img width="1536" height="645" alt="ISA" src="https://github.com/user-attachments/assets/e313bca0-1116-4c06-9e3f-2ba8ec3cca6c" />

* R-type: Used for register-to-register ALU operations
* I-type: Used for immediate operations, memory access, and branches
* J-type: Used for jump instructions (not included in this processor)

Supported instruction categories include:
- Arithmetic and logical operations (ADD, SUB, AND, OR, SLT, MUL)
- Immediate operations (ADDI, SUBI, SLTI)
- Memory access operations (LW, SW)
- Branch instructions (BEQZ, BNEQZ)
- Program control instruction (HLT)

## Architecture Overview
<img width="1608" height="978" alt="architecture" src="https://github.com/user-attachments/assets/7d86ed73-df50-4c68-a60d-6dd5077a2717" />


* The processor is a 32-bit MIPS32-like RISC architecture implemented using a classic five-stage pipeline consisting of Instruction Fetch (IF), Instruction    Decode (ID), Execute (EX), Memory Access (MEM), and Write Back (WB) stages. Pipeline registers are inserted between consecutive stages to enable concurrent  execution of multiple instructions and improve instruction throughput.

* The design employs a **two-phase clocking scheme**, where `clk1` drives the IF, EX, and WB stages, while `clk2` drives the ID and MEM stages. This approach reduces **resource contention** between stages and helps **mitigate structural hazards** during pipeline operation.

* To improve pipeline efficiency, the processor incorporates forwarding logic for resolving data hazards, load-use hazard detection with pipeline stalling, and branch handling mechanisms with pipeline flushing. These features ensure correct execution while minimizing performance degradation due to instruction dependencies and control-flow changes.

* The processor supports arithmetic, logical, immediate, memory-access, and branch instructions through a unified datapath and control architecture. The complete datapath, hazard mitigation logic, and pipeline organization are illustrated in the block diagram above.

  ## Pipeline stages
  ### Instruction Fetch (IF)

The Instruction Fetch (IF) stage is responsible for supplying instructions to the pipeline. During each clock cycle, the Program Counter (PC) is used to access the instruction memory and fetch the next instruction for execution. The fetched instruction, along with the incremented PC value, is stored in the IF/ID pipeline register for use by the Decode stage.

The processor supports sequential instruction execution by incrementing the PC after every fetch operation. In the event of a taken branch, the PC is redirected to the branch target address and the incorrectly fetched instruction is flushed from the pipeline to maintain correct program execution.

Key responsibilities of the IF stage include:

* Maintaining and updating the Program Counter (PC).
* Fetching instructions from memory.
* Passing fetched instructions to the IF/ID pipeline register.
* Supporting PC redirection during branch operations.
* Cooperating with hazard control logic during pipeline stalls and flushes.

 ### Instruction Decode (ID)

The Instruction Decode (ID) stage interprets the fetched instruction and prepares the required operands and control information for execution. During this stage, source register values are read from the register file, immediate operands are sign-extended, and the instruction is classified into its corresponding operation type.

The processor performs early branch evaluation in the Decode stage to reduce branch penalties. For branch instructions (`BEQZ` and `BNEQZ`), the branch condition is checked immediately after register read, allowing the processor to detect taken branches earlier and minimize the number of instructions that must be flushed from the pipeline.

This stage also incorporates load-use hazard detection logic. When a load instruction in the pipeline is followed by an instruction that depends on the loaded value, the hazard detection unit stalls the pipeline, freezes the Program Counter and IF/ID register, and inserts a bubble into the ID/EX pipeline register to ensure correct execution.

Key responsibilities of the ID stage include:

* Decoding instruction opcodes and determining instruction type.
* Reading source operands from the register file.
* Performing sign extension of immediate values.
* Generating information required for subsequent pipeline stages.
* Early branch condition evaluation for control hazard reduction.
* Detecting load-use data hazards and initiating pipeline stalls.
* Updating the ID/EX pipeline register.

### Execute (EX)

The Execute (EX) stage performs arithmetic, logical, comparison, and address-generation operations required by the instruction. Based on the decoded instruction type, the Arithmetic Logic Unit (ALU) executes operations such as addition, subtraction, logical AND/OR, set-less-than comparison, and multiplication.

For memory access instructions, the EX stage computes the effective memory address by adding the base register value to the sign-extended immediate offset. Branch target addresses are also calculated during this stage when required.

To improve pipeline performance, the processor incorporates operand forwarding mechanisms within the Execute stage. The forwarding logic resolves read-after-write (RAW) data hazards by selecting the most recent operand values from later pipeline stages instead of waiting for them to be written back to the register file. This significantly reduces unnecessary pipeline stalls and improves instruction throughput.

Key responsibilities of the EX stage include:

* Performing arithmetic and logical ALU operations.
* Executing comparison operations for conditional instructions.
* Calculating effective addresses for load and store instructions.
* Generating branch target addresses.
* Implementing operand forwarding to resolve data hazards.
* Selecting the most recent operand values from pipeline registers.
* Passing execution results to the EX/MEM pipeline register.

### Memory Access (MEM)

The Memory Access (MEM) stage is responsible for executing data memory operations. For load instructions (`LW`), the memory location calculated in the Execute stage is accessed and the retrieved data is forwarded to the Write Back stage. For store instructions (`SW`), the value from the source register is written to the specified memory address.

The processor utilizes a unified memory architecture for both instructions and data. Memory addresses generated during the Execute stage are used to perform the required read or write operation during this stage.

The MEM stage also propagates execution results and control information through the EX/MEM and MEM/WB pipeline registers, ensuring proper synchronization between memory operations and subsequent write-back activities.

Key responsibilities of the MEM stage include:

* Reading data from memory for load instructions (`LW`).
* Writing data to memory for store instructions (`SW`).
* Accessing memory using addresses computed in the Execute stage.
* Propagating ALU results and memory data to later pipeline stages.
* Updating the MEM/WB pipeline register.

### Write Back (WB)

The Write Back (WB) stage is the final stage of the pipeline and is responsible for updating the register file with the results of instruction execution. Depending on the instruction type, either the ALU result or data retrieved from memory is written back to the destination register.

For arithmetic, logical, comparison, and immediate instructions, the ALU result generated in the Execute stage is written to the register file. For load instructions (`LW`), the data obtained from memory during the Memory Access stage is written to the specified destination register.

The processor includes control mechanisms to ensure that only valid instructions update the architectural state. Instructions affected by pipeline flushes or branch redirections are prevented from modifying the register file, preserving correct program execution.

Key responsibilities of the WB stage include:

* Writing ALU results to destination registers.
* Writing loaded memory data to destination registers.
* Updating the architectural state of the processor.
* Preventing invalid or flushed instructions from modifying registers.
* Supporting controlled program termination through the `HLT` instruction.
