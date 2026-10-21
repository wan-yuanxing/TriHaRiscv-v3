`timescale 1ns / 1ps
// Exercises the common DDR boundary independently of cache tag/controller state.
module tb_cpu_cache_axi;
    parameter integer CORRUPT_DATA = 0;
    reg clk = 0, rst_n = 0;
    always #5 clk = !clk;
    reg [31:0] rng = 32'h763d93e1;
    integer cycles = 0, checks = 0, reads = 0, writes = 0;
    reg [31:0] memory [0:4095];
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
        if (cycles > 100000) check(0, "transport watchdog");
    end
    reg i_arvalid = 0, i_rready = 0;
    reg [31:0] i_araddr = 0;
    reg [7:0] i_len = 7;
    wire i_arready, i_rvalid, i_rlast;
    wire [31:0] i_rdata;
    wire [1:0] i_rresp;
    wire [3:0] i_rid;
    reg d_rd = 0;
    reg [3:0] d_wr = 0;
    reg [7:0] d_len = 0;
    reg [31:0] d_addr = 0, d_wdata = 0;
    wire d_accept, d_ack, d_error;
    wire [31:0] d_rdata;
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
    reg read_bad_id = 0, write_bad_id = 0;
    integer read_bad_last = 0;
    integer read_error_beat = -1;
    triha_cpu_cache_axi u_dut (
        .clk_i(clk), .rst_ni(rst_n),
        .i_arvalid_i(i_arvalid), .i_araddr_i(i_araddr), .i_arid_i(4'd1), .i_arlen_i(i_len),
        .i_arready_o(i_arready), .i_rvalid_o(i_rvalid), .i_rdata_o(i_rdata),
        .i_rresp_o(i_rresp), .i_rid_o(i_rid), .i_rlast_o(i_rlast), .i_rready_i(i_rready),
        .d_rd_i(d_rd), .d_wr_i(d_wr), .d_len_i(d_len), .d_addr_i(d_addr), .d_wdata_i(d_wdata),
        .d_accept_o(d_accept), .d_ack_o(d_ack), .d_error_o(d_error), .d_rdata_o(d_rdata),
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
                have_aw <= 1; saved_awaddr <= awaddr; bid <= awid ^ write_bad_id;
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
                                memory[(saved_awaddr[13:2] + lane/4) & 4095][(lane%4)*8 +: 8] <= saved_wdata[lane*8 +: 8];
                end
            end
            if (bvalid && bready) begin bvalid <= 0; have_aw <= 0; have_w <= 0; writes <= writes + 1; end
            if (arvalid && arready) begin
                check(araddr[3:0] == 0 && arlen <= 1 && arsize == 4 && arburst == 1, "AR geometry");
                check(({1'b0,araddr[11:0]} + ((arlen+1)*16)) <= 4096, "read cannot cross 4KiB");
                read_pending <= 1; saved_araddr <= araddr; read_count <= arlen + 1;
                read_beat <= 0; rid <= arid ^ read_bad_id; reads <= reads + 1;
            end
            if (rvalid && rready) begin
                rvalid <= 0;
                if (read_beat == read_count - 1 || read_bad_last == 1) read_pending <= 0;
                else read_beat <= read_beat + 1;
            end
            if (read_pending && !rvalid && rng[6]) begin
                rvalid <= 1;
                rlast <= read_bad_last == 1 ? read_beat == 0 : read_bad_last == 2 ? 1'b0 : read_beat == read_count - 1;
                rresp <= read_beat == read_error_beat ? 2'b10 : 0;
                for (lane = 0; lane < 4; lane = lane + 1)
                    rdata[lane*32 +: 32] <= memory[(saved_araddr[13:2]+read_beat*4+lane)&4095] ^ CORRUPT_DATA;
            end
        end
    end
    always @(negedge clk) i_rready = rng[8];
    task i_read;
        input [31:0] address;
        input expect_error;
        integer beat;
        begin
            @(negedge clk); i_araddr = address; i_arvalid = 1;
            begin : ia forever begin @(posedge clk); if (i_arready) disable ia; end end
            @(negedge clk); i_arvalid = 0;
            beat = 0;
            while (beat < 8) begin
                @(posedge clk);
                if (i_rvalid && i_rready) begin
                    check(i_rid == 1 && i_rlast == (beat == 7), "I response ID/count/LAST");
                    check((i_rresp != 0) === expect_error, "I burst error propagated");
                    if (!expect_error) check(i_rdata === memory[(address[13:2]+beat)&4095], "I serialized word");
                    beat = beat + 1;
                end
            end
            @(negedge clk);
        end
    endtask
    task i_read_short;
        input [31:0] address;
        integer beat;
        begin
            @(negedge clk); i_araddr = address; i_len = 1; i_arvalid = 1;
            begin : isa forever begin @(posedge clk); if (i_arready) disable isa; end end
            @(negedge clk); i_arvalid = 0;
            beat = 0;
            while (beat < 2) begin
                @(posedge clk);
                if (i_rvalid && i_rready) begin
                    check(i_rid == 1 && i_rlast == (beat == 1) && i_rresp == 0, "uncached I response geometry");
                    check(i_rdata === memory[(address[13:2]+beat)&4095], "uncached I response word/lane");
                    beat = beat + 1;
                end
            end
            @(negedge clk); i_len = 7;
        end
    endtask
    task d_read;
        input [31:0] address;
        input integer words;
        input expect_error;
        integer beat;
        begin
            @(negedge clk); d_addr = address; d_len = words - 1; d_rd = 1;
            begin : da forever begin @(posedge clk); if (d_accept) disable da; end end
            @(negedge clk); d_rd = 0;
            beat = 0;
            while (beat < words) begin
                @(posedge clk);
                if (d_ack) begin
                    check(d_error === expect_error, "D read error propagated");
                    if (!expect_error) check(d_rdata === memory[(address[13:2]+beat)&4095], "D serialized lane");
                    beat = beat + 1;
                end
            end
            @(negedge clk);
        end
    endtask
    task d_write;
        input [31:0] address;
        input [3:0] mask;
        input [31:0] value;
        input expect_error;
        reg [31:0] expected, before_neighbor;
        integer b;
        begin
            expected = memory[address[13:2]];
            before_neighbor = memory[(address[13:2]+1)&4095];
            if (!expect_error)
                for (b = 0; b < 4; b = b + 1) if (mask[b]) expected[b*8 +: 8] = value[b*8 +: 8];
            @(negedge clk); d_addr = address; d_len = 0; d_wr = mask; d_wdata = value;
            begin : wa forever begin @(posedge clk); if (d_accept) disable wa; end end
            @(negedge clk); d_wr = 0;
            begin : wb forever begin @(posedge clk); if (d_ack) disable wb; end end
            check(d_error === expect_error, "D write response error");
            check(memory[address[13:2]] === expected, "D write exact word/byte strobes");
            check(memory[(address[13:2]+1)&4095] === before_neighbor, "D write leaves neighbor intact");
            @(negedge clk);
        end
    endtask
    task reset_after_fault;
        begin
            repeat (3) @(negedge clk);
            check(protocol_fault && !i_arready && !d_accept, "protocol fault quarantines new transactions");
            check(!read_pending && !rvalid && !have_aw && !have_w && !bvalid, "fault test drained physical transaction");
            rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
            @(negedge clk); check(!protocol_fault, "coordinated reset clears quarantine");
        end
    endtask
    integer n;
    initial begin
        for (n = 0; n < 4096; n = n + 1) memory[n] = 32'h3155a72b ^ (n*32'h8721345);
        repeat (4) @(negedge clk); rst_n = 1;
        i_read(32'h80000fe0, 0);
        i_read_short(32'h80000100);
        i_read_short(32'h80000108);
        d_read(32'h80001020, 8, 0);
        for (n = 0; n < 4; n = n + 1) d_read(32'h82000100+n*4, 1, 0);
        for (n = 1; n < 16; n = n + 1) d_write(32'h82000100+(n%4)*4, n[3:0], 32'h543210ef ^ n, 0);
        write_error = 1; d_write(32'h82000100, 4'hf, 32'hdeadbeef, 1); write_error = 0;
        for (n = 0; n < 2; n = n + 1) begin
            read_error_beat = n; i_read(32'h80001200, 1); d_read(32'h80001220, 8, 1);
        end
        read_error_beat = -1;
        fork i_read(32'h80001300, 0); d_read(32'h80001320, 8, 0); join
        check(!protocol_fault, "ordinary backpressure/errors must not poison adapter");
        check(reads >= 12 && writes == 16, "transport exercised reads/writes/errors");
        n = reads;
        d_read(32'h10000000, 1, 1);
        check(reads == n, "MMIO cannot be widened to DDR read");
        d_write(32'h10000000, 4'hf, 32'hdeadbeef, 1);
        check(writes == 16, "MMIO cannot be widened to DDR write");
        read_bad_id = 1; i_read(32'h80001340, 1); read_bad_id = 0; reset_after_fault;
        read_bad_last = 1; d_read(32'h80001360, 8, 1); read_bad_last = 0; reset_after_fault;
        read_bad_last = 2; i_read(32'h80001380, 1); read_bad_last = 0; reset_after_fault;
        write_bad_id = 1; d_write(32'h82000100, 4'hf, memory[64], 1); write_bad_id = 0; reset_after_fault;
        $display("CPU_CACHE_AXI_PASS checks=%0d reads=%0d writes=%0d", checks, reads, writes);
        $finish;
    end
endmodule
