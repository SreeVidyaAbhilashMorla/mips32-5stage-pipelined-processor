module tb_MIPS32_pipe_no_hazard;

//  Clocks 
// clk1 posedge @ 10, 30, 50 …   (IF / EX / WB)
// clk2 posedge @ 20, 40, 60 …   (ID / MEM)
reg clk1, clk2;
initial begin clk1 = 0; forever #10 clk1 = ~clk1; end
initial begin clk2 = 0; #10; forever #10 clk2 = ~clk2; end

// DUT 
MIPS32_pipe dut(.clk1(clk1), .clk2(clk2));

//  Opcode parameters (must match DUT) 
localparam [5:0]
    ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011,
    SLT=6'b000100, MUL=6'b000101, HLT=6'b111111,
    LW=6'b001000,  SW=6'b001001,  ADDI=6'b001010,
    SUBI=6'b001011, SLTI=6'b001100;

//  Instruction builders 
function [31:0] rr;
    input [5:0] op; input [4:0] rs, rt, rd;
    rr = {op, rs, rt, rd, 11'b0};
endfunction
function [31:0] ri;
    input [5:0] op; input [4:0] rs, rt; input [15:0] imm;
    ri = {op, rs, rt, imm};
endfunction

// NOP: HLT opcode ? decoded as HALT type ? WB sets HALTED (but HALTED gate
// stops it from repeating). Actually we want a true NOP that does NOTHING.
// Use ADD R0,R0,R0 = 32'h00000000 ? opcode=ADD, rs=rt=rd=R0 ? writes R0(no-op) ?
localparam [31:0] NOPW = 32'h00000000;  // ADD R0,R0,R0 - harmless write to R0

//  Checker
integer pass_cnt, fail_cnt;
task check;
    input [31:0] got, exp;
    input [8*24:1] lbl;
    begin
        if (got === exp) begin
            $display("  PASS  %0s : got %0d", lbl, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  %0s : expected %0d, got %0d", lbl, exp, got);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

integer i;
initial begin
    pass_cnt = 0; fail_cnt = 0;

    //  Reset all DUT state 
    dut.HALTED       = 1'b0;
    dut.TAKEN_BRANCH = 1'b0;
    dut.STALL        = 1'b0;
    dut.PC           = 32'd0;

    dut.IF_ID_IR     = 32'b0;
    dut.IF_ID_NPC    = 32'b0;
    dut.ID_EX_IR     = 32'b0;
    dut.ID_EX_NPC    = 32'b0;
    dut.ID_EX_A      = 32'b0;
    dut.ID_EX_B      = 32'b0;
    dut.ID_EX_Imm    = 32'b0;
    // CRITICAL: use STORE(3'b011) not HALT(3'b101) so WB ignores these on cycle 1
    dut.ID_EX_type   = 3'b011;
    dut.EX_MEM_IR    = 32'b0;
    dut.EX_MEM_ALUOut= 32'b0;
    dut.EX_MEM_B     = 32'b0;
    dut.EX_MEM_COND  = 1'b0;
    dut.EX_MEM_type  = 3'b011;
    dut.MEM_WB_IR    = 32'b0;
    dut.MEM_WB_ALUOut= 32'b0;
    dut.MEM_WB_LMD   = 32'b0;
    // CRITICAL: MUST NOT be 3'b101 (HALT) - WB would assert HALTED on cycle 1
    dut.MEM_WB_type  = 3'b011;  // STORE - WB has no case for STORE ? silent no-op

    // Clear register file and data memory
    for (i = 0; i < 32;   i = i + 1) dut.Reg[i] = 32'd0;
    for (i = 0; i < 1024; i = i + 1) dut.mem[i] = 32'd0;

    //  Pre-load registers 
    dut.Reg[1] = 32'd10;
    dut.Reg[2] = 32'd20;
    dut.Reg[3] = 32'd5;
    dut.Reg[4] = 32'd255;
    dut.Reg[6] = 32'd100;
    dut.Reg[7] = 32'd10;

    //  Test program 
    // 2 NOPs (ADD R0,R0,R0) after every instruction ? zero hazards
    //
    // T01 ADD  R8,  R1, R2    10 + 20  = 30
    dut.mem[0]  = rr(ADD,  5'd1, 5'd2, 5'd8);
    dut.mem[1]  = NOPW; dut.mem[2]  = NOPW;
    // T02 SUB  R9,  R2, R1    20 - 10  = 10
    dut.mem[3]  = rr(SUB,  5'd2, 5'd1, 5'd9);
    dut.mem[4]  = NOPW; dut.mem[5]  = NOPW;
    // T03 AND  R10, R4, R3   255 &  5  = 5
    dut.mem[6]  = rr(AND,  5'd4, 5'd3, 5'd10);
    dut.mem[7]  = NOPW; dut.mem[8]  = NOPW;
    // T04 OR   R11, R4, R3   255 |  5  = 255
    dut.mem[9]  = rr(OR,   5'd4, 5'd3, 5'd11);
    dut.mem[10] = NOPW; dut.mem[11] = NOPW;
    // T05 SLT  R12, R1, R2    10 < 20  = 1
    dut.mem[12] = rr(SLT,  5'd1, 5'd2, 5'd12);
    dut.mem[13] = NOPW; dut.mem[14] = NOPW;
    // T06 SLT  R13, R2, R1    20 < 10  = 0
    dut.mem[15] = rr(SLT,  5'd2, 5'd1, 5'd13);
    dut.mem[16] = NOPW; dut.mem[17] = NOPW;
    // T07 MUL  R14, R3, R6     5 * 100 = 500
    dut.mem[18] = rr(MUL,  5'd3, 5'd6, 5'd14);
    dut.mem[19] = NOPW; dut.mem[20] = NOPW;
    // T08 ADDI R15, R1, 7     10 +   7 = 17
    dut.mem[21] = ri(ADDI, 5'd1, 5'd15, 16'd7);
    dut.mem[22] = NOPW; dut.mem[23] = NOPW;
    // T09 SUBI R16, R6, 30   100 -  30 = 70
    dut.mem[24] = ri(SUBI, 5'd6, 5'd16, 16'd30);
    dut.mem[25] = NOPW; dut.mem[26] = NOPW;
    // T10 SLTI R17, R1, 15    10 <  15 = 1
    dut.mem[27] = ri(SLTI, 5'd1, 5'd17, 16'd15);
    dut.mem[28] = NOPW; dut.mem[29] = NOPW;
    // T11 SLTI R18, R6, 15   100 <  15 = 0
    dut.mem[30] = ri(SLTI, 5'd6, 5'd18, 16'd15);
    dut.mem[31] = NOPW; dut.mem[32] = NOPW;
    // T12 SW   R7, 50(R0)    mem[50]   = 10
    dut.mem[33] = ri(SW,   5'd0, 5'd7,  16'd50);
    dut.mem[34] = NOPW; dut.mem[35] = NOPW;
    // T13 LW   R19, 50(R0)   R19       = 10
    dut.mem[36] = ri(LW,   5'd0, 5'd19, 16'd50);
    dut.mem[37] = NOPW; dut.mem[38] = NOPW;
    // HLT
    dut.mem[39] = {HLT, 26'b0};
    // Fill tail with HLT so runaway fetch is safe
    for (i = 40; i < 1024; i = i + 1) dut.mem[i] = {HLT, 26'b0};

    //  Run until HALTED 
    $display("\n  Running ...\n");
    wait(dut.HALTED === 1'b1);
    repeat(4) @(posedge clk1);   // let final WB settle

    //  Print register file 
    $display("--- Register File ---");
    $display("R1  = %0d  (seed, expected 10)",  dut.Reg[1]);
    $display("R2  = %0d  (seed, expected 20)",  dut.Reg[2]);
    $display("R3  = %0d  (seed, expected  5)",  dut.Reg[3]);
    $display("R8  = %0d  (expected 30)",  dut.Reg[8]);
    $display("R9  = %0d  (expected 10)",  dut.Reg[9]);
    $display("R10 = %0d  (expected  5)",  dut.Reg[10]);
    $display("R11 = %0d  (expected 255)", dut.Reg[11]);
    $display("R12 = %0d  (expected  1)",  dut.Reg[12]);
    $display("R13 = %0d  (expected  0)",  dut.Reg[13]);
    $display("R14 = %0d  (expected 500)", dut.Reg[14]);
    $display("R15 = %0d  (expected 17)",  dut.Reg[15]);
    $display("R16 = %0d  (expected 70)",  dut.Reg[16]);
    $display("R17 = %0d  (expected  1)",  dut.Reg[17]);
    $display("R18 = %0d  (expected  0)",  dut.Reg[18]);
    $display("R19 = %0d  (expected 10)",  dut.Reg[19]);
    $display("mem[50] = %0d  (expected 10)", dut.mem[50]);

    $display("\n--- Pass/Fail Checks ---");
    check(dut.Reg[8],  32'd30,  "ADD  R8 =30");
    check(dut.Reg[9],  32'd10,  "SUB  R9 =10");
    check(dut.Reg[10], 32'd5,   "AND  R10= 5");
    check(dut.Reg[11], 32'd255, "OR   R11=255");
    check(dut.Reg[12], 32'd1,   "SLT  R12= 1");
    check(dut.Reg[13], 32'd0,   "SLT  R13= 0");
    check(dut.Reg[14], 32'd500, "MUL  R14=500");
    check(dut.Reg[15], 32'd17,  "ADDI R15=17");
    check(dut.Reg[16], 32'd70,  "SUBI R16=70");
    check(dut.Reg[17], 32'd1,   "SLTI R17= 1");
    check(dut.Reg[18], 32'd0,   "SLTI R18= 0");
    check(dut.mem[50], 32'd10,  "SW   mem[50]=10");
    check(dut.Reg[19], 32'd10,  "LW   R19=10");
    check(dut.Reg[0],  32'd0,   "R0   always 0");

    $display("\n--- Summary ---");
    $display("PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("ALL TESTS PASSED.");
    else
        $display("SOME TESTS FAILED - check output above.");

    $finish;
end

// Watchdog
initial begin #500000; $display("WATCHDOG: timeout"); $finish; end

// Waveform
initial begin
    $dumpfile("tb_MIPS32_pipe_no_hazard.vcd");
    $dumpvars(0, tb_MIPS32_pipe_no_hazard);
end

endmodule
