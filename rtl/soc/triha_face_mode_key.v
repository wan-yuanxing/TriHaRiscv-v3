`timescale 1ns/1ps
`default_nettype none
// Video-domain requested mode. CPU observes it through the existing AXI-Lite
// CDC and remains the sole owner of display submissions and frame references.
module triha_face_mode_key #(parameter integer CLOCK_HZ=125000000,STABLE_MS=20)(
    input wire clk_i,rst_ni,button_ni,output reg [1:0] mode_o
);
    wire press_pulse;
    video_button_debounce #(.CLOCK_HZ(CLOCK_HZ),.STABLE_MS(STABLE_MS)) u_button(
        .clk(clk_i),.reset_n(rst_ni),.button_async(button_ni),.pressed(),.press_pulse(press_pulse));
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)mode_o<=0;
        else if(press_pulse)mode_o<=mode_o==2?2'd0:mode_o+2'd1;
    end
endmodule
`default_nettype wire
