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

## Hazard Handling
### Structural Hazards

Structural hazards occur when multiple pipeline stages compete for the same hardware resource during a clock cycle. To mitigate such conflicts, the processor employs a two-phase clocking scheme that separates pipeline activity across two non-overlapping clock phases.

The Instruction Fetch (IF), Execute (EX), and Write Back (WB) stages operate on `clk1`, while the Instruction Decode (ID) and Memory Access (MEM) stages operate on `clk2`. This arrangement distributes resource utilization across different clock phases, reducing contention between pipeline stages and enabling smooth concurrent execution of instructions.

Additionally, control mechanisms are incorporated to prevent unintended state updates during pipeline flushes and branch redirections, ensuring correct processor operation even in the presence of control-flow changes.

### Structural Hazard Mitigation Techniques

* Two-phase clocking architecture (`clk1` and `clk2`).
* Separation of pipeline stage activity across clock phases.
* Controlled write-back synchronization.
* Protection against invalid state updates during pipeline flushes.
## Data Hazards

Data hazards occur when an instruction depends on the result of a previous instruction that has not yet completed its passage through the pipeline. Such dependencies can lead to incorrect execution if the required operand is not available when needed.

To ensure correct execution while maintaining pipeline performance, the processor implements multiple hazard mitigation techniques, including operand forwarding and load-use hazard detection. These mechanisms reduce unnecessary stalls and allow dependent instructions to execute with minimal performance degradation.

The processor addresses data hazards through:

* Operand forwarding from later pipeline stages.
* Load-use hazard detection and pipeline stalling.
* Bubble insertion to preserve correct instruction execution.

### Operand Forwarding

In a pipelined processor, a Read-After-Write (RAW) dependency occurs when an instruction requires a value that is being produced by a preceding instruction but has not yet been written back to the register file. Without hazard mitigation, the dependent instruction would have to stall until the value becomes available.

To reduce performance loss due to such dependencies, the processor implements operand forwarding. Instead of waiting for the result to be written back to the register file, the forwarding logic routes the most recent value directly from later pipeline stages to the Execute stage.

The forwarding unit continuously monitors source and destination register dependencies between instructions in different pipeline stages. When a dependency is detected, the forwarded value is selected as the ALU operand, allowing execution to proceed without introducing unnecessary stalls.

### Forwarding Paths Implemented

* EX/MEM → EX forwarding
* MEM/WB → EX forwarding
* Forwarding support for both source operands (`rs` and `rt`)
* Dynamic operand selection based on dependency detection

### Example

Consider the following instruction sequence:

```assembly
ADD R1, R2, R3
SUB R4, R1, R5
```

The `SUB` instruction requires the value of `R1`, which is produced by the preceding `ADD` instruction. Instead of waiting for the result to reach the Write Back stage, the forwarding unit supplies the ALU result directly to the Execute stage of the dependent instruction. This eliminates the need for a pipeline stall and improves instruction throughput.

### Load-Use Hazard Detection

Although operand forwarding resolves most Read-After-Write (RAW) dependencies, it cannot eliminate hazards that occur immediately after a load instruction. In a load operation, the requested data becomes available only after the Memory Access (MEM) stage, making it unavailable to the immediately following instruction during its Execute stage.

To handle this situation, the processor implements a load-use hazard detection mechanism. The hazard detection logic monitors dependencies between instructions in the pipeline and identifies cases where an instruction attempts to use a value that is currently being loaded from memory.

When such a dependency is detected, the processor temporarily stalls the pipeline by preventing further instruction fetch and decode operations. A bubble (NOP) is inserted into the pipeline, allowing the load instruction to progress and produce the required data before the dependent instruction is executed.

### Hazard Resolution Strategy

* Detect dependencies involving load instructions.
* Freeze the Program Counter (PC) update.
* Freeze the IF/ID pipeline register.
* Insert a bubble into the ID/EX pipeline register.
* Resume normal execution once the required data becomes available.

### Example

Consider the following instruction sequence:

```assembly
LW  R1, 0(R2)
ADD R3, R1, R4
```

The `ADD` instruction requires the value loaded into `R1`. Since the data is not available until the completion of the Memory Access stage, forwarding alone cannot resolve the dependency. The hazard detection unit inserts a stall cycle, ensuring that the correct value is available before the `ADD` instruction enters execution.

## Control Hazards

Control hazards arise when the processor encounters branch instructions that may alter the normal sequential flow of execution. Since the next instruction address depends on the outcome of the branch condition, instructions fetched before the branch decision is known may not belong to the correct execution path.

To minimize branch penalties, the processor performs branch evaluation during the Instruction Decode (ID) stage. By resolving branch decisions earlier in the pipeline, the number of incorrectly fetched instructions is reduced, resulting in improved pipeline efficiency compared to conventional designs that resolve branches in the Execute stage.

When a branch is determined to be taken, the Program Counter (PC) is redirected to the target address and the incorrectly fetched instruction is flushed from the pipeline. This ensures that execution continues from the correct instruction stream while maintaining architectural correctness.

### Control Hazard Mitigation Techniques

* Early branch resolution in the Decode stage.
* Program Counter (PC) redirection for taken branches.
* Pipeline flushing of incorrectly fetched instructions.
* Prevention of invalid register and memory updates from flushed instructions.

### Supported Branch Instructions

* `BEQZ` – Branch if register value equals zero.
* `BNEQZ` – Branch if register value is not equal to zero.

### Example

```assembly
BEQZ R1, TARGET
ADD  R2, R3, R4
```

If the branch condition evaluates to true, the processor redirects execution to `TARGET` and flushes the incorrectly fetched `ADD` instruction. This prevents the wrong-path instruction from modifying the processor state and ensures correct program execution.

## Verification and Testing
### Test Case 1: Functional Verification (No Hazards)
RTL Source:
`RTL/MIPS32_pipe.v`
Testbench:
`Testbench/tb_MIPS32_pipe_no_hazard.v`

#### Objective
This testbench validates the correct execution of all supported instruction classes in the absence of pipeline hazards. To isolate functional correctness from hazard-related effects, NOP instructions are inserted between consecutive operations, ensuring that no data dependencies exist between instructions.

The test program verifies:
* Arithmetic operations (ADD, SUB, MUL)
* Logical operations (AND, OR)
* Comparison operations (SLT, SLTI)
* Immediate instructions (ADDI, SUBI)
* Memory operations (LW, SW)
* Register write-back functionality
* Memory read/write correctness
#### Test Program
| Test ID | Instruction      | Inputs       | Expected Result |
| ------- | ---------------- | ------------ | --------------- |
| T01     | ADD R8, R1, R2   | R1=10, R2=20 | R8=30           |
| T02     | SUB R9, R2, R1   | R2=20, R1=10 | R9=10           |
| T03     | AND R10, R4, R3  | R4=255, R3=5 | R10=5           |
| T04     | OR R11, R4, R3   | R4=255, R3=5 | R11=255         |
| T05     | SLT R12, R1, R2  | R1=10, R2=20 | R12=1           |
| T06     | SLT R13, R2, R1  | R2=20, R1=10 | R13=0           |
| T07     | MUL R14, R3, R6  | R3=5, R6=100 | R14=500         |
| T08     | ADDI R15, R1, 7  | R1=10        | R15=17          |
| T09     | SUBI R16, R6, 30 | R6=100       | R16=70          |
| T10     | SLTI R17, R1, 15 | R1=10        | R17=1           |
| T11     | SLTI R18, R6, 15 | R6=100       | R18=0           |
| T12     | SW R7, 50(R0)    | R7=10        | Mem[50]=10      |
| T13     | LW R19, 50(R0)   | Mem[50]=10   | R19=10          |

#### Simulation Result
<img width="1613" height="801" alt="Screenshot 2026-06-24 095303" src="https://github.com/user-attachments/assets/94f18090-ae9e-4016-ad8a-31624081afa3" />


<img width="1572" height="717" alt="image" src="https://github.com/user-attachments/assets/a5123263-a2d4-48f2-83fb-5133b8f98259" />


### Test Case 2: Data Hazard Verification – Operand Forwarding
RTL Source:
`RTL/MIPS32_pipe.v`
Testbench:
`Testbench/tb_MIPS32_forwarding.v`
#### Objective
This test verifies the functionality of the forwarding unit in resolving Read-After-Write (RAW) data hazards without introducing pipeline stalls. Two forwarding scenarios are evaluated:

* EX/MEM → EX forwarding
* MEM/WB → EX forwarding

The test ensures that dependent instructions receive the most recent operand values directly from later pipeline stages rather than waiting for register write-back.
#### Test Program
<img width="780" height="240" alt="Screenshot 2026-06-24 162046" src="https://github.com/user-attachments/assets/ee6d949d-49ab-4b6c-a9e6-3d0677ba3e48" />

#### Test 1: EX/MEM → EX Forwarding
```assembly
ADD R5, R1, R2
SUB R6, R5, R3
```
The SUB instruction immediately depends on the result produced by the preceding ADD instruction. Since the value of R5 has not yet been written back to the register file, the forwarding unit supplies the result directly from the EX/MEM pipeline register to the Execute stage of the dependent instruction.
#### Expected Result
```assembly
R5 = 30
R6 = 25
```
#### Test 2: MEM/WB → EX Forwarding
```assembly
ADD R8, R1, R2
NOP
SUB R9, R8, R3
```
A single-cycle gap is introduced between the producer and consumer instructions. When the SUB instruction enters the Execute stage, the value of R8 is available in the MEM/WB pipeline register. The forwarding unit supplies this value directly to the ALU input, eliminating the need for additional stalls.

#### Expected Result
```assembly
R8 = 30
R9 = 25
```
#### Simulation Result
<img width="602" height="388" alt="Screenshot 2026-06-24 161936" src="https://github.com/user-attachments/assets/4ec41a7a-8d7f-4f8b-be68-bc607c2b8ddf" />


<img width="1582" height="757" alt="image" src="https://github.com/user-attachments/assets/752165ba-aa94-422d-9e01-fc49f110b68f" />

### Test Case 3: Data Hazard Verification – Load-Use Hazard Detection
#### Objective

This test verifies the processor's ability to detect and resolve load-use data hazards. Unlike normal RAW dependencies that can be handled through operand forwarding, a load instruction does not produce valid data until the Memory Access (MEM) stage. Therefore, an immediately dependent instruction must be stalled to ensure correct execution.
#### Test Program
<img width="577" height="110" alt="Screenshot 2026-06-25 102246" src="https://github.com/user-attachments/assets/ddc7ff2c-46b0-4d83-8dfb-19bf951bea1d" />

```assembly
LW  R5, 50(R0)
ADD R6, R5, R1
```
#### Hazard Scenario

The ADD instruction requires the value of R5 immediately after it is loaded from memory. Since the data is not yet available when the dependent instruction reaches the Execute stage, forwarding alone cannot resolve the dependency.

The hazard detection unit identifies this condition and temporarily stalls the pipeline, allowing the load instruction to complete before the dependent instruction proceeds.

#### Expected Behavior

- Load-use dependency detected.
- Program Counter (PC) update is stalled.
- IF/ID pipeline register is frozen.
- A bubble (NOP) is inserted into the pipeline.
- Execution resumes once the loaded data becomes available.
  
#### Expected Result
```assembly
mem[50] = 99
R1      = 10
R5      = 99
R6      = 109
```
#### Simulation Result
<img width="582" height="363" alt="Screenshot 2026-06-25 102404" src="https://github.com/user-attachments/assets/5fec7b33-80be-471b-8652-0e2081b5e837" />

<img width="1581" height="688" alt="Screenshot 2026-06-25 103105" src="https://github.com/user-attachments/assets/cecfd83b-a4b3-4a80-9469-1aee1d483033" />

### Test Case 4: Control Hazard Verification
#### Objective

This test validates the processor's control hazard handling mechanism for branch instructions. The goal is to ensure that branch decisions are resolved correctly, wrong-path instructions are flushed from the pipeline, and execution continues from the correct target address.

The verification covers both taken and not-taken branch scenarios, branch flushing behavior, consecutive branches, and branch target execution.

#### Branch Instructions Tested
<img width="631" height="182" alt="image" src="https://github.com/user-attachments/assets/55b45aa9-836c-41f2-a10a-a9c0d6c016fb" />

#### Simulation Result
<img width="591" height="471" alt="Screenshot 2026-06-25 170117" src="https://github.com/user-attachments/assets/b470af9f-f768-4fd4-b666-3bd25e124df0" />

<img width="1566" height="650" alt="Screenshot 2026-06-25 165923" src="https://github.com/user-attachments/assets/56dd57fd-7f9a-479c-94da-77116bf02dc6" />
<img width="1572" height="211" alt="Screenshot 2026-06-25 165951" src="https://github.com/user-attachments/assets/d8761400-ad44-4582-86f2-95f6a390e2ee" />


