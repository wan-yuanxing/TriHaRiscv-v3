`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"

// Portable fixed-mode RX monitor, in the receiver's 40 MHz pixel-clock domain.
// HS/VS/DE/RGB and enable/rx_ready must already be synchronous to pixel_clk;
// reset_n asserts asynchronously and releases through an external synchronizer.
// This block measures clock cycles, not pixel-clock frequency. Supported input
// is RGB888, 800x600 active, 1056x628 total, with positive HS and VS.
//
// The first positive VS edge after reset/disable/not-ready opens an interval.
// Earlier partial input is discarded. Registered candidate pixels retain all
// RGB888 bits; frame_start accompanies the first candidate at effective (0,0).
// At the NEXT positive VS edge frame_end closes that interval and frame_good
// qualifies its complete geometry. A consumer must await frame_good before
// publishing candidate storage. These events are not DMA/CAPTURE_DONE events.
// Control loss aborts the interval without frame_end, preventing frame splicing.
//
// mode_locked is earned only by a complete good interval and drops on a fault.
// mode_error is sticky until reset; readiness loss within an interval sets it.
// Measurements describe the last nonempty completed row (active_width), last
// completed interval (active_height/v_total), and last HS period (h_total).
// Measurements clear on control loss. Blanked RGB and coordinates are zero.
module video_rx (
    input  wire        pixel_clk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire        rx_ready,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output reg         pixel_valid,
    output reg  [23:0] rgb_out,
    output reg  [10:0] x,
    output reg  [10:0] y,
    output reg         frame_start,
    output reg         frame_end,
    output reg         frame_good,
    output reg         mode_locked,
    output reg  [10:0] active_width,
    output reg  [10:0] active_height,
    output reg  [10:0] h_total,
    output reg  [10:0] v_total,
    output reg         mode_error
);
    localparam [10:0] H_ACTIVE = `VIDEO_H_ACTIVE;
    localparam [10:0] V_ACTIVE = `VIDEO_V_ACTIVE;
    localparam [10:0] H_TOTAL = `VIDEO_H_TOTAL;
    localparam [10:0] V_TOTAL = `VIDEO_V_TOTAL;
    localparam [10:0] H_LAST = H_TOTAL - 11'd1;
    localparam [19:0] FRAME_LAST = `VIDEO_H_TOTAL * `VIDEO_V_TOTAL - 1;

    reg hs_previous, vs_previous, de_previous;
    reg inputs_primed;
    reg hs_seen, hs_period_seen;
    reg frame_open, frame_started, frame_bad;
    reg active_region_done;
    reg [10:0] h_cycles;
    reg [10:0] v_lines;
    reg [10:0] line_pixels;
    reg [10:0] active_rows;
    reg [19:0] frame_cycles;

    wire hs_rise = inputs_primed && hs_in && !hs_previous;
    wire vs_rise = inputs_primed && vs_in && !vs_previous;
    // Saturated counters keep missing edges from eventually wrapping to a
    // seemingly supported geometry. Timeouts also invalidate a vanished sync.
    wire h_fault = hs_seen && (hs_rise ? h_cycles != H_LAST : h_cycles >= H_LAST);
    wire frame_timeout = frame_cycles >= FRAME_LAST && !vs_rise;
    wire row_fault = hs_rise && line_pixels != 0 && line_pixels != H_ACTIVE;
    wire de_fault = de_in && (hs_in || vs_in || active_region_done ||
                    line_pixels >= H_ACTIVE || active_rows >= V_ACTIVE ||
                    (!de_previous && line_pixels != 0));
    wire interval_fault = h_fault || frame_timeout || row_fault || de_fault;
    wire [11:0] closing_lines = {1'b0, v_lines} + (hs_rise ? 12'd1 : 12'd0);
    wire closing_good = frame_started && !frame_bad && !interval_fault &&
                        hs_period_seen && active_rows == V_ACTIVE &&
                        line_pixels == 0 && closing_lines == {1'b0, V_TOTAL} &&
                        frame_cycles == FRAME_LAST && !de_in;

    always @(posedge pixel_clk or negedge reset_n) begin
        if (!reset_n) begin
            pixel_valid <= 1'b0;
            rgb_out <= 24'd0;
            x <= 11'd0;
            y <= 11'd0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            frame_good <= 1'b0;
            mode_locked <= 1'b0;
            mode_error <= 1'b0;
            active_width <= 11'd0;
            active_height <= 11'd0;
            h_total <= 11'd0;
            v_total <= 11'd0;
            hs_previous <= 1'b0;
            vs_previous <= 1'b0;
            de_previous <= 1'b0;
            inputs_primed <= 1'b0;
            hs_seen <= 1'b0;
            hs_period_seen <= 1'b0;
            frame_open <= 1'b0;
            frame_started <= 1'b0;
            frame_bad <= 1'b0;
            active_region_done <= 1'b0;
            h_cycles <= 11'd0;
            v_lines <= 11'd0;
            line_pixels <= 11'd0;
            active_rows <= 11'd0;
            frame_cycles <= 20'd0;
        end else begin
            pixel_valid <= 1'b0;
            rgb_out <= 24'd0;
            x <= 11'd0;
            y <= 11'd0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            frame_good <= 1'b0;
            hs_previous <= hs_in;
            vs_previous <= vs_in;
            de_previous <= de_in;

            if (!enable || !rx_ready) begin
                inputs_primed <= 1'b0;
                if (!rx_ready && frame_open)
                    mode_error <= 1'b1;
                mode_locked <= 1'b0;
                active_width <= 11'd0;
                active_height <= 11'd0;
                h_total <= 11'd0;
                v_total <= 11'd0;
                hs_seen <= 1'b0;
                hs_period_seen <= 1'b0;
                frame_open <= 1'b0;
                frame_started <= 1'b0;
                frame_bad <= 1'b0;
                active_region_done <= 1'b0;
                h_cycles <= 11'd0;
                v_lines <= 11'd0;
                line_pixels <= 11'd0;
                active_rows <= 11'd0;
                frame_cycles <= 20'd0;
            end else begin
                inputs_primed <= 1'b1;
                // Independent positive HS edge-to-edge cycle measurement.
                if (hs_rise) begin
                    hs_seen <= 1'b1;
                    h_cycles <= 11'd0;
                    if (hs_seen) begin
                        h_total <= h_cycles == 11'h7ff ? 11'h7ff : h_cycles + 11'd1;
                        hs_period_seen <= 1'b1;
                    end
                end else if (hs_seen && h_cycles != 11'h7ff) begin
                    h_cycles <= h_cycles + 11'd1;
                end

                if (vs_rise) begin
                    if (frame_open) begin
                        frame_end <= 1'b1;
                        frame_good <= closing_good;
                        mode_locked <= closing_good;
                        active_height <= active_rows;
                        v_total <= closing_lines > 12'd2047 ? 11'h7ff : closing_lines[10:0];
                        if (!closing_good)
                            mode_error <= 1'b1;
                    end
                    frame_open <= 1'b1;
                    frame_started <= 1'b0;
                    frame_bad <= de_in;
                    active_region_done <= 1'b0;
                    line_pixels <= 11'd0;
                    active_rows <= 11'd0;
                    v_lines <= 11'd0;
                    frame_cycles <= 20'd0;
                    if (de_in) begin
                        mode_error <= 1'b1;
                        mode_locked <= 1'b0;
                    end
                end else if (frame_open) begin
                    if (frame_cycles != 20'hfffff)
                        frame_cycles <= frame_cycles + 20'd1;
                    if (interval_fault) begin
                        frame_bad <= 1'b1;
                        mode_error <= 1'b1;
                        mode_locked <= 1'b0;
                    end

                    // HS follows the active burst in the supported raster.
                    // Rows are finalized here, so DE gaps or a missing row
                    // cannot be joined together into an accepted frame.
                    if (hs_rise) begin
                        if (v_lines != 11'h7ff)
                            v_lines <= v_lines + 11'd1;
                        line_pixels <= 11'd0;
                        if (line_pixels != 0) begin
                            active_width <= line_pixels;
                            if (active_rows != 11'h7ff)
                                active_rows <= active_rows + 11'd1;
                        end else if (frame_started) begin
                            active_region_done <= 1'b1;
                        end
                    end else if (de_in) begin
                        if (line_pixels != 11'h7ff)
                            line_pixels <= line_pixels + 11'd1;
                        if (!frame_bad && !interval_fault) begin
                            pixel_valid <= 1'b1;
                            rgb_out <= rgb_in;
                            x <= line_pixels;
                            y <= active_rows;
                            if (!frame_started) begin
                                frame_start <= 1'b1;
                                frame_started <= 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
