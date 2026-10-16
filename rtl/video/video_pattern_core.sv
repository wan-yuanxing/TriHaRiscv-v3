`timescale 1ns/1ps
`default_nettype none
// Portable synthesis boundary. pixel_clk is supplied externally at 40 MHz.
// The board wrapper must synchronize reset release and supply PLL/HDMI I/O.
module video_pattern_core (
    input wire pixel_clk,
    input wire reset_n,
    output wire hsync,
    output wire vsync,
    output wire de,
    output wire frame_start,
    output wire [23:0] rgb
);
    wire [10:0] x, y;
    video_timing timing (
        .pixel_clk(pixel_clk), .reset_n(reset_n), .x(x), .y(y),
        .hsync(hsync), .vsync(vsync), .de(de), .frame_start(frame_start)
    );
    video_test_pattern pattern (.x(x), .y(y), .de(de), .rgb(rgb));
endmodule
`default_nettype wire
