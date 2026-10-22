/* Simulation-only observer. No force, writes to the DUT, or timed software changes. */
`define PCORE u_dut.u_system.u_soc.u_core.u_cpu
`define PISSUE `PCORE.u_issue
`define PCACHE u_dut.u_system.u_soc.u_router.u_cache
`define PDC `PCACHE.u_dcache
`define PBRIDGE u_dut.u_system.u_bridge
integer reads = 0, timed_cycles = 0;
reg [31:0] started = 0, stopped = 0;
reg active = 0, classified = 0;
integer issue = 0, cancel = 0, lsu = 0, pipe_wait = 0, div_wait = 0;
integer csr_wait = 0, frontend = 0, unit_wait = 0, dependency = 0, other = 0;
integer wb = 0, stores = 0, dc_reads = 0, dc_writes = 0;
integer read_hits = 0, read_misses = 0, uncached_reads = 0;
integer store_hits = 0, store_misses = 0, uncached_writes = 0;
integer refills = 0, lower_writes = 0;
integer native_aw = 0, native_ar = 0, native_wbeats = 0, native_rbeats = 0;
integer dc_state_cycles [0:13];
integer bridge_state_cycles [0:13];
integer n;
integer wb_file, store_file;
initial begin
    wb_file = $fopen("ddr-profile.wb.log", "w");
    store_file = $fopen("ddr-profile.store.log", "w");
    if (!wb_file || !store_file) $fatal(1, "CPU_DDR_PROFILE_FAIL trace_open");
    for (n = 0; n < 14; n = n + 1) begin
        dc_state_cycles[n] = 0;
        bridge_state_cycles[n] = 0;
    end
end
always @(posedge u_dut.ddr_clk) if (active) begin
    if (`PBRIDGE.h_awvalid && `PBRIDGE.h_awready) native_aw = native_aw + 1;
    if (`PBRIDGE.h_arvalid && `PBRIDGE.h_arready) native_ar = native_ar + 1;
    if (`PBRIDGE.nw_take) native_wbeats = native_wbeats + 1;
    if (`PBRIDGE.nr_take) native_rbeats = native_rbeats + 1;
end
always @(posedge u_dut.cpu_clk) if (u_dut.u_system.cpu_rst_n) begin
    if (active) begin
        timed_cycles = timed_cycles + 1;
        if (`PISSUE.opcode_a_issue_r) issue = issue + 1;
        else if (`PISSUE.branch_csr_request_i || `PISSUE.squash_w) cancel = cancel + 1;
        else if (`PISSUE.lsu_stall_i) lsu = lsu + 1;
        else if (`PISSUE.stall_w) pipe_wait = pipe_wait + 1;
        else if (`PISSUE.div_pending_q) div_wait = div_wait + 1;
        else if (`PISSUE.csr_pending_q) csr_wait = csr_wait + 1;
        else if (!`PISSUE.opcode_a_valid_r) frontend = frontend + 1;
        else if ((`PISSUE.pipe0_load_e1_w || `PISSUE.pipe0_store_e1_w) &&
                 (`PISSUE.issue_a_mul_w || `PISSUE.issue_a_div_w || `PISSUE.issue_a_csr_w)) unit_wait = unit_wait + 1;
        else if (`PISSUE.scoreboard_r[`PISSUE.issue_a_ra_idx_w] ||
                 `PISSUE.scoreboard_r[`PISSUE.issue_a_rb_idx_w] ||
                 `PISSUE.scoreboard_r[`PISSUE.issue_a_rd_idx_w]) dependency = dependency + 1;
        else other = other + 1;
        if (`PISSUE.pipe0_valid_wb_w) begin
            if (`PISSUE.pipe0_exception_wb_w != 0) $fatal(1, "CPU_DDR_PROFILE_FAIL timed_exception");
            wb = wb + 1;
            $fwrite(wb_file, "%08h %08h %02h %08h %02h\n", `PISSUE.pipe0_pc_wb_w,
                `PISSUE.pipe0_opc_wb_w, `PISSUE.pipe0_rd_wb_w,
                (|`PISSUE.pipe0_rd_wb_w) ? `PISSUE.pipe0_result_wb_w : 32'b0,
                `PISSUE.pipe0_exception_wb_w);
        end
        if (`PISSUE.pipe1_valid_wb_w) $fatal(1, "CPU_DDR_PROFILE_FAIL dual_completion");
        if ((|`SOC.data_wstrb) && `SOC.data_accept) begin
            stores = stores + 1;
            $fwrite(store_file, "%08h %h %08h\n", `SOC.data_addr, `SOC.data_wstrb, `SOC.data_wdata);
        end
        if ((^`PDC.state_q === 1'bx) || `PDC.state_q > 13 ||
            (^`PBRIDGE.state === 1'bx) || `PBRIDGE.state > 13)
            $fatal(1, "CPU_DDR_PROFILE_FAIL unknown_state");
        dc_state_cycles[`PDC.state_q] = dc_state_cycles[`PDC.state_q] + 1;
        bridge_state_cycles[`PBRIDGE.state] = bridge_state_cycles[`PBRIDGE.state] + 1;
        if (`PDC.mem_accept_o && `PDC.request_w) begin
            if (`PDC.mem_rd_i) dc_reads = dc_reads + 1;
            if (|`PDC.mem_wr_i) dc_writes = dc_writes + 1;
        end
        if ((`PDC.state_q == 2 || `PDC.state_q == 7) && !classified) begin
            classified = 1;
            if (|`PDC.write_mask_q) begin
                if (!`PDC.cacheable_q) uncached_writes = uncached_writes + 1;
                else if (`PDC.hit_w) store_hits = store_hits + 1;
                else store_misses = store_misses + 1;
            end else if (!`PDC.cacheable_q) uncached_reads = uncached_reads + 1;
            else if (`PDC.hit_w) read_hits = read_hits + 1;
            else read_misses = read_misses + 1;
        end
        if (`PDC.outport_accept_i && `PDC.outport_rd_o && `PDC.state_q == 3) refills = refills + 1;
        if (`PDC.outport_accept_i && |`PDC.outport_wr_o) lower_writes = lower_writes + 1;
    end
    if (`PDC.state_q == 1) classified = 0;
    if (`PCORE.u_csr.opcode_valid_i &&
        `PCORE.u_csr.opcode_pc_i >= PAYLOAD_BASE && `PCORE.u_csr.opcode_pc_i < PAYLOAD_BASE+32'h20000 &&
        (`PCORE.u_csr.opcode_opcode_i & 32'hfffff07f) == 32'hc0002073) begin
        if (reads == 0) begin
            started = `PCORE.u_csr.u_csrfile.csr_mcycle_q;
            active = 1;
        end else if (reads == 1) begin
            stopped = `PCORE.u_csr.u_csrfile.csr_mcycle_q;
            active = 0;
        end else $fatal(1, "CPU_DDR_PROFILE_FAIL extra_cycle_read");
        reads = reads + 1;
    end
end
initial begin
    wait (u_dut.done_w);
    repeat (32) @(posedge u_dut.cpu_clk);
    $fclose(wb_file); $fclose(store_file);
    if (reads != 2 || timed_cycles != (stopped-started))
        $fatal(1, "CPU_DDR_PROFILE_FAIL CSR_window");
    $display("CPU_DDR_PROFILE_WINDOW cycles=%0d start=%0d stop=%0d reads=%0d",timed_cycles,started,stopped,reads);
    $display("CPU_DDR_PROFILE_ISSUE issue=%0d cancel=%0d lsu=%0d pipe=%0d div=%0d csr=%0d frontend=%0d unit=%0d dependency=%0d other=%0d wb=%0d stores=%0d",issue,cancel,lsu,pipe_wait,div_wait,csr_wait,frontend,unit_wait,dependency,other,wb,stores);
    $display("CPU_DDR_PROFILE_DC reads=%0d writes=%0d read_hits=%0d read_misses=%0d uncached_reads=%0d store_hits=%0d store_misses=%0d uncached_writes=%0d refills=%0d lower_writes=%0d",dc_reads,dc_writes,read_hits,read_misses,uncached_reads,store_hits,store_misses,uncached_writes,refills,lower_writes);
    $display("CPU_DDR_PROFILE_DC_STATES idle=%0d lookup=%0d refill_req=%0d refill=%0d relookup=%0d response=%0d write_req=%0d write_wait=%0d store_update=%0d uncached_req=%0d uncached_wait=%0d reset=%0d invalidate=%0d flush=%0d",dc_state_cycles[1],dc_state_cycles[2],dc_state_cycles[3],dc_state_cycles[4],dc_state_cycles[5],dc_state_cycles[6],dc_state_cycles[7],dc_state_cycles[8],dc_state_cycles[9],dc_state_cycles[10],dc_state_cycles[11],dc_state_cycles[0],dc_state_cycles[12],dc_state_cycles[13]);
    $display("CPU_DDR_PROFILE_BRIDGE idle=%0d collect=%0d wpre=%0d waddr=%0d wdata=%0d vpre=%0d vaddr=%0d vdata=%0d raddr=%0d rdata=%0d rpre=%0d rresp=%0d bresp=%0d quarantine=%0d native_aw=%0d native_ar=%0d native_wbeats=%0d native_rbeats=%0d",bridge_state_cycles[0],bridge_state_cycles[1],bridge_state_cycles[2],bridge_state_cycles[3],bridge_state_cycles[4],bridge_state_cycles[5],bridge_state_cycles[6],bridge_state_cycles[7],bridge_state_cycles[8],bridge_state_cycles[9],bridge_state_cycles[10],bridge_state_cycles[11],bridge_state_cycles[12],bridge_state_cycles[13],native_aw,native_ar,native_wbeats,native_rbeats);
end
`undef PCORE
`undef PISSUE
`undef PCACHE
`undef PDC
`undef PBRIDGE
