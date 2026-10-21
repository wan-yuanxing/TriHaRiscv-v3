`timescale 1ns/1ps
module tb_cpu_axi_cdc;
    parameter integer CORRUPT_DATA = 0;
    parameter integer MAX_CYCLES = 50000;
    parameter integer CPU_HALF_NS = 5;
    parameter integer DDR_HALF_NS = 4;
    reg cpu_clk = 0, ddr_clk = 0, rst_n = 0;
    always #(CPU_HALF_NS) cpu_clk = !cpu_clk;
    initial begin #1; forever #(DDR_HALF_NS) ddr_clk = !ddr_clk; end
    wire cpu_rst_n, ddr_rst_n;
    reg ready = 0, fault = 0, block_sinks = 0;
    reg [7:0] epoch = 0;
    wire ready_sync, fault_sync;
    integer cycles = 0;
    always @(posedge cpu_clk) begin
        cycles <= cycles+1;
        if (cycles > MAX_CYCLES) $fatal(1, "CPU_AXI_CDC_FAIL watchdog");
    end
    wire [48:0] aw_source, aw_sink;
    wire aw_sv, aw_sr, aw_dv, aw_dr, aw_done;
    wire [144:0] w_source, w_sink;
    wire w_sv, w_sr, w_dv, w_dr, w_done;
    wire [5:0] b_source, b_sink;
    wire b_sv, b_sr, b_dv, b_dr, b_done;
    wire [48:0] ar_source, ar_sink;
    wire ar_sv, ar_sr, ar_dv, ar_dr, ar_done;
    wire [134:0] r_source, r_sink;
    wire r_sv, r_sr, r_dv, r_dr, r_done;
    triha_axi128_cdc u_dut (
        .cpu_clk_i(cpu_clk),
        .ddr_clk_i(ddr_clk),
        .rst_ni(rst_n),
        .cpu_rst_no(cpu_rst_n),
        .ddr_rst_no(ddr_rst_n),
        .ddr_ready_i(ready),
        .ddr_fault_i(fault),
        .cpu_ddr_ready_o(ready_sync),
        .cpu_ddr_fault_o(fault_sync),
        .s_awvalid_i(aw_sv),
        .s_awready_o(aw_sr),
        .m_awvalid_o(aw_dv),
        .m_awready_i(aw_dr),
        .s_awaddr_i(aw_source[17 +: 32]),
        .m_awaddr_o(aw_sink[17 +: 32]),
        .s_awid_i(aw_source[13 +: 4]),
        .m_awid_o(aw_sink[13 +: 4]),
        .s_awlen_i(aw_source[5 +: 8]),
        .m_awlen_o(aw_sink[5 +: 8]),
        .s_awsize_i(aw_source[2 +: 3]),
        .m_awsize_o(aw_sink[2 +: 3]),
        .s_awburst_i(aw_source[0 +: 2]),
        .m_awburst_o(aw_sink[0 +: 2]),
        .s_wvalid_i(w_sv),
        .s_wready_o(w_sr),
        .m_wvalid_o(w_dv),
        .m_wready_i(w_dr),
        .s_wdata_i(w_source[17 +: 128]),
        .m_wdata_o(w_sink[17 +: 128]),
        .s_wstrb_i(w_source[1 +: 16]),
        .m_wstrb_o(w_sink[1 +: 16]),
        .s_wlast_i(w_source[0 +: 1]),
        .m_wlast_o(w_sink[0 +: 1]),
        .s_bvalid_o(b_dv),
        .s_bready_i(b_dr),
        .m_bvalid_i(b_sv),
        .m_bready_o(b_sr),
        .s_bid_o(b_sink[2 +: 4]),
        .m_bid_i(b_source[2 +: 4]),
        .s_bresp_o(b_sink[0 +: 2]),
        .m_bresp_i(b_source[0 +: 2]),
        .s_arvalid_i(ar_sv),
        .s_arready_o(ar_sr),
        .m_arvalid_o(ar_dv),
        .m_arready_i(ar_dr),
        .s_araddr_i(ar_source[17 +: 32]),
        .m_araddr_o(ar_sink[17 +: 32]),
        .s_arid_i(ar_source[13 +: 4]),
        .m_arid_o(ar_sink[13 +: 4]),
        .s_arlen_i(ar_source[5 +: 8]),
        .m_arlen_o(ar_sink[5 +: 8]),
        .s_arsize_i(ar_source[2 +: 3]),
        .m_arsize_o(ar_sink[2 +: 3]),
        .s_arburst_i(ar_source[0 +: 2]),
        .m_arburst_o(ar_sink[0 +: 2]),
        .s_rvalid_o(r_dv),
        .s_rready_i(r_dr),
        .m_rvalid_i(r_sv),
        .m_rready_o(r_sr),
        .s_rdata_o(r_sink[7 +: 128]),
        .m_rdata_i(r_source[7 +: 128]),
        .s_rid_o(r_sink[3 +: 4]),
        .m_rid_i(r_source[3 +: 4]),
        .s_rresp_o(r_sink[1 +: 2]),
        .m_rresp_i(r_source[1 +: 2]),
        .s_rlast_o(r_sink[0 +: 1]),
        .m_rlast_i(r_source[0 +: 1])
    );
    cdc_channel_check #(.WIDTH(49), .SALT(1), .CORRUPT(CORRUPT_DATA && 0)) u_aw_check (
        .source_clk(cpu_clk), .sink_clk(ddr_clk), .source_rst_n(cpu_rst_n), .sink_rst_n(ddr_rst_n),
        .epoch(epoch), .block_sink(block_sinks), .source_data(aw_source),
        .source_valid(aw_sv), .source_ready(aw_sr), .sink_data(aw_sink),
        .sink_valid(aw_dv), .sink_ready(aw_dr), .done(aw_done)
    );
    cdc_channel_check #(.WIDTH(145), .SALT(2), .CORRUPT(CORRUPT_DATA && 0)) u_w_check (
        .source_clk(cpu_clk), .sink_clk(ddr_clk), .source_rst_n(cpu_rst_n), .sink_rst_n(ddr_rst_n),
        .epoch(epoch), .block_sink(block_sinks), .source_data(w_source),
        .source_valid(w_sv), .source_ready(w_sr), .sink_data(w_sink),
        .sink_valid(w_dv), .sink_ready(w_dr), .done(w_done)
    );
    cdc_channel_check #(.WIDTH(6), .SALT(3), .CORRUPT(CORRUPT_DATA && 0)) u_b_check (
        .source_clk(ddr_clk), .sink_clk(cpu_clk), .source_rst_n(ddr_rst_n), .sink_rst_n(cpu_rst_n),
        .epoch(epoch), .block_sink(block_sinks), .source_data(b_source),
        .source_valid(b_sv), .source_ready(b_sr), .sink_data(b_sink),
        .sink_valid(b_dv), .sink_ready(b_dr), .done(b_done)
    );
    cdc_channel_check #(.WIDTH(49), .SALT(4), .CORRUPT(CORRUPT_DATA && 0)) u_ar_check (
        .source_clk(cpu_clk), .sink_clk(ddr_clk), .source_rst_n(cpu_rst_n), .sink_rst_n(ddr_rst_n),
        .epoch(epoch), .block_sink(block_sinks), .source_data(ar_source),
        .source_valid(ar_sv), .source_ready(ar_sr), .sink_data(ar_sink),
        .sink_valid(ar_dv), .sink_ready(ar_dr), .done(ar_done)
    );
    cdc_channel_check #(.WIDTH(135), .SALT(5), .CORRUPT(CORRUPT_DATA && 1)) u_r_check (
        .source_clk(ddr_clk), .sink_clk(cpu_clk), .source_rst_n(ddr_rst_n), .sink_rst_n(cpu_rst_n),
        .epoch(epoch), .block_sink(block_sinks), .source_data(r_source),
        .source_valid(r_sv), .source_ready(r_sr), .sink_data(r_sink),
        .sink_valid(r_dv), .sink_ready(r_dr), .done(r_done)
    );
    initial begin
        #17; rst_n = 1; ready = 1;
        repeat (100) @(negedge cpu_clk);
        block_sinks = 1;
        repeat (20) @(negedge cpu_clk);
        // Status changes are observations, never a FIFO reset or VALID gate.
        ready = 0; fault = 1;
        repeat (8) @(negedge cpu_clk);
        if (ready_sync !== 0 || fault_sync !== 1) $fatal(1,"CPU_AXI_CDC_FAIL status synchronizers");
        block_sinks = 0;
        wait(aw_done && w_done && b_done && ar_done && r_done);
        repeat (10) @(negedge cpu_clk);
        // Start a second epoch, fill live queues, then coordinate both resets.
        #2; rst_n = 0; epoch = 1;
        repeat (8) @(negedge cpu_clk); rst_n = 1; block_sinks = 1;
        repeat (40) @(negedge cpu_clk);
        #2; rst_n = 0; epoch = 2; ready = 1; fault = 0;
        repeat (8) @(negedge cpu_clk); rst_n = 1; block_sinks = 0;
        wait(aw_done && w_done && b_done && ar_done && r_done);
        repeat (10) @(negedge cpu_clk);
        if (ready_sync !== 1 || fault_sync !== 0) $fatal(1,"CPU_AXI_CDC_FAIL reset recovery");
        $display("CPU_AXI_CDC_PASS channels=5 messages_per_channel_epoch=256 epochs_completed=2 live_reset=1 cpu_half=%0d ddr_half=%0d", CPU_HALF_NS, DDR_HALF_NS);
        $finish;
    end
endmodule

module cdc_channel_check #(
    parameter integer WIDTH = 32, SALT = 1, CORRUPT = 0
) (
    input wire source_clk, sink_clk, source_rst_n, sink_rst_n,
    input wire [7:0] epoch,
    input wire block_sink,
    output reg [WIDTH-1:0] source_data,
    output reg source_valid,
    input wire source_ready,
    input wire [WIDTH-1:0] sink_data,
    input wire sink_valid,
    output wire sink_ready,
    output wire done
);
    integer sent = 0, received = 0, stall_cycles = 0;
    reg [31:0] source_rng = 32'h12345678 + SALT, sink_rng = 32'h513791ac + SALT;
    reg stalled = 0;
    reg [WIDTH-1:0] saved;
    function [WIDTH-1:0] pattern;
        input integer index;
        input [7:0] generation;
        integer bit_number;
        reg [31:0] word;
        begin
            for (bit_number = 0; bit_number < WIDTH; bit_number = bit_number+1) begin
                word = (32'h7193acde * (index+1)) ^ (32'h3897c6ab * (bit_number/32+SALT)) ^
                    (32'h01010101 * generation);
                pattern[bit_number] = word[bit_number%32];
            end
        end
    endfunction
    assign sink_ready = !block_sink && sink_rst_n && sink_rng[2];
    assign done = received == 256;
    // Advance only at actual handshakes; payload holds through arbitrary stalls.
    always @(posedge source_clk or negedge source_rst_n) begin
        if (!source_rst_n) begin
            sent <= 0; source_rng <= 32'h12345678 + SALT;
            source_data <= 0; source_valid <= 0;
        end
        else begin
            source_rng <= {source_rng[30:0], source_rng[31]^source_rng[21]^source_rng[1]^source_rng[0]};
            if (source_valid && source_ready) sent <= sent+1;
            if (!source_valid || source_ready) begin
                source_valid <= (sent + (source_valid && source_ready)) < 256 && source_rng[0];
                source_data <= pattern(sent + (source_valid && source_ready), epoch);
            end
        end
    end
    always @(posedge sink_clk or negedge sink_rst_n) begin
        if (!sink_rst_n) begin received <= 0; stalled <= 0; sink_rng <= 32'h513791ac + SALT; stall_cycles <= 0; end
        else begin
            sink_rng <= {sink_rng[30:0], sink_rng[31]^sink_rng[21]^sink_rng[1]^sink_rng[0]};
            if (stalled && (!sink_valid || sink_data !== saved)) $fatal(1,"CPU_AXI_CDC_FAIL unstable blocked channel %0d", SALT);
            stalled <= sink_valid && !sink_ready;
            saved <= sink_data;
            if (sink_valid && !sink_ready) stall_cycles <= stall_cycles+1;
            if (sink_valid && sink_ready) begin
                if (received >= sent || (sink_data ^ CORRUPT) !== pattern(received, epoch))
                    $fatal(1,"CPU_AXI_CDC_FAIL payload/order channel=%0d index=%0d epoch=%0d", SALT, received, epoch);
                received <= received+1;
                if (received == 255 && stall_cycles == 0) $fatal(1,"CPU_AXI_CDC_FAIL no backpressure coverage");
            end
        end
    end
endmodule
