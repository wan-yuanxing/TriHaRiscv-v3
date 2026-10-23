/* Passive TCM observer. Categories partition the real cycle-CSR interval;
 * role-qualified hazards are opportunity counts, not claimed saved cycles.
 */
`timescale 1ns/1ps
module tb_dual_profile;
    tb_triha_core #(.DUAL_ISSUE(1), .FIRMWARE_MODE(1), .MAX_CYCLES(3000000)) u_tb ();
    `define I u_tb.u_dut.u_cpu.u_issue
    `define C u_tb.u_dut.u_cpu.u_csr.u_csrfile
    integer reads = 0, wb_file, store_file;
    integer wb_events = 0, stores = 0;
    integer total = 0, issued = 0, paired = 0, frontend = 0, lsu = 0;
    integer pipe_wait = 0, div_wait = 0, csr_wait = 0, cancel = 0, unit_wait = 0, dependency = 0;
    integer false_a = 0, false_b = 0, pair_no_word = 0, pair_structure = 0, pair_dependency = 0;
    integer early_mul_opportunity = 0;
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
        wb_file = $fopen("tcm.wb.log", "w");
        store_file = $fopen("tcm.store.log", "w");
        if (!wb_file || !store_file) $fatal(1, "TCM_PROFILE_FAIL trace_open");
    end
    always @(posedge u_tb.clk) if (u_tb.rst_ni) begin
        if (`C.csr_ren_i && `C.csr_raddr_i == 12'hc00) begin
            if (reads == 0) start_cycle = `C.csr_mcycle_q;
            else if (reads == 1) elapsed = `C.csr_mcycle_q - start_cycle;
            reads = reads + 1;
        end
        if (reads == 1) begin
            sample_issue;
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
            if (|u_tb.data_wstrb && u_tb.data_accept) begin
                stores = stores + 1;
                $fwrite(store_file, "%08h %h %08h\n", u_tb.data_addr, u_tb.data_wstrb, u_tb.data_wdata);
            end
        end
    end
    task sample_issue;
        begin
            total = total + 1;
            a_roles = roles(`I.opcode_a_r, `I.issue_a_invalid_w, `I.opcode_a_fault_r);
            b_roles = roles(`I.opcode_b_r, `I.issue_b_invalid_w, `I.opcode_b_fault_r);
            a_real_busy = busy(`I.opcode_a_r, `I.scoreboard_r, a_roles);
            b_real_busy = busy(`I.opcode_b_r, `I.scoreboard_r, b_roles);
            if (`I.opcode_a_issue_r && `I.opcode_a_accept_r) begin
                issued = issued + 1;
                if (`I.dual_issue_w) paired = paired + 1;
                else if (!`I.opcode_b_valid_r) pair_no_word = pair_no_word + 1;
                else if (!`I.dual_issue_ok_w) pair_structure = pair_structure + 1;
                else begin
                    pair_dependency = pair_dependency + 1;
                    if (!b_real_busy) false_b = false_b + 1;
                end
            end else if (`I.branch_csr_request_i || `I.squash_w) cancel = cancel + 1;
            else if (`I.lsu_stall_i) lsu = lsu + 1;
            else if (`I.stall_w) pipe_wait = pipe_wait + 1;
            else if (`I.div_pending_q) div_wait = div_wait + 1;
            else if (`I.csr_pending_q) csr_wait = csr_wait + 1;
            else if (!`I.opcode_a_valid_r) frontend = frontend + 1;
            else if ((`I.pipe0_load_e1_w || `I.pipe0_store_e1_w || `I.pipe1_load_e1_w || `I.pipe1_store_e1_w) &&
                     (`I.issue_a_mul_w || `I.issue_a_div_w || `I.issue_a_csr_w)) unit_wait = unit_wait + 1;
            else begin
                dependency = dependency + 1;
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
    always @(negedge u_tb.clk) if (u_tb.rst_ni) begin
        if (reads == 2 && !printed) begin
            printed = 1;
            $fclose(wb_file); $fclose(store_file);
            if (total != elapsed || total != issued + cancel + lsu + pipe_wait + div_wait + csr_wait + frontend + unit_wait + dependency ||
                issued != paired + pair_no_word + pair_structure + pair_dependency || wb_events != u_tb.retired_window)
                $fatal(1, "TCM_PROFILE_FAIL partition_or_window total=%0d elapsed=%0d wb=%0d parent_wb=%0d", total, elapsed, wb_events, u_tb.retired_window);
            $display("TCM_PROFILE_PASS cycles=%0d wb=%0d stores=%0d issued=%0d paired=%0d frontend=%0d lsu=%0d pipe=%0d div=%0d csr=%0d cancel=%0d unit=%0d dependency=%0d false_a=%0d false_b=%0d pair_no_word=%0d pair_structure=%0d pair_dependency=%0d narrow_mul_opportunity=%0d",
                total, wb_events, stores, issued, paired, frontend, lsu, pipe_wait, div_wait, csr_wait, cancel, unit_wait,
                dependency, false_a, false_b, pair_no_word, pair_structure, pair_dependency, early_mul_opportunity);
        end
    end
    `undef I
    `undef C
endmodule
