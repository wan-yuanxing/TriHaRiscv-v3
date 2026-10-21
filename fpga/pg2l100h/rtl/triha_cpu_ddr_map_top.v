/* Area fixture only. Report u_system and child hierarchies; exclude scan logic.
 * This is not a frequency, physical DDR or board acceptance target. */
module triha_cpu_ddr_map_top (
    input wire cpu_clk_i,
    input wire ddr_clk_i,
    input wire rst_ni,
    input wire shift_i,
    input wire capture_i,
    input wire scan_i,
    output wire scan_o
);
    reg [272:0] inputs_q;
    reg [381:0] outputs_q;
    wire [381:0] observed_w;
    assign scan_o = outputs_q[0];
    always @(posedge cpu_clk_i or negedge rst_ni) begin
        if (!rst_ni) begin inputs_q <= 0; outputs_q <= 0; end
        else begin
            if (shift_i) inputs_q <= {scan_i, inputs_q[272:1]};
            if (capture_i) outputs_q <= observed_w;
            else if (shift_i) outputs_q <= {1'b0, outputs_q[381:1]};
        end
    end
    triha_cpu_ddr u_system (
        .cpu_clk_i(cpu_clk_i), .ddr_clk_i(ddr_clk_i), .rst_ni(rst_ni),
        .external_irq_i(inputs_q[0 +: 1]),
        .ddr_ready_i(inputs_q[1 +: 1]),
        .ddr_fault_i(inputs_q[2 +: 1]),
        .h_awready_i(inputs_q[3 +: 1]),
        .h_wready_i(inputs_q[4 +: 1]),
        .h_wid_i(inputs_q[5 +: 4]),
        .h_wlast_i(inputs_q[9 +: 1]),
        .h_arready_i(inputs_q[10 +: 1]),
        .h_rdata_i(inputs_q[11 +: 256]),
        .h_rid_i(inputs_q[267 +: 4]),
        .h_rlast_i(inputs_q[271 +: 1]),
        .h_rvalid_i(inputs_q[272 +: 1]),
        .cpu_ddr_fault_o(observed_w[0 +: 1]),
        .protocol_fault_o(observed_w[1 +: 1]),
        .bridge_fault_code_o(observed_w[2 +: 8]),
        .uart_tx_o(observed_w[10 +: 1]),
        .done_o(observed_w[11 +: 1]),
        .exit_code_o(observed_w[12 +: 8]),
        .h_awaddr_o(observed_w[20 +: 28]),
        .h_awlen_o(observed_w[48 +: 4]),
        .h_awid_o(observed_w[52 +: 4]),
        .h_awvalid_o(observed_w[56 +: 1]),
        .h_wdata_o(observed_w[57 +: 256]),
        .h_wstrb_o(observed_w[313 +: 32]),
        .h_araddr_o(observed_w[345 +: 28]),
        .h_arlen_o(observed_w[373 +: 4]),
        .h_arid_o(observed_w[377 +: 4]),
        .h_arvalid_o(observed_w[381 +: 1])
    );
endmodule
