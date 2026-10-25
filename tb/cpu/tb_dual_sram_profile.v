/* Passive real-SRAM observer. Categories partition the real cycle-CSR interval;
 * role-qualified hazards are opportunity counts, not claimed saved cycles.
 */
`timescale 1ns/1ps
module tb_dual_sram_profile;
    tb_dual_sram u_tb ();
    `define I u_tb.u_dut.u_core.u_cpu.u_issue
    `define C u_tb.u_dut.u_core.u_cpu.u_csr.u_csrfile
    `define F u_tb.u_dut.u_core.u_cpu.u_frontend.u_decode.genblk1.u_fifo
    integer reads = 0, wb_file, store_file;
    integer wb_events = 0, stores = 0;
    integer total = 0, issued = 0, paired = 0, frontend = 0, lsu = 0;
    integer pipe_wait = 0, div_wait = 0, csr_wait = 0, cancel = 0, unit_wait = 0, dependency = 0;
    integer false_a = 0, false_b = 0, pair_no_word = 0, pair_structure = 0, pair_dependency = 0;
    integer early_mul_opportunity = 0;
    integer a_waw_only=0,b_waw_only=0;
    integer structure_lsu_pair=0, structure_branch_a=0, structure_other=0;
    integer pair_raw=0, pair_waw=0, pair_older=0;
    integer queue0=0,queue1=0,queue2=0,queue3=0,queue4=0,queue5=0,queue6=0,queue7=0,queue8=0;
    integer backpressure=0,backpressure_pop=0,frontend_empty=0,frontend_pc=0;
    integer branch_pairs=0,branch_zero_eqne=0,branch_zero_signed=0,branch_zero_unsigned=0,branch_nonzero=0;
    integer conditional_branches=0,conditional_taken=0,conditional_not_taken=0;
    integer direct_jumps=0,indirect_jumps=0,pc_mismatch_cycles=0,pc_mismatch_episodes=0;
    reg pc_mismatch_previous=0;
    reg [31:0] start_cycle = 0, elapsed = 0;
    reg printed = 0;
    reg [2:0] a_roles, b_roles;
    reg a_real_busy, b_real_busy;
    reg early0, early1;
    reg [31:0] busy_after_early;

    // Independent ISA major-opcode model: bits are {rd,rs2,rs1}.
    // Illegal/fetch-fault packets keep the original conservative policy.
    function [2:0] roles;
        input [31:0] op;
        input invalid;
        input [1:0] fault;
        begin
            roles = 3'b111;
            if (!invalid && fault == 0)
                case (op[6:0])
                    7'h37, 7'h17, 7'h6f: roles = 3'b100;
                    7'h67, 7'h03, 7'h13: roles = 3'b101;
                    7'h23, 7'h63: roles = 3'b011;
                    7'h33: roles = 3'b111;
                    7'h73: roles = op[14:12] == 0 ? 3'b000 : (op[14] ? 3'b100 : 3'b101);
                    7'h0f: roles = 3'b000;
                    default: roles = 3'b111;
                endcase
        end
    endfunction
    function busy;
        input [31:0] op, scoreboard;
        input [2:0] used;
        begin
            busy = (used[0] && |op[19:15] && scoreboard[op[19:15]]) ||
                   (used[1] && |op[24:20] && scoreboard[op[24:20]]) ||
                   (used[2] && |op[11:7] && scoreboard[op[11:7]]);
        end
    endfunction
    initial begin
        wb_file = $fopen("sram.wb.log", "w");
        store_file = $fopen("sram.store.log", "w");
        if (!wb_file || !store_file) $fatal(1, "SRAM_PROFILE_FAIL trace_open");
    end
    always @(posedge u_tb.clk) if (u_tb.rst_n) begin
        if (`C.csr_ren_i && `C.csr_raddr_i == 12'hc00) begin
            if (reads == 0) start_cycle = `C.csr_mcycle_q;
            else if (reads == 1) elapsed = `C.csr_mcycle_q - start_cycle;
            reads = reads + 1;
        end
        if (reads == 1) begin
            sample_issue;
            sample_branch(u_tb.u_dut.u_core.u_cpu.exec0_opcode_valid_w,
                u_tb.u_dut.u_core.u_cpu.opcode0_opcode_w,`I.branch_d_exec0_request_i);
            sample_branch(u_tb.u_dut.u_core.u_cpu.exec1_opcode_valid_w,
                u_tb.u_dut.u_core.u_cpu.opcode1_opcode_w,`I.branch_d_exec1_request_i);
            if (`I.mispredicted_r) begin
                pc_mismatch_cycles=pc_mismatch_cycles+1;
                if (!pc_mismatch_previous) pc_mismatch_episodes=pc_mismatch_episodes+1;
            end
            if (`I.pipe0_valid_wb_w) begin
                wb_events = wb_events + 1;
                $fwrite(wb_file, "%08h %08h %02h %08h %02h\n", `I.pipe0_pc_wb_w,
                    `I.pipe0_opc_wb_w, `I.pipe0_rd_wb_w,
                    |`I.pipe0_rd_wb_w ? `I.pipe0_result_wb_w : 32'b0, `I.pipe0_exception_wb_w);
            end
            if (`I.pipe1_valid_wb_w) begin
                wb_events = wb_events + 1;
                $fwrite(wb_file, "%08h %08h %02h %08h %02h\n", `I.pipe1_pc_wb_w,
                    `I.pipe1_opc_wb_w, `I.pipe1_rd_wb_w,
                    |`I.pipe1_rd_wb_w ? `I.pipe1_result_wb_w : 32'b0, `I.pipe1_exception_wb_w);
            end
            if (|u_tb.u_dut.data_wstrb && u_tb.u_dut.data_accept) begin
                stores = stores + 1;
                $fwrite(store_file, "%08h %h %08h\n", u_tb.u_dut.data_addr, u_tb.u_dut.data_wstrb, u_tb.u_dut.data_wdata);
            end
        end
        pc_mismatch_previous=`I.mispredicted_r;
    end
    // Observable issue/recovery events, not a hypothetical new pipeline score.
    task sample_branch;
        input valid;
        input [31:0] opcode;
        input taken;
        begin
            if(valid)case(opcode[6:0])
                7'h63:case(opcode[14:12])
                    0,1,4,5,6,7:begin
                        conditional_branches=conditional_branches+1;
                        case(taken)
                            1'b1:conditional_taken=conditional_taken+1;
                            1'b0:conditional_not_taken=conditional_not_taken+1;
                            default:$fatal(1,"SRAM_PROFILE_FAIL unknown_branch_result");
                        endcase
                    end
                endcase
                7'h6f:direct_jumps=direct_jumps+1;
                7'h67:if(opcode[14:12]==0)indirect_jumps=indirect_jumps+1;
            endcase
        end
    endtask
    task sample_issue;
        begin
            total = total + 1;
            case (`F.count_q)
                0: queue0=queue0+1;
                1: queue1=queue1+1;
                2: queue2=queue2+1;
                3: queue3=queue3+1;
                4: queue4=queue4+1;
                5: queue5=queue5+1;
                6: queue6=queue6+1;
                7: queue7=queue7+1;
                8: queue8=queue8+1;
                default: $fatal(1,"SRAM_PROFILE_FAIL queue_occupancy");
            endcase
            if (!`F.accept_o && u_tb.u_dut.u_core.u_cpu.u_frontend.fetch_valid_w) begin
                backpressure=backpressure+1;
                if (`F.pop_a_w || `F.pop_b_w) backpressure_pop=backpressure_pop+1;
            end
            a_roles = roles(`I.opcode_a_r, `I.issue_a_invalid_w, `I.opcode_a_fault_r);
            b_roles = roles(`I.opcode_b_r, `I.issue_b_invalid_w, `I.opcode_b_fault_r);
            a_real_busy = busy(`I.opcode_a_r, `I.scoreboard_r, a_roles);
            b_real_busy = busy(`I.opcode_b_r, `I.scoreboard_r, b_roles);
            if (`I.opcode_a_issue_r && `I.opcode_a_accept_r) begin
                issued = issued + 1;
                if(`I.dual_issue_w && `I.issue_a_branch_w)begin
                    branch_pairs=branch_pairs+1;
                    if(`I.opcode_a_r[19:15]==0 || `I.opcode_a_r[24:20]==0)
                        case(`I.opcode_a_r[14:12])
                            0,1:branch_zero_eqne=branch_zero_eqne+1;
                            4,5:branch_zero_signed=branch_zero_signed+1;
                            6,7:branch_zero_unsigned=branch_zero_unsigned+1;
                        endcase
                    else branch_nonzero=branch_nonzero+1;
                end
                if (`I.dual_issue_w) paired = paired + 1;
                else if (!`I.opcode_b_valid_r) pair_no_word = pair_no_word + 1;
                else if (!`I.dual_issue_ok_w) begin
                    pair_structure = pair_structure + 1;
                    if (`I.issue_a_lsu_w && `I.issue_b_lsu_w) structure_lsu_pair=structure_lsu_pair+1;
                    else if (`I.issue_a_branch_w) structure_branch_a=structure_branch_a+1;
                    else structure_other=structure_other+1;
                end
                else begin
                    pair_dependency = pair_dependency + 1;
                    if(b_roles[2] && |`I.opcode_b_r[11:7] && `I.scoreboard_r[`I.opcode_b_r[11:7]] &&
                       !busy(`I.opcode_b_r,`I.scoreboard_r,{1'b0,b_roles[1:0]})) b_waw_only=b_waw_only+1;
                    if (a_roles[2] && |`I.opcode_a_r[11:7] &&
                        ((b_roles[0] && `I.opcode_b_r[19:15]==`I.opcode_a_r[11:7]) ||
                         (b_roles[1] && `I.opcode_b_r[24:20]==`I.opcode_a_r[11:7]))) pair_raw=pair_raw+1;
                    else if (a_roles[2] && b_roles[2] && |`I.opcode_a_r[11:7] &&
                        `I.opcode_b_r[11:7]==`I.opcode_a_r[11:7]) pair_waw=pair_waw+1;
                    else pair_older=pair_older+1;
                    if (!b_real_busy) false_b = false_b + 1;
                end
            end else if (`I.branch_csr_request_i || `I.squash_w) cancel = cancel + 1;
            else if (`I.lsu_stall_i) lsu = lsu + 1;
            else if (`I.stall_w) pipe_wait = pipe_wait + 1;
            else if (`I.div_pending_q) div_wait = div_wait + 1;
            else if (`I.csr_pending_q) csr_wait = csr_wait + 1;
            else if (!`I.opcode_a_valid_r) begin
                frontend = frontend + 1;
                if (`F.count_q==0) frontend_empty=frontend_empty+1;
                else frontend_pc=frontend_pc+1;
            end
            else if ((`I.pipe0_load_e1_w || `I.pipe0_store_e1_w || `I.pipe1_load_e1_w || `I.pipe1_store_e1_w) &&
                     (`I.issue_a_mul_w || `I.issue_a_div_w || `I.issue_a_csr_w)) unit_wait = unit_wait + 1;
            else begin
                dependency = dependency + 1;
                if(a_roles[2] && |`I.opcode_a_r[11:7] && `I.scoreboard_r[`I.opcode_a_r[11:7]] &&
                   !busy(`I.opcode_a_r,`I.scoreboard_r,{1'b0,a_roles[1:0]})) a_waw_only=a_waw_only+1;
                if (!a_real_busy) false_a = false_a + 1;
                early0 = `I.writeback_mul_early_valid_i && `I.pipe0_mul_e1_w &&
                    (`I.pipe0_opcode_e1_w & 32'hfe00707f) == 32'h02000033;
                early1 = `I.writeback_mul_early_valid_i && `I.pipe1_mul_e1_w &&
                    (`I.pipe1_opcode_e1_w & 32'hfe00707f) == 32'h02000033;
                // Rebuild pre-A busy state with only eligible E1 MUL blockers
                // removed. Loads/wide/high MUL and another same-rd producer
                // remain busy. The resource interlock was classified above.
                busy_after_early = 0;
                if (`I.pipe0_load_e1_w || (`I.pipe0_mul_e1_w && !early0))
                    busy_after_early[`I.pipe0_rd_e1_w] = 1'b1;
                if (`I.pipe1_load_e1_w || (`I.pipe1_mul_e1_w && !early1))
                    busy_after_early[`I.pipe1_rd_e1_w] = 1'b1;
                if ((early0 || early1) && a_real_busy && !busy(`I.opcode_a_r, busy_after_early, a_roles))
                    early_mul_opportunity = early_mul_opportunity + 1;
            end
        end
    endtask
    always @(negedge u_tb.clk) if (u_tb.rst_n) begin
        if (reads == 2 && !printed) begin
            printed = 1;
            $fclose(wb_file); $fclose(store_file);
            if (total != elapsed || total != issued + cancel + lsu + pipe_wait + div_wait + csr_wait + frontend + unit_wait + dependency ||
                pair_structure != structure_lsu_pair+structure_branch_a+structure_other ||
                pair_dependency != pair_raw+pair_waw+pair_older ||
                total != queue0+queue1+queue2+queue3+queue4+queue5+queue6+queue7+queue8 ||
                frontend != frontend_empty+frontend_pc ||
                branch_pairs != branch_zero_eqne+branch_zero_signed+branch_zero_unsigned+branch_nonzero ||
                issued != paired + pair_no_word + pair_structure + pair_dependency || wb_events != u_tb.wb_window)
                $fatal(1, "SRAM_PROFILE_FAIL partition_or_window total=%0d elapsed=%0d wb=%0d parent_wb=%0d", total, elapsed, wb_events, u_tb.wb_window);
            $display("SRAM_PROFILE_PASS cycles=%0d wb=%0d stores=%0d issued=%0d paired=%0d frontend=%0d lsu=%0d pipe=%0d div=%0d csr=%0d cancel=%0d unit=%0d dependency=%0d false_a=%0d false_b=%0d pair_no_word=%0d pair_structure=%0d pair_dependency=%0d narrow_mul_opportunity=%0d structure_lsu_pair=%0d structure_branch_a=%0d structure_other=%0d pair_raw=%0d pair_waw=%0d pair_older=%0d a_waw_only=%0d b_waw_only=%0d queue0=%0d queue1=%0d queue2=%0d queue3=%0d queue4=%0d queue5=%0d queue6=%0d queue7=%0d queue8=%0d backpressure=%0d backpressure_pop=%0d frontend_empty=%0d frontend_pc=%0d branch_pairs=%0d branch_zero_eqne=%0d branch_zero_signed=%0d branch_zero_unsigned=%0d branch_nonzero=%0d",
                total, wb_events, stores, issued, paired, frontend, lsu, pipe_wait, div_wait, csr_wait, cancel, unit_wait,
                dependency, false_a, false_b, pair_no_word, pair_structure, pair_dependency, early_mul_opportunity, structure_lsu_pair, structure_branch_a, structure_other, pair_raw, pair_waw, pair_older, a_waw_only, b_waw_only,
                queue0,queue1,queue2,queue3,queue4,queue5,queue6,queue7,queue8,backpressure,backpressure_pop,frontend_empty,frontend_pc,
                branch_pairs,branch_zero_eqne,branch_zero_signed,branch_zero_unsigned,branch_nonzero);
            if(conditional_branches!=conditional_taken+conditional_not_taken)
                $fatal(1,"SRAM_PROFILE_FAIL branch_partition");
            $display("SRAM_BRANCH_PROFILE_PASS conditional=%0d taken=%0d not_taken=%0d jal=%0d jalr=%0d pc_mismatch_cycles=%0d pc_mismatch_episodes=%0d",
                conditional_branches,conditional_taken,conditional_not_taken,direct_jumps,indirect_jumps,pc_mismatch_cycles,pc_mismatch_episodes);
        end
    end
    `undef I
    `undef C
    `undef F
endmodule
