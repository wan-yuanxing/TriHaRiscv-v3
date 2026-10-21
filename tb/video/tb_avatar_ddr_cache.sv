`timescale 1ns/1ps
module tb_avatar_ddr_cache #(parameter integer TEXELS=68,CASE_ID=0,PAGE=0,parameter real PIXEL_HALF=12.5);
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0;
    always #4 core_clk=~core_clk;always #(PIXEL_HALF) pixel_clk=~pixel_clk;
    localparam [31:0] BASE=PAGE==2?32'h82800000-TEXELS*4:PAGE==1?32'h82600ff0:32'h82600000;
    reg online=1,load_valid=0;wire load_ready;
    reg [31:0] load_base=0,load_bytes=0,load_asset_id=0,load_generation=0,expected_crc=0;
    wire result_valid;reg result_ready=0;wire result_success;wire [7:0] result_code;
    wire [31:0] result_asset_id,result_generation,checked_bytes,crc;
    wire fault,port_drained,asset_ready,pixel_asset_ready;wire [7:0] fault_code;
    wire [31:0] asset_id,asset_generation,words_written;
    reg pixel_req_valid=0;reg [17:0] pixel_req_addr=0;
    reg [31:0] pixel_req_asset_id=0,pixel_req_generation=0;
    wire sample_valid,sample_error;wire [31:0] sample_rgba;
    wire [3:0] arid;wire [31:0] araddr;wire [7:0] arlen;wire [2:0] arsize;wire [1:0] arburst;
    wire arvalid;reg arready=0;reg [3:0] rid=0;reg [127:0] rdata=0;reg [1:0] rresp=0;
    reg rlast=0,rvalid=0;wire rready;
    avatar_ddr_cache #(.TEXELS(TEXELS),.TIMEOUT_CYCLES(128)) dut(.*);
    reg [31:0] memory[0:TEXELS-1],wanted[0:TEXELS-1],crc_file[0:0];
    integer cycles=0,bursts=0,beats=0,compared=0,gen=11;
    integer model_left=0,model_address=0,model_index=0;
    reg active=0;reg [31:0] next_address=BASE;
    reg [44:0] held_ar;reg was_ar=0;reg [127:0] held_r;reg held_last;reg [5:0] held_response;
    reg was_r=0,delayed=0,sealed_injected=0;integer delay_until=0;
    reg [31:0] held_asset,held_gen;
    always @(negedge core_clk)begin
        if(!core_reset_n)begin arready=0;rvalid=0;end
        else begin
            arready=(cycles%7!=0)&&!(CASE_ID==12&&!delayed)&&!(CASE_ID==16&&cycles<50);
            if(CASE_ID==16&&arvalid&&!active&&!rvalid&&cycles<50)begin
                rvalid=1;rid=9;rresp=0;rlast=0;rdata={memory[3],memory[2],memory[1],memory[0]};
            end
            if(asset_ready&&!sealed_injected)begin
                if(CASE_ID==17)online=0;
                if(CASE_ID==18)begin rvalid=1;rid=9;rresp=0;rlast=1;rdata=0;end
                sealed_injected=1;
            end
            if(!rvalid&&active&&cycles%5!=0&&!(CASE_ID==13&&cycles<delay_until))begin
                rvalid=1;rid=4'h9;rresp=0;rlast=model_left==1;
                rdata={memory[model_index+3],memory[model_index+2],memory[model_index+1],memory[model_index]};
                if(beats==2)begin
                    if(CASE_ID==7||CASE_ID==19)rresp=2;
                    if(CASE_ID==8)rid=3;
                    if(CASE_ID==9)rlast=1;
                    if(CASE_ID==11)rdata[72]=1'bx;
                end
                if(CASE_ID==10&&model_left==1)rlast=0;
            end
        end
    end
    always @(posedge core_clk)begin
        if(!core_reset_n)begin
            cycles<=0;bursts<=0;beats<=0;active<=0;model_left<=0;next_address<=BASE;was_ar<=0;was_r<=0;
            delay_until<=300;
        end else begin
            cycles<=cycles+1;
            if(was_ar&&{arvalid,araddr,arlen,arsize,arburst}!=={1'b1,held_ar})$fatal(1,"AVATAR_DDR_AR_RETRACTED");
            was_ar<=arvalid&&!arready;held_ar<={araddr,arlen,arsize,arburst};
            if(was_r&&{rvalid,rdata,rlast,rid,rresp}!=={1'b1,held_r,held_last,held_response})$fatal(1,"AXI_MODEL_R_CHANGED");
            was_r<=rvalid&&!rready;held_r<=rdata;held_last<=rlast;held_response<={rid,rresp};
            if(arvalid&&arready)begin
                if(active||araddr!==next_address||arid!==9||arsize!==4||arburst!==1||arlen>15||
                   {1'b0,araddr[11:0]}+({5'd0,arlen}+13'd1)*16>4096||araddr+(arlen+1)*16>BASE+TEXELS*4)
                    $fatal(1,"AVATAR_DDR_BURST addr=%h len=%0d next=%h",araddr,arlen,next_address);
                active<=1;model_left<=arlen+1;model_index<=(araddr-BASE)/4;bursts<=bursts+1;
                next_address<=araddr+(arlen+1)*16;
            end
            if(rvalid&&rready)begin
                if(!active)$fatal(1,"AXI_MODEL_NO_READ");
                rvalid<=0;beats<=beats+1;model_left<=model_left-1;model_index<=model_index+4;
                if(model_left==1)active<=0;
            end
            if(CASE_ID==12&&arvalid&&!delayed&&cycles>30)begin online<=0;delayed<=1;end
            if(CASE_ID==15&&beats==2)online<=0;
            if(asset_ready&&((fault&&CASE_ID!=18)||words_written!=TEXELS))$fatal(1,"AVATAR_DDR_EARLY_READY");
        end
    end
    task automatic reset_both;
        begin core_reset_n=0;pixel_reset_n=0;load_valid=0;result_ready=0;pixel_req_valid=0;online=1;
            repeat(5)@(negedge core_clk);repeat(3)@(negedge pixel_clk);core_reset_n=1;pixel_reset_n=1;
        end
    endtask
    task automatic start;
        begin
            @(negedge core_clk);load_base=BASE;load_bytes=TEXELS*4;load_asset_id=7;load_generation=gen;expected_crc=crc_file[0];
            case(CASE_ID)
                1:load_base=32'h825ffff0;
                2:load_base=32'h82800010-TEXELS*4;
                3:load_base=BASE+1;
                4:load_bytes=TEXELS*4-4;
                5:load_asset_id='x;
                6:expected_crc=crc_file[0]^32'h80000000;
            endcase
            load_valid=1;do @(posedge core_clk);while(!load_ready);
            @(negedge core_clk);load_valid=0;load_base='x;load_bytes='x;load_asset_id='x;load_generation='x;expected_crc='x;
        end
    endtask
    task automatic request(input integer index,input bit bad);
        begin
            @(negedge pixel_clk);pixel_req_valid=1;pixel_req_addr=index*4;pixel_req_asset_id=bad?8:7;pixel_req_generation=gen;
            @(posedge pixel_clk);#1;
            if(sample_valid!==1||sample_error!==bad||(!bad&&sample_rgba!==wanted[index]))
                $fatal(1,"AVATAR_DDR_PIXEL %0d got=%h expected=%h err=%b",index,sample_rgba,wanted[index],sample_error);
            compared=compared+1;
        end
    endtask
    string directory;integer i;reg [136:0] saved_result;
    initial begin
        if(!$value$plusargs("DIR=%s",directory))$fatal(1,"AVATAR_DDR_DIR");
        $readmemh({directory,"/bus_words.hex"},memory);$readmemh({directory,"/expected_words.hex"},wanted);$readmemh({directory,"/crc.hex"},crc_file);
        reset_both();start();
        if(CASE_ID==14)begin wait(words_written>12);reset_both();gen=12;
            if(asset_ready||pixel_asset_ready||fault)$fatal(1,"AVATAR_DDR_RESET_READY");start();end
        wait(result_valid);#1;
        if((CASE_ID==0||CASE_ID==14||CASE_ID==17||CASE_ID==18))begin
            if(!result_success||result_code||(CASE_ID==18?(fault!==1||fault_code!=6||port_drained):(fault||!port_drained))||!asset_ready||checked_bytes!=TEXELS*4||crc!==crc_file[0]||
               result_asset_id!=7||result_generation!=gen||asset_id!=7||asset_generation!=gen||beats!=TEXELS/4||next_address!=BASE+TEXELS*4)
                $fatal(1,"AVATAR_DDR_RESULT code=%0d bytes=%0d crc=%h expected=%h",result_code,checked_bytes,crc,crc_file[0]);
            saved_result={result_success,result_code,result_asset_id,result_generation,checked_bytes,crc};
            repeat(20)begin @(negedge core_clk);if(!result_valid||{result_success,result_code,result_asset_id,result_generation,checked_bytes,crc}!==saved_result)$fatal(1,"AVATAR_DDR_RESULT_HOLD");end
            repeat(6)@(negedge pixel_clk);if(!pixel_asset_ready)$fatal(1,"AVATAR_DDR_PIXEL_NOT_READY");
            for(i=0;i<TEXELS;i=i+1)request(i,0);request(0,1);
            @(negedge pixel_clk);pixel_req_valid=0;
            @(negedge core_clk);result_ready=1;load_valid=1;load_asset_id=99;load_generation=200;
            repeat(20)begin @(negedge core_clk);if(load_ready||asset_id!=7||asset_generation!=gen)$fatal(1,"AVATAR_DDR_SEALED_REPLACED");end
            load_valid=0;request(TEXELS-1,0);
        end else begin
            if(CASE_ID==19)begin
                if(result_code!=2||!port_drained)$fatal(1,"AVATAR_DDR_LATE_STRAY_BASELINE");
                @(negedge core_clk);rvalid=1;rid=9;rresp=0;rlast=1;rdata=0;
                repeat(3)@(negedge core_clk);
                if(port_drained||fault_code!=2||result_code!=2)$fatal(1,"AVATAR_DDR_LATE_STRAY_DRAIN");
            end
            if(result_success||!result_code||!fault||asset_ready||pixel_asset_ready||load_ready)$fatal(1,"AVATAR_DDR_FAILURE_NOT_ISOLATED");
            if(CASE_ID<=5&&bursts!=0)$fatal(1,"AVATAR_DDR_BAD_DESCRIPTOR_AR");
            if(CASE_ID>=7&&CASE_ID!=14&&bursts!=1)$fatal(1,"AVATAR_DDR_DRAIN_NEW_BURST");
            if((CASE_ID==8||CASE_ID==9||CASE_ID==10||CASE_ID==11||CASE_ID==16)&&port_drained)$fatal(1,"AVATAR_DDR_UNCERTAIN_DRAIN");
            if(CASE_ID==6&&(words_written!=TEXELS-1||checked_bytes!=TEXELS*4||crc!==crc_file[0]))$fatal(1,"AVATAR_DDR_CRC_SEALED");
            saved_result={result_success,result_code,result_asset_id,result_generation,checked_bytes,crc};
            repeat(20)begin @(negedge core_clk);if(!result_valid||{result_success,result_code,result_asset_id,result_generation,checked_bytes,crc}!==saved_result)$fatal(1,"AVATAR_DDR_FAILURE_HOLD");end
            repeat(6)@(negedge pixel_clk);request(0,1);
        end
        $display("AVATAR_DDR_PASS case=%0d texels=%0d bursts=%0d beats=%0d compared=%0d code=%0d",CASE_ID,TEXELS,bursts,beats,compared,result_code);$finish;
    end
    initial begin #50000000;$fatal(1,"AVATAR_DDR_TIMEOUT");end
endmodule
