module tb_MIPS32_load_use;

// ── Clocks ───────────────────────────────────────────────────────────────────
reg clk1, clk2;
initial begin clk1 = 0; forever #10 clk1 = ~clk1; end
initial begin clk2 = 0; #10; forever #10 clk2 = ~clk2; end

// ── DUT ──────────────────────────────────────────────────────────────────────
MIPS32_pipe dut(.clk1(clk1), .clk2(clk2));

// ── Opcodes ──────────────────────────────────────────────────────────────────
localparam [5:0] ADD=6'b000000, LW=6'b001000, HLT=6'b111111;

// ── Instruction builders ──────────────────────────────────────────────────────
function [31:0] rr;
    input [5:0] op; input [4:0] rs,rt,rd;
    rr = {op,rs,rt,rd,11'b0};
endfunction
function [31:0] ri;
    input [5:0] op; input [4:0] rs,rt; input [15:0] imm;
    ri = {op,rs,rt,imm};
endfunction

localparam [31:0] NOP = 32'h00000000; // ADD R0,R0,R0

// ── Checker ───────────────────────────────────────────────────────────────────
integer pass_cnt, fail_cnt;
task check;
    input [31:0] got, exp;
    input [8*40:1] lbl;
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

// ── Monitor: capture EX_MEM_ALUOut when ADD is in EX ─────────────────────────
// ADD R6 opcode = 00a13000 hex = {ADD,R5,R1,R6,0}
// We detect when EX_MEM_IR matches ADD R6 and record the ALU output
reg [31:0] add_alu_result;
reg        add_alu_captured;
wire [31:0] ADD_R6_R5_R1 = rr(ADD, 5'd5, 5'd1, 5'd6);

always @(posedge clk1) begin
    if (dut.EX_MEM_IR === ADD_R6_R5_R1 && dut.EX_MEM_type === 3'b000) begin
        add_alu_result  <= dut.EX_MEM_ALUOut;
        add_alu_captured <= 1'b1;
    end
end

// ── STALL counter ─────────────────────────────────────────────────────────────
integer stall_count;
always @(posedge clk2)
    if (dut.STALL === 1'b1) stall_count = stall_count + 1;

integer i;
initial begin
    pass_cnt        = 0;
    fail_cnt        = 0;
    stall_count     = 0;
    add_alu_result  = 32'hx;
    add_alu_captured = 1'b0;

    // ── Reset DUT state ───────────────────────────────────────────────────────
    dut.HALTED       = 1'b0;
    dut.TAKEN_BRANCH = 1'b0;
    dut.STALL        = 1'b0;
    dut.PC           = 32'd0;

    dut.IF_ID_IR     = 32'b0;  dut.IF_ID_NPC     = 32'b0;
    dut.ID_EX_IR     = 32'b0;  dut.ID_EX_NPC     = 32'b0;
    dut.ID_EX_A      = 32'b0;  dut.ID_EX_B       = 32'b0;
    dut.ID_EX_Imm    = 32'b0;  dut.ID_EX_type    = 3'b011;
    dut.EX_MEM_IR    = 32'b0;  dut.EX_MEM_ALUOut = 32'b0;
    dut.EX_MEM_B     = 32'b0;  dut.EX_MEM_COND   = 1'b0;
    dut.EX_MEM_type  = 3'b011;
    dut.MEM_WB_IR    = 32'b0;  dut.MEM_WB_ALUOut = 32'b0;
    dut.MEM_WB_LMD   = 32'b0;  dut.MEM_WB_type   = 3'b011;

    for (i = 0; i < 32;   i = i+1) dut.Reg[i] = 32'd0;

    // Fill with HLT first, then write program and data
    for (i = 0; i < 1024; i = i+1) dut.mem[i] = {HLT, 26'b0};

    // Data
    dut.mem[50] = 32'd99;

    // Registers
    dut.Reg[1] = 32'd10;

    // Program:
    //  0: LW  R5, 50(R0)   -- load 99 into R5
    //  1: ADD R6, R5, R1   -- load-use hazard: needs R5 immediately
    //  (rest are HLT from fill)
    dut.mem[0] = ri(LW,  5'd0, 5'd5, 16'd50);
    dut.mem[1] = rr(ADD, 5'd5, 5'd1, 5'd6);

    // ── Run until HALTED ──────────────────────────────────────────────────────
    $display("\n  Running load-use hazard test ...\n");
    wait(dut.HALTED === 1'b1);
    repeat(4) @(posedge clk1);

    // ── Results ───────────────────────────────────────────────────────────────
    $display("--- Pipeline register results ---");
    $display("R5               = %0d  (expected 99  — LW wrote this)", dut.Reg[5]);
    $display("EX_MEM_ALUOut    = %0d  (captured when ADD was in EX)", add_alu_result);
    $display("mem[50]          = %0d  (expected 99  — unchanged)", dut.mem[50]);

    $display("\n--- Stall check ---");
    $display("STALL fired %0d cycle(s)  (expected exactly 1)", stall_count);

    $display("\n--- Pass/Fail ---");
    check(dut.Reg[5],      32'd99,  "LW  R5 = 99  (load completed)");
    check(add_alu_result,  32'd109, "ADD EX_MEM_ALUOut = 109 (fwd worked)");
    check(dut.mem[50],     32'd99,  "mem[50] unchanged = 99");

    if (stall_count == 1) begin
        $display("  PASS  STALL fired exactly 1 cycle");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL  STALL count = %0d (expected 1)", stall_count);
        fail_cnt = fail_cnt + 1;
    end

    $display("\n--- Summary ---");
    $display("PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("ALL LOAD-USE HAZARD TESTS PASSED.");
    else
        $display("SOME TESTS FAILED.");

    $finish;
end

initial begin #500000; $display("WATCHDOG: timeout"); $finish; end

initial begin
    $dumpfile("tb_MIPS32_load_use.vcd");
    $dumpvars(0, tb_MIPS32_load_use);
    $dumpvars(0, dut.Reg[1], dut.Reg[5]);
end

endmodule
