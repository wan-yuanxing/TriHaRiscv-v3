`timescale 1ns/1ps
`default_nettype none
// Raw pixel-domain diagnostics. Inputs must already be coherent registered
// samples in pixel_clk; no synchronizers, HS-derived line units, or mode rules
// are applied here. VS high is the rise-to-fall pixel-clock difference and VS
// period is the rise-to-rise difference. Each retains its last completed value.
//
// The first enabled sample primes edge history without inventing transitions.
// An initial high VS therefore cannot complete a width until a rise is seen.
// Counters accumulate observed edges after priming. Reset clears immediately;
// a disabled clock clears all metrics/counters and invalidates partial samples.
// Re-enabling starts a new observation epoch. All arithmetic is modulo 2^32.
module video_rx_probe(
    input wire pixel_clk,reset_n,enable,hs_in,vs_in,de_in,
    output reg [31:0] vs_high_clocks,vs_period_clocks,
    output reg [31:0] hs_rises,hs_falls,vs_rises,vs_falls,de_rises
);
    reg hs_d,vs_d,de_d,primed,vs_seen;
    reg [31:0] tick,vs_tick;
    wire hs_rise=primed && hs_in && !hs_d;
    wire hs_fall=primed && !hs_in && hs_d;
    wire vs_rise=primed && vs_in && !vs_d;
    wire vs_fall=primed && !vs_in && vs_d;
    wire de_rise=primed && de_in && !de_d;

    always @(posedge pixel_clk or negedge reset_n) begin
        if(!reset_n) begin
            hs_d<=0;vs_d<=0;de_d<=0;primed<=0;vs_seen<=0;
            tick<=0;vs_tick<=0;
            vs_high_clocks<=0;vs_period_clocks<=0;
            hs_rises<=0;hs_falls<=0;vs_rises<=0;vs_falls<=0;de_rises<=0;
        end else if(!enable) begin
            hs_d<=0;vs_d<=0;de_d<=0;primed<=0;vs_seen<=0;
            tick<=0;vs_tick<=0;
            vs_high_clocks<=0;vs_period_clocks<=0;
            hs_rises<=0;hs_falls<=0;vs_rises<=0;vs_falls<=0;de_rises<=0;
        end else begin
            hs_d<=hs_in;vs_d<=vs_in;de_d<=de_in;primed<=1;
            tick<=tick+1'b1;
            if(hs_rise) hs_rises<=hs_rises+1'b1;
            if(hs_fall) hs_falls<=hs_falls+1'b1;
            if(de_rise) de_rises<=de_rises+1'b1;
            if(vs_rise) begin
                vs_rises<=vs_rises+1'b1;
                if(vs_seen) vs_period_clocks<=tick-vs_tick;
                vs_tick<=tick;vs_seen<=1;
            end
            if(vs_fall) begin
                vs_falls<=vs_falls+1'b1;
                if(vs_seen) vs_high_clocks<=tick-vs_tick;
            end
        end
    end
endmodule
`default_nettype wire
