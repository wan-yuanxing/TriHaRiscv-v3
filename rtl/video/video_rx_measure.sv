`timescale 1ns/1ps
`default_nettype none
// Pixel-domain measurements plus independent DMT09h edge/geometry checks.
// VS may transition at the active origin or the HS boundary. Units are clocks/lines;
// this block cannot measure its own clock frequency. Inputs are synchronous.
module video_rx_measure(
    input wire pixel_clk,reset_n,enable,hs_in,vs_in,de_in,
    output reg timing_locked,mode_error,
    output reg [15:0] h_active,v_active,h_total,v_total,
    output reg [15:0] h_sync,v_sync,h_front,h_back,v_front,v_back,
    output reg [31:0] good_frames,bad_frames
);
    reg hs_d,vs_d,de_d,primed;
    reg [31:0] tick,hs_tick,hs_fall_tick,de_tick,de_fall_tick;
    reg [31:0] line_index,vs_line,vs_fall_line,last_de_line,vs_tick;
    reg hs_seen,hs_fall_seen,de_seen,de_fall_seen,vs_seen,vs_fall_seen;
    reg de_since_hs,first_de;
    reg [15:0] active_lines;
    reg open_interval,interval_bad;
    wire hs_rise=primed && hs_in && !hs_d;
    wire hs_fall=primed && !hs_in && hs_d;
    wire vs_rise=primed && vs_in && !vs_d;
    wire vs_fall=primed && !vs_in && vs_d;
    wire de_rise=primed && de_in && !de_d;
    wire de_fall=primed && !de_in && de_d;
    wire [31:0] line_now=line_index+(hs_rise?32'd1:32'd0);
    wire edge_fault=(de_in&&(hs_in||vs_in)) ||
        (hs_seen&&(hs_rise?tick-hs_tick!=1056:tick-hs_tick>=1056)) ||
        (hs_fall&&hs_seen&&tick-hs_tick!=128) ||
        (hs_rise&&de_since_hs&&tick-de_fall_tick!=40) ||
        (de_rise&&hs_fall_seen&&tick-hs_fall_tick!=88) ||
        (de_fall&&de_seen&&tick-de_tick!=800) ||
        (vs_fall&&vs_seen&&(line_now-vs_line!=4||tick-vs_tick!=4224)) ||
        (de_rise&&first_de&&vs_fall_seen&&line_now-vs_fall_line!=23) ||
        (vs_seen&&!vs_rise&&tick-vs_tick>=663168);
    wire closing_good=!interval_bad && !edge_fault && tick-vs_tick==663168 &&
        line_now-vs_line==628 && active_lines==600 && v_sync==4 && v_back==23 &&
        line_now-last_de_line-1==1 && h_total==1056 && h_active==800 &&
        h_sync==128 && h_front==40 && h_back==88 && !de_in;
    always @(posedge pixel_clk or negedge reset_n) begin
        if(!reset_n) begin
            hs_d<=0;vs_d<=0;de_d<=0;primed<=0;tick<=0;line_index<=0;
            hs_tick<=0;hs_fall_tick<=0;de_tick<=0;de_fall_tick<=0;
            vs_line<=0;vs_fall_line<=0;last_de_line<=0;vs_tick<=0;
            hs_seen<=0;hs_fall_seen<=0;de_seen<=0;de_fall_seen<=0;
            vs_seen<=0;vs_fall_seen<=0;de_since_hs<=0;first_de<=1;
            active_lines<=0;open_interval<=0;interval_bad<=0;
            timing_locked<=0;mode_error<=0;good_frames<=0;bad_frames<=0;
            h_active<=0;v_active<=0;h_total<=0;v_total<=0;
            h_sync<=0;v_sync<=0;h_front<=0;h_back<=0;v_front<=0;v_back<=0;
        end else if(!enable) begin
            hs_d<=hs_in;vs_d<=vs_in;de_d<=de_in;primed<=0;
            hs_seen<=0;hs_fall_seen<=0;de_seen<=0;de_fall_seen<=0;
            vs_seen<=0;vs_fall_seen<=0;de_since_hs<=0;first_de<=1;
            active_lines<=0;open_interval<=0;interval_bad<=0;
            timing_locked<=0;
            h_active<=0;v_active<=0;h_total<=0;v_total<=0;
            h_sync<=0;v_sync<=0;h_front<=0;h_back<=0;v_front<=0;v_back<=0;
            if(open_interval) mode_error<=1;
        end else begin
            primed<=1;hs_d<=hs_in;vs_d<=vs_in;de_d<=de_in;tick<=tick+1'b1;
            if(hs_rise) begin
                if(hs_seen) h_total<=tick-hs_tick;
                if(de_since_hs && de_fall_seen) h_front<=tick-de_fall_tick;
                hs_seen<=1;hs_tick<=tick;line_index<=line_index+1'b1;de_since_hs<=0;
            end
            if(hs_fall) begin
                if(hs_seen) h_sync<=tick-hs_tick;
                hs_fall_tick<=tick;hs_fall_seen<=1;
            end
            if(de_rise) begin
                if(hs_fall_seen) h_back<=tick-hs_fall_tick;
                de_tick<=tick;de_seen<=1;
                if(active_lines!=16'hffff) active_lines<=active_lines+1'b1;
                if(first_de && vs_fall_seen) begin
                    v_back<=line_now-vs_fall_line;first_de<=0;
                end
            end
            if(de_fall) begin
                if(de_seen) h_active<=tick-de_tick;
                de_fall_tick<=tick;de_fall_seen<=1;de_since_hs<=1;last_de_line<=line_now;
            end
            if(vs_fall) begin
                if(vs_seen) v_sync<=line_now-vs_line;
                vs_fall_line<=line_now;vs_fall_seen<=1;
            end
            if(vs_rise) begin
                if(vs_seen) begin
                    v_total<=line_now-vs_line;
                    v_active<=active_lines;
                    if(de_fall_seen) v_front<=line_now-last_de_line-1'b1;
                end
                vs_seen<=1;vs_line<=line_now;vs_tick<=tick;active_lines<=0;first_de<=1;
                if(open_interval) begin
                    timing_locked<=closing_good;
                    if(closing_good) good_frames<=good_frames+1'b1;
                    else begin bad_frames<=bad_frames+1'b1;mode_error<=1;end
                end
                open_interval<=1;interval_bad<=edge_fault;
            end else if(open_interval) begin
                if(edge_fault) begin interval_bad<=1;timing_locked<=0;mode_error<=1;end
            end
        end
    end
endmodule
`default_nettype wire
