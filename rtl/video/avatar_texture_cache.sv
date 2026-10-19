`timescale 1ns/1ps
`default_nettype none
// One RGBA material, loaded once and immutable until a coordinated reset.
// No replacement/invalidation while pixel references may exist. A future DDR
// fetcher or CPU producer feeds this stream; this module performs no DDR DMA.
module avatar_texture_cache #(parameter integer TEXELS=65536)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,
    input wire load_valid,output wire load_ready,
    input wire [31:0] load_asset_id,load_generation,
    input wire s_valid,s_last,input wire [31:0] s_rgba,output wire s_ready,
    output reg asset_ready,load_fault,
    output reg [31:0] asset_id,asset_generation,words_written,
    output reg pixel_asset_ready,
    input wire pixel_req_valid,input wire [17:0] pixel_req_addr,
    input wire [31:0] pixel_req_asset_id,pixel_req_generation,
    output reg sample_valid,sample_error,output reg [31:0] sample_rgba
);
    generate if(TEXELS<1||TEXELS>65536)begin:invalid_parameters
        initial $fatal(1,"avatar_texture_cache requires 1..65536 texels");
    end endgenerate
    reg [31:0] texture [0:TEXELS-1];
    reg loading;
    reg [15:0] write_index;
    reg core_run=0,pixel_run=0;
    always @(posedge core_clk)core_run<=core_reset_n;
    always @(posedge pixel_clk)pixel_run<=pixel_reset_n;
    assign load_ready=core_run&&core_reset_n&&!loading&&!asset_ready&&!load_fault;
    assign s_ready=core_run&&core_reset_n&&loading&&!load_fault;
    wire last_matches=s_last===(words_written==TEXELS-1);
    wire known_rgba=(^s_rgba!==1'bx);
    wire write_word=core_run&&s_valid&&s_ready&&last_matches&&known_rgba;
    // Neither RAM contents nor the synchronous RAM read register is reset.
    always @(posedge core_clk)if(write_word)texture[write_index]<=s_rgba;
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin
            loading<=0;write_index<=0;asset_ready<=0;load_fault<=0;
            asset_id<=0;asset_generation<=0;words_written<=0;
        end else begin
            if(load_valid&&load_ready)begin
                if((^load_asset_id===1'bx)||(^load_generation===1'bx))load_fault<=1;
                else begin loading<=1;asset_id<=load_asset_id;asset_generation<=load_generation;end
            end
            if(s_valid&&s_ready)begin
                if(!last_matches||!known_rgba)begin loading<=0;load_fault<=1;end
                else begin
                    words_written<=words_written+1'b1;
                    if(words_written==TEXELS-1)begin loading<=0;asset_ready<=1;end
                    else write_index<=write_index+1'b1;
                end
            end
        end
    end
    (* ASYNC_REG="TRUE" *) reg ready_meta,ready_sync;
    reg [31:0] pixel_asset_id,pixel_generation;
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin ready_meta<=0;ready_sync<=0;end
        else begin ready_meta<=asset_ready;ready_sync<=ready_meta;end
    end
    // Identity was latched before loading began, and the complete RAM became
    // immutable before readiness crossed. FDC binds both stable identity buses.
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin pixel_asset_ready<=0;pixel_asset_id<=0;pixel_generation<=0;end
        else if(ready_sync&&!pixel_asset_ready)begin
            pixel_asset_ready<=1;pixel_asset_id<=asset_id;pixel_generation<=asset_generation;
        end
    end
    wire address_ok=(^pixel_req_addr!==1'bx)&&pixel_req_addr[1:0]===2'b00&&
                    {1'b0,pixel_req_addr[17:2]}<TEXELS;
    wire request_ok=pixel_asset_ready&&address_ok&&pixel_req_asset_id===pixel_asset_id&&
                    pixel_req_generation===pixel_generation;
    always @(posedge pixel_clk)begin
        if(pixel_run&&pixel_req_valid&&request_ok)sample_rgba<=texture[pixel_req_addr[17:2]];
    end
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin sample_valid<=0;sample_error<=0;end
        else begin sample_valid<=pixel_req_valid;
            sample_error<=pixel_req_valid&&!request_ok;end
    end
endmodule
`default_nettype wire
