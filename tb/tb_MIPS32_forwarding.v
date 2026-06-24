module tb_MIPS32_forwarding;

// ── Clocks ──────────────────────────────────────────────────────────────────
reg clk1, clk2;
initial begin clk1 = 0; forever #10 clk1 = ~clk1; end
initial begin clk2 = 0; #10; forever #10 clk2 = ~clk2; end

// ── DUT ─────────────────────────────────────────────────────────────────────
MIPS32_pipe dut(.clk1(clk1), .clk2(clk2));

// ── Opcodes ─────────────────────────────────────────────────────────────────
localparam [5:0]
    ADD=6'b000000, SUB=6'b000001, HLT=6'b111111;

// ── Instruction builders ─────────────────────────────────────────────────────
function [31:0] rr;
    input [5:0] op; input [4:0] rs,rt,rd;
    rr = {op,rs,rt,rd,11'b0};
endfunction

// NOP = ADD R0,R0,R0 - writes R0 (no-op), safe bubble
localparam [31:0] NOP = 32'h00000000;

// ── Checker ──────────────────────────────────────────────────────────────────
integer pass_cnt, fail_cnt;
task check;
    input [31:0] got, exp;
    input [8*32:1] lbl;
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

    // ── Reset all DUT state ──────────────────────────────────────────────────
    dut.HALTED       = 1'b0;
    dut.TAKEN_BRANCH = 1'b0;
    dut.STALL        = 1'b0;
    dut.PC           = 32'd0;

    dut.IF_ID_IR     = 32'b0;  dut.IF_ID_NPC     = 32'b0;
    dut.ID_EX_IR     = 32'b0;  dut.ID_EX_NPC     = 32'b0;
    dut.ID_EX_A      = 32'b0;  dut.ID_EX_B       = 32'b0;
    dut.ID_EX_Imm    = 32'b0;  dut.ID_EX_type    = 3'b011; // STORE - WB ignores
    dut.EX_MEM_IR    = 32'b0;  dut.EX_MEM_ALUOut = 32'b0;
    dut.EX_MEM_B     = 32'b0;  dut.EX_MEM_COND   = 1'b0;
    dut.EX_MEM_type  = 3'b011;
    dut.MEM_WB_IR    = 32'b0;  dut.MEM_WB_ALUOut = 32'b0;
    dut.MEM_WB_LMD   = 32'b0;  dut.MEM_WB_type   = 3'b011; // STORE - WB ignores

    for (i = 0; i < 32;   i = i+1) dut.Reg[i] = 32'd0;
    for (i = 0; i < 1024; i = i+1) dut.mem[i] = 32'd0;

    // ── Seed registers ───────────────────────────────────────────────────────
    // R1=10, R2=20, R3=5
    dut.Reg[1] = 32'd10;
    dut.Reg[2] = 32'd20;
    dut.Reg[3] = 32'd5;

    // ══════════════════════════════════════════════════════════════════════════
    //  TEST 1 - EX/EX forwarding
    //
    //  Cycle:  IF        ID        EX             MEM    WB
    //  ------- --------- --------- -------------- ------ ------
    //    N     ADD R5... -         -              -      -
    //    N+1   SUB R6... ADD R5... -              -      -
    //    N+2   NOP       SUB R6... ADD R5→EX_MEM  -      -
    //    N+3   ...       NOP       SUB R6 ← EX_MEM_ALUOut=30 forwarded!
    //
    //  SUB R6 enters EX at N+3. At that moment EX_MEM_ALUOut holds ADD's
    //  result (30). The forwarding mux detects:
    //    EX_MEM_type == RR_ALU  AND
    //    EX_MEM_IR[15:11] == 5  (rd of ADD = R5)  AND
    //    ID_EX_IR[25:21]  == 5  (rs of SUB = R5)
    //  → supplies EX_A = 30 instead of the stale Reg[5]=0
    // ══════════════════════════════════════════════════════════════════════════
    dut.mem[0] = rr(ADD, 5'd1, 5'd2, 5'd5);  // ADD R5, R1, R2  → R5=30
    dut.mem[1] = rr(SUB, 5'd5, 5'd3, 5'd6);  // SUB R6, R5, R3  → R6=25  (NO NOP - EX/EX fwd)
    dut.mem[2] = NOP;
    dut.mem[3] = NOP;

    // ══════════════════════════════════════════════════════════════════════════
    //  TEST 2 - MEM/WB forwarding  (1 NOP gap between producer and consumer)
    //
    //  Cycle:  IF        ID        EX             MEM          WB
    //  ------- --------- --------- -------------- ------------ ------
    //    M     ADD R8... -         -              -            -
    //    M+1   NOP       ADD R8... -              -            -
    //    M+2   SUB R9... NOP       ADD R8→EX_MEM  -            -
    //    M+3   NOP       SUB R9... NOP            ADD→MEM_WB   -
    //    M+4   ...       NOP       SUB R9 ← MEM_WB_ALUOut=30 forwarded!
    //
    //  SUB R9 enters EX at M+4. At that point MEM_WB_ALUOut = 30 (ADD result).
    //  The forwarding mux detects:
    //    MEM_WB_type == RR_ALU  AND
    //    MEM_WB_IR[15:11] == 8  (rd of ADD = R8)  AND
    //    ID_EX_IR[25:21]  == 8  (rs of SUB = R8)
    //  → supplies EX_A = 30 instead of stale Reg[8]=0
    // ══════════════════════════════════════════════════════════════════════════
    dut.mem[4] = rr(ADD, 5'd1, 5'd2, 5'd8);  // ADD R8, R1, R2  → R8=30
    dut.mem[5] = NOP;                          // 1 NOP gap (MEM/WB path, not EX/EX)
    dut.mem[6] = rr(SUB, 5'd8, 5'd3, 5'd9);  // SUB R9, R8, R3  → R9=25  (MEM/WB fwd)
    dut.mem[7] = NOP;
    dut.mem[8] = NOP;

    // HLT
    dut.mem[9] = {HLT, 26'b0};
    for (i = 10; i < 1024; i = i+1) dut.mem[i] = {HLT, 26'b0};

    // ── Run ─────────────────────────────────────────────────────────────────
    $display("\n  Running forwarding tests ...\n");
    wait(dut.HALTED === 1'b1);
    repeat(4) @(posedge clk1);

    // ── Results ─────────────────────────────────────────────────────────────
    $display("--- Register File ---");
    $display("R1 = %0d  (seed, expected 10)", dut.Reg[1]);
    $display("R2 = %0d  (seed, expected 20)", dut.Reg[2]);
    $display("R3 = %0d  (seed, expected  5)", dut.Reg[3]);
    $display("R5 = %0d  (expected 30  - ADD result, EX/EX producer)", dut.Reg[5]);
    $display("R6 = %0d  (expected 25  - SUB via EX/EX forward)",      dut.Reg[6]);
    $display("R8 = %0d  (expected 30  - ADD result, MEM/WB producer)", dut.Reg[8]);
    $display("R9 = %0d  (expected 25  - SUB via MEM/WB forward)",      dut.Reg[9]);

    $display("\n--- Pass/Fail ---");
    check(dut.Reg[5], 32'd30, "EX/EX  producer  R5=30");
    check(dut.Reg[6], 32'd25, "EX/EX  consumer  R6=25");
    check(dut.Reg[8], 32'd30, "MEM/WB producer  R8=30");
    check(dut.Reg[9], 32'd25, "MEM/WB consumer  R9=25");

    $display("\n--- Summary ---");
    $display("PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("ALL FORWARDING TESTS PASSED.");
    else
        $display("SOME TESTS FAILED.");

    $finish;
end

initial begin #200000; $display("WATCHDOG: timeout"); $finish; end

initial begin
    $dumpfile("tb_MIPS32_forwarding.vcd");
    $dumpvars(0, tb_MIPS32_forwarding);
    // Also explicitly dump the register array entries we care about
    $dumpvars(0, dut.Reg[1], dut.Reg[2], dut.Reg[3]);
    $dumpvars(0, dut.Reg[5], dut.Reg[6]);
    $dumpvars(0, dut.Reg[8], dut.Reg[9]);
end

endmodule
