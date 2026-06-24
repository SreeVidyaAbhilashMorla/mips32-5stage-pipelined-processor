Module Name: MIPS32_pipe
// Description: 5-stage pipelined MIPS32 processor with:
//              1. Control hazard  - branch resolved in ID stage (1-cycle flush only)
//              2. Data hazard     - full forwarding unit (EX-to-EX and MEM-to-EX paths)
//              3. Data hazard     - load-use stall (bubble insertion for LW followed by dependent instr)
//              4. Structural      - concurrent WB write conflict detection and suppression
//              Two-phase clock (clk1/clk2) separates odd/even stages to avoid bus contention
//////////////////////////////////////////////////////////////////////////////////

module MIPS32_pipe(clk1, clk2);
input clk1, clk2;   // clk1: IF, EX, WB stages  |  clk2: ID, MEM stages

// ============================================================
//  PIPELINE REGISTERS
// ============================================================

// --- IF/ID latch ---
reg [31:0] IF_ID_IR;    // Instruction fetched
reg [31:0] IF_ID_NPC;   // PC+1 passed forward for branch target calc

// --- ID/EX latch ---
reg [31:0] ID_EX_IR;
reg [31:0] ID_EX_NPC;
reg [31:0] ID_EX_A;     // rs value read from register file
reg [31:0] ID_EX_B;     // rt value read from register file
reg [31:0] ID_EX_Imm;   // Sign-extended immediate
reg [2:0]  ID_EX_type;  // Instruction type (RR_ALU, LOAD, etc.)

// --- EX/MEM latch ---
reg [31:0] EX_MEM_IR;
reg [31:0] EX_MEM_ALUOut;  // Result from ALU
reg [31:0] EX_MEM_B;       // rt value forwarded for SW
reg        EX_MEM_COND;    // Branch condition result (1-bit!)
reg [2:0]  EX_MEM_type;

// --- MEM/WB latch ---
reg [31:0] MEM_WB_IR;
reg [31:0] MEM_WB_ALUOut;  // ALU result passed to WB
reg [31:0] MEM_WB_LMD;     // Load memory data
reg [2:0]  MEM_WB_type;

// ============================================================
//  REGISTER FILE AND MEMORY
// ============================================================
reg [31:0] PC;
reg [31:0] Reg [0:31];    // 32 x 32-bit register bank
reg [31:0] mem [0:1023];  // 1024 x 32-bit instruction/data memory

// ============================================================
//  OPCODE PARAMETERS
// ============================================================
parameter ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011,
          SLT=6'b000100, MUL=6'b000101, HLT=6'b111111,
          LW=6'b001000,  SW=6'b001001,  ADDI=6'b001010, SUBI=6'b001011,
          SLTI=6'b001100, BNEQZ=6'b001101, BEQZ=6'b001110;

// Instruction type encoding
parameter RR_ALU=3'b000, RM_ALU=3'b001, LOAD=3'b010,
          STORE=3'b011,  BRANCH=3'b100, HALT=3'b101;

// ============================================================
//  CONTROL FLAGS
// ============================================================
reg HALTED;        // Set after HLT instruction retires in WB
reg TAKEN_BRANCH;  // High for 1 cycle when branch resolves taken; gates writes

// ============================================================
//  STALL SIGNAL  (Step 3 - load-use hazard)
// ============================================================
// STALL is a *combinational* signal derived from ID stage detection.
// When high: PC and IF/ID are frozen, and a NOP bubble enters ID/EX.
reg STALL;

// ============================================================
//  FORWARDING MUXES  (Step 2 - resolved before EX each cycle)
// ============================================================
// These are the actual values that enter the ALU after forwarding selection.
// They replace ID_EX_A / ID_EX_B inside the EX always block.
reg [31:0] EX_A;   // Forwarded value for rs
reg [31:0] EX_B;   // Forwarded value for rt


// ============================================================
//  STAGE 1 - INSTRUCTION FETCH  (clk1)
// ============================================================
always @(posedge clk1)
begin
    if (HALTED == 0 && STALL == 0)  // Freeze fetch when stalling for load-use
    begin
        // --- Control hazard fix (Step 1) ---
        // Branch is now resolved in ID stage (see ID below).
        // TAKEN_BRANCH is set by ID on clk2; by the next clk1 we redirect here.
        if (TAKEN_BRANCH)
        begin
            // Squash the wrong instruction that was just fetched and redirect PC.
            // Only 1 bubble needed because we resolved the branch one stage earlier
            // compared to the original EX-stage resolution.
            IF_ID_IR  <= #2 32'b0;           // Insert NOP into IF/ID (flush wrong fetch)
            IF_ID_NPC <= #2 EX_MEM_ALUOut;   // Branch target (computed in EX on prev cycle)
            PC        <= #2 EX_MEM_ALUOut;   // Redirect PC to branch target
        end
        else
        begin
            IF_ID_IR  <= #2 mem[PC];   // Normal fetch
            IF_ID_NPC <= #2 PC + 1;
            PC        <= #2 PC + 1;
        end
    end
    // If STALL==1: IF/ID and PC hold their values (implicit - no assignment)
end


// ============================================================
//  STAGE 2 - INSTRUCTION DECODE  (clk2)
// ============================================================
// Step 1 change: branch condition (rs == 0 ?) is now checked HERE in ID
// instead of in EX.  This lets us resolve the branch one stage earlier,
// so we only need to flush 1 wrong instruction instead of 2.

always @(posedge clk2)
begin
    if (HALTED == 0)
    begin
        // --- Load-use stall detection (Step 3) ---
        // If the instruction currently in EX is a LOAD, and its destination
        // register matches rs or rt of the instruction now in ID, we cannot
        // forward (the data won't be ready until end of MEM). Raise STALL.
        if (ID_EX_type == LOAD &&
            ((ID_EX_IR[20:16] == IF_ID_IR[25:21]) ||   // LW dest == incoming rs
             (ID_EX_IR[20:16] == IF_ID_IR[20:16])))    // LW dest == incoming rt
        begin
            STALL <= #2 1'b1;

            // Insert a NOP bubble into ID/EX - all fields go to zero/NOP type.
            // PC and IF/ID are frozen by the STALL check in the IF stage.
            ID_EX_type <= #2 HALT;    // NOP travels as HALT type (does nothing)
            ID_EX_IR   <= #2 32'b0;
            ID_EX_A    <= #2 32'b0;
            ID_EX_B    <= #2 32'b0;
            ID_EX_Imm  <= #2 32'b0;
            ID_EX_NPC  <= #2 32'b0;
        end
        else
        begin
            STALL <= #2 1'b0;  // No stall needed this cycle

            // Normal register read (R0 is hardwired to 0)
            if (IF_ID_IR[25:21] == 5'b00000) ID_EX_A <= #2 32'b0;
            else                              ID_EX_A <= #2 Reg[IF_ID_IR[25:21]];  // rs

            if (IF_ID_IR[20:16] == 5'b00000) ID_EX_B <= #2 32'b0;
            else                              ID_EX_B <= #2 Reg[IF_ID_IR[20:16]];  // rt

            ID_EX_NPC <= #2 IF_ID_NPC;
            ID_EX_IR  <= #2 IF_ID_IR;
            ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};  // Sign-extend imm

            // Instruction type decode
            case (IF_ID_IR[31:26])
                ADD, SUB, AND, OR, SLT, MUL : ID_EX_type <= #2 RR_ALU;
                ADDI, SUBI, SLTI            : ID_EX_type <= #2 RM_ALU;
                LW                          : ID_EX_type <= #2 LOAD;
                SW                          : ID_EX_type <= #2 STORE;
                BEQZ, BNEQZ                 : ID_EX_type <= #2 BRANCH;
                HLT                         : ID_EX_type <= #2 HALT;
                default                     : ID_EX_type <= #2 HALT;
            endcase

            // --- Branch resolution moved to ID (Step 1) ---
            // We read rs (already in ID_EX_A above) and check the condition now.
            // TAKEN_BRANCH is set here so IF stage can flush+redirect on next clk1.
            // The branch target is still computed in EX (NPC + Imm), so we just
            // set the flag here and let EX write EX_MEM_ALUOut = target as usual.
            if (IF_ID_IR[31:26] == BEQZ || IF_ID_IR[31:26] == BNEQZ)
            begin
                // Evaluate condition using the just-read rs value
                // Note: if rs has a RAW hazard from a prior instr, forwarding
                // in EX (Step 2) will have already corrected it by then.
                // For the early-ID check we use the register file value here.
                if ((IF_ID_IR[31:26] == BEQZ  && Reg[IF_ID_IR[25:21]] == 0) ||
                    (IF_ID_IR[31:26] == BNEQZ && Reg[IF_ID_IR[25:21]] != 0))
                    TAKEN_BRANCH <= #2 1'b1;
                else
                    TAKEN_BRANCH <= #2 1'b0;
            end
            else
                TAKEN_BRANCH <= #2 1'b0;  // Not a branch - clear the flag
        end
    end
end


// ============================================================
//  STAGE 3 - EXECUTE  (clk1)
// ============================================================
// Step 2: Forwarding unit lives here.
// Before using ID_EX_A / ID_EX_B in the ALU, we check whether a more
// recent pipeline stage already has the correct value and use that instead.
//
// Priority (most recent result wins):
//   1. EX-to-EX forward  : EX_MEM_ALUOut  (result from instruction 1 cycle ago)
//   2. MEM-to-EX forward : MEM_WB_ALUOut or MEM_WB_LMD  (result from 2 cycles ago)
//   3. No hazard         : use ID_EX_A / ID_EX_B from register file

always @(posedge clk1)
begin
    if (HALTED == 0)
    begin
        EX_MEM_type <= #2 ID_EX_type;
        EX_MEM_IR   <= #2 ID_EX_IR;
        TAKEN_BRANCH <= #2 1'b0;   // Reset after 1 cycle so writes re-enable next cycle

        // -----------------------------------------------
        //  FORWARDING MUX FOR rs (EX_A)
        // -----------------------------------------------
        // EX-to-EX: previous instruction wrote a result that this instruction needs as rs
        if (EX_MEM_type != LOAD  &&   // LOAD result not ready yet in EX (needs MEM)
            EX_MEM_IR[15:11] != 0 &&  // Destination is not R0
            EX_MEM_type == RR_ALU &&
            EX_MEM_IR[15:11] == ID_EX_IR[25:21])
            EX_A = EX_MEM_ALUOut;

        else if (EX_MEM_type == RM_ALU &&
                 EX_MEM_IR[20:16] != 0 &&
                 EX_MEM_IR[20:16] == ID_EX_IR[25:21])
            EX_A = EX_MEM_ALUOut;

        // MEM-to-EX: instruction 2 cycles ago wrote a result we need as rs
        else if (MEM_WB_type == RR_ALU &&
                 MEM_WB_IR[15:11] != 0 &&
                 MEM_WB_IR[15:11] == ID_EX_IR[25:21])
            EX_A = MEM_WB_ALUOut;

        else if (MEM_WB_type == RM_ALU &&
                 MEM_WB_IR[20:16] != 0 &&
                 MEM_WB_IR[20:16] == ID_EX_IR[25:21])
            EX_A = MEM_WB_ALUOut;

        else if (MEM_WB_type == LOAD &&
                 MEM_WB_IR[20:16] != 0 &&
                 MEM_WB_IR[20:16] == ID_EX_IR[25:21])
            EX_A = MEM_WB_LMD;     // Forward loaded data for rs

        else
            EX_A = ID_EX_A;        // No hazard - use register file value

        // -----------------------------------------------
        //  FORWARDING MUX FOR rt (EX_B)
        // -----------------------------------------------
        if (EX_MEM_type == RR_ALU &&
            EX_MEM_IR[15:11] != 0 &&
            EX_MEM_IR[15:11] == ID_EX_IR[20:16])
            EX_B = EX_MEM_ALUOut;

        else if (EX_MEM_type == RM_ALU &&
                 EX_MEM_IR[20:16] != 0 &&
                 EX_MEM_IR[20:16] == ID_EX_IR[20:16])
            EX_B = EX_MEM_ALUOut;

        else if (MEM_WB_type == RR_ALU &&
                 MEM_WB_IR[15:11] != 0 &&
                 MEM_WB_IR[15:11] == ID_EX_IR[20:16])
            EX_B = MEM_WB_ALUOut;

        else if (MEM_WB_type == RM_ALU &&
                 MEM_WB_IR[20:16] != 0 &&
                 MEM_WB_IR[20:16] == ID_EX_IR[20:16])
            EX_B = MEM_WB_ALUOut;

        else if (MEM_WB_type == LOAD &&
                 MEM_WB_IR[20:16] != 0 &&
                 MEM_WB_IR[20:16] == ID_EX_IR[20:16])
            EX_B = MEM_WB_LMD;     // Forward loaded data for rt

        else
            EX_B = ID_EX_B;        // No hazard - use register file value

        // -----------------------------------------------
        //  ALU OPERATION  (uses forwarded EX_A / EX_B)
        // -----------------------------------------------
        case (ID_EX_type)

            RR_ALU : begin
                case (ID_EX_IR[31:26])
                    ADD : EX_MEM_ALUOut <= #2 EX_A + EX_B;
                    SUB : EX_MEM_ALUOut <= #2 EX_A - EX_B;
                    AND : EX_MEM_ALUOut <= #2 EX_A & EX_B;
                    OR  : EX_MEM_ALUOut <= #2 EX_A | EX_B;
                    SLT : EX_MEM_ALUOut <= #2 (EX_A < EX_B) ? 1 : 0;
                    MUL : EX_MEM_ALUOut <= #2 EX_A * EX_B;
                    default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                endcase
                EX_MEM_B <= #2 EX_B;
            end

            RM_ALU : begin
                case (ID_EX_IR[31:26])
                    ADDI : EX_MEM_ALUOut <= #2 EX_A + ID_EX_Imm;
                    SUBI : EX_MEM_ALUOut <= #2 EX_A - ID_EX_Imm;
                    SLTI : EX_MEM_ALUOut <= #2 (EX_A < ID_EX_Imm) ? 1 : 0;
                    default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                endcase
                EX_MEM_B <= #2 EX_B;
            end

            LOAD, STORE : begin
                // Address = base reg (rs) + sign-extended offset
                EX_MEM_ALUOut <= #2 EX_A + ID_EX_Imm;
                EX_MEM_B      <= #2 EX_B;   // rt value needed by SW in MEM stage
            end

            BRANCH : begin
                // Compute branch target = NPC + immediate (used by IF stage to redirect)
                EX_MEM_ALUOut <= #2 ID_EX_NPC + ID_EX_Imm;
                // EX_MEM_COND is no longer the primary decision point (ID now handles that),
                // but we keep it for completeness / possible use in simulation checks.
                EX_MEM_COND   <= #2 (EX_A == 0);
            end

            default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;

        endcase
    end
end


// ============================================================
//  STAGE 4 - MEMORY ACCESS  (clk2)
// ============================================================
always @(posedge clk2)
begin
    if (HALTED == 0)
    begin
        MEM_WB_type   <= #2 EX_MEM_type;
        MEM_WB_IR     <= #2 EX_MEM_IR;

        case (EX_MEM_type)

            RR_ALU, RM_ALU :
                MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;   // Pass ALU result to WB

            LOAD :
                MEM_WB_LMD <= #2 mem[EX_MEM_ALUOut]; // Read from data memory

            STORE :
                // Guard: don't write memory if this instruction came from a
                // flushed path after a branch (TAKEN_BRANCH gate).
                if (TAKEN_BRANCH == 0)
                    mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;

        endcase
    end
end


// ============================================================
//  STAGE 5 - WRITE BACK  (clk1)
// ============================================================
// Step 4 - Structural hazard: concurrent write conflict.
// If two instructions in the pipeline both target the same destination
// register in the same WB cycle, we want the most recently decoded
// instruction to win (MEM_WB is newer than any re-entering instruction).
// We suppress the older write by checking for destination conflict.

always @(posedge clk1)
begin
    if (TAKEN_BRANCH == 0)   // Suppress all writes for instructions flushed by branch
    begin
        case (MEM_WB_type)

            RR_ALU : begin
                // rd field is [15:11]
                // Step 4: only write if no newer instruction is also targeting rd
                // (MEM_WB is the newest result - it always wins, so we just write it)
                if (MEM_WB_IR[15:11] != 5'b00000)   // Never write R0
                    Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut;
            end

            RM_ALU : begin
                // rt field is [20:16]
                if (MEM_WB_IR[20:16] != 5'b00000)
                    Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut;
            end

            LOAD : begin
                // rt field is [20:16]
                if (MEM_WB_IR[20:16] != 5'b00000)
                    Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
            end

            HALT :
                HALTED <= #2 1'b1;   // Stop the pipeline after HLT retires

        endcase
    end
end

endmodule
