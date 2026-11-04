`timescale 1ns/1ps
`include "avatar_preset.vh"
// Continuous producer and independent raw-RGBA pixel oracle. No span-table
// lookup or implementation hierarchy is used by this test.
module tb_avatar_span_stream #(parameter integer RESET_DURING_LOAD=0,
                              parameter real PIXEL_HALF=12.5);
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0;
    always #4 core_clk=~core_clk;
    always #(PIXEL_HALF) pixel_clk=~pixel_clk;
    reg load_valid=0,s_valid=0,s_last=0,pixel_req_valid=0;
    reg [31:0] load_asset_id=`TRIHA_AVATAR_ID,load_generation=`TRIHA_AVATAR_GENERATION;
    reg [31:0] s_rgba=0,pixel_req_asset_id=`TRIHA_AVATAR_ID,pixel_req_generation=`TRIHA_AVATAR_GENERATION;
    reg [17:0] pixel_req_addr=0;
    wire load_ready,s_ready,asset_ready,load_fault,pixel_asset_ready,sample_valid,sample_error;
    wire [31:0] asset_id,asset_generation,words_written,sample_rgba;
    avatar_texture_cache #(.COMPACT_PRESET(1)) dut(.*);
    reg [31:0] wanted[0:65535];
    integer compared=0,accepted=0;
    task automatic reset_both;
        begin
            core_reset_n=0;pixel_reset_n=0;load_valid=0;s_valid=0;pixel_req_valid=0;
            repeat(5)@(negedge core_clk);
            if(asset_ready||pixel_asset_ready||load_fault)$fatal(1,"SPAN_RESET_PUBLICATION");
            core_reset_n=1;pixel_reset_n=1;
        end
    endtask
    task automatic open_asset;
        begin
            @(negedge core_clk);load_valid=1;
            do @(posedge core_clk);while(!load_ready);
            @(negedge core_clk);load_valid=0;
        end
    endtask
    task automatic send_word(input integer index,input bit corrupt);
        begin
            @(negedge core_clk);s_valid=1;s_last=index==65535;
            s_rgba=corrupt?wanted[index]^32'd1:wanted[index];
            do @(posedge core_clk);while(!s_ready);
            accepted=accepted+1;
            #1;if(load_fault)$fatal(1,"SPAN_STREAM_FAULT index=%0d",index);
            if(index!=65535&&asset_ready)$fatal(1,"SPAN_EARLY_SEAL");
        end
    endtask
    string directory;integer i,first_nonzero;
    initial begin
        if(!$value$plusargs("DIR=%s",directory))$fatal(1,"SPAN_DIR");
        $readmemh({directory,"/expected_words.hex"},wanted);
        first_nonzero=0;
        while(first_nonzero<65536&&wanted[first_nonzero]==0)first_nonzero=first_nonzero+1;
        if(first_nonzero==65536)$fatal(1,"SPAN_EMPTY_FIXTURE");
        reset_both();open_asset();
        if(RESET_DURING_LOAD)begin
            for(i=0;i<=first_nonzero;i=i+1)send_word(i,i==first_nonzero);
            // Reset after acceptance and before the next write clock. A new
            // complete load must replace all stale or pending material bytes.
            @(negedge core_clk);reset_both();open_asset();accepted=0;
        end
        for(i=0;i<65536;i=i+1)send_word(i,0);
        @(negedge core_clk);s_valid=0;
        wait(asset_ready);repeat(6)@(negedge pixel_clk);
        if(!pixel_asset_ready||words_written!=65536||load_ready||s_ready)$fatal(1,"SPAN_SEAL");
        for(i=65535;i>=0;i=i-1)begin
            @(negedge pixel_clk);pixel_req_valid=1;pixel_req_addr=i*4;
            @(posedge pixel_clk);#1;
            if(!sample_valid||sample_error||sample_rgba!==wanted[i])
                $fatal(1,"SPAN_PIXEL index=%0d got=%h expected=%h",i,sample_rgba,wanted[i]);
            compared=compared+1;
        end
        $display("AVATAR_SPAN_STREAM_PASS accepted=%0d compared=%0d reset=%0d",accepted,compared,RESET_DURING_LOAD);
        $finish;
    end
    initial begin #10000000;$fatal(1,"SPAN_TIMEOUT");end
endmodule
