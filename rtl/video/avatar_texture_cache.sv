`timescale 1ns/1ps
`default_nettype none
// One RGBA material, loaded once and immutable until a coordinated reset.
// No replacement/invalidation while pixel references may exist. A future DDR
// fetcher or CPU producer feeds this stream; this module performs no DDR DMA.
module avatar_texture_cache #(parameter integer TEXELS=65536,COMPACT_PRESET=0)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,
    input wire load_valid,output wire load_ready,
    input wire [31:0] load_asset_id,load_generation,
    input wire s_valid,s_last,input wire [31:0] s_rgba,output wire s_ready,
    output reg asset_ready,load_fault,
    output reg [31:0] asset_id,asset_generation,words_written,
    output reg pixel_asset_ready,
    input wire pixel_req_valid,input wire [17:0] pixel_req_addr,
    input wire [31:0] pixel_req_asset_id,pixel_req_generation,
    output reg sample_valid,sample_error,output wire [31:0] sample_rgba
);
    `include "avatar_span_table.vh"
    generate if(TEXELS<1||TEXELS>65536)begin:invalid_parameters
        initial $fatal(1,"avatar_texture_cache requires 1..65536 texels");
    end endgenerate
    reg loading,sealing;
    reg [15:0] write_index;
    reg core_run=0,pixel_run=0;
    always @(posedge core_clk)core_run<=core_reset_n;
    always @(posedge pixel_clk)pixel_run<=pixel_reset_n;
    assign load_ready=core_run&&core_reset_n&&!loading&&!asset_ready&&!load_fault;
    assign s_ready=core_run&&core_reset_n&&loading&&!load_fault&&!sealing;
    wire last_matches=s_last===(words_written==TEXELS-1);
    wire known_rgba=(^s_rgba!==1'bx);
    wire storage_ok,write_complete;
    wire write_word=core_run&&s_valid&&s_ready&&last_matches&&known_rgba&&storage_ok;
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin
            loading<=0;sealing<=0;write_index<=0;asset_ready<=0;load_fault<=0;
            asset_id<=0;asset_generation<=0;words_written<=0;
        end else begin
            if(load_valid&&load_ready)begin
                if((^load_asset_id===1'bx)||(^load_generation===1'bx))load_fault<=1;
                else begin loading<=1;asset_id<=load_asset_id;asset_generation<=load_generation;end
            end
            if(s_valid&&s_ready)begin
                if(!last_matches||!known_rgba||!storage_ok)begin loading<=0;load_fault<=1;end
                else begin
                    words_written<=words_written+1'b1;
                    if(words_written==TEXELS-1)sealing<=1;
                    else write_index<=write_index+1'b1;
                end
            end
            // Complete only after the final physical RAM write; reject further
            // input while a compact-cache final write is still in flight.
            if(write_complete)begin loading<=0;sealing<=0;asset_ready<=1;end
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
    // RAM and read data registers have no reset. Readiness remains the only
    // publication event, after the complete checked stream is immutable.
    generate if(!COMPACT_PRESET)begin:g_full
        reg [31:0] texture[0:TEXELS-1];
        reg [31:0] read_data;
        assign storage_ok=1'b1;
        assign write_complete=write_word&&s_last;
        always @(posedge core_clk)if(write_word)texture[write_index]<=s_rgba;
        always @(posedge pixel_clk)
            if(pixel_run&&pixel_req_valid&&request_ok)read_data<=texture[pixel_req_addr[17:2]];
        assign sample_rgba=read_data;
    end else begin:g_spans
        if(TEXELS!=65536||AVATAR_PACKED_TEXELS<1||AVATAR_PACKED_TEXELS>65536)begin:invalid_preset
            initial $fatal(1,"compact preset requires one nonempty 256x256 image");
        end
        localparam integer MAIN_WORDS=AVATAR_PACKED_TEXELS>32768?32768:AVATAR_PACKED_TEXELS;
        localparam integer TAIL_WORDS=AVATAR_PACKED_TEXELS>32768?AVATAR_PACKED_TEXELS-32768:1;
        reg [31:0] main_ram[0:MAIN_WORDS-1];
        reg [31:0] tail_ram[0:TAIL_WORDS-1];
        reg [31:0] main_data,tail_data;
        reg [16:0] packed_write;
        reg [7:0] row_left;
        reg [8:0] row_right;
        wire [32:0] first_span=avatar_span(8'd0);
        wire [32:0] next_span=avatar_span(write_index[15:8]+8'd1);
        wire keep_word=write_index[7:0]>=row_left&&{1'b0,write_index[7:0]}<row_right;
        assign storage_ok=(keep_word||s_rgba==32'd0)&&
                          (!s_last||(keep_word?packed_write==AVATAR_PACKED_TEXELS-1:
                                              packed_write==AVATAR_PACKED_TEXELS));
        always @(posedge core_clk or negedge core_reset_n)begin
            if(!core_reset_n)begin packed_write<=0;row_left<=0;row_right<=0;end
            else begin
                if(load_valid&&load_ready)begin
                    packed_write<=0;row_left<=first_span[16:9];row_right<=first_span[8:0];
                end
                if(write_word)begin
                    if(keep_word)packed_write<=packed_write+1'b1;
                    if(write_index[7:0]==255)begin row_left<=next_span[16:9];row_right<=next_span[8:0];end
                end
            end
        end
        // Isolate the 125 MHz RAM enable/address/data from span validation.
        // Accepted-word counting can lead the physical write by one clock;
        // neither core nor pixel readiness is published until it commits.
        reg delayed_write,delayed_last;
        reg [15:0] delayed_address;
        reg [31:0] delayed_rgba;
        always @(posedge core_clk or negedge core_reset_n)begin
            if(!core_reset_n)begin delayed_write<=0;delayed_last<=0;end
            else begin delayed_write<=write_word&&keep_word;delayed_last<=write_word&&s_last;end
        end
        // Data is consumed only when delayed_write is asserted. Capture it
        // unconditionally to remove span validation from these data-register enables.
        always @(posedge core_clk)begin
            delayed_address<=packed_write[15:0];delayed_rgba<=s_rgba;
        end
        always @(posedge core_clk)begin
            if(delayed_write&&!delayed_address[15])main_ram[delayed_address[14:0]]<=delayed_rgba;
            if(delayed_write&&delayed_address[15])tail_ram[delayed_address[14:0]]<=delayed_rgba;
        end
        assign write_complete=delayed_last&&!load_fault;
        wire [32:0] read_span=avatar_span(pixel_req_addr[17:10]);
        wire [8:0] read_delta={1'b0,pixel_req_addr[9:2]}-{1'b0,read_span[16:9]};
        wire read_stored=pixel_req_addr[9:2]>=read_span[16:9]&&{1'b0,pixel_req_addr[9:2]}<read_span[8:0];
        wire [15:0] packed_read=read_span[32:17]+read_delta;
        reg read_zero,read_tail;
        always @(posedge pixel_clk)if(pixel_run&&pixel_req_valid&&request_ok)begin
            read_zero<=!read_stored;read_tail<=packed_read[15];
            if(read_stored&&!packed_read[15])main_data<=main_ram[packed_read[14:0]];
            if(read_stored&&packed_read[15])tail_data<=tail_ram[packed_read[14:0]];
        end
        assign sample_rgba=read_zero?32'd0:read_tail?tail_data:main_data;
    end endgenerate
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin sample_valid<=0;sample_error<=0;end
        else begin sample_valid<=pixel_req_valid;
            sample_error<=pixel_req_valid&&!request_ok;end
    end
endmodule
`default_nettype wire
