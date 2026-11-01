`timescale 1ns/1ps
`default_nettype none
module tb_avatar_row_cache #(parameter integer CASE_ID=0);
    localparam integer TEXELS=256,ROW_TEXELS=64,ASSET_BYTES=TEXELS*4;
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0,online=1;
    always #4 core_clk=~core_clk;
    always #12.5 pixel_clk=~pixel_clk;
    reg load_valid=0,result_ready=1;
    reg [31:0] load_base=32'h82600000,load_bytes=ASSET_BYTES,load_asset_id=7,load_generation=71,expected_crc;
    wire load_ready,result_valid,result_success,asset_ready,pixel_asset_ready;
    wire [31:0] asset_id,asset_generation,words_written;
    wire [7:0] result_code;wire [31:0] result_asset_id,result_generation,checked_bytes,crc;
    reg sample_req_valid=0;wire sample_req_ready;reg [17:0] sample_req_addr;
    reg [31:0] sample_req_asset_id=7,sample_req_generation=71;
    reg prefetch_valid=0;wire prefetch_ready;reg [17:0] prefetch_addr=0;
    reg [31:0] prefetch_asset_id=7,prefetch_generation=71;
    wire sample_rsp_valid,sample_rsp_error;wire [31:0] sample_rsp_rgba,sample_rgba;
    assign sample_rsp_rgba=sample_rgba;
    wire [3:0] arid;wire [31:0] araddr;wire [7:0] arlen;wire [2:0] arsize;wire [1:0] arburst;wire arvalid;reg arready=0;
    reg [3:0] rid=9;reg [127:0] rdata;reg [1:0] rresp=0;reg rlast=0,rvalid=0;wire rready;
    wire fault;wire [7:0] fault_code;wire port_drained;
    avatar_row_cache #(.TEXELS(TEXELS),.ROW_TEXELS(ROW_TEXELS),.TIMEOUT_CYCLES(40)) dut(.*);
    reg [7:0] memory[0:ASSET_BYTES-1];reg bus_active=0;reg [31:0] bus_address;integer bus_beat=0;reg stall=0;
    integer i,j,requests=0,responses=0;
    function automatic [7:0] asset_byte(input integer n);
        asset_byte=(n*37+19*(n>>3)+8'h5a) & 8'hff;
    endfunction
    function automatic [31:0] crc_byte(input [31:0] old_crc,input [7:0] b);
        reg [31:0] v;integer k;begin v=old_crc^{24'd0,b};for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end
    endfunction
    function automatic [31:0] asset_crc;
        reg [31:0] v;integer n;begin v=32'hffffffff;for(n=0;n<ASSET_BYTES;n=n+1)v=crc_byte(v,asset_byte(n));asset_crc=~v;end
    endfunction
    always @* begin
        rdata=0;
        for(j=0;j<16;j=j+1)if(bus_address+bus_beat*16+j<ASSET_BYTES)
            rdata[j*8+:8]=memory[bus_address+bus_beat*16+j];
        arready=!bus_active&&!stall;
        rvalid=bus_active&&!stall;
        rlast=bus_beat==15;
        if(CASE_ID==1&&bus_active&&bus_beat==0&&dut.state==6)rid=4'h8;else rid=4'h9;
    end
    always @(posedge core_clk) begin
        if(!core_reset_n)begin bus_active<=0;bus_beat<=0;end
        else begin
            if(arvalid&&arready)begin bus_active<=1;bus_address<=araddr-load_base;bus_beat<=0;end
            if(bus_active&&rvalid&&rready)begin
                if(bus_beat==15)begin bus_active<=0;bus_beat<=0;end else bus_beat<=bus_beat+1;
            end
        end
    end
    task automatic sample(input integer texel,input bit want_error);
        begin
            @(negedge pixel_clk);sample_req_addr=texel*4;sample_req_valid=1;
            do @(posedge pixel_clk);while(!sample_req_ready);
            @(negedge pixel_clk);sample_req_valid=0;requests=requests+1;
            wait(sample_rsp_valid);responses=responses+1;
            if(sample_rsp_error!==want_error)$fatal(1,"ROW_CACHE_SAMPLE_ERROR texel=%0d got=%b want=%b",texel,sample_rsp_error,want_error);
            if(!want_error&&sample_rsp_rgba!=={asset_byte(texel*4+3),asset_byte(texel*4+2),asset_byte(texel*4+1),asset_byte(texel*4)})
                $fatal(1,"ROW_CACHE_SAMPLE_DATA texel=%0d got=%h",texel,sample_rsp_rgba);
            @(negedge pixel_clk);
        end
    endtask
    initial begin
        for(i=0;i<ASSET_BYTES;i=i+1)memory[i]=asset_byte(i);
        expected_crc=asset_crc();
        repeat(8)@(negedge core_clk);core_reset_n=1;pixel_reset_n=1;
        @(negedge core_clk);load_valid=1;
        do @(posedge core_clk);while(!load_ready);
        @(negedge core_clk);load_valid=0;
        wait(result_valid);
        if(CASE_ID==0)begin
            if(!result_success||result_code!=0||checked_bytes!=ASSET_BYTES||crc!=expected_crc||!asset_ready)
                $fatal(1,"ROW_CACHE_LOAD_PROOF code=%h bytes=%0d crc=%h",result_code,checked_bytes,crc);
            sample(3,0);sample(7,0);sample(66,0);sample(130,0);
            if(fault||responses!=4)$fatal(1,"ROW_CACHE_NORMAL fault=%b responses=%0d",fault,responses);
            $display("AVATAR_ROW_CACHE_PASS case=0 requests=%0d responses=%0d rows=3",requests,responses);
        end else if(CASE_ID==1)begin
            if(!result_success)$fatal(1,"ROW_CACHE_BAD_LOAD");sample(3,1);
            if(!fault||fault_code!=2)$fatal(1,"ROW_CACHE_BAD_RID fault=%b code=%h",fault,fault_code);
            $display("AVATAR_ROW_CACHE_PASS case=1 late_bad_response=1 code=%h",fault_code);
        end else begin
            if(!result_success)$fatal(1,"ROW_CACHE_TIMEOUT_LOAD");stall=1;sample(3,1);
            if(!fault||fault_code!=4)$fatal(1,"ROW_CACHE_TIMEOUT fault=%b code=%h",fault,fault_code);
            $display("AVATAR_ROW_CACHE_PASS case=2 deadline=1 code=%h",fault_code);
        end
        $finish;
    end
    initial begin #10000000;$fatal(1,"ROW_CACHE_WATCHDOG");end
endmodule
`default_nettype wire
