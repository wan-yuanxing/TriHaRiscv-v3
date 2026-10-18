`timescale 1ns/1ps
module tb_nchw_parameters #(
    parameter integer W=1,AH=1,PT=0,PB=0,RS=16,PS=16
);
    detect_nchw_dma #(.WIDTH(W),.ACTIVE_HEIGHT(AH),.PAD_TOP(PT),.PAD_BOTTOM(PB),
        .ROW_STRIDE(RS),.PLANE_STRIDE(PS)) dut(
        .clk(1'b0),.reset_n(1'b0),.online(1'b0),.abort(1'b0),.req_valid(1'b0),
        .req_base(32'd0),.req_tag(32'd0),.s_valid(1'b0),.s_rgb(24'd0),.s_row_last(1'b0),
        .result_ready(1'b0),.awready(1'b0),.wready(1'b0),.bid(4'd0),.bresp(2'd0),.bvalid(1'b0));
    initial begin #1;$display("NCHW_PARAMETERS_ACCEPTED");$finish;end
endmodule
