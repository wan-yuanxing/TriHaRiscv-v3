`timescale 1ns/1ps
`default_nettype none
// Qualify whole healthy frames before a one-shot capture can select its SOF.
// Timing lock may precede source image recovery after HDMI reinitialization.
// This bounded startup policy never classifies or rejects pixels by color.
module video_capture_startup_guard #(
    parameter integer STABLE_FRAMES=128
)(
    input wire pixel_clk,reset_n,mode_good,rx_ready,
    input wire frame_start,frame_end,frame_good,
    output wire capture_ready
);
    localparam integer CW=STABLE_FRAMES>1?$clog2(STABLE_FRAMES+1):1;
    reg [CW-1:0] completed_frames;
    reg frame_open;
    generate if(STABLE_FRAMES<1)begin:invalid_parameters
        initial $fatal(1,"Startup guard requires STABLE_FRAMES >= 1");
    end endgenerate
    assign capture_ready=mode_good && rx_ready && completed_frames==STABLE_FRAMES;
    always @(posedge pixel_clk or negedge reset_n)begin
        if(!reset_n)begin completed_frames<=0;frame_open<=0;end
        else if(mode_good && rx_ready)begin
            if(frame_start)frame_open<=1;
            if(frame_end)begin
                frame_open<=0;
                if(frame_open && frame_good)begin
                    if(completed_frames<STABLE_FRAMES)completed_frames<=completed_frames+1'b1;
                end else completed_frames<=0;
            end
        end else begin completed_frames<=0;frame_open<=0;end
    end
endmodule
`default_nettype wire
