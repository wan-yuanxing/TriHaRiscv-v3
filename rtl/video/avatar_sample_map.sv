`timescale 1ns/1ps
`default_nettype none
// Exact nearest-neighbor address in a 256x256 texture, one pixel every clock.
// A pixel sampled at edge n produces a request after edge n+8 (nine stages).
// Coordinates are raw-image coordinates; only output coverage is clipped.
module avatar_sample_map (
    input wire clk, rst, enable,
    input wire [10:0] pixel_x, pixel_y,
    input wire signed [15:0] target_x0, target_y0, target_x1, target_y1,
    output wire request_valid,
    output wire [15:0] texel_index
);
    wire signed [16:0] px = {6'd0,pixel_x};
    wire signed [16:0] py = {6'd0,pixel_y};
    wire signed [16:0] x0 = {target_x0[15],target_x0};
    wire signed [16:0] y0 = {target_y0[15],target_y0};
    wire signed [16:0] x1 = {target_x1[15],target_x1};
    wire signed [16:0] y1 = {target_y1[15],target_y1};
    wire covered = enable && pixel_x<800 && pixel_y<600 &&
                   x0<x1 && y0<y1 && px>=x0 && px<x1 && py>=y0 && py<y1;
    reg [15:0] remainder_x [0:8], remainder_y [0:8];
    reg [15:0] denominator_x [0:8], denominator_y [0:8];
    reg [7:0] fraction_x [0:8], fraction_y [0:8];
    reg [8:0] hit;

    always @(posedge clk) begin
        if (rst) begin
            remainder_x[0]<=0; remainder_y[0]<=0;
            denominator_x[0]<=1; denominator_y[0]<=1;
            fraction_x[0]<=0; fraction_y[0]<=0; hit[0]<=0;
        end else begin
            // Covered implies 0<=distance<denominator<=65535. Signed 17bit
            // subtraction retains the full difference between signed endpoints.
            remainder_x[0]<=covered ? px-x0 : 17'd0;
            remainder_y[0]<=covered ? py-y0 : 17'd0;
            denominator_x[0]<=covered ? x1-x0 : 17'd1;
            denominator_y[0]<=covered ? y1-y0 : 17'd1;
            fraction_x[0]<=0; fraction_y[0]<=0; hit[0]<=covered;
        end
    end
    genvar stage;
    generate for (stage=0;stage<8;stage=stage+1) begin: fractional_divide
        wire [16:0] twice_x = {remainder_x[stage],1'b0};
        wire [16:0] twice_y = {remainder_y[stage],1'b0};
        wire take_x = twice_x >= {1'b0,denominator_x[stage]};
        wire take_y = twice_y >= {1'b0,denominator_y[stage]};
        always @(posedge clk) begin
            if (rst) begin
                remainder_x[stage+1]<=0; remainder_y[stage+1]<=0;
                denominator_x[stage+1]<=1; denominator_y[stage+1]<=1;
                fraction_x[stage+1]<=0; fraction_y[stage+1]<=0;
                hit[stage+1]<=0;
            end else begin
                remainder_x[stage+1]<=take_x ? twice_x-{1'b0,denominator_x[stage]} : twice_x;
                remainder_y[stage+1]<=take_y ? twice_y-{1'b0,denominator_y[stage]} : twice_y;
                denominator_x[stage+1]<=denominator_x[stage];
                denominator_y[stage+1]<=denominator_y[stage];
                fraction_x[stage+1]<={fraction_x[stage][6:0],take_x};
                fraction_y[stage+1]<={fraction_y[stage][6:0],take_y};
                hit[stage+1]<=hit[stage];
            end
        end
    end endgenerate
    assign request_valid = !rst && hit[8];
    assign texel_index = {fraction_y[8],fraction_x[8]};
endmodule
`default_nettype wire
