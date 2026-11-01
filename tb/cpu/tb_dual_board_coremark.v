`timescale 1ns/1ps
/* Physical UART decoding of the short board preflight; no accelerated UART. */
module tb_cpu_coremark;
    reg ref_clk = 0;
    reg rst_n = 0;
    wire tx;
    wire [3:0] led;
    integer cycles = 0, bit_index, reads = 0, paired = 0;
    reg [7:0] serial_byte;
    reg [31:0] started = 0, elapsed = 0;
    integer profile_cycles=0, profile_issue=0, profile_frontend=0, profile_lsu=0;
    integer profile_pipe=0, profile_div=0, profile_csr=0, profile_cancel=0;
    integer profile_unit=0, profile_dependency=0, profile_other=0, profile_false=0;
    integer profile_wb=0, profile_stores=0, wb_file, store_file;
    `define PROFILE_ISSUE u_dut.u_soc.u_core.u_cpu.u_issue
    // Diagnostic ISA field-use model. This is outside the synthesized design.
    function [2:0] profile_register_use;
        input [31:0] opcode;
        begin
            profile_register_use=3'b111; // rd, rs2, rs1; unknown stays conservative
            case (opcode[6:0])
                7'h03,7'h13,7'h67: profile_register_use=3'b101;
                7'h17,7'h37,7'h6f: profile_register_use=3'b100;
                7'h23,7'h63: profile_register_use=3'b011;
                7'h73: case (opcode[14:12])
                    3'b001,3'b010,3'b011: profile_register_use=3'b101;
                    3'b101,3'b110,3'b111: profile_register_use=3'b100;
                    default: profile_register_use=3'b111;
                endcase
            endcase
        end
    endfunction
    wire [2:0] profile_use = (`PROFILE_ISSUE.issue_a_invalid_w ||
        (|`PROFILE_ISSUE.opcode_a_fault_r)) ? 3'b111 :
        profile_register_use(`PROFILE_ISSUE.opcode_a_r);
    wire profile_real_dependency =
        (profile_use[0] && (|`PROFILE_ISSUE.issue_a_ra_idx_w) && `PROFILE_ISSUE.scoreboard_r[`PROFILE_ISSUE.issue_a_ra_idx_w]) ||
        (profile_use[1] && (|`PROFILE_ISSUE.issue_a_rb_idx_w) && `PROFILE_ISSUE.scoreboard_r[`PROFILE_ISSUE.issue_a_rb_idx_w]) ||
        (profile_use[2] && (|`PROFILE_ISSUE.issue_a_rd_idx_w) && `PROFILE_ISSUE.scoreboard_r[`PROFILE_ISSUE.issue_a_rd_idx_w]);
    wire profile_old_dependency = `PROFILE_ISSUE.scoreboard_r[`PROFILE_ISSUE.issue_a_ra_idx_w] ||
        `PROFILE_ISSUE.scoreboard_r[`PROFILE_ISSUE.issue_a_rb_idx_w] ||
        `PROFILE_ISSUE.scoreboard_r[`PROFILE_ISSUE.issue_a_rd_idx_w];
    wire profile_unit_wait = (`PROFILE_ISSUE.pipe0_load_e1_w || `PROFILE_ISSUE.pipe0_store_e1_w ||
        `PROFILE_ISSUE.pipe1_load_e1_w || `PROFILE_ISSUE.pipe1_store_e1_w) &&
        (`PROFILE_ISSUE.issue_a_mul_w || `PROFILE_ISSUE.issue_a_div_w || `PROFILE_ISSUE.issue_a_csr_w);
    always #4 ref_clk = ~ref_clk;
    triha_cpu_board_top u_dut (
        .ref_clk_pi(ref_clk), .ref_clk_ni(~ref_clk), .rst_ni(rst_n),
        .uart_tx_o(tx), .led_o(led)
    );
    initial begin
        wb_file=$fopen("coremark.wb.log","w");
        store_file=$fopen("coremark.store.log","w");
        if (!wb_file || !store_file) $fatal(1,"CPU_COREMARK_SIM_FAIL trace_open");
        #1;
        if (u_dut.u_soc.u_core.u_cpu.SUPPORT_DUAL_ISSUE != 1 ||
            u_dut.u_soc.u_core.DUAL_ISSUE != 1 ||
            u_dut.u_soc.u_core.u_cpu.EARLY_MUL_BYPASS != 1 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BTB_ENTRIES != 512 ||
            u_dut.u_soc.u_core.u_cpu.BTB_DIRECT_MAPPED != 1 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BTB_ENTRIES_W != 9 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BHT_ENTRIES != 512 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BHT_ENTRIES_W != 9 ||
            u_dut.u_soc.u_core.u_cpu.NUM_RAS_ENTRIES != 4 ||
            u_dut.u_soc.u_core.u_cpu.NUM_RAS_ENTRIES_W != 2 ||
            u_dut.u_soc.u_core.u_cpu.GSHARE_ENABLE != 0) begin
            $display("CPU_COREMARK_SIM_FAIL actual predictor profile must be BTB512/BHT512/RAS4 PC-indexed");
            $finish;
        end
        $display("CPU_COREMARK_CONFIG btb=512 bht=512 ras=4 gshare=0 dual_issue=1 indexed_btb=1 early_mul=1");
        #316; rst_n = 1;
    end
    initial forever begin
        @(negedge tx);
        repeat (1302) @(posedge u_dut.cpu_clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            serial_byte[bit_index] = tx;
            repeat (868) @(posedge u_dut.cpu_clk);
        end
        if (tx !== 1'b1) begin $display("CPU_COREMARK_SIM_FAIL UART stop"); $finish; end
        $write("%c", serial_byte);
    end
    always @(posedge u_dut.cpu_clk) if (u_dut.cpu_reset_n) begin
        cycles = cycles + 1;
        if (`PROFILE_ISSUE.opcode_b_issue_r) paired = paired + 1;
        // Count edges after start rdcycle through stop rdcycle, before changing reads.
        if (reads==1) begin
            profile_cycles=profile_cycles+1;
            if (`PROFILE_ISSUE.opcode_a_issue_r) profile_issue=profile_issue+1;
            else if (`PROFILE_ISSUE.branch_csr_request_i || `PROFILE_ISSUE.squash_w) profile_cancel=profile_cancel+1;
            else if (`PROFILE_ISSUE.lsu_stall_i) profile_lsu=profile_lsu+1;
            else if (`PROFILE_ISSUE.stall_w) profile_pipe=profile_pipe+1;
            else if (`PROFILE_ISSUE.div_pending_q) profile_div=profile_div+1;
            else if (`PROFILE_ISSUE.csr_pending_q) profile_csr=profile_csr+1;
            else if (!`PROFILE_ISSUE.opcode_a_valid_r) profile_frontend=profile_frontend+1;
            else if (profile_unit_wait) profile_unit=profile_unit+1;
            else if (profile_old_dependency) begin
                profile_dependency=profile_dependency+1;
                if (!profile_real_dependency) profile_false=profile_false+1;
            end else profile_other=profile_other+1;
            if (`PROFILE_ISSUE.pipe0_valid_wb_w) begin
                if (`PROFILE_ISSUE.pipe0_exception_wb_w!=0)
                    $fatal(1,"CPU_COREMARK_SIM_FAIL timed_exception");
                profile_wb=profile_wb+1;
                $fwrite(wb_file,"%08h %08h %02h %08h\n",`PROFILE_ISSUE.pipe0_pc_wb_w,
                    `PROFILE_ISSUE.pipe0_opc_wb_w,`PROFILE_ISSUE.pipe0_rd_wb_w,
                    (|`PROFILE_ISSUE.pipe0_rd_wb_w) ? `PROFILE_ISSUE.pipe0_result_wb_w : 32'b0);
            end
            if (`PROFILE_ISSUE.pipe1_valid_wb_w) begin
                if (`PROFILE_ISSUE.pipe1_exception_wb_w!=0)
                    $fatal(1,"CPU_COREMARK_SIM_FAIL timed_exception");
                profile_wb=profile_wb+1;
                $fwrite(wb_file,"%08h %08h %02h %08h\n",`PROFILE_ISSUE.pipe1_pc_wb_w,
                    `PROFILE_ISSUE.pipe1_opc_wb_w,`PROFILE_ISSUE.pipe1_rd_wb_w,
                    (|`PROFILE_ISSUE.pipe1_rd_wb_w) ? `PROFILE_ISSUE.pipe1_result_wb_w : 32'b0);
            end
            if ((|u_dut.u_soc.data_wstrb) && u_dut.u_soc.data_accept) begin
                profile_stores=profile_stores+1;
                $fwrite(store_file,"%08h %h %08h\n",u_dut.u_soc.data_addr,u_dut.u_soc.data_wstrb,
                    u_dut.u_soc.data_wdata & {{8{u_dut.u_soc.data_wstrb[3]}},{8{u_dut.u_soc.data_wstrb[2]}},
                                            {8{u_dut.u_soc.data_wstrb[1]}},{8{u_dut.u_soc.data_wstrb[0]}}});
            end
        end
        // csr_ren_i is the issued-opcode valid, including ordinary instructions.
        // Decode the actual rdcycle instruction; jalr -1024 also has bits31:20=c00.
        if (u_dut.u_soc.u_core.u_cpu.u_csr.opcode_valid_i &&
            (u_dut.u_soc.u_core.u_cpu.u_csr.opcode_opcode_i & 32'hfffff07f) == 32'hc0002073) begin
            if (reads == 0) started = u_dut.u_soc.u_core.u_cpu.u_csr.u_csrfile.csr_mcycle_q;
            else if (reads == 1) elapsed = u_dut.u_soc.u_core.u_cpu.u_csr.u_csrfile.csr_mcycle_q - started;
            reads = reads + 1;
        end
        if (cycles > 20000000) begin
            $display("CPU_COREMARK_SIM_FAIL timeout"); $finish;
        end
    end
    initial begin
        wait(u_dut.done);
        repeat (9000) @(posedge u_dut.cpu_clk);
        $fclose(wb_file); $fclose(store_file);
        if (profile_cycles!=elapsed || profile_cycles!=profile_issue+profile_frontend+profile_lsu+
            profile_pipe+profile_div+profile_csr+profile_cancel+profile_unit+profile_dependency+profile_other)
            $fatal(1,"CPU_COREMARK_SIM_FAIL profile_sum");
        $display("CPU_COREMARK_PROFILE cycles=%0d issue=%0d frontend=%0d lsu=%0d pipe=%0d div=%0d csr=%0d cancel=%0d unit=%0d dependency=%0d other=%0d false_dependency=%0d wb=%0d stores=%0d",
            profile_cycles,profile_issue,profile_frontend,profile_lsu,profile_pipe,profile_div,profile_csr,
            profile_cancel,profile_unit,profile_dependency,profile_other,profile_false,profile_wb,profile_stores);
        if (paired == 0) $fatal(1,"CPU_COREMARK_SIM_FAIL no_actual_dual_pair");
        $display("CPU_BOARD_DUAL_PAIR_PASS pairs=%0d",paired);
        if (u_dut.exit_code !== 0 || reads != 2)
            $display("CPU_COREMARK_SIM_FAIL exit=%0d reads=%0d cycles=%0d", u_dut.exit_code, reads, elapsed);
        else $display("\nCPU_COREMARK_SIM_PASS cycles=%0d reads=%0d", elapsed, reads);
        $finish;
    end
    `undef PROFILE_ISSUE
endmodule
