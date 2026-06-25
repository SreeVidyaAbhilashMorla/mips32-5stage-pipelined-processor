module tb_MIPS32_controlhazard ;
 
    reg clk1, clk2;
    MIPS32_pipe dut(.clk1(clk1),.clk2(clk2));
 
    // clk1 posedge: 5,15,25...    clk2 posedge: 10,20,30...
    initial clk1=0; always #5 clk1=~clk1;
    initial clk2=0; initial #5 clk2=1; always #5 clk2=~clk2;
 
    parameter ADD=6'b000000,SUB=6'b000001,OR=6'b000011;
    parameter HLT=6'b111111;
    parameter LW=6'b001000,SW=6'b001001,ADDI=6'b001010;
    parameter BNEQZ=6'b001101,BEQZ=6'b001110;
 
    function [31:0] R_type;
        input [5:0] op; input [4:0] rs,rt,rd;
        R_type={op,rs,rt,rd,11'b0};
    endfunction
    function [31:0] I_type;
        input [5:0] op; input [4:0] rs,rt; input [15:0] imm;
        I_type={op,rs,rt,imm};
    endfunction
 
    integer pass_count=0, fail_count=0, i;
 
    task check;
        input [64*8-1:0] name;
        input [31:0] actual, expected;
        begin
            if (actual===expected) begin
                $display("  PASS  %0s  got=%0d", name, actual);
                pass_count=pass_count+1;
            end else begin
                $display("  FAIL  %0s  expected=%0d  got=%0d", name, expected, actual);
                fail_count=fail_count+1;
            end
        end
    endtask
 
    // Force all pipeline state to safe NOP (RR_ALU with zeros = ADD R0,R0,R0)
    // Load memory BEFORE releasing so first IF fetch reads correct instruction
    task force_reset;
        begin
            force dut.PC=0; force dut.HALTED=0; force dut.TAKEN_BRANCH=0;
            force dut.STALL=0; force dut.STARTED=0;
            force dut.IF_ID_IR=0; force dut.IF_ID_NPC=0;
            force dut.ID_EX_IR=0; force dut.ID_EX_NPC=0;
            force dut.ID_EX_A=0; force dut.ID_EX_B=0; force dut.ID_EX_Imm=0;
            force dut.ID_EX_type=3'b000;     // RR_ALU NOP
            force dut.EX_MEM_IR=0; force dut.EX_MEM_ALUOut=0;
            force dut.EX_MEM_B=0; force dut.EX_MEM_COND=0;
            force dut.EX_MEM_type=3'b000;
            force dut.MEM_WB_IR=0; force dut.MEM_WB_ALUOut=0;
            force dut.MEM_WB_LMD=0; force dut.MEM_WB_type=3'b000;
            for(i=0;i<32;  i=i+1) dut.Reg[i]=0;
            for(i=0;i<1024;i=i+1) dut.mem[i]=0;
        end
    endtask
 
    task release_and_run;
        begin
            @(posedge clk1);   // align, then release on edge
            release dut.PC; release dut.HALTED; release dut.TAKEN_BRANCH;
            release dut.STALL; release dut.STARTED;
            release dut.IF_ID_IR; release dut.IF_ID_NPC;
            release dut.ID_EX_IR; release dut.ID_EX_NPC;
            release dut.ID_EX_A; release dut.ID_EX_B; release dut.ID_EX_Imm;
            release dut.ID_EX_type;
            release dut.EX_MEM_IR; release dut.EX_MEM_ALUOut;
            release dut.EX_MEM_B; release dut.EX_MEM_COND; release dut.EX_MEM_type;
            release dut.MEM_WB_IR; release dut.MEM_WB_ALUOut;
            release dut.MEM_WB_LMD; release dut.MEM_WB_type;
        end
    endtask
 
    task wait_halt;
        input integer max_cyc;
        integer c;
        begin
            c=0;
            while(dut.HALTED==0 && c<max_cyc) begin @(posedge clk1); c=c+1; end
            if(c>=max_cyc) $display("  WARNING: halt timeout at %0d cycles", max_cyc);
            repeat(12) @(posedge clk1);   // drain all 5 stages fully
        end
    endtask
 
    // ============================================================
    initial begin
        $display("================================================");
        $display("  MIPS32_pipe — Control Hazard Testbench");
        $display("================================================");
        repeat(4) @(posedge clk1);
 
        // ============================================================
        // TEST 1 — BEQZ TAKEN (rs == 0)
        //
        // mem[0]: BEQZ R1, +3      R1=0 → condition TRUE → jump to mem[4]
        // mem[1]: ADDI R2,R0,11    wrong path — must be FLUSHED (R2 stays 0)
        // mem[2]: ADDI R3,R0,22    wrong path — must be FLUSHED (R3 stays 0)
        // mem[3]: ADDI R4,R0,33    wrong path — may or may not reach WB
        //                          depending on how many cycles before flush
        // mem[4]: ADDI R5,R0,55    correct target — R5=55
        // mem[5]: HLT
        //
        // With branch resolved in ID:
        //   Cycle N:   BEQZ in ID  → TAKEN_BRANCH=1
        //   Cycle N+1: IF flushes mem[1], fetches mem[4]
        //   Only 1 wrong instruction (mem[1]) entered pipeline before flush
        //   mem[2] and beyond never enter IF
        // ============================================================
        $display("\n--- TEST 1: BEQZ TAKEN (R1==0) ---");
        force_reset;
        dut.Reg[1]=0;
        dut.mem[0]=I_type(BEQZ, 5'd1,5'd0,16'd3);     // BEQZ R1, offset=3
        dut.mem[1]=I_type(ADDI, 5'd0,5'd2,16'd11);    // wrong — flushed
        dut.mem[2]=I_type(ADDI, 5'd0,5'd3,16'd22);    // never fetched
        dut.mem[3]=I_type(ADDI, 5'd0,5'd4,16'd33);    // never fetched
        dut.mem[4]=I_type(ADDI, 5'd0,5'd5,16'd55);    // correct target
        dut.mem[5]={HLT,26'b0};
        release_and_run;
        wait_halt(80);
        check("T1 R2=0 (flushed)",  dut.Reg[2], 32'd0);
        check("T1 R3=0 (unfetched)",dut.Reg[3], 32'd0);
        check("T1 R5=55 (target)",  dut.Reg[5], 32'd55);
 
        // ============================================================
        // TEST 2 — BEQZ NOT TAKEN (rs != 0)
        //
        // mem[0]: BEQZ R1, +3     R1=7 → condition FALSE → fall through
        // mem[1]: ADDI R2,R0,11   executes normally → R2=11
        // mem[2]: HLT
        //
        // No flush should happen. R2 must be written.
        // ============================================================
        $display("\n--- TEST 2: BEQZ NOT TAKEN (R1!=0) ---");
        force_reset;
        dut.Reg[1]=7;
        dut.mem[0]=I_type(BEQZ, 5'd1,5'd0,16'd3);
        dut.mem[1]=I_type(ADDI, 5'd0,5'd2,16'd11);    // must execute
        dut.mem[2]={HLT,26'b0};
        release_and_run;
        wait_halt(60);
        check("T2 R2=11 (executed)", dut.Reg[2], 32'd11);
        check("T2 R5=0 (not exec)", dut.Reg[5], 32'd0);
 
        // ============================================================
        // TEST 3 — BNEQZ TAKEN (rs != 0)
        //
        // mem[0]: BNEQZ R1, +3    R1=99 → condition TRUE → jump to mem[4]
        // mem[1]: ADDI R2,R0,11   wrong path — flushed
        // mem[4]: ADDI R6,R0,77   correct target → R6=77
        // mem[5]: HLT
        // ============================================================
        $display("\n--- TEST 3: BNEQZ TAKEN (R1!=0) ---");
        force_reset;
        dut.Reg[1]=99;
        dut.mem[0]=I_type(BNEQZ,5'd1,5'd0,16'd3);
        dut.mem[1]=I_type(ADDI, 5'd0,5'd2,16'd11);    // wrong path
        dut.mem[2]=I_type(ADDI, 5'd0,5'd3,16'd22);    // never fetched
        dut.mem[3]=I_type(ADDI, 5'd0,5'd4,16'd33);    // never fetched
        dut.mem[4]=I_type(ADDI, 5'd0,5'd6,16'd77);    // correct target
        dut.mem[5]={HLT,26'b0};
        release_and_run;
        wait_halt(80);
        check("T3 R2=0 (flushed)",  dut.Reg[2], 32'd0);
        check("T3 R6=77 (target)",  dut.Reg[6], 32'd77);
 
        // ============================================================
        // TEST 4 — BNEQZ NOT TAKEN (rs == 0)
        //
        // mem[0]: BNEQZ R1, +3    R1=0 → condition FALSE → fall through
        // mem[1]: ADDI R2,R0,44   executes normally → R2=44
        // mem[2]: HLT
        // ============================================================
        $display("\n--- TEST 4: BNEQZ NOT TAKEN (R1==0) ---");
        force_reset;
        dut.Reg[1]=0;
        dut.mem[0]=I_type(BNEQZ,5'd1,5'd0,16'd3);
        dut.mem[1]=I_type(ADDI, 5'd0,5'd2,16'd44);
        dut.mem[2]={HLT,26'b0};
        release_and_run;
        wait_halt(60);
        check("T4 R2=44 (executed)", dut.Reg[2], 32'd44);
        check("T4 R6=0 (not exec)", dut.Reg[6], 32'd0);
 
        // ============================================================
        // TEST 5 — BRANCH FLUSH KILLS A WRONG-PATH SW
        //
        // The instruction after the branch is a SW.
        // It must NOT write to memory because it is on the wrong path.
        //
        // mem[0]: ADDI R9,R0,200   R9=200  (safe memory addr for SW)
        // mem[1]: ADDI R10,R0,88   R10=88  (value to store)
        // mem[2]: BEQZ R1, +2      R1=0 → taken → jump to mem[5]
        // mem[3]: SW R10,0(R9)     wrong path — must NOT write mem[200]
        // mem[4]: ADDI R3,R0,99    wrong path — must NOT write R3
        // mem[5]: ADDI R5,R0,66    correct target → R5=66
        // mem[6]: HLT
        //
        // After test: mem[200] must still be 0
        // ============================================================
        $display("\n--- TEST 5: Branch Flush Kills Wrong-Path SW ---");
        force_reset;
        dut.Reg[1]=0;
        dut.mem[0] =I_type(ADDI,5'd0,5'd9, 16'd200);  // R9=200
        dut.mem[1] =I_type(ADDI,5'd0,5'd10,16'd88);   // R10=88
        dut.mem[2] =I_type(BEQZ,5'd1,5'd0, 16'd2);    // BEQZ R1,+2 → mem[5]
        dut.mem[3] =I_type(SW,  5'd9,5'd10,16'd0);    // wrong path SW
        dut.mem[4] =I_type(ADDI,5'd0,5'd3, 16'd99);   // wrong path
        dut.mem[5] =I_type(ADDI,5'd0,5'd5, 16'd66);   // correct target
        dut.mem[6] ={HLT,26'b0};
        release_and_run;
        wait_halt(100);
        check("T5 R3=0 (flushed)",      dut.Reg[3],  32'd0);
        check("T5 R5=66 (target)",      dut.Reg[5],  32'd66);
        check("T5 mem[200]=0 (no SW)",  dut.mem[200],32'd0);
 
        // ============================================================
        // TEST 6 — FORWARD THEN BRANCH
        //
        // The branch register rs has a RAW dependency (just computed).
        // We insert 2 NOPs so forwarding resolves it before the branch
        // reads the register file in ID.
        //
        // mem[0]: ADDI R1,R0,0     R1=0  (set branch condition)
        // mem[1]: NOP
        // mem[2]: NOP
        // mem[3]: BEQZ R1, +2     R1=0 → taken → jump to mem[6]
        // mem[4]: ADDI R2,R0,99   wrong path
        // mem[5]: ADDI R3,R0,99   wrong path
        // mem[6]: ADDI R8,R0,42   correct target → R8=42
        // mem[7]: HLT
        // ============================================================
        $display("\n--- TEST 6: Forwarded Value then BEQZ ---");
        force_reset;
        dut.mem[0]=I_type(ADDI,5'd0,5'd1,16'd0);      // R1=0
        dut.mem[1]=32'b0;                               // NOP
        dut.mem[2]=32'b0;                               // NOP
        dut.mem[3]=I_type(BEQZ,5'd1,5'd0,16'd2);      // BEQZ R1,+2 → mem[6]
        dut.mem[4]=I_type(ADDI,5'd0,5'd2,16'd99);     // wrong path
        dut.mem[5]=I_type(ADDI,5'd0,5'd3,16'd99);     // wrong path
        dut.mem[6]=I_type(ADDI,5'd0,5'd8,16'd42);     // correct target
        dut.mem[7]={HLT,26'b0};
        release_and_run;
        wait_halt(100);
        check("T6 R1=0",             dut.Reg[1], 32'd0);
        check("T6 R2=0 (flushed)",   dut.Reg[2], 32'd0);
        check("T6 R8=42 (target)",   dut.Reg[8], 32'd42);
 
        // ============================================================
        // TEST 7 — TWO CONSECUTIVE BRANCHES (both taken)
        //
        // Tests that after the first branch flushes and redirects,
        // the second branch at the target also resolves correctly.
        //
        // mem[0]: BEQZ R1, +2     R1=0 → taken → jump to mem[3]
        // mem[1]: ADDI R2,R0,99   wrong path — flushed
        // mem[2]: ADDI R3,R0,99   wrong path — not fetched
        // mem[3]: BEQZ R1, +2     R1=0 → taken → jump to mem[6]
        // mem[4]: ADDI R4,R0,99   wrong path — flushed
        // mem[5]: ADDI R5,R0,99   wrong path — not fetched
        // mem[6]: ADDI R9,R0,77   final target → R9=77
        // mem[7]: HLT
        // ============================================================
        $display("\n--- TEST 7: Two Consecutive Branches (both taken) ---");
        force_reset;
        dut.Reg[1]=0;
        dut.mem[0]=I_type(BEQZ, 5'd1,5'd0,16'd2);    // branch 1 → mem[3]
        dut.mem[1]=I_type(ADDI, 5'd0,5'd2,16'd99);   // flushed
        dut.mem[2]=I_type(ADDI, 5'd0,5'd3,16'd99);   // not fetched
        dut.mem[3]=I_type(BEQZ, 5'd1,5'd0,16'd2);    // branch 2 → mem[6]
        dut.mem[4]=I_type(ADDI, 5'd0,5'd4,16'd99);   // flushed
        dut.mem[5]=I_type(ADDI, 5'd0,5'd5,16'd99);   // not fetched
        dut.mem[6]=I_type(ADDI, 5'd0,5'd9,16'd77);   // final target
        dut.mem[7]={HLT,26'b0};
        release_and_run;
        wait_halt(100);
        check("T7 R2=0 (flushed)",  dut.Reg[2], 32'd0);
        check("T7 R4=0 (flushed)",  dut.Reg[4], 32'd0);
        check("T7 R9=77 (target)",  dut.Reg[9], 32'd77);
 
        // ============================================================
        // TEST 8 — BRANCH FOLLOWED BY COMPUTATION AT TARGET
        //
        // After the branch target executes, results must be correct.
        // Target does ADD using preloaded registers → verifies pipeline
        // resumes cleanly after flush.
        //
        // mem[0]: BEQZ R1, +1     R1=0 → taken → jump to mem[2]
        // mem[1]: ADDI R10,R0,99  wrong path — flushed
        // mem[2]: ADD  R3,R4,R5   target: R3 = R4+R5 = 25+17 = 42
        // mem[3]: HLT
        // ============================================================
        $display("\n--- TEST 8: Computation at Branch Target ---");
        force_reset;
        dut.Reg[1]=0;
        dut.Reg[4]=25;
        dut.Reg[5]=17;
        dut.mem[0]=I_type(BEQZ, 5'd1,5'd0,16'd1);        // BEQZ R1,+1 → mem[2]
        dut.mem[1]=I_type(ADDI, 5'd0,5'd10,16'd99);      // wrong path
        dut.mem[2]=R_type(ADD,  5'd4,5'd5,5'd3);         // R3=R4+R5=42
        dut.mem[3]={HLT,26'b0};
        release_and_run;
        wait_halt(60);
        check("T8 R10=0 (flushed)", dut.Reg[10],32'd0);
        check("T8 R3=42 (target)",  dut.Reg[3], 32'd42);
 
        // ============================================================
        $display("\n================================================");
        $display("  Results: %0d PASSED,  %0d FAILED  (out of %0d)",
                  pass_count,fail_count,pass_count+fail_count);
        $display("================================================");
        $finish;
    end
 
endmodule
