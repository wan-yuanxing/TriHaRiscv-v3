`timescale 1ns/1ps
`default_nettype none
// MES2L676-100HP TX-only fixed-mode board test. LED1 is PLL lock, LED2 error,
// LED3 TX init complete; these legacy reference port names are retained for pins.
module video_board_smoke_top(
    input wire sys_clk,
    input wire rst_in,
    output wire rstn_out,
    output wire hd_scl,
    inout wire hd_sda,
    output wire pix_clk,
    output reg vs_out,
    output reg hs_out,
    output reg de_out,
    output reg [7:0] r_out,
    output reg [7:0] g_out,
    output reg [7:0] b_out,
    output wire heart_beat_led,
    output wire ddr_init_done,
    output wire init_over_rx,
    output wire hdmi_int_led
);
    wire cfg_clk, locked, pixel_reset_n, cfg_reset_n;
    video_clock_reset clocks (
        .sys_clk(sys_clk), .reset_n(rst_in), .pixel_clk(pix_clk),
        .cfg_clk(cfg_clk), .locked(locked), .pixel_reset_n(pixel_reset_n),
        .cfg_reset_n(cfg_reset_n), .tx_reset_n(rstn_out));
    hdmi_tx_init tx (.clk_cfg(cfg_clk), .reset_n(rstn_out),
                     .iic_scl(hd_scl), .iic_sda(hd_sda),
                     .init_done(hdmi_int_led), .init_error(init_over_rx));
    assign ddr_init_done = locked; // LED1: PLL lock. No DDR is instantiated.
    reg [23:0] heartbeat_count;
    always @(posedge cfg_clk or negedge cfg_reset_n) begin
        if(!cfg_reset_n) heartbeat_count <= 0;
        else heartbeat_count <= heartbeat_count + 1'b1;
    end
    assign heart_beat_led=heartbeat_count[23];
    wire hs,vs,de,frame_start;
    wire [23:0] rgb;
    video_pattern_core pattern (.pixel_clk(pix_clk), .reset_n(pixel_reset_n),
        .hsync(hs), .vsync(vs), .de(de), .frame_start(frame_start), .rgb(rgb));
    // Match the reference launch convention; all controls share the pixel delay.
    // External receiver setup/hold and sampling polarity remain to be verified.
    always @(posedge pix_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            hs_out<=0; vs_out<=0; de_out<=0;
            r_out<=0; g_out<=0; b_out<=0;
        end else begin
            hs_out<=hs; vs_out<=vs; de_out<=de;
            r_out<=rgb[23:16]; g_out<=rgb[15:8]; b_out<=rgb[7:0];
        end
    end
endmodule
`default_nettype wire
