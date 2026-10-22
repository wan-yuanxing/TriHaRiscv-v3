`timescale 1ns / 1ps
// Independent byte-mask memory oracle; both caches operate in the same run.
module tb_cpu_cache;
    parameter integer CORRUPT_DATA = 0;
    parameter integer FAST_RESPONSE_CHECK = 0;
    parameter integer STORE_RESPONSE_CHECK = 0;
    reg expect_fast_load = 0;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0;
    reg [31:0] memory [0:65535];
    reg [31:0] arch_memory [0:65535];
    integer checks = 0, i_reads = 0, d_reads = 0, d_writes = 0;
    integer i_hits = 0, d_hits = 0, simultaneous = 0;
    reg [31:0] rng = 32'h31872ac5;
    integer cycles = 0;
    task fail;
        input [511:0] reason;
        begin $display("CPU_CACHE_FAIL %0s cycle=%0d", reason, cycles); $fatal(1); end
    endtask
    task check;
        input ok;
        input [511:0] reason;
        begin checks = checks + 1; if (ok !== 1'b1) fail(reason); end
    endtask
    always @(posedge clk) begin
        cycles <= cycles + 1;
        rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
        if (cycles > 100000) fail("watchdog");
    end

    reg i_req = 0, i_flush = 0, i_inval = 0;
    reg [31:0] i_addr = 0;
    wire i_accept, i_valid, i_error;
    wire [63:0] i_data;
    wire arvalid, rready;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [3:0] arid;
    wire [1:0] arburst;
    reg i_pending = 0;
    wire arready = !i_pending && rng[0];
    reg rvalid = 0, rlast = 0;
    reg [31:0] rdata = 0;
    reg [1:0] rresp = 0;
    reg [3:0] rid = 0;
    reg [31:0] i_memaddr;
    integer i_beat = 0, i_error_beat = -1, i_captured_error = -1;
    triha_icache #(.AXI_ID(1)) u_i (
        .clk_i(clk), .rst_ni(rst_n), .req_rd_i(i_req), .req_flush_i(i_flush),
        .req_invalidate_i(i_inval), .req_pc_i(i_addr), .req_accept_o(i_accept),
        .req_valid_o(i_valid), .req_error_o(i_error), .req_inst_o(i_data),
        .axi_awready_i(1'b0), .axi_wready_i(1'b0), .axi_bvalid_i(1'b0),
        .axi_bresp_i(2'b0), .axi_bid_i(4'b0), .axi_arready_i(arready),
        .axi_rvalid_i(rvalid), .axi_rdata_i(rdata), .axi_rresp_i(rresp),
        .axi_rid_i(rid), .axi_rlast_i(rlast), .axi_arvalid_o(arvalid),
        .axi_araddr_o(araddr), .axi_arlen_o(arlen), .axi_arid_o(arid),
        .axi_arburst_o(arburst), .axi_rready_o(rready),
        .axi_awvalid_o(), .axi_awaddr_o(), .axi_awid_o(), .axi_awlen_o(),
        .axi_awburst_o(), .axi_wvalid_o(), .axi_wdata_o(), .axi_wstrb_o(),
        .axi_wlast_o(), .axi_bready_o()
    );

    reg [31:0] d_addr = 0, d_wdata = 0;
    reg d_rd = 0, d_cacheable = 1, d_inval = 0, d_flush = 0, d_writeback = 0;
    reg [3:0] d_wr = 0;
    reg [10:0] d_tag = 0;
    wire [31:0] d_data;
    wire d_accept, d_ack, d_error;
    wire [10:0] d_resp_tag;
    wire [3:0] p_wr;
    wire p_rd;
    wire [7:0] p_len;
    wire [31:0] p_addr, p_wdata;
    reg d_pending = 0, d_pending_write;
    wire p_accept = !d_pending && rng[4];
    reg p_ack = 0, p_error = 0;
    reg [31:0] p_rdata = 0;
    reg [31:0] d_memaddr, d_memdata;
    reg [3:0] d_memmask;
    integer d_beat = 0, d_count, d_wait = 0, store_delay = 40;
    integer d_error_beat = -1, d_captured_error;
    reg store_error = 0, captured_store_error;
    reg store_ack_due = 0;
    always @(posedge clk) store_ack_due <= rst_n && p_ack && d_pending_write &&
        u_d.state_q == 9 && !u_d.cacheable_q;
    always @(negedge clk) if ((FAST_RESPONSE_CHECK || STORE_RESPONSE_CHECK) && store_ack_due)
        check(d_ack, "store responds directly after the real lower acknowledgement");
    triha_dcache u_d (
        .clk_i(clk), .rst_ni(rst_n), .mem_addr_i(d_addr), .mem_data_wr_i(d_wdata),
        .mem_rd_i(d_rd), .mem_wr_i(d_wr), .mem_cacheable_i(d_cacheable),
        .mem_req_tag_i(d_tag), .mem_invalidate_i(d_inval),
        .mem_writeback_i(d_writeback), .mem_flush_i(d_flush), .mem_data_rd_o(d_data),
        .mem_accept_o(d_accept), .mem_ack_o(d_ack), .mem_error_o(d_error),
        .mem_resp_tag_o(d_resp_tag), .outport_accept_i(p_accept),
        .outport_ack_i(p_ack), .outport_error_i(p_error), .outport_read_data_i(p_rdata),
        .outport_wr_o(p_wr), .outport_rd_o(p_rd), .outport_len_o(p_len),
        .outport_addr_o(p_addr), .outport_write_data_o(p_wdata)
    );
    integer lane;
    always @(posedge clk) begin
        if (!rst_n) begin
            i_pending <= 0; rvalid <= 0; rlast <= 0;
            d_pending <= 0; p_ack <= 0; p_error <= 0;
        end else begin
            if (i_pending && d_pending) simultaneous <= simultaneous + 1;
            if (arvalid && arready) begin
                check(arlen == 7 && arburst == 1 && araddr[4:0] == 0, "I refill burst geometry");
                i_pending <= 1; i_memaddr <= araddr; i_beat <= 0;
                i_captured_error <= i_error_beat; i_reads <= i_reads + 1; rid <= arid;
            end
            if (rvalid && rready) begin
                rvalid <= 0;
                if (rlast) i_pending <= 0;
                else i_beat <= i_beat + 1;
            end
            if (i_pending && !rvalid && rng[2]) begin
                rvalid <= 1; rlast <= i_beat == 7;
                rdata <= memory[(i_memaddr[17:2] + i_beat) & 65535];
                rresp <= i_beat == i_captured_error ? 2'b10 : 0;
            end
            p_ack <= 0; p_error <= 0;
            if ((p_rd || |p_wr) && p_accept) begin
                check(!(p_rd && |p_wr), "D lower request mutually exclusive");
                check(p_len == 0 || (p_len == 7 && p_rd && p_addr[4:0] == 0), "D lower burst geometry");
                d_pending <= 1; d_pending_write <= |p_wr; d_memaddr <= p_addr;
                d_memdata <= p_wdata; d_memmask <= p_wr; d_count <= p_len + 1;
                d_beat <= 0; d_wait <= |p_wr ? store_delay : 2;
                d_captured_error <= d_error_beat; captured_store_error <= store_error;
                if (p_rd) d_reads <= d_reads + 1; else d_writes <= d_writes + 1;
            end
            if (d_pending && !p_ack) begin
                if (d_wait > 0) begin
                    d_wait <= d_wait - 1;
                    if (d_pending_write) check(!d_ack, "store completed before lower response");
                end else if (rng[6]) begin
                    p_ack <= 1;
                    p_error <= d_pending_write ? captured_store_error : d_beat == d_captured_error;
                    p_rdata <= memory[(d_memaddr[17:2] + d_beat) & 65535] ^ CORRUPT_DATA;
                    if (d_pending_write && !captured_store_error)
                        for (lane = 0; lane < 4; lane = lane + 1)
                            if (d_memmask[lane]) memory[d_memaddr[17:2]][lane*8 +: 8] <= d_memdata[lane*8 +: 8];
                    if (d_beat == d_count - 1) d_pending <= 0;
                    else d_beat <= d_beat + 1;
                end
            end
        end
    end

    task i_read;
        input [31:0] address;
        input expect_error;
        integer guard;
        reg [63:0] expected;
        begin
            expected = {memory[((address[17:3] << 1) + 1) & 65535], memory[(address[17:3] << 1) & 65535]};
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
            expected = cacheable && address >= 32'h80000000 && address < 32'h82000000 ?
                       arch_memory[address[17:2]] : memory[address[17:2]];
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
            if ((FAST_RESPONSE_CHECK || STORE_RESPONSE_CHECK) && mask != 0 && cacheable &&
                address >= 32'h80000000 && address < 32'h82000000)
                check(p_wr == 0, "cached store is not dispatched as write-through");
            if (FAST_RESPONSE_CHECK && expect_fast_load)
                check(d_ack, "resident load responds in synchronous lookup cycle");
            if (STORE_RESPONSE_CHECK && expect_fast_load)
                check(!d_ack, "resident load retains response register boundary");
            while (!d_ack) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 4000) fail("D response timeout");
            end
            check(d_error === expect_error, "D error completion");
            check(d_resp_tag === expected_tag, "D preserved response tag");
            if (mask == 0 && !expect_error) check(d_data === expected, "D returned load word");
            if (mask != 0 && !expect_error)
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (mask[lane]) arch_memory[address[17:2]][lane*8 +: 8] = value[lane*8 +: 8];
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
            while (!d_ack) begin @(negedge clk); guard = guard + 1; if (guard > 20000) fail("D maintenance timeout"); end
            check(!d_error, "D clean maintenance response");
            @(negedge clk);
        end
    endtask
    integer n, before_count;
    initial begin
        for (n = 0; n < 65536; n = n + 1) begin
            memory[n] = (n * 32'h971acb35) ^ 32'h52a8c319;
            arch_memory[n] = memory[n];
        end
        repeat (4) @(negedge clk); rst_n = 1;
        i_read(32'h80000028, 0); before_count = i_reads;
        i_read(32'h80000028, 0); check(i_reads == before_count, "I second access must hit"); i_hits = i_hits + 1;
        i_read(32'h80002028, 0); before_count = i_reads;
        i_read(32'h80000028, 0); check(i_reads == before_count, "I two ways resident"); i_hits = i_hits + 1;
        i_read(32'h80004028, 0);
        d_access(32'h80000048, 0, 0, 1, 0); before_count = d_reads;
        expect_fast_load = 1;
        d_access(32'h80000048, 0, 0, 1, 0); check(d_reads == before_count, "D second access must hit"); d_hits = d_hits + 1;
        expect_fast_load = 0;
        d_access(32'h80000048, 4'b0101, 32'h12345678, 1, 0); before_count = d_reads;
        d_access(32'h80000048, 0, 0, 1, 0); check(d_reads == before_count, "D successful store retains updated hit"); d_hits = d_hits + 1;
        before_count = d_reads;
        d_access(32'h800060ac, 4'b1111, 32'h98765432, 1, 0);
        check(d_reads == before_count + 1, "D write miss allocates a line");
        before_count = d_reads;
        d_access(32'h800060ac, 0, 0, 1, 0); check(d_reads == before_count, "D allocated store hit avoids reread");
        // Two clean ways are filled before a conflicting line forces the dirty victim out.
        d_access(32'h800160ac, 0, 0, 1, 0);
        d_access(32'h800260ac, 0, 0, 1, 0); check(memory[(32'h800060ac >> 2) & 16'hffff] === arch_memory[(32'h800060ac >> 2) & 16'hffff], "dirty victim is written back");
        d_access(32'h800160ac, 4'b1111, 32'hdeadbeef, 1, 0);
        store_error = 1;
        d_access(32'h800360ac, 0, 0, 1, 1); store_error = 0;
        for (n = 0; n < 8; n = n + 1) begin
            d_error_beat = n;
            d_access(32'h80008000 + n*32, 0, 0, 1, 1); d_error_beat = -1; before_count = d_reads;
            d_access(32'h80008000 + n*32, 0, 0, 1, 0);
            check(d_reads == before_count + 1, "D errored refill cannot become valid");
        end
        for (n = 0; n < 8; n = n + 1) begin
            i_error_beat = n;
            i_read(32'h8000a000 + n*32, 1); i_error_beat = -1; before_count = i_reads;
            i_read(32'h8000a000 + n*32, 0);
            check(i_reads == before_count + 1, "I errored refill cannot become valid");
        end
        i_read(32'h80000028, 0);
        memory[10] = memory[10] ^ 32'h679231ac;
        fork
            i_read(32'h8001c008, 0);
            begin
                wait (i_pending);
                @(negedge clk); i_flush = 1;
                @(negedge clk); i_flush = 0;
            end
        join
        while (!i_accept) @(negedge clk);
        i_read(32'h80000028, 0);
        d_access(32'h82000048, 0, 0, 1, 0); before_count = d_reads;
        d_access(32'h82000048, 0, 0, 1, 0); check(d_reads == before_count + 1, "shared DDR ignores permissive cacheable input");
        fork
            d_access(32'h8001c010, 0, 0, 1, 0);
            begin
                wait (d_pending && !d_pending_write);
                @(negedge clk); d_flush = 1; d_tag = d_tag + 1;
                begin : queued_flush_accept
                    forever begin @(posedge clk); if (d_accept) disable queued_flush_accept; end
                end
                @(negedge clk); d_flush = 0;
                while (!d_ack) @(negedge clk);
                check(!d_error, "held D flush completes after owned refill drains");
                @(negedge clk);
            end
        join
        before_count = d_reads;
        d_access(32'h8001c010, 0, 0, 1, 0);
        check(d_reads == before_count + 1, "queued D flush discards completed refill");
        d_maintenance(0); d_maintenance(1); d_maintenance(2);
        fork
            begin i_read(32'h8001c008, 0); i_read(32'h8001c028, 0); end
            begin d_access(32'h8001e014, 0, 0, 1, 0); d_access(32'h8001e034, 0, 0, 1, 0); end
        join
        check(simultaneous > 0, "joint I/D outstanding coverage");
        check(i_hits > 0 && d_hits > 0 && d_writes >= 8, "paired cache coverage");
        check(!i_pending && !d_pending, "drain before reset");
        @(negedge clk); rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
        d_maintenance(1);
        before_count = d_reads; d_access(32'h80000048, 0, 0, 1, 0);
        check(d_reads == before_count + 1, "reset clears D validity");
        before_count = i_reads; i_read(32'h80000028, 0);
        check(i_reads == before_count + 1, "reset clears I validity");
        $display("CPU_CACHE_PASS checks=%0d i_reads=%0d d_reads=%0d writes=%0d i_hits=%0d d_hits=%0d overlap=%0d", checks, i_reads, d_reads, d_writes, i_hits, d_hits, simultaneous);
        $finish;
    end
endmodule
