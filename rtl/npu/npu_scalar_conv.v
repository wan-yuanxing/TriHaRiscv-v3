`timescale 1ns/1ps
// Functional single-lane NCHW Dense/DW convolution. Cache lifetime is one START.
// Completion requires every output write response; reset must drain/reset the
// complete memory path. This module implements no independent in-flight abort.
module npu_scalar_conv (
    input wire clk_i, rst_ni, start_i,
    input wire [31:0] cfg_input_base_i, cfg_weight_base_i, cfg_bias_base_i,
    input wire [31:0] cfg_requant_base_i, cfg_output_base_i,
    input wire [15:0] cfg_input_width_i, cfg_input_height_i,
    input wire [15:0] cfg_output_width_i, cfg_output_height_i,
    input wire [15:0] cfg_input_channels_i, cfg_output_channels_i,
    input wire [1:0] cfg_kernel_i, cfg_stride_i, cfg_padding_i,
    input wire cfg_depthwise_i, cfg_input_signed_i,
    input wire [1:0] cfg_output_format_i,
    output reg busy_o, done_o, error_o,
    output reg [7:0] error_code_o,
    output reg [31:0] total_cycles_o, compute_cycles_o, dma_wait_cycles_o,
    output wire mem_req_valid_o, mem_req_write_o,
    output wire [31:0] mem_req_addr_o,
    output wire [127:0] mem_req_wdata_o,
    output wire [15:0] mem_req_wstrb_o,
    input wire mem_req_ready_i, mem_rsp_valid_i,
    input wire [127:0] mem_rsp_rdata_i,
    input wire mem_rsp_error_i
);
    localparam [4:0] IDLE=0, VALIDATE=1, CHANNEL=2, BIAS_DONE=3,
        REQUANT_DONE=4, PIXEL=5, MAC_PREP=6, INPUT_DONE=7, WEIGHT_DONE=8,
        PRODUCT=9, ROUND=10, WRITE_REQ=11, WRITE_WAIT=12,
        READ_LOOKUP=13, READ_REQ=14, READ_WAIT=15,
        GEOMETRY=16, SIZES_A=17, SIZES_B=18, SIZES_C=19,
        ABS_VALUE=20, RESTORE_SIGN=21, SATURATE=22;
    reg [4:0] state_q, return_q;
    reg [31:0] input_base_q, weight_base_q, bias_base_q, requant_base_q, output_base_q;
    reg [15:0] iw_q, ih_q, ow_q, oh_q, ci_count_q, co_count_q;
    reg [1:0] kernel_q, stride_q, padding_q, format_q;
    reg dw_q, signed_q;
    reg [15:0] co_q, oy_q, ox_q, ci_q;
    reg [1:0] ky_q, kx_q;
    reg [31:0] k_index_q, output_index_q;
    reg signed [31:0] bias_q, accumulator_q, multiplier_q;
    reg [5:0] shift_q;
    reg signed [8:0] input_q;
    reg signed [63:0] product_q, rounded_q;
    reg [63:0] magnitude_q, rounded_magnitude_q;
    reg negative_q;
    reg [15:0] output_q;
    reg [31:0] read_address_q;
    reg [1:0] cache_slot_q;
    reg [2:0] cache_valid_q;
    reg [27:0] cache_tag_q [0:2];
    reg [127:0] cache_data_q [0:2];
    reg [127:0] read_value_q;
    // Geometry is rejected before bounded-width intermediates are computed.
    // Separate clocks avoid a chain of DSP multipliers in START validation.
    reg [16:0] plane_q, output_plane_q;
    reg [22:0] input_bytes_q, output_elements_q;
    reg [23:0] output_bytes_q;
    reg [15:0] weight_bytes_q;
    reg [9:0] k_count_q;
    reg [3:0] kernel_area_q;
    reg [2:0] co_blocks_q;
    wire [63:0] plane_bytes = {47'd0,plane_q};
    wire [63:0] input_bytes = {41'd0,input_bytes_q};
    wire [63:0] k_count = {54'd0,k_count_q};
    wire [63:0] weight_bytes = {48'd0,weight_bytes_q};
    wire [63:0] bias_bytes = {48'd0,co_count_q}*4;
    wire [63:0] requant_bytes = {48'd0,co_count_q}*8;
    wire [63:0] output_bytes = {40'd0,output_bytes_q};
    wire signed [10:0] ix_small =
        (stride_q==2 ? $signed({1'b0,ox_q[8:0],1'b0}) : $signed({2'b0,ox_q[8:0]})) +
        $signed({9'd0,kx_q})-$signed({9'd0,padding_q});
    wire signed [10:0] iy_small =
        (stride_q==2 ? $signed({1'b0,oy_q[8:0],1'b0}) : $signed({2'b0,oy_q[8:0]})) +
        $signed({9'd0,ky_q})-$signed({9'd0,padding_q});
    wire signed [31:0] ix=ix_small, iy=iy_small;
    wire [16:0] row_offset=iy_small[8:0]*iw_q[8:0];
    wire [22:0] channel_offset=(dw_q?co_q[6:0]:ci_q[6:0])*plane_q;
    wire padded = ix<0 || iy<0 || ix>=$signed({16'd0,iw_q}) || iy>=$signed({16'd0,ih_q});
    wire [31:0] input_address = input_base_q+channel_offset+row_offset+{23'd0,ix_small[8:0]};
    wire [31:0] weight_address = weight_base_q+((co_q>>4)*k_count+k_index_q)*16+(co_q&15);
    wire [31:0] output_address = output_base_q+output_index_q*(format_q==3?2:1);
    wire signed [16:0] mac_product = $signed(input_q)*$signed(read_value_q[7:0]);
    wire signed [32:0] mac_sum = $signed({accumulator_q[31],accumulator_q})+
                                $signed({{16{mac_product[16]}},mac_product});

    function span_valid;
        input [31:0] base;
        input [63:0] length;
        begin
            span_valid=base[3:0]==0 && length!=0 && base>=32'h82000000 &&
                ({32'd0,base}+length)<=64'h88000000;
        end
    endfunction
    function overlaps;
        input [31:0] a,b;
        input [63:0] na,nb;
        begin overlaps=({32'd0,a} < {32'd0,b}+nb) && ({32'd0,b} < {32'd0,a}+na); end
    endfunction
    reg bad_config, bad_geometry;
    always @* begin
        bad_geometry = iw_q==0 || ih_q==0 || iw_q>320 || ih_q>320 || ow_q>322 || oh_q>322 ||
            ci_count_q==0 || co_count_q==0 || ci_count_q>64 || co_count_q>64 ||
            (kernel_q!=1 && kernel_q!=3) || (stride_q!=1 && stride_q!=2) || padding_q>1 ||
            (format_q!=1 && format_q!=2 && format_q!=3) || (dw_q && ci_count_q!=co_count_q) ||
            iw_q+2*padding_q<kernel_q || ih_q+2*padding_q<kernel_q ||
            ow_q!=((iw_q+2*padding_q-kernel_q)>>(stride_q==2))+1 ||
            oh_q!=((ih_q+2*padding_q-kernel_q)>>(stride_q==2))+1;
        bad_config = bad_geometry ||
            !span_valid(input_base_q,input_bytes) || !span_valid(weight_base_q,weight_bytes) ||
            !span_valid(bias_base_q,bias_bytes) || !span_valid(requant_base_q,requant_bytes) ||
            !span_valid(output_base_q,output_bytes) ||
            overlaps(output_base_q,input_base_q,output_bytes,input_bytes) ||
            overlaps(output_base_q,weight_base_q,output_bytes,weight_bytes) ||
            overlaps(output_base_q,bias_base_q,output_bytes,bias_bytes) ||
            overlaps(output_base_q,requant_base_q,output_bytes,requant_bytes);
        // synthesis translate_off
        if ((^{iw_q,ih_q,ow_q,oh_q,ci_count_q,co_count_q,kernel_q,stride_q,padding_q,
                format_q,dw_q,signed_q,input_base_q,weight_base_q,bias_base_q,requant_base_q,output_base_q})===1'bx)
            begin bad_config=1;bad_geometry=1;end
        // synthesis translate_on
    end
    function [63:0] rne_magnitude;
        input [63:0] magnitude;
        input [5:0] shift;
        reg [63:0] whole,fraction,half;
        begin
            whole=magnitude;
            if(shift!=0)begin
                whole=magnitude>>shift;
                fraction=magnitude&((64'd1<<shift)-1);
                half=64'd1<<(shift-1);
                if(fraction>half || (fraction==half && whole[0]))whole=whole+1;
            end
            rne_magnitude=whole;
        end
    endfunction
    wire signed [63:0] rounded_value=rounded_q;
    reg [15:0] saturated;
    always @* begin
        case(format_q)
            1: saturated=rounded_value<0?16'd0:rounded_value>255?16'd255:{8'd0,rounded_value[7:0]};
            2: saturated=rounded_value< -127?16'h0081:rounded_value>127?16'h007f:{8'd0,rounded_value[7:0]};
            default: saturated=rounded_value< -32767?16'h8001:rounded_value>32767?16'h7fff:rounded_value[15:0];
        endcase
    end
    assign mem_req_valid_o=busy_o && (state_q==READ_REQ || state_q==WRITE_REQ);
    assign mem_req_write_o=state_q==WRITE_REQ;
    assign mem_req_addr_o=state_q==WRITE_REQ ? {output_address[31:4],4'd0} : {read_address_q[31:4],4'd0};
    assign mem_req_wdata_o={112'd0,output_q} << (output_address[3:0]*8);
    assign mem_req_wstrb_o=(format_q==3?16'd3:16'd1) << output_address[3:0];

    task finish_error;
        input [7:0] code;
        begin busy_o<=0;done_o<=1;error_o<=1;error_code_o<=code;state_q<=IDLE; end
    endtask
    task schedule_read;
        input [31:0] address;
        input [1:0] slot;
        input [4:0] next_state;
        begin read_address_q<=address;cache_slot_q<=slot;return_q<=next_state;state_q<=READ_LOOKUP; end
    endtask
    task advance_k;
        begin
            k_index_q<=k_index_q+1;
            state_q<=MAC_PREP;
            if(kx_q+1<kernel_q)kx_q<=kx_q+1;
            else begin
                kx_q<=0;
                if(ky_q+1<kernel_q)ky_q<=ky_q+1;
                else begin
                    ky_q<=0;
                    if(!dw_q && ci_q+1<ci_count_q)ci_q<=ci_q+1;
                    else state_q<=PRODUCT;
                end
            end
        end
    endtask
    integer c;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            state_q<=IDLE;busy_o<=0;done_o<=0;error_o<=0;error_code_o<=0;
            total_cycles_o<=0;compute_cycles_o<=0;dma_wait_cycles_o<=0;cache_valid_q<=0;
            input_base_q<=0;weight_base_q<=0;bias_base_q<=0;requant_base_q<=0;output_base_q<=0;
            iw_q<=0;ih_q<=0;ow_q<=0;oh_q<=0;ci_count_q<=0;co_count_q<=0;
            kernel_q<=0;stride_q<=0;padding_q<=0;format_q<=0;dw_q<=0;signed_q<=0;
            co_q<=0;oy_q<=0;ox_q<=0;ci_q<=0;ky_q<=0;kx_q<=0;k_index_q<=0;output_index_q<=0;
            bias_q<=0;accumulator_q<=0;multiplier_q<=0;shift_q<=0;input_q<=0;product_q<=0;output_q<=0;
            rounded_q<=0;magnitude_q<=0;rounded_magnitude_q<=0;negative_q<=0;
            read_address_q<=0;cache_slot_q<=0;return_q<=IDLE;read_value_q<=0;
            plane_q<=0;output_plane_q<=0;input_bytes_q<=0;output_elements_q<=0;
            output_bytes_q<=0;weight_bytes_q<=0;k_count_q<=0;kernel_area_q<=0;co_blocks_q<=0;
            for(c=0;c<3;c=c+1)begin cache_tag_q[c]<=0;cache_data_q[c]<=0;end
        end else begin
            done_o<=0;
            if(busy_o)begin
                if(total_cycles_o!=32'hffffffff)total_cycles_o<=total_cycles_o+1;
                if((state_q==READ_REQ || state_q==READ_WAIT || state_q==WRITE_REQ || state_q==WRITE_WAIT) && dma_wait_cycles_o!=32'hffffffff)
                    dma_wait_cycles_o<=dma_wait_cycles_o+1;
            end
            case(state_q)
                IDLE: if(start_i)begin
                    input_base_q<=cfg_input_base_i;weight_base_q<=cfg_weight_base_i;
                    bias_base_q<=cfg_bias_base_i;requant_base_q<=cfg_requant_base_i;output_base_q<=cfg_output_base_i;
                    iw_q<=cfg_input_width_i;ih_q<=cfg_input_height_i;ow_q<=cfg_output_width_i;oh_q<=cfg_output_height_i;
                    ci_count_q<=cfg_input_channels_i;co_count_q<=cfg_output_channels_i;
                    kernel_q<=cfg_kernel_i;stride_q<=cfg_stride_i;padding_q<=cfg_padding_i;
                    format_q<=cfg_output_format_i;dw_q<=cfg_depthwise_i;signed_q<=cfg_input_signed_i;
                    busy_o<=1;error_o<=0;error_code_o<=0;cache_valid_q<=0;
                    total_cycles_o<=0;compute_cycles_o<=0;dma_wait_cycles_o<=0;state_q<=GEOMETRY;
                end
                GEOMETRY: if(bad_geometry)finish_error(1);else state_q<=SIZES_A;
                SIZES_A: begin
                    plane_q<=iw_q[8:0]*ih_q[8:0];output_plane_q<=ow_q[8:0]*oh_q[8:0];
                    kernel_area_q<=kernel_q*kernel_q;co_blocks_q<=({1'b0,co_count_q[6:0]}+8'd15)>>4;
                    state_q<=SIZES_B;
                end
                SIZES_B: begin
                    input_bytes_q<=plane_q*ci_count_q[6:0];
                    output_elements_q<=output_plane_q*co_count_q[6:0];
                    k_count_q<=(dw_q?7'd1:ci_count_q[6:0])*kernel_area_q;
                    state_q<=SIZES_C;
                end
                SIZES_C: begin
                    weight_bytes_q<=(k_count_q*co_blocks_q)<<4;
                    output_bytes_q<=format_q==3?{output_elements_q,1'b0}:{1'b0,output_elements_q};
                    state_q<=VALIDATE;
                end
                VALIDATE: if(bad_config)finish_error(1);else begin co_q<=0;oy_q<=0;ox_q<=0;output_index_q<=0;state_q<=CHANNEL;end
                CHANNEL: schedule_read(bias_base_q+co_q*4,2,BIAS_DONE);
                BIAS_DONE: begin bias_q<=read_value_q[31:0];schedule_read(requant_base_q+co_q*8,2,REQUANT_DONE);end
                REQUANT_DONE: if(read_value_q[63:32]>63)finish_error(3);else begin multiplier_q<=read_value_q[31:0];shift_q<=read_value_q[37:32];state_q<=PIXEL;end
                PIXEL: begin accumulator_q<=bias_q;ci_q<=0;ky_q<=0;kx_q<=0;k_index_q<=0;state_q<=MAC_PREP;end
                MAC_PREP: if(padded)advance_k();else schedule_read(input_address,0,INPUT_DONE);
                INPUT_DONE: begin
                    input_q<=signed_q ? {read_value_q[7],read_value_q[7:0]} : {1'b0,read_value_q[7:0]};
                    schedule_read(weight_address,1,WEIGHT_DONE);
                end
                WEIGHT_DONE: if(mac_sum[32]!=mac_sum[31])finish_error(2);else begin
                    accumulator_q<=mac_sum[31:0];
                    if(compute_cycles_o!=32'hffffffff)compute_cycles_o<=compute_cycles_o+1;
                    advance_k();
                end
                PRODUCT: begin product_q<=$signed(accumulator_q)*$signed(multiplier_q);state_q<=ABS_VALUE;end
                ABS_VALUE: begin
                    magnitude_q<=product_q[63] ? (~product_q+64'd1) : product_q;
                    negative_q<=product_q[63];state_q<=ROUND;
                end
                ROUND: begin rounded_magnitude_q<=rne_magnitude(magnitude_q,shift_q);state_q<=RESTORE_SIGN;end
                RESTORE_SIGN: begin
                    rounded_q<=negative_q ? -$signed(rounded_magnitude_q) : $signed(rounded_magnitude_q);
                    state_q<=SATURATE;
                end
                SATURATE: begin output_q<=saturated;state_q<=WRITE_REQ;end
                WRITE_REQ: if(mem_req_ready_i)state_q<=WRITE_WAIT;
                WRITE_WAIT: if(mem_rsp_valid_i)begin
                    if(mem_rsp_error_i)finish_error(4);
                    else if(ox_q+1==ow_q && oy_q+1==oh_q && co_q+1==co_count_q)begin busy_o<=0;done_o<=1;state_q<=IDLE;end
                    else begin
                        output_index_q<=output_index_q+1;state_q<=PIXEL;
                        if(ox_q+1<ow_q)ox_q<=ox_q+1;
                        else begin ox_q<=0;if(oy_q+1<oh_q)oy_q<=oy_q+1;else begin oy_q<=0;co_q<=co_q+1;state_q<=CHANNEL;end end
                    end
                end
                READ_LOOKUP: if(cache_valid_q[cache_slot_q] && cache_tag_q[cache_slot_q]==read_address_q[31:4])begin
                    read_value_q<=cache_data_q[cache_slot_q]>>(read_address_q[3:0]*8);state_q<=return_q;
                end else state_q<=READ_REQ;
                READ_REQ: if(mem_req_ready_i)state_q<=READ_WAIT;
                READ_WAIT: if(mem_rsp_valid_i)begin
                    if(mem_rsp_error_i)finish_error(4);
                    else begin
                        cache_valid_q[cache_slot_q]<=1;cache_tag_q[cache_slot_q]<=read_address_q[31:4];
                        cache_data_q[cache_slot_q]<=mem_rsp_rdata_i;
                        read_value_q<=mem_rsp_rdata_i>>(read_address_q[3:0]*8);state_q<=return_q;
                    end
                end
                default: finish_error(1);
            endcase
        end
    end
endmodule
