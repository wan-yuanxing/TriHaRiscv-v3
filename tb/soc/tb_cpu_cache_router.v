`timescale 1ns / 1ps
// Exercises the common DDR boundary independently of cache tag/controller state.
module tb_cpu_cache_router;
    parameter integer CACHE_ENABLE = 1;
    parameter integer MAX_CYCLES = 200000;
    reg ddr_ready = 0, ddr_fault = 0;
    wire fault;
    wire uart_tx, done;
    wire [7:0] exit_code;
    parameter integer CORRUPT_DATA = 0;
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
        if (cycles > MAX_CYCLES) check(0, "transport watchdog");
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
    reg i_req = 0, i_flush = 0, i_inval = 0;
    reg [31:0] i_addr = 0;
    wire i_accept, i_valid, i_error;
    wire [63:0] i_data;
    reg [31:0] d_addr = 0, d_wdata = 0;
    reg d_rd = 0, d_cacheable = 1, d_inval = 0, d_flush = 0, d_writeback = 0;
    reg [3:0] d_wr = 0;
    reg [10:0] d_tag = 0;
    wire [31:0] d_data;
    wire d_accept, d_ack, d_error;
    wire [10:0] d_resp_tag;
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
    wire awready = !have_aw && !bvalid && rng[0];
    wire wready = !have_w && !bvalid && rng[2];
    wire arready = !read_pending && !rvalid && rng[4];
    reg [1:0] bresp = 0, rresp = 0;
    reg [3:0] bid = 0, rid = 0;
    reg [127:0] rdata = 0, saved_wdata;
    reg [15:0] saved_strobe;
    reg [31:0] saved_awaddr, saved_araddr;
    integer write_wait = 0, read_beat = 0, read_count;
    reg write_error = 0;
    integer read_error_beat = -1;
    triha_cpu_memory_router #(.CACHE_ENABLE(CACHE_ENABLE)) u_dut (
        .ddr_ready_i(ddr_ready), .ddr_fault_i(ddr_fault), .ddr_fault_o(fault),
        .uart_tx_o(uart_tx), .done_o(done), .exit_code_o(exit_code),
        .clk_i(clk), .rst_ni(rst_n), .inst_req_i(i_req), .inst_flush_i(i_flush),
        .inst_invalidate_i(i_inval), .inst_addr_i(i_addr), .inst_accept_o(i_accept),
        .inst_valid_o(i_valid), .inst_error_o(i_error), .inst_rdata_o(i_data),
        .data_addr_i(d_addr), .data_wdata_i(d_wdata), .data_re_i(d_rd), .data_wstrb_i(d_wr),
        .data_cacheable_i(d_cacheable), .data_req_tag_i(d_tag), .data_invalidate_i(d_inval),
        .data_flush_i(d_flush), .data_writeback_i(d_writeback), .data_rdata_o(d_data),
        .data_accept_o(d_accept), .data_ack_o(d_ack), .data_error_o(d_error), .data_resp_tag_o(d_resp_tag),
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
                    bvalid <= 1; bresp <= write_error ? 2'b10 : 0;
                    if (!write_error)
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
            if (read_pending && !rvalid && rng[6]) begin
                rvalid <= 1; rlast <= read_beat == read_count - 1;
                rresp <= read_beat == read_error_beat ? 2'b10 : 0;
                for (lane = 0; lane < 4; lane = lane + 1)
                    rdata[lane*32 +: 32] <= memory[word_index(saved_araddr)+read_beat*4+lane] ^ CORRUPT_DATA;
            end
        end
    end
    task i_read;
        input [31:0] address;
        input expect_error;
        integer guard;
        reg [63:0] expected;
        begin
            expected = {memory[word_index({address[31:3],3'b0})+1], memory[word_index({address[31:3],3'b0})]};
            if (address == 0) expected = 64'h00028067000102b7;
            @(negedge clk); i_addr = address; i_req = 1;
            guard = 0;
            begin : i_wait_accept
                forever begin
                    @(posedge clk); guard = guard + 1;
                    if (i_accept) disable i_wait_accept;
                    if (guard > 2000) fail("I accept timeout");
                end
            end
            @(negedge clk); i_req = 0;
            while (!i_valid) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 4000) fail("I response timeout");
            end
            check(i_error === expect_error, "I error completion");
            if (!expect_error) check(i_data === expected, "I returned instruction pair");
            @(negedge clk);
        end
    endtask
    task d_access;
        input [31:0] address;
        input [3:0] mask;
        input [31:0] value;
        input cacheable;
        input expect_error;
        integer guard;
        reg [31:0] expected;
        reg [10:0] expected_tag;
        begin
            expected = memory[word_index(address)];
            if (address == 32'h2002000c) expected = fault ? 2 : (ddr_ready ? 1 : 0);
            if (address == 32'h20020000) expected = 32'h54524841;
            @(negedge clk); d_addr = address; d_wr = mask; d_wdata = value;
            d_rd = mask == 0; d_cacheable = cacheable; d_tag = d_tag + 1; expected_tag = d_tag;
            guard = 0;
            begin : d_wait_accept
                forever begin
                    @(posedge clk); guard = guard + 1;
                    if (d_accept) disable d_wait_accept;
                    if (guard > 2000) fail("D accept timeout");
                end
            end
            @(negedge clk); d_rd = 0; d_wr = 0;
            while (!d_ack) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 4000) fail("D response timeout");
            end
            check(d_error === expect_error, "D error completion");
            check(d_resp_tag === expected_tag, "D preserved response tag");
            if (mask == 0 && !expect_error) check(d_data === expected, "D returned load word");
            @(negedge clk);
        end
    endtask
    task d_maintenance;
        input integer operation;
        integer guard;
        begin
            @(negedge clk); d_inval = operation == 0; d_flush = operation == 1;
            d_writeback = operation == 2; d_tag = d_tag + 1;
            begin : maintenance_accept
                forever begin @(posedge clk); if (d_accept) disable maintenance_accept; end
            end
            @(negedge clk); d_inval = 0; d_flush = 0; d_writeback = 0;
            guard = 0;
            while (!d_ack) begin @(negedge clk); guard = guard + 1; if (guard > 1000) fail("D maintenance timeout"); end
            check(!d_error, "D clean maintenance response");
            @(negedge clk);
        end
    endtask
    integer n, before_count;
    initial begin
        for (n = 0; n < 131072; n = n + 1) memory[n] = 32'h3155a72b ^ (n*32'h8721345);
        for (n = 16384; n < 24576; n = n + 1) memory[n] = 32'ha5a5a5a5;
        repeat (4) @(negedge clk); rst_n = 1;
        i_read(0, 0); i_read(32'h10000, 0);
        d_access(32'h10000, 0, 0, 0, 0);
        d_access(32'h2002000c, 0, 0, 0, 0);
        d_access(32'h2002000c, 15, 0, 0, 1);
        check(reads == 0 && writes == 0, "local traffic must never reach DDR");
        d_addr = 0; d_maintenance(1);
        // A request held while DDR is unready cannot be accepted or widened.
        @(negedge clk); d_addr = 32'h80000100; d_rd = 1;
        repeat (12) begin @(posedge clk); check(!d_accept && !arvalid, "DDR init gating"); end
        @(negedge clk); d_rd = 0; ddr_ready = 1;
        i_read(32'h80000028, 0); before_count = i_reads;
        i_read(32'h80000028, 0);
        check(!CACHE_ENABLE || i_reads == before_count, "system I hit");
        d_access(32'h80000100, 0, 0, 1, 0); before_count = d_reads;
        d_access(32'h80000100, 0, 0, 1, 0);
        check(!CACHE_ENABLE || d_reads == before_count, "system D hit");
        d_access(32'h82000100, 0, 0, 1, 0); before_count = d_reads;
        d_access(32'h82000100, 0, 0, 1, 0);
        check(d_reads == before_count+1, "shared data bypass");
        i_read(32'h82000300, 0); before_count = i_reads;
        i_read(32'h82000300, 0); check(i_reads == before_count+1, "shared fetch bypass");
        d_access(32'h80000104, 15, 32'h9573acde, 1, 0);
        d_access(32'h80000104, 5, 32'h12345678, 1, 0);
        d_access(32'h80000104, 0, 0, 1, 0);
        check(memory[word_index(32'h80000104)] == 32'h9534ac78, "partial lower store lanes");
        fork
            i_read(32'h80003000, 0);
            d_access(32'h80004000, 0, 0, 1, 0);
        join
        // Ready can fall after AW acceptance, before W/B. Completion must drain.
        fork
            d_access(32'h82000800, 15, 32'h7193acde, 0, 0);
            begin
                wait(awvalid && awready); @(negedge clk); ddr_ready = 0;
            end
        join
        check(memory[word_index(32'h82000800)] == 32'h7193acde, "store drains after ready removal");
        d_access(32'h2002000c, 0, 0, 0, 0);
        i_read(0, 0);
        @(negedge clk); ddr_ready = 1;
        // Change to local STATUS immediately after accepting a slow DDR read.
        @(negedge clk); d_addr = 32'h80006000; d_rd = 1; d_tag = 11'h321;
        begin : accept_slow_d
            forever begin @(posedge clk); if (d_accept) disable accept_slow_d; end
        end
        @(negedge clk); d_addr = 32'h2002000c; d_tag = 11'h322;
        while (!d_ack) begin @(negedge clk); check(!d_accept, "target change waits for DDR response"); end
        check(d_resp_tag == 11'h321 && d_data == memory[word_index(32'h80006000)], "old DDR owner and tag");
        begin : accept_status
            forever begin @(posedge clk); if (d_accept) disable accept_status; end
        end
        @(negedge clk); d_rd = 0;
        while (!d_ack) @(negedge clk);
        check(d_resp_tag == 11'h322 && d_data == 1 && !d_error, "new status owner");
        @(negedge clk);
        // Instruction target changes must also wait, with nonzero stale RAM outputs.
        @(negedge clk); i_addr = 32'h80006080; i_req = 1;
        begin : accept_slow_i
            forever begin @(posedge clk); if (i_accept) disable accept_slow_i; end
        end
        @(negedge clk); i_addr = 0;
        while (!i_valid) begin @(negedge clk); check(!i_accept, "fetch target waits for DDR response"); end
        check(i_data == {memory[word_index(32'h80006080)+1],memory[word_index(32'h80006080)]}, "old fetch owner");
        begin : accept_rom
            forever begin @(posedge clk); if (i_accept) disable accept_rom; end
        end
        @(negedge clk); i_req = 0;
        while (!i_valid) @(negedge clk);
        check(i_data == 64'h00028067000102b7 && !i_error, "ROM response excludes stale cache data");
        @(negedge clk);
        // Removing ready and asserting fault never retracts an accepted refill.
        fork
            d_access(32'h80007000, 0, 0, 1, 0);
            begin
                wait(arvalid && arready); @(negedge clk); ddr_ready = 0; ddr_fault = 1;
            end
        join
        check(fault, "platform fault latched");
        d_access(32'h80007100, 0, 0, 1, 1);
        i_read(32'h80007100, 1);
        d_access(32'h10000, 0, 0, 0, 0); i_read(0, 0);
        d_access(32'h2002000c, 0, 0, 0, 0);
        @(negedge clk); ddr_fault = 0; ddr_ready = 1;
        repeat (4) @(negedge clk);
        check(fault, "fault cannot be cleared by ready");
        // Only coordinated reset admits new DDR traffic after a fatal fault.
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1;
        d_access(32'h2002000c, 0, 0, 0, 0);
        d_access(32'h80000100, 0, 0, 1, 0);
        check(!protocol_fault && !fault && i_reads > 0 && d_reads > 0, "system coverage");
        $display("CPU_CACHE_ROUTER_PASS checks=%0d reads=%0d writes=%0d", checks, reads, writes);
        $finish;
    end
endmodule
