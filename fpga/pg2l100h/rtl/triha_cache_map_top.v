/* Mapping fixture only. All cache bus input bits are controllable and
 * all output bits are captured individually before serial observation.
 * Fixture FF/LUT/IO resources are excluded from the u_cache area report.
 * Not a board image, DDR controller, frequency or CPU integration acceptance.
 */
module triha_cache_map_top (
    input wire clk_i,
    input wire rst_ni,
    input wire shift_i,
    input wire capture_i,
    input wire scan_i,
    output wire scan_o
);
    reg [264:0] inputs_q;
    reg [361:0] outputs_q;
    wire [361:0] observed_w;
    assign scan_o = outputs_q[0];
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin inputs_q <= 0; outputs_q <= 0; end
        else begin
            if (shift_i) inputs_q <= {scan_i, inputs_q[264:1]};
            if (capture_i) outputs_q <= observed_w;
            else if (shift_i) outputs_q <= {1'b0, outputs_q[361:1]};
        end
    end
    triha_cache_subsystem u_cache (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .inst_req_i(inputs_q[0 +: 1]),
        .inst_flush_i(inputs_q[1 +: 1]),
        .inst_invalidate_i(inputs_q[2 +: 1]),
        .inst_addr_i(inputs_q[3 +: 32]),
        .inst_accept_o(observed_w[0 +: 1]),
        .inst_valid_o(observed_w[1 +: 1]),
        .inst_error_o(observed_w[2 +: 1]),
        .inst_rdata_o(observed_w[3 +: 64]),
        .data_addr_i(inputs_q[35 +: 32]),
        .data_wdata_i(inputs_q[67 +: 32]),
        .data_re_i(inputs_q[99 +: 1]),
        .data_wstrb_i(inputs_q[100 +: 4]),
        .data_cacheable_i(inputs_q[104 +: 1]),
        .data_req_tag_i(inputs_q[105 +: 11]),
        .data_invalidate_i(inputs_q[116 +: 1]),
        .data_writeback_i(inputs_q[117 +: 1]),
        .data_flush_i(inputs_q[118 +: 1]),
        .data_rdata_o(observed_w[67 +: 32]),
        .data_accept_o(observed_w[99 +: 1]),
        .data_ack_o(observed_w[100 +: 1]),
        .data_error_o(observed_w[101 +: 1]),
        .data_resp_tag_o(observed_w[102 +: 11]),
        .protocol_fault_o(observed_w[113 +: 1]),
        .axi_awvalid_o(observed_w[114 +: 1]),
        .axi_awaddr_o(observed_w[115 +: 32]),
        .axi_awid_o(observed_w[147 +: 4]),
        .axi_awlen_o(observed_w[151 +: 8]),
        .axi_awsize_o(observed_w[159 +: 3]),
        .axi_awburst_o(observed_w[162 +: 2]),
        .axi_awready_i(inputs_q[119 +: 1]),
        .axi_wvalid_o(observed_w[164 +: 1]),
        .axi_wdata_o(observed_w[165 +: 128]),
        .axi_wstrb_o(observed_w[293 +: 16]),
        .axi_wlast_o(observed_w[309 +: 1]),
        .axi_wready_i(inputs_q[120 +: 1]),
        .axi_bvalid_i(inputs_q[121 +: 1]),
        .axi_bresp_i(inputs_q[122 +: 2]),
        .axi_bid_i(inputs_q[124 +: 4]),
        .axi_bready_o(observed_w[310 +: 1]),
        .axi_arvalid_o(observed_w[311 +: 1]),
        .axi_araddr_o(observed_w[312 +: 32]),
        .axi_arid_o(observed_w[344 +: 4]),
        .axi_arlen_o(observed_w[348 +: 8]),
        .axi_arsize_o(observed_w[356 +: 3]),
        .axi_arburst_o(observed_w[359 +: 2]),
        .axi_arready_i(inputs_q[128 +: 1]),
        .axi_rvalid_i(inputs_q[129 +: 1]),
        .axi_rdata_i(inputs_q[130 +: 128]),
        .axi_rresp_i(inputs_q[258 +: 2]),
        .axi_rid_i(inputs_q[260 +: 4]),
        .axi_rlast_i(inputs_q[264 +: 1]),
        .axi_rready_o(observed_w[361 +: 1])
    );
endmodule
