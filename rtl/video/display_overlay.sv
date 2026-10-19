`timescale 1ns/1ps
`default_nettype none
// F3b pixel component, not an atomic display-record receiver or DDR prefetcher.
// Caller supplies a committed, same-clock record. Thirteen register stages:
// input edge n -> request after n+8 -> cache samples n+9 and registers response
// -> consume response n+10 -> RGB/metadata/flags after n+12. No backpressure.
module display_overlay #(
    parameter integer LINE_WIDTH=2, POINT_RADIUS=2,
    parameter [23:0] BOX_COLOR=24'h00ff00, PRIMARY_COLOR=24'hff0000,
                    POINT_COLOR=24'hffff00
)(
    input wire clk, rst,
    input wire [31:0] pixel_frame_id,
    input wire [10:0] pixel_x, pixel_y,
    input wire [23:0] pixel_rgb,
    input wire pixel_de, pixel_hs, pixel_vs, pixel_sof,
    input wire [1:0] mode,
    input wire result_valid, result_has_face,
    input wire [31:0] result_frame_id,
    input wire primary_valid,
    input wire [3:0] primary_index,
    input wire points_enable,
    input wire [15:0] box_valid,
    input wire [255:0] box_x0, box_y0, box_x1, box_y1,
    input wire [79:0] point_valid,
    input wire [1279:0] point_x, point_y,
    input wire avatar_enable,
    input wire signed [15:0] avatar_x0, avatar_y0, avatar_x1, avatar_y1,
    output wire avatar_req_valid,
    output wire [17:0] avatar_req_addr,
    input wire sample_valid, sample_error,
    input wire [31:0] sample_rgba,
    output reg [23:0] out_rgb,
    output reg [10:0] out_x, out_y,
    output reg [31:0] out_frame_id,
    output reg out_de, out_hs, out_vs, out_sof,
    output reg out_box, out_point, out_avatar, out_fault, overlay_fault
);
    generate if (LINE_WIDTH<1 || LINE_WIDTH>800 || POINT_RADIUS<0 || POINT_RADIUS>31) begin: invalid_parameters
        initial $fatal(1,"display_overlay requires line width 1..800, point radius 0..31");
    end endgenerate

    wire qualified = pixel_de && pixel_x<800 && pixel_y<600 &&
                     result_valid && result_has_face && result_frame_id==pixel_frame_id;
    wire [15:0] texel_index;
    avatar_sample_map u_map (
        .clk(clk),.rst(rst),.enable(qualified && mode==2 && avatar_enable),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.target_x0(avatar_x0),.target_y0(avatar_y0),
        .target_x1(avatar_x1),.target_y1(avatar_y1),
        .request_valid(avatar_req_valid),.texel_index(texel_index));
    assign avatar_req_addr = {texel_index,2'b00};

    // Rectangles are clipped before the inner border is drawn. A degenerate
    // rectangle suppresses all its points. Primary border beats ordinary border;
    // enabled points beat both borders. Lane i corresponds to box/point i.
    integer i,j,left,top,right,bottom,point_px,point_py;
    reg border_hit, primary_hit, point_hit;
    reg [23:0] selected_rgb;
    reg selected_box, selected_point;
    always @* begin
        border_hit=0; primary_hit=0; point_hit=0;
        left=0; top=0; right=0; bottom=0; point_px=0; point_py=0;
        for (i=0;i<16;i=i+1) begin
            left=$signed(box_x0[i*16+:16]); top=$signed(box_y0[i*16+:16]);
            right=$signed(box_x1[i*16+:16]); bottom=$signed(box_y1[i*16+:16]);
            if (left<0) left=0;
            if (top<0) top=0;
            if (right>800) right=800;
            if (bottom>600) bottom=600;
            if (box_valid[i] && left<right && top<bottom) begin
                if ($signed({1'b0,pixel_x})>=left && $signed({1'b0,pixel_x})<right &&
                    $signed({1'b0,pixel_y})>=top && $signed({1'b0,pixel_y})<bottom &&
                    ($signed({1'b0,pixel_x})-left<LINE_WIDTH ||
                     right-1-$signed({1'b0,pixel_x})<LINE_WIDTH ||
                     $signed({1'b0,pixel_y})-top<LINE_WIDTH ||
                     bottom-1-$signed({1'b0,pixel_y})<LINE_WIDTH)) begin
                    border_hit=1;
                    if (primary_valid && primary_index==i) primary_hit=1;
                end
                for (j=0;j<5;j=j+1) begin
                    point_px=$signed(point_x[(i*5+j)*16+:16]);
                    point_py=$signed(point_y[(i*5+j)*16+:16]);
                    if (points_enable && point_valid[i*5+j] &&
                        $signed({1'b0,pixel_x})>=point_px-POINT_RADIUS &&
                        $signed({1'b0,pixel_x})<=point_px+POINT_RADIUS &&
                        $signed({1'b0,pixel_y})>=point_py-POINT_RADIUS &&
                        $signed({1'b0,pixel_y})<=point_py+POINT_RADIUS) point_hit=1;
                end
            end
        end
        selected_rgb=pixel_rgb; selected_box=0; selected_point=0;
        if (qualified && mode==1) begin
            if (point_hit) begin selected_rgb=POINT_COLOR; selected_point=1; end
            else if (border_hit) begin
                selected_rgb=primary_hit ? PRIMARY_COLOR : BOX_COLOR;
                selected_box=1;
            end
        end
    end

    // Stage0..9: preserve every pixel, including blanking. The cache response
    // registered from request stage8 is available with context stage9.
    reg [83:0] context_pipe [0:9];
    reg hit_d;
    integer delay_index;
    always @(posedge clk) begin
        if (rst) begin
            for (delay_index=0;delay_index<10;delay_index=delay_index+1) context_pipe[delay_index]<=0;
            hit_d<=0;
        end else begin
            context_pipe[0]<={pixel_frame_id,pixel_x,pixel_y,pixel_de,pixel_hs,pixel_vs,pixel_sof,
                             selected_rgb,selected_box,selected_point};
            for (delay_index=1;delay_index<10;delay_index=delay_index+1)
                context_pipe[delay_index]<=context_pipe[delay_index-1];
            hit_d<=avatar_req_valid;
        end
    end
    wire [57:0] metadata = context_pipe[9][83:26];
    wire [23:0] background = context_pipe[9][25:2];
    wire use_avatar = hit_d && sample_valid && !sample_error;
    wire pixel_fault = hit_d && (!sample_valid || sample_error);
    wire [7:0] alpha = use_avatar ? sample_rgba[7:0] : 8'd0;
    // Cache data has no meaning outside a successful response slot. Mask both
    // operands: in 4-state simulation an unknown foreground multiplied by zero
    // would otherwise corrupt RAW/BOX and the required original-pixel fallback.
    wire [23:0] foreground = use_avatar ? sample_rgba[31:8] : 24'd0;

    function automatic [15:0] weighted(input [7:0] foreground, back, a);
        reg [15:0] fg_product, bg_product;
        begin
            fg_product=a*foreground;
            bg_product=(8'd255-a)*back;
            weighted=fg_product+bg_product+16'd127;
        end
    endfunction
    reg [15:0] sum_r, sum_g, sum_b, round_r, round_g, round_b;
    reg [57:0] metadata_a, metadata_b;
    reg [3:0] flags_a, flags_b;
    always @(posedge clk) begin
        if (rst) begin
            sum_r<=0; sum_g<=0; sum_b<=0; round_r<=0; round_g<=0; round_b<=0;
            metadata_a<=0; metadata_b<=0; flags_a<=0; flags_b<=0;
            out_rgb<=0; out_x<=0; out_y<=0; out_frame_id<=0;
            out_de<=0; out_hs<=0; out_vs<=0; out_sof<=0;
            out_box<=0; out_point<=0; out_avatar<=0; out_fault<=0; overlay_fault<=0;
        end else begin
            // Stage10. With alpha zero this also gives exact background recovery.
            sum_r<=weighted(foreground[23:16],background[23:16],alpha);
            sum_g<=weighted(foreground[15:8],background[15:8],alpha);
            sum_b<=weighted(foreground[7:0],background[7:0],alpha);
            metadata_a<=metadata;
            flags_a<={context_pipe[9][1:0],use_avatar,pixel_fault};
            // Stage11. For 0<=s<=65152, floor(s/255)=(s+1+(s>>8))>>8.
            round_r<=sum_r+16'd1+{8'd0,sum_r[15:8]};
            round_g<=sum_g+16'd1+{8'd0,sum_g[15:8]};
            round_b<=sum_b+16'd1+{8'd0,sum_b[15:8]};
            metadata_b<=metadata_a; flags_b<=flags_a;
            // Stage12: all flags and identity describe this exact output pixel.
            out_rgb<={round_r[15:8],round_g[15:8],round_b[15:8]};
            {out_frame_id,out_x,out_y,out_de,out_hs,out_vs,out_sof}<=metadata_b;
            {out_box,out_point,out_avatar,out_fault}<=flags_b;
            overlay_fault<=overlay_fault || flags_b[0];
        end
    end
endmodule
`default_nettype wire
