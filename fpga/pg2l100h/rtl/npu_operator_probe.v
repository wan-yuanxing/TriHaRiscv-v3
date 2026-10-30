`timescale 1ns/1ps
// Registered scan boundary for component STA only; no board/pin/SoC claim.
module npu_operator_probe (input wire clk_i, rst_ni, scan_i, scan_shift_i, capture_i, output wire scan_o);
    reg [250:0] input_q;
    reg [290:0] output_q;
    wire [290:0] sampled;
    assign scan_o=output_q[0];
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin input_q<=0;output_q<=0;end
        else begin
            if(scan_shift_i)input_q<={scan_i,input_q[250:1]};
            if(capture_i)output_q<=sampled;else if(scan_shift_i)output_q<={1'b0,output_q[290:1]};
        end
    end
    npu_operator_top u_operator (
.clk_i(clk_i),.rst_ni(rst_ni),
        .s_axi_awaddr_i(input_q[0 +: 32]),
        .s_axi_awvalid_i(input_q[32]),
        .s_axi_wdata_i(input_q[33 +: 32]),
        .s_axi_wstrb_i(input_q[65 +: 4]),
        .s_axi_wvalid_i(input_q[69]),
        .s_axi_bready_i(input_q[70]),
        .s_axi_araddr_i(input_q[71 +: 32]),
        .s_axi_arvalid_i(input_q[103]),
        .s_axi_rready_i(input_q[104]),
        .m_axi_arready_i(input_q[105]),
        .m_axi_rid_i(input_q[106 +: 4]),
        .m_axi_rdata_i(input_q[110 +: 128]),
        .m_axi_rresp_i(input_q[238 +: 2]),
        .m_axi_rlast_i(input_q[240]),
        .m_axi_rvalid_i(input_q[241]),
        .m_axi_awready_i(input_q[242]),
        .m_axi_wready_i(input_q[243]),
        .m_axi_bid_i(input_q[244 +: 4]),
        .m_axi_bresp_i(input_q[248 +: 2]),
        .m_axi_bvalid_i(input_q[250]),
        .s_axi_awready_o(sampled[0]),
        .s_axi_wready_o(sampled[1]),
        .s_axi_bresp_o(sampled[2 +: 2]),
        .s_axi_bvalid_o(sampled[4]),
        .s_axi_arready_o(sampled[5]),
        .s_axi_rdata_o(sampled[6 +: 32]),
        .s_axi_rresp_o(sampled[38 +: 2]),
        .s_axi_rvalid_o(sampled[40]),
        .irq_o(sampled[41]),
        .fault_o(sampled[42]),
        .m_axi_arid_o(sampled[43 +: 4]),
        .m_axi_araddr_o(sampled[47 +: 32]),
        .m_axi_arlen_o(sampled[79 +: 8]),
        .m_axi_arsize_o(sampled[87 +: 3]),
        .m_axi_arburst_o(sampled[90 +: 2]),
        .m_axi_arvalid_o(sampled[92]),
        .m_axi_rready_o(sampled[93]),
        .m_axi_awid_o(sampled[94 +: 4]),
        .m_axi_awaddr_o(sampled[98 +: 32]),
        .m_axi_awlen_o(sampled[130 +: 8]),
        .m_axi_awsize_o(sampled[138 +: 3]),
        .m_axi_awburst_o(sampled[141 +: 2]),
        .m_axi_awvalid_o(sampled[143]),
        .m_axi_wdata_o(sampled[144 +: 128]),
        .m_axi_wstrb_o(sampled[272 +: 16]),
        .m_axi_wlast_o(sampled[288]),
        .m_axi_wvalid_o(sampled[289]),
        .m_axi_bready_o(sampled[290])
    );
endmodule
