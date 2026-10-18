`timescale 1ns/1ps
module tb_three_capture_parameters #(
    parameter integer W=0,H=10,PT=0,PB=0,TC=100
);
    reg clk=0,reset_n=0;
    always #4 clk=~clk;
    wire ready,arm,error,completion,success,awvalid;
    wire [7:0] code,result_code;
    video_three_branch_capture #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB),
        .TIMEOUT_CYCLES(TC)) dut(
        .clk(clk),.reset_n(reset_n),.init_done(reset_n),.abort(1'b0),
        .req_valid(reset_n),.req_ready(ready),.req_slot(2'd0),.req_frame_id(32'd1),.req_preprocess_version(32'd1),
        .m_valid(1'b0),.m_data(48'd0),.source_fault(1'b0),.overflow(1'b0),
        .accepted_ready(1'b1),.completion_ready(1'b0),.arm_toggle(arm),.error(error),.error_code(code),
        .completion_valid(completion),.completion_success(success),.completion_code(result_code),
        .awvalid(awvalid),.awready(1'b1),.wready(1'b1),.bid(4'd0),.bresp(2'd0),.bvalid(1'b0));
    always @(posedge clk)if(reset_n&&(arm||awvalid))$fatal(1,"invalid geometry generated traffic");
    initial begin
        repeat(3)@(negedge clk);reset_n=1;repeat(40)@(negedge clk);
        if(!error||code!==8'h08||!completion||success||result_code!==8'h08)$fatal(1,"invalid geometry not rejected");
        $display("THREE_CAPTURE_PARAMETERS_PASS W=%0d H=%0d PT=%0d PB=%0d TC=%0d",W,H,PT,PB,TC);$finish;
    end
endmodule
