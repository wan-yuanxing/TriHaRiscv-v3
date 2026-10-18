`timescale 1ns/1ps
`default_nettype none
// KEY0 resets local datapaths. Only PLL startup/loss restarts the HDMI PHYs
// and their EDID/I2C initialization, so recapture does not disturb the source.
module video_preview_clock_reset #(
    parameter integer STARTUP_CYCLES=10000
)(
    input wire sys_clk,reset_n,
    output wire pixel_clk,cfg_clk,locked,
    output wire pixel_reset_n,cfg_reset_n,tx_reset_n
);
    video_pll pll(.clkin1(sys_clk),.clkout0(pixel_clk),.clkout1(cfg_clk),.lock(locked));
    wire async_ready=reset_n&&locked;
    (* syn_preserve=1 *) reg [1:0] pixel_release,cfg_release;
    always @(posedge pixel_clk or negedge async_ready)
        if(!async_ready)pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    always @(posedge cfg_clk or negedge async_ready)
        if(!async_ready)cfg_release<=0;
        else cfg_release<={cfg_release[0],1'b1};
    assign pixel_reset_n=async_ready&&pixel_release[1];
    assign cfg_reset_n=async_ready&&cfg_release[1];

    // This release chain and counter deliberately have no KEY0 dependency.
    // PLL lock starts low after FPGA configuration, as in the vendor target.
    (* syn_preserve=1 *) reg [1:0] link_release;
    always @(posedge cfg_clk or negedge locked)
        if(!locked)link_release<=0;
        else link_release<={link_release[0],1'b1};
    localparam integer CW=STARTUP_CYCLES>1?$clog2(STARTUP_CYCLES):1;
    reg [CW-1:0] startup_count;
    reg tx_release;
    always @(posedge cfg_clk or negedge locked)begin
        if(!locked)begin startup_count<=0;tx_release<=0;end
        else if(!link_release[1])begin startup_count<=0;tx_release<=0;end
        else if(!tx_release)begin
            if(startup_count==STARTUP_CYCLES-1)tx_release<=1;
            else startup_count<=startup_count+1'b1;
        end
    end
    assign tx_reset_n=locked&&tx_release;
endmodule
`default_nettype wire
