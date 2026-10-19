`timescale 1ns/1ps
module tb_avatar_texture_cache;
    parameter integer TEXELS=37;
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0;
    always #4 core_clk=~core_clk;
    always #12.5 pixel_clk=~pixel_clk;
    reg load_valid=0;
    wire load_ready;
    reg [31:0] load_asset_id=0,load_generation=0;
    reg s_valid=0,s_last=0;
    reg [31:0] s_rgba=0;
    wire s_ready,asset_ready,load_fault,pixel_asset_ready;
    wire [31:0] asset_id,asset_generation,words_written;
    reg pixel_req_valid=0;
    reg [17:0] pixel_req_addr=0;
    reg [31:0] pixel_req_asset_id=0,pixel_req_generation=0;
    wire sample_valid,sample_error;
    wire [31:0] sample_rgba;
    avatar_texture_cache #(.TEXELS(TEXELS)) dut(.*);
    integer scenario=0,variant=0,i,t,compared=0;
    task automatic check(input bit ok,input string why);
        if(!ok)$fatal(1,"avatar_cache case%0d: %s",scenario,why);
    endtask
    function automatic [31:0] pattern(input integer word_index);
        pattern=(32'h3c817fa5 ^ (word_index*32'h1f1357bd)) ^ (variant?32'h9e76a120:32'd0);
    endfunction
    task automatic reset_both;
        begin
            core_reset_n=0;pixel_reset_n=0;load_valid=0;s_valid=0;pixel_req_valid=0;
            repeat(4)@(negedge core_clk);repeat(3)@(negedge pixel_clk);
            check(!asset_ready&&!sample_valid&&!load_fault,"reset must clear readiness/response/fault");
            core_reset_n=1;pixel_reset_n=1;
        end
    endtask
    task automatic start_load;
        begin
            @(negedge core_clk);load_valid=1;load_asset_id=32'h12345678;
            load_generation=variant+9;
            do @(posedge core_clk);while(!load_ready);
            @(negedge core_clk);load_valid=0;load_asset_id='x;load_generation='x;
        end
    endtask
    task automatic send_word(input integer n,input bit last,input bit poison);
        begin
            @(negedge core_clk);s_valid=1;s_rgba=poison?32'hxxxxxxxx:pattern(n);s_last=last;
            do @(posedge core_clk);while(!s_ready);
            @(negedge core_clk);s_valid=0;s_rgba='x;s_last='x;
        end
    endtask
    task automatic load_all;
        begin
            start_load();
            for(i=0;i<TEXELS;i=i+1)begin
                if(i%7==0)begin
                    repeat(2)@(negedge core_clk);
                    check(!asset_ready&&words_written==i,"partial or stalled load became ready");
                end
                send_word(i,i==TEXELS-1,0);
                check(asset_ready===(i==TEXELS-1),"last-word readiness boundary");
            end
            check(words_written==TEXELS&&!s_ready&&!load_ready&&!load_fault,"cache not sealed after complete load");
            check(asset_id==32'h12345678&&asset_generation==variant+9,"asset identity not immutable");
            repeat(6)@(negedge pixel_clk);
            check(pixel_asset_ready,"complete cache not published to pixel domain");
        end
    endtask
    // Request is sampled on the following rising edge, synchronous data and
    // response controls must both be available immediately after that edge.
    task automatic request(input bit valid,input [17:0] addr,input bit bad_id,input bit bad_gen,input bit fail);
        reg old_valid,old_error;
        reg [31:0] old_rgba;
        begin
            @(negedge pixel_clk);
            old_valid=sample_valid;old_error=sample_error;old_rgba=sample_rgba;
            pixel_req_valid=valid;pixel_req_addr=addr;
            pixel_req_asset_id=bad_id?32'h11111111:32'h12345678;
            pixel_req_generation=bad_gen?0:variant+9;
            #1;
            check({sample_valid,sample_error,sample_rgba}==={old_valid,old_error,old_rgba},
                  "response changed before the request sampling edge");
            @(posedge pixel_clk);#1;
            check(sample_valid===valid,"request response slot missing or delayed");
            if(valid)begin
                check(sample_error===fail,"response error qualification");
                if(!fail)begin check(sample_rgba===pattern(addr/4),"texture word/first-last/reset readback");compared=compared+1;end
            end
        end
    endtask
    initial begin
        if($value$plusargs("CASE=%d",scenario))begin end
        reset_both();
        case(scenario)
        0:begin
            request(1,0,0,0,1);request(0,0,0,0,0);load_all();
            // Full-rate back-to-back requests, including the first/last word.
            for(t=0;t<TEXELS;t=t+1)request(1,t*4,0,0,0);
            request(1,1,0,0,1);request(1,2,0,0,1);
            if(TEXELS<65536)request(1,TEXELS*4,0,0,1);
            request(1,0,1,0,1);request(1,0,0,1,1);request(0,0,0,0,0);
            @(negedge core_clk);load_valid=1;s_valid=1;s_rgba=0;s_last=1;
            repeat(5)@(negedge core_clk);
            check(!load_ready&&!s_ready&&asset_ready&&!load_fault,"sealed cache accepted replacement");
            load_valid=0;s_valid=0;request(1,(TEXELS-1)*4,0,0,0);
        end
        1,2,3:begin
            start_load();send_word(0,scenario==1,scenario==3);
            if(scenario==2)for(i=1;i<TEXELS;i=i+1)send_word(i,0,0);
            repeat(5)@(negedge core_clk);
            check(load_fault&&!asset_ready&&!load_ready&&!s_ready,"bad stream not isolated");
            repeat(5)@(negedge pixel_clk);request(1,0,0,0,1);
        end
        4:begin
            load_all();request(1,0,0,0,0);reset_both();variant=1;
            request(1,0,0,0,1);load_all();
            for(t=0;t<TEXELS;t=t+1)request(1,t*4,0,0,0);
        end
        5:begin start_load();send_word(0,0,0);reset_both();variant=1;
            request(1,0,0,0,1);load_all();request(1,(TEXELS-1)*4,0,0,0);end
        default:$fatal(1,"Unknown case");
        endcase
        $display("AVATAR_TEXTURE_CACHE_PASS case=%0d compared=%0d",scenario,compared);$finish;
    end
    initial begin #20000000;$fatal(1,"avatar_cache timeout");end
endmodule
