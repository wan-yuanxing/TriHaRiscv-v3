`timescale 1ns / 1ps
// Exercises the common DDR boundary independently of cache tag/controller state.
module tb_cpu_cache_cpu;
    parameter integer CORRUPT_DATA = 0;
    parameter integer CACHE_ENABLE = 1;
    parameter integer COREMARK_MODE = 0;
    reg clk = 0, rst_n = 0;
    always #5 clk = !clk;
    reg [31:0] rng = 32'h763d93e1;
    integer cycles = 0, checks = 0, reads = 0, writes = 0;
    reg [31:0] memory [0:131071];
    task check;
        input ok;
        input [511:0] message;
        begin
            checks = checks + 1;
            if (ok !== 1'b1) begin $display("CPU_CACHE_FAIL %0s cycle=%0d", message, cycles); $fatal(1); end
        end
    endtask
    always @(posedge clk) begin
        rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
        cycles <= cycles + 1;
        if (cycles > (COREMARK_MODE ? 30000000 : 100000)) check(0, "transport watchdog");
    end
    task fail;
        input [511:0] message;
        begin check(0, message); end
    endtask
    function integer word_index;
        input [31:0] address;
        begin word_index = {address[25], address[17:2]}; end
    endfunction
    integer i_reads = 0, d_reads = 0;
    wire protocol_fault;
    wire awvalid, wvalid, wlast, bready, arvalid, rready;
    wire [31:0] awaddr, araddr;
    wire [3:0] awid, arid;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, arburst;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg have_aw = 0, have_w = 0, read_pending = 0;
    reg bvalid = 0, rvalid = 0, rlast = 0;
    wire awready = !have_aw && !bvalid && (COREMARK_MODE || rng[0]);
    wire wready = !have_w && !bvalid && (COREMARK_MODE || rng[2]);
    wire arready = !read_pending && !rvalid && (COREMARK_MODE || rng[4]);
    reg [1:0] bresp = 0, rresp = 0;
    reg [3:0] bid = 0, rid = 0;
    reg [127:0] rdata = 0, saved_wdata;
    reg [15:0] saved_strobe;
    reg [31:0] saved_awaddr, saved_araddr;
    integer write_wait = 0, read_beat = 0, read_count;
    reg write_error = 0;
    integer read_error_beat = -1;
    wire d_ack = u_dut.u_core.data_ack_i;
    triha_cached_core #(.CACHE_ENABLE(CACHE_ENABLE)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .external_irq_i(1'b0),
        .protocol_fault_o(protocol_fault),
        .axi_awvalid_o(awvalid), .axi_awaddr_o(awaddr), .axi_awid_o(awid), .axi_awlen_o(awlen),
        .axi_awsize_o(awsize), .axi_awburst_o(awburst), .axi_awready_i(awready),
        .axi_wvalid_o(wvalid), .axi_wdata_o(wdata), .axi_wstrb_o(wstrb), .axi_wlast_o(wlast), .axi_wready_i(wready),
        .axi_bvalid_i(bvalid), .axi_bresp_i(bresp), .axi_bid_i(bid), .axi_bready_o(bready),
        .axi_arvalid_o(arvalid), .axi_araddr_o(araddr), .axi_arid_o(arid), .axi_arlen_o(arlen),
        .axi_arsize_o(arsize), .axi_arburst_o(arburst), .axi_arready_i(arready),
        .axi_rvalid_i(rvalid), .axi_rdata_i(rdata), .axi_rresp_i(rresp), .axi_rid_i(rid),
        .axi_rlast_i(rlast), .axi_rready_o(rready)
    );
    integer lane;
    reg hold_aw = 0, hold_w = 0, hold_ar = 0;
    reg [48:0] last_aw, last_ar;
    reg [144:0] last_w;
    always @(posedge clk) begin
        if (!rst_n) begin
            bvalid <= 0; rvalid <= 0; have_aw <= 0; have_w <= 0; read_pending <= 0;
            hold_aw <= 0; hold_w <= 0; hold_ar <= 0;
        end else begin
            if (hold_aw) check(awvalid && {awaddr,awid,awlen,awsize,awburst} === last_aw, "AW must remain stable");
            if (hold_w) check(wvalid && {wdata,wstrb,wlast} === last_w, "W must remain stable");
            if (hold_ar) check(arvalid && {araddr,arid,arlen,arsize,arburst} === last_ar, "AR must remain stable");
            hold_aw <= awvalid && !awready; last_aw <= {awaddr,awid,awlen,awsize,awburst};
            hold_w <= wvalid && !wready; last_w <= {wdata,wstrb,wlast};
            hold_ar <= arvalid && !arready; last_ar <= {araddr,arid,arlen,arsize,arburst};
            if (awvalid && awready) begin
                check(awaddr[3:0] == 0 && awlen == 0 && awsize == 4 && awburst == 1, "scalar AW geometry");
                have_aw <= 1; saved_awaddr <= awaddr; bid <= awid;
            end
            if (wvalid && wready) begin
                check(wlast, "scalar WLAST");
                have_w <= 1; saved_wdata <= wdata; saved_strobe <= wstrb; write_wait <= 30;
            end
            if (have_aw && have_w && !bvalid) begin
                if (write_wait > 0) begin write_wait <= write_wait - 1; check(!d_ack, "D store waits for B"); end
                else begin
                    bvalid <= 1; bresp <= (write_error || (!COREMARK_MODE && saved_awaddr == 32'h80018020)) ? 2'b10 : 0;
                    if (!write_error && (COREMARK_MODE || saved_awaddr != 32'h80018020))
                        for (lane = 0; lane < 16; lane = lane + 1)
                            if (saved_strobe[lane])
                                memory[word_index(saved_awaddr) + lane/4][(lane%4)*8 +: 8] <= saved_wdata[lane*8 +: 8];
                end
            end
            if (bvalid && bready) begin bvalid <= 0; have_aw <= 0; have_w <= 0; writes <= writes + 1; end
            if (arvalid && arready) begin
                check(araddr[3:0] == 0 && arlen <= 1 && arsize == 4 && arburst == 1, "AR geometry");
                check(({1'b0,araddr[11:0]} + ((arlen+1)*16)) <= 4096, "read cannot cross 4KiB");
                read_pending <= 1; saved_araddr <= araddr; read_count <= arlen + 1;
                read_beat <= 0; rid <= arid; reads <= reads + 1;
                if (arid != 2) i_reads <= i_reads + 1; else d_reads <= d_reads + 1;
            end
            if (rvalid && rready) begin
                rvalid <= 0;
                if (rlast) read_pending <= 0; else read_beat <= read_beat + 1;
            end
            if (read_pending && !rvalid && (COREMARK_MODE || rng[6])) begin
                rvalid <= 1; rlast <= read_beat == read_count - 1;
                // Cached stores fault synchronously on failed write allocation;
                // a later dirty writeback failure is reported by maintenance.
                rresp <= (read_beat == read_error_beat || (!COREMARK_MODE && (saved_araddr == 32'h80018000 || saved_araddr == 32'h80018020 || saved_araddr == 32'h80018200))) ? 2'b10 : 0;
                for (lane = 0; lane < 4; lane = lane + 1)
                    rdata[lane*32 +: 32] <= memory[word_index(saved_araddr)+read_beat*4+lane] ^ CORRUPT_DATA;
            end
        end
    end
    integer n, wb_file, store_file, wb_count = 0, store_count = 0;
    integer cycle_reads = 0, timed_cycles = 0;
    reg [31:0] cycle_started = 0, cycle_elapsed = 0;
    `define CORE u_dut.u_core.u_cpu
    initial begin
        #1;
        check(u_dut.CACHE_ENABLE == CACHE_ENABLE && u_dut.u_core.DUAL_ISSUE == 0,
            "actual CPU/cache elaboration parameters");
        wb_file = $fopen("cpu-cache.wb.log", "w");
        store_file = $fopen("cpu-cache.store.log", "w");
        if (!wb_file || !store_file) $fatal(1, "CPU_CACHE_FAIL trace_open");
        for (n = 0; n < 131072; n = n + 1) memory[n] = 32'h3155a72b ^ (n*32'h8721345);
        $readmemh("firmware.hex", memory, 0, 32767);
        repeat (6) @(negedge clk); rst_n = 1;
        $display("CPU_CACHE_CPU_CONFIG single=1 cache_enable=%0d modeled_axi128=1 directed_faults=%0d coremark=%0d", CACHE_ENABLE, !COREMARK_MODE, COREMARK_MODE);
    end
    always @(posedge clk) if (rst_n) begin
        if (!COREMARK_MODE || cycle_reads == 1) begin
        if (COREMARK_MODE) timed_cycles = timed_cycles + 1;
        if (`CORE.u_issue.pipe0_valid_wb_w) begin
            wb_count = wb_count + 1;
            $fwrite(wb_file, "%08h %08h %02h %08h %02h\n", `CORE.u_issue.pipe0_pc_wb_w,
                `CORE.u_issue.pipe0_opc_wb_w, `CORE.u_issue.pipe0_rd_wb_w,
                (|`CORE.u_issue.pipe0_rd_wb_w) ? `CORE.u_issue.pipe0_result_wb_w : 32'b0,
                `CORE.u_issue.pipe0_exception_wb_w);
        end
        if ((|u_dut.u_core.data_wstrb_o) && u_dut.u_core.data_accept_i) begin
            store_count = store_count + 1;
            $fwrite(store_file, "%08h %h %08h\n", u_dut.u_core.data_addr_o,
                u_dut.u_core.data_wstrb_o, u_dut.u_core.data_wdata_o);
        end
        end
        if (COREMARK_MODE && `CORE.u_csr.opcode_valid_i &&
            (`CORE.u_csr.opcode_opcode_i & 32'hfffff07f) == 32'hc0002073) begin
            if (cycle_reads == 0) cycle_started = `CORE.u_csr.u_csrfile.csr_mcycle_q;
            else if (cycle_reads == 1) cycle_elapsed = `CORE.u_csr.u_csrfile.csr_mcycle_q - cycle_started;
            cycle_reads = cycle_reads + 1;
        end
    end
    always @(negedge clk) if (rst_n) begin
        if (`CORE.u_issue.pipe1_valid_wb_w) check(0, "unexpected dual completion");
        if (`CORE.u_csr.u_csrfile.csr_waddr_i == 12'h8b2 && `CORE.u_csr.u_csrfile.exception_i == 0 &&
            `CORE.u_csr.u_csrfile.csr_wdata_i[31:24] == 1)
            $write("%c", `CORE.u_csr.u_csrfile.csr_wdata_i[7:0]);
        if (`CORE.u_csr.u_csrfile.csr_waddr_i == 12'h8b2 && `CORE.u_csr.u_csrfile.exception_i == 0 &&
            `CORE.u_csr.u_csrfile.csr_wdata_i[31:24] == 0) begin
            $fclose(wb_file); $fclose(store_file);
            check(`CORE.u_csr.u_csrfile.csr_wdata_i[7:0] == 0, "software cache/fault check returned nonzero checkpoint");
            check(!protocol_fault && i_reads > 0 && d_reads > 0 && writes > 0, "real CPU exercised both caches and writes");
            if (COREMARK_MODE) begin
                check(cycle_reads == 2 && cycle_elapsed > 0 && timed_cycles == cycle_elapsed, "CoreMark actual cycle window");
                $display("CPU_CACHE_COREMARK_PASS cycles=%0d wb=%0d stores=%0d I_reads=%0d D_reads=%0d lower_writes=%0d", cycle_elapsed, wb_count, store_count, i_reads, d_reads, writes);
            end else
                $display("CPU_CACHE_CPU_PASS cycles=%0d wb=%0d stores=%0d I_reads=%0d D_reads=%0d lower_writes=%0d", cycles, wb_count, store_count, i_reads, d_reads, writes);
            $finish;
        end
    end
    `undef CORE
endmodule
