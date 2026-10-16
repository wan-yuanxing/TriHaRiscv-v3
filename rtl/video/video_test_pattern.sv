`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"

// Full-height RGB888 bars, ordered white/yellow/cyan/green/magenta/red/blue/black.
// y is retained as part of the pixel-coordinate interface; these bars are
// intentionally constant vertically. DE controls both horizontal and vertical
// blanking, including reset blanking supplied by video_timing.
module video_test_pattern (
    input  wire [10:0] x,
    input  wire [10:0] y,
    input  wire        de,
    output wire [23:0] rgb
);
    localparam integer BAR_WIDTH = `VIDEO_H_ACTIVE / 8;

    assign rgb = !de                 ? 24'h000000 :
                 x < BAR_WIDTH      ? 24'hffffff :
                 x < BAR_WIDTH * 2  ? 24'hffff00 :
                 x < BAR_WIDTH * 3  ? 24'h00ffff :
                 x < BAR_WIDTH * 4  ? 24'h00ff00 :
                 x < BAR_WIDTH * 5  ? 24'hff00ff :
                 x < BAR_WIDTH * 6  ? 24'hff0000 :
                 x < BAR_WIDTH * 7  ? 24'h0000ff :
                                       24'h000000;
endmodule

`default_nettype wire
