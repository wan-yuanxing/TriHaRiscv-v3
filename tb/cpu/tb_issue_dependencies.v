/* ISA vectors exercise actual issue gates, including true dependency guards. */
`timescale 1ns/1ps
module tb_issue_dependencies #(parameter DUAL_ISSUE=0, BROKEN=0);
    reg clk=0, rst=1, clock_run=1;
    reg [31:0] op_a=32'h13, op_b=32'h13, busy=0;
    integer checks=0;
    wire ai,ae,al,ab,am,ad,ac,ar,bi,be,bl,bb,bm,bd,bc,br;
    always #5 if (clock_run) clk=~clk;
    biriscv_decoder u_a (.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(op_a),
        .invalid_o(ai),.exec_o(ae),.lsu_o(al),.branch_o(ab),.mul_o(am),.div_o(ad),.csr_o(ac),.rd_valid_o(ar));
    biriscv_decoder u_b (.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(op_b),
        .invalid_o(bi),.exec_o(be),.lsu_o(bl),.branch_o(bb),.mul_o(bm),.div_o(bd),.csr_o(bc),.rd_valid_o(br));
    triha_cpu #(.SUPPORT_DUAL_ISSUE(DUAL_ISSUE),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    `define I u_dut.u_issue
    task check_a;
        input [31:0] opcode,blocked; input expected; input [255:0] reason;
        begin
            op_a=opcode; busy=blocked; #1; checks=checks+1;
            if (`I.opcode_a_issue_r!==expected || `I.opcode_a_accept_r!==expected)
                $fatal(1,"ISSUE_DEPENDENCIES_FAIL %0s op=%h busy=%h expected=%b actual=%b",reason,opcode,blocked,expected,`I.opcode_a_issue_r);
        end
    endtask
    task check_b;
        input [31:0] opcode,blocked; input expected;
        begin
            op_b=opcode; busy=blocked; #1; checks=checks+1;
            if (`I.opcode_b_issue_r!==expected || `I.opcode_b_accept_r!==expected)
                $fatal(1,"ISSUE_DEPENDENCIES_FAIL lane_b op=%h busy=%h expected=%b actual=%b",opcode,blocked,expected,`I.opcode_b_issue_r);
        end
    endtask
    // Register roles are supplied by each ISA test vector, independently of RTL decode.
    task sweep_busy;
        input [31:0] opcode;
        input [2:0] roles;
        integer regno;
        reg blocked;
        begin
            for (regno=0;regno<32;regno=regno+1) begin
                blocked=(regno!=0) && ((roles[0] && opcode[19:15]==regno) ||
                    (roles[1] && opcode[24:20]==regno) || (roles[2] && opcode[11:7]==regno));
                check_a(opcode,32'b1<<regno,!blocked,"ISA_busy_register_sweep");
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0; clock_run=0;
        force `I.opcode_a_r=op_a; force `I.opcode_b_r=op_b;
        force `I.opcode_a_valid_r=1; force `I.opcode_b_valid_r=0;
        force `I.opcode_a_fault_r=0; force `I.opcode_b_fault_r=0;
        force `I.issue_a_exec_w=ae; force `I.issue_a_lsu_w=al; force `I.issue_a_branch_w=ab;
        force `I.issue_a_mul_w=am; force `I.issue_a_div_w=ad; force `I.issue_a_csr_w=ac;
        force `I.issue_a_invalid_w=ai; force `I.issue_a_sb_alloc_w=ar;
        force `I.issue_b_exec_w=be; force `I.issue_b_lsu_w=bl; force `I.issue_b_branch_w=bb;
        force `I.issue_b_mul_w=bm; force `I.issue_b_div_w=bd; force `I.issue_b_csr_w=bc;
        force `I.issue_b_invalid_w=bi; force `I.issue_b_sb_alloc_w=br;
        force `I.squash_w=0; force `I.branch_csr_request_i=0; force `I.take_interrupt_i=0;
        force `I.lsu_stall_i=0; force `I.stall_w=0; force `I.div_pending_q=0; force `I.csr_pending_q=0;
        force `I.pipe0_load_e1_w=0; force `I.pipe0_store_e1_w=0; force `I.pipe0_mul_e1_w=0;
        force `I.pipe1_load_e1_w=0; force `I.pipe1_store_e1_w=0; force `I.pipe1_mul_e1_w=0;
        force `I.scoreboard_r=busy;
        check_a(32'h00538313,32'h20,1,"addi_immediate_not_rs2");
        check_a(32'h0043a303,32'h10,1,"load_offset_not_rs2");
        check_a(32'h00538337,32'ha0,1,"lui_not_sources");
        check_a(32'h00538317,32'ha0,1,"auipc_not_sources");
        check_a(32'h0053836f,32'ha0,1,"jal_not_sources");
        check_a(32'h00538363,32'h40,1,"branch_not_rd");
        check_a(32'h0053a323,32'h40,1,"store_not_rd");
        check_a(32'h3402d373,32'h20,1,"csr_immediate_not_source");
        check_a(32'h00538313,32'h80,0,"addi_real_rs1");
        check_a(32'h00538313,32'h40,0,"addi_real_waw");
        check_a(32'h00538333,32'h20,0,"add_real_rs2");
        check_a(32'h00538363,32'h20,0,"branch_real_rs2");
        check_a(32'h0053a323,32'h20,0,"store_real_rs2");
        check_a(32'h34029373,32'h20,0,"csr_real_rs1");
        check_a(32'hfe538333,32'h20,0,"illegal_conservative");
        force `I.opcode_a_fault_r=1;
        check_a(32'h00538313,32'h20,0,"fetch_fault_conservative");
        force `I.opcode_a_fault_r=0;
        check_a(32'h00000313,1,1,"x0_never_busy");
        force `I.squash_w=1; check_a(32'h00538313,0,0,"squash"); force `I.squash_w=0;
        force `I.branch_csr_request_i=1; check_a(32'h00538313,0,0,"redirect"); force `I.branch_csr_request_i=0;
        force `I.lsu_stall_i=1; check_a(32'h00538313,0,0,"lsu_wait"); force `I.lsu_stall_i=0;
        force `I.pipe0_load_e1_w=1;
        check_a(32'h34005073,32'hffffffff,0,"unit_wait_no_registers");
        force `I.pipe0_load_e1_w=0;
        sweep_busy(32'h00538313,3'b101); // ADDI
        sweep_busy(32'h0053a313,3'b101); // SLTI
        sweep_busy(32'h0053b313,3'b101); // SLTIU
        sweep_busy(32'h0053c313,3'b101); // XORI
        sweep_busy(32'h0053e313,3'b101); // ORI
        sweep_busy(32'h0053f313,3'b101); // ANDI
        sweep_busy(32'h00539313,3'b101); // SLLI
        sweep_busy(32'h0053d313,3'b101); // SRLI
        sweep_busy(32'h4053d313,3'b101); // SRAI
        sweep_busy(32'h00538303,3'b101); // LB
        sweep_busy(32'h00539303,3'b101); // LH
        sweep_busy(32'h0053a303,3'b101); // LW
        sweep_busy(32'h0053c303,3'b101); // LBU
        sweep_busy(32'h0053d303,3'b101); // LHU
        sweep_busy(32'h00538337,3'b100); // LUI
        sweep_busy(32'h00538317,3'b100); // AUIPC
        sweep_busy(32'h0053836f,3'b100); // JAL
        sweep_busy(32'h00538367,3'b101); // JALR
        sweep_busy(32'h00538363,3'b011); // BEQ
        sweep_busy(32'h00539363,3'b011); // BNE
        sweep_busy(32'h0053c363,3'b011); // BLT
        sweep_busy(32'h0053d363,3'b011); // BGE
        sweep_busy(32'h0053e363,3'b011); // BLTU
        sweep_busy(32'h0053f363,3'b011); // BGEU
        sweep_busy(32'h00538323,3'b011); // SB
        sweep_busy(32'h00539323,3'b011); // SH
        sweep_busy(32'h0053a323,3'b011); // SW
        sweep_busy(32'h00538333,3'b111); // ADD
        sweep_busy(32'h40538333,3'b111); // SUB
        sweep_busy(32'h02538333,3'b111); // MUL
        sweep_busy(32'h02539333,3'b111); // MULH
        sweep_busy(32'h0253a333,3'b111); // MULHSU
        sweep_busy(32'h0253b333,3'b111); // MULHU
        sweep_busy(32'h0253c333,3'b111); // DIV
        sweep_busy(32'h0253d333,3'b111); // DIVU
        sweep_busy(32'h0253e333,3'b111); // REM
        sweep_busy(32'h0253f333,3'b111); // REMU
        sweep_busy(32'h34029373,3'b101); // CSRRW
        sweep_busy(32'h3402a373,3'b101); // CSRRS
        sweep_busy(32'h3402b373,3'b101); // CSRRC
        sweep_busy(32'h3402d373,3'b100); // CSRRWI
        sweep_busy(32'h3402e373,3'b100); // CSRRSI
        sweep_busy(32'h3402f373,3'b100); // CSRRCI
        sweep_busy(32'hffffffff,3'b111); // illegal stays conservative
        force `I.stall_w=1; check_a(32'h00538313,0,0,"pipe_wait"); force `I.stall_w=0;
        force `I.div_pending_q=1; check_a(32'h00538313,0,0,"div_wait"); force `I.div_pending_q=0;
        force `I.csr_pending_q=1; check_a(32'h00538313,0,0,"csr_wait"); force `I.csr_pending_q=0;
        force `I.opcode_b_valid_r=1; op_a=32'h00000513;
        check_b(32'h00538313,32'h20,DUAL_ISSUE!=0);
        check_b(32'h00538313,32'h80,0);
        release `I.scoreboard_r; op_a=32'h00100293;
        check_b(32'h00028333,0,0); // actual lane-A allocation must block true RAW
        check_b(32'h00500313,0,DUAL_ISSUE!=0); // immediate 5 is not x5
        check_b(32'h00000293,0,0); // true WAW
        if (BROKEN) begin
            force `I.scoreboard_r=0; // destroy real hazard state, must be rejected
            if (DUAL_ISSUE) check_b(32'h00028333,0,0);
            else check_a(32'h00538333,32'h20,0,"destroyed_busy_state");
        end
        $display("ISSUE_DEPENDENCIES_PASS dual=%0d checks=%0d",DUAL_ISSUE,checks); $finish;
    end
    `undef I
endmodule
