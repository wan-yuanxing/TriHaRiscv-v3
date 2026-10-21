/* Area fixture only: preserves every CPU+Cache external bus bit.
 * Report u_subsystem and its children, excluding scan FF/LUT/IO.
 * Not a board target or physical frequency acceptance.
 */
module triha_cached_core_map_top #(
    parameter integer CACHE_ENABLE = 1
) (
    input wire clk_i, input wire rst_ni,
    input wire shift_i, input wire capture_i, input wire scan_i,
    output wire scan_o
);
    reg [146:0] inputs_q;
    reg [248:0] outputs_q;
    wire [248:0] observed_w;
    assign scan_o = outputs_q[0];
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin inputs_q <= 0; outputs_q <= 0; end
        else begin
            if (shift_i) inputs_q <= {scan_i,inputs_q[146:1]};
            if (capture_i) outputs_q <= observed_w;
            else if (shift_i) outputs_q <= {1'b0,outputs_q[248:1]};
        end
    end
    triha_cached_core #(.CACHE_ENABLE(CACHE_ENABLE)) u_subsystem (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .external_irq_i(inputs_q[0 +: 1]),
        .protocol_fault_o(observed_w[0 +: 1]),
        .axi_awvalid_o(observed_w[1 +: 1]),
        .axi_awaddr_o(observed_w[2 +: 32]),
        .axi_awid_o(observed_w[34 +: 4]),
        .axi_awlen_o(observed_w[38 +: 8]),
        .axi_awsize_o(observed_w[46 +: 3]),
        .axi_awburst_o(observed_w[49 +: 2]),
        .axi_awready_i(inputs_q[1 +: 1]),
        .axi_wvalid_o(observed_w[51 +: 1]),
        .axi_wdata_o(observed_w[52 +: 128]),
        .axi_wstrb_o(observed_w[180 +: 16]),
        .axi_wlast_o(observed_w[196 +: 1]),
        .axi_wready_i(inputs_q[2 +: 1]),
        .axi_bvalid_i(inputs_q[3 +: 1]),
        .axi_bresp_i(inputs_q[4 +: 2]),
        .axi_bid_i(inputs_q[6 +: 4]),
        .axi_bready_o(observed_w[197 +: 1]),
        .axi_arvalid_o(observed_w[198 +: 1]),
        .axi_araddr_o(observed_w[199 +: 32]),
        .axi_arid_o(observed_w[231 +: 4]),
        .axi_arlen_o(observed_w[235 +: 8]),
        .axi_arsize_o(observed_w[243 +: 3]),
        .axi_arburst_o(observed_w[246 +: 2]),
        .axi_arready_i(inputs_q[10 +: 1]),
        .axi_rvalid_i(inputs_q[11 +: 1]),
        .axi_rdata_i(inputs_q[12 +: 128]),
        .axi_rresp_i(inputs_q[140 +: 2]),
        .axi_rid_i(inputs_q[142 +: 4]),
        .axi_rlast_i(inputs_q[146 +: 1]),
        .axi_rready_o(observed_w[248 +: 1])
    );
endmodule
