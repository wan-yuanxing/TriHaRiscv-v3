`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"

// Fixed 800x600 raster. The origin is the first active pixel; blanking follows
// the active area. reset_n asserts asynchronously and must release in this
// clock domain through an external reset synchronizer.
module video_timing (
    input  wire        pixel_clk,
    input  wire        reset_n,
    output wire [10:0] x,
    output wire [10:0] y,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire        frame_start
);
    localparam integer H_SYNC_START = `VIDEO_H_ACTIVE + `VIDEO_H_FRONT;
    localparam integer H_SYNC_END = H_SYNC_START + `VIDEO_H_SYNC;
    localparam integer V_SYNC_START = `VIDEO_V_ACTIVE + `VIDEO_V_FRONT;
    localparam integer V_SYNC_END = V_SYNC_START + `VIDEO_V_SYNC;

    reg [10:0] h_count;
    reg [10:0] v_count;

    always @(posedge pixel_clk or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 11'd0;
            v_count <= 11'd0;
        end else if (h_count == `VIDEO_H_TOTAL - 1) begin
            h_count <= 11'd0;
            if (v_count == `VIDEO_V_TOTAL - 1)
                v_count <= 11'd0;
            else
                v_count <= v_count + 11'd1;
        end else begin
            h_count <= h_count + 11'd1;
        end
    end

    assign x = h_count;
    assign y = v_count;
    assign hsync = reset_n && h_count >= H_SYNC_START && h_count < H_SYNC_END;
    assign vsync = reset_n && v_count >= V_SYNC_START && v_count < V_SYNC_END;
    assign de = reset_n && h_count < `VIDEO_H_ACTIVE && v_count < `VIDEO_V_ACTIVE;
    assign frame_start = reset_n && h_count == 11'd0 && v_count == 11'd0;
endmodule

`default_nettype wire
