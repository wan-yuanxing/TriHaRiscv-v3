/* Area fixture only: report u_system and its children; exclude scan registers.
 * Never use this serial observation fixture for timing or board acceptance. */
module triha_cached_soc_map_top #(
    parameter integer CACHE_ENABLE = 1
) (
    input wire clk_i,
    input wire rst_ni,
    input wire shift_i,
    input wire capture_i,
    input wire scan_i,
    output wire scan_o
);
    reg [148:0] inputs_q;
    reg [259:0] outputs_q;
    wire [259:0] observed_w;
    assign scan_o = outputs_q[0];
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin inputs_q <= 0; outputs_q <= 0; end
        else begin
            if (shift_i) inputs_q <= {scan_i,inputs_q[148:1]};
            if (capture_i) outputs_q <= observed_w;
            else if (shift_i) outputs_q <= {1'b0,outputs_q[259:1]};
        end
    end
    triha_cached_soc #(.CACHE_ENABLE(CACHE_ENABLE)) u_system (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .external_irq_i(inputs_q[0 +: 1]),
        .ddr_ready_i(inputs_q[1 +: 1]),
        .ddr_fault_i(inputs_q[2 +: 1]),
        .axi_awready_i(inputs_q[3 +: 1]),
        .axi_wready_i(inputs_q[4 +: 1]),
        .axi_bvalid_i(inputs_q[5 +: 1]),
        .axi_bresp_i(inputs_q[6 +: 2]),
        .axi_bid_i(inputs_q[8 +: 4]),
        .axi_arready_i(inputs_q[12 +: 1]),
        .axi_rvalid_i(inputs_q[13 +: 1]),
        .axi_rdata_i(inputs_q[14 +: 128]),
        .axi_rresp_i(inputs_q[142 +: 2]),
        .axi_rid_i(inputs_q[144 +: 4]),
        .axi_rlast_i(inputs_q[148 +: 1]),
        .ddr_fault_o(observed_w[0 +: 1]),
        .uart_tx_o(observed_w[1 +: 1]),
        .done_o(observed_w[2 +: 1]),
        .exit_code_o(observed_w[3 +: 8]),
        .protocol_fault_o(observed_w[11 +: 1]),
        .axi_awvalid_o(observed_w[12 +: 1]),
        .axi_awaddr_o(observed_w[13 +: 32]),
        .axi_awid_o(observed_w[45 +: 4]),
        .axi_awlen_o(observed_w[49 +: 8]),
        .axi_awsize_o(observed_w[57 +: 3]),
        .axi_awburst_o(observed_w[60 +: 2]),
        .axi_wvalid_o(observed_w[62 +: 1]),
        .axi_wdata_o(observed_w[63 +: 128]),
        .axi_wstrb_o(observed_w[191 +: 16]),
        .axi_wlast_o(observed_w[207 +: 1]),
        .axi_bready_o(observed_w[208 +: 1]),
        .axi_arvalid_o(observed_w[209 +: 1]),
        .axi_araddr_o(observed_w[210 +: 32]),
        .axi_arid_o(observed_w[242 +: 4]),
        .axi_arlen_o(observed_w[246 +: 8]),
        .axi_arsize_o(observed_w[254 +: 3]),
        .axi_arburst_o(observed_w[257 +: 2]),
        .axi_rready_o(observed_w[259 +: 1])
    );
endmodule
