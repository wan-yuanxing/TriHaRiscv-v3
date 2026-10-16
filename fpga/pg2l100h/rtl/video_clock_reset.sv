`timescale 1ns/1ps
`default_nettype none
module video_clock_reset #(
    parameter integer STARTUP_CYCLES = 10000
)(
    input wire sys_clk,
    input wire reset_n,
    output wire pixel_clk,
    output wire cfg_clk,
    output wire locked,
    output wire pixel_reset_n,
    output wire cfg_reset_n,
    output wire tx_reset_n
);
    video_pll pll (.clkin1(sys_clk), .clkout0(pixel_clk),
                   .clkout1(cfg_clk), .lock(locked));
    wire async_ready = reset_n && locked;
    (* syn_preserve = 1 *) reg [1:0] pixel_release, cfg_release;
    always @(posedge pixel_clk or negedge async_ready) begin
        if(!async_ready) pixel_release <= 2'b00;
        else pixel_release <= {pixel_release[0],1'b1};
    end
    always @(posedge cfg_clk or negedge async_ready) begin
        if(!async_ready) cfg_release <= 2'b00;
        else cfg_release <= {cfg_release[0],1'b1};
    end
    assign pixel_reset_n = async_ready && pixel_release[1];
    assign cfg_reset_n = async_ready && cfg_release[1];
    reg tx_release;
    assign tx_reset_n = async_ready && tx_release;
    localparam integer COUNTER_WIDTH = STARTUP_CYCLES > 1 ? $clog2(STARTUP_CYCLES) : 1;
    reg [COUNTER_WIDTH-1:0] startup_count;
    always @(posedge cfg_clk or negedge async_ready) begin
        if(!async_ready) begin
            startup_count <= 0;
            tx_release <= 0;
        end else if(!cfg_reset_n) begin
            startup_count <= 0;
            tx_release <= 0;
        end else if(!tx_release) begin
            if(startup_count == STARTUP_CYCLES-1) tx_release <= 1;
            else startup_count <= startup_count + 1'b1;
        end
    end
endmodule
`default_nettype wire
