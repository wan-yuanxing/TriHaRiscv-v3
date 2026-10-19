`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
// Real native-port byte memory, with numerical oracles independent of DUT buses.
module tb_video_raw_engine #(parameter integer W=30,H=20,PT=2,PB=1);
    localparam integer PW=W/2,PH=H/2,IW=W*2/5,AH=H*2/5,IH=PT+AH+PB;
    localparam integer RS=(W*3+15)/16*16,PS=(PW*3+15)/16*16,IS=(IW+15)/16*16,IP=IS*IH;
    localparam integer TIMEOUT=200000;
    reg clk=0,pixel_clk=0,reset_n=0,pixel_reset_n=0,init_done=0;
    always #4 clk=~clk;always #25 pixel_clk=~pixel_clk;
    reg [10:0] pixel_x=0,pixel_y=0;
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==99)begin pixel_x<=0;pixel_y<=pixel_y==H+13?0:pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
    wire pixel_hs=pixel_x>=80&&pixel_x<90,pixel_vs=pixel_y>=H+10;
    wire pixel_de=pixel_x<W&&pixel_y<H,frame_start=pixel_x==0&&pixel_y==0;
    wire [23:0] out_rgb;wire out_hs,out_vs,out_de;
    reg source_fault=0,overflow=0,enabled=0,pause_eof=0;
    reg m_valid;reg [47:0] m_data;wire m_ready,arm_toggle,cancel,busy,done,error;
    wire [7:0] error_code,phase;
    wire [31:0] captured_pixels,preview_pixels,input_pixels,source_crc,preview_crc,fifo_peak,ddr_crc,preview_ddr_crc;
    wire [31:0] frame_id,commits,completed_scans,read_lines,underflows;
    wire [31:0] raw_written_bytes,preview_written_bytes,input_written_bytes,preprocess_version,capture_frame_id;
    wire [31:0] raw_base,preview_base,input_base,input_ddr_crc,input_checked_bytes;
    wire capture_complete,port_drained;
    wire [27:0] axi_awaddr,axi_araddr;wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_arvalid;
    wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen;
    wire axi_awready,axi_arready,axi_wready;wire [255:0] axi_wdata,axi_rdata;wire [31:0] axi_wstrb;
    wire [3:0] axi_wusero_id,axi_rid;wire axi_wusero_last,axi_rlast,axi_rvalid;
    `ifndef VIDEO_RAW_ENGINE_DUT
    `define VIDEO_RAW_ENGINE_DUT video_raw_engine
    `endif
    `VIDEO_RAW_ENGINE_DUT #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(TIMEOUT),.PAD_TOP(PT),.PAD_BOTTOM(PB)) dut(.*);
    reg hold_aw=0,hold_ar=0,hold_w=0,hold_r=0,x_read=0,inject_r=0,bad_wlast=0,bad_rlast=0;
    reg [3:0] bad_wid=0,bad_rid=0;reg [255:0] read_xor=0;
    wire [31:0] aw_commands,ar_commands,write_beats,read_beats,first_w,first_r;
    axi_bridge_native_model memory(
        .clk(clk),.rst_n(reset_n),.gaps(1'b1),.hold_aw(hold_aw),.hold_ar(hold_ar),.hold_w(hold_w),.hold_r(hold_r),.idle_wready(1'b0),
        .bad_wid(bad_wid),.bad_rid(bad_rid),.bad_wlast(bad_wlast),.bad_rlast(bad_rlast),.x_read(x_read),.inject_r(inject_r),.read_xor(read_xor),
        .h_awaddr(axi_awaddr),.h_araddr(axi_araddr),.h_awlen(axi_awlen),.h_arlen(axi_arlen),.h_awid(axi_awuser_id),.h_arid(axi_aruser_id),
        .h_awvalid(axi_awvalid),.h_arvalid(axi_arvalid),.h_awready(axi_awready),.h_arready(axi_arready),.h_wready(axi_wready),.h_rvalid(axi_rvalid),
        .h_wdata(axi_wdata),.h_wstrb(axi_wstrb),.h_rdata(axi_rdata),.h_wid(axi_wusero_id),.h_rid(axi_rid),.h_wlast(axi_wusero_last),.h_rlast(axi_rlast),
        .aw_commands(aw_commands),.ar_commands(ar_commands),.write_beats(write_beats),.read_beats(read_beats),.first_w(first_w),.first_r(first_r));
    function automatic [7:0] source_byte(input integer x,y,c);
        source_byte=8'((37*x+19*y+83*c+((x*y)>>3))%256);
    endfunction
    function automatic [7:0] expected(input integer branch,row,x,c);
        integer sx,sy,wx,wy,top,bottom,total;
        begin
            if(branch==0)expected=source_byte(x,row,c);
            else if(branch==1)begin
                total=int'(source_byte(2*x,2*row,c))+int'(source_byte(2*x+1,2*row,c))+
                      int'(source_byte(2*x,2*row+1,c))+int'(source_byte(2*x+1,2*row+1,c));
                expected=8'((total+2)/4);
            end else if(row<PT||row>=PT+AH)expected=0;
            else begin
                sx=(5*x+1)/2;sy=(5*(row-PT)+1)/2;wx=x%2==0?1:3;wy=(row-PT)%2==0?1:3;
                top=wx*int'(source_byte(sx,sy,c))+(4-wx)*int'(source_byte(sx+1,sy,c));
                bottom=wx*int'(source_byte(sx,sy+1,c))+(4-wx)*int'(source_byte(sx+1,sy+1,c));
                expected=8'((wy*top/4+(4-wy)*bottom/4+2)/4);
            end
        end
    endfunction
    // MSB-first polynomial plus bit reversal is independent of the RTL's CRC recurrence.
    function automatic [31:0] oracle(input integer branch);
        reg [31:0] c,v;reg [7:0] b;integer y,x,ch,n,k;
        begin
            c=32'hffffffff;
            if(branch<2)begin
                for(y=0;y<(branch==0?H:PH);y=y+1)for(x=0;x<(branch==0?W:PW);x=x+1)for(ch=0;ch<3;ch=ch+1)begin
                    b=expected(branch,y,x,ch);for(n=0;n<8;n=n+1)c=(c<<1)^((c[31]^b[n])?32'h04c11db7:0);
                end
            end else begin
                for(ch=2;ch>=0;ch=ch-1)for(y=0;y<IH;y=y+1)for(x=0;x<IW;x=x+1)begin
                    b=expected(2,y,x,ch);for(n=0;n<8;n=n+1)c=(c<<1)^((c[31]^b[n])?32'h04c11db7:0);
                end
            end
            for(k=0;k<32;k=k+1)v[k]=~c[31-k];oracle=v;
        end
    endfunction
    integer sent=0,case_id=0,tests=0,read_stage=0,requests=0,arms=0;
    reg old_arm=0;reg [31:0] raw_oracle,preview_oracle,input_oracle;
    always @* begin
        m_valid=enabled&&sent<=W*H&&!(pause_eof&&sent==W*H);
        m_data=sent<W*H?{2'b00,(sent%W==W-1),21'd0,source_byte(sent%W,sent/W,0),source_byte(sent%W,sent/W,1),source_byte(sent%W,sent/W,2)}:
            {2'b01,1'b0,1'b1,12'd37,raw_oracle};
    end
    reg held_aw=0,held_ar=0;reg [35:0] saved_aw,saved_ar;
    always @(posedge clk)begin
        if(!reset_n)begin sent<=0;read_stage<=0;requests<=0;arms<=0;old_arm<=0;held_aw<=0;held_ar<=0;end
        else begin
            if(m_valid&&m_ready)sent<=sent+1;
            if(arm_toggle!=old_arm)begin arms<=arms+1;old_arm<=arm_toggle;end
            if(dut.capture.req_valid&&dut.capture.req_ready)requests<=requests+1;
            if(held_aw&&(!axi_awvalid||{axi_awaddr,axi_awlen,axi_awuser_id}!==saved_aw))$fatal(1,"advertised native AW changed");
            if(held_ar&&(!axi_arvalid||{axi_araddr,axi_arlen,axi_aruser_id}!==saved_ar))$fatal(1,"advertised native AR changed");
            held_aw<=axi_awvalid&&!axi_awready;saved_aw<={axi_awaddr,axi_awlen,axi_awuser_id};
            held_ar<=axi_arvalid&&!axi_arready;saved_ar<={axi_araddr,axi_arlen,axi_aruser_id};
            if(dut.arvalid&&dut.arready)begin
                if(!capture_complete||!port_drained||raw_written_bytes!=W*H*3||preview_written_bytes!=PW*PH*3||input_written_bytes!=IW*IH*3)
                    $fatal(1,"read before successful capture and all write retirements");
                if(dut.arid==6)begin
                    if(dut.araddr>=raw_base&&dut.araddr<raw_base+RS*H)begin if(read_stage>0)$fatal(1,"raw reader ownership returned");end
                    else if(dut.araddr>=preview_base&&dut.araddr<preview_base+PS*PH)begin
                        if(read_stage>1||ddr_crc!==raw_oracle)$fatal(1,"preview read before raw CRC retirement");read_stage<=1;
                    end else $fatal(1,"checked reader outside public planes");
                end else if(dut.arid==7)begin
                    if(read_stage>2||preview_ddr_crc!==preview_oracle||dut.araddr<input_base||dut.araddr>=input_base+3*IP)$fatal(1,"input ownership/descriptor");read_stage<=2;
                end else if(dut.arid==0)begin
                    if((case_id!=16&&input_ddr_crc!==input_oracle)||input_checked_bytes!==3*IW*IH||dut.crc_reader.busy||dut.input_reader.busy||dut.araddr<raw_base||dut.araddr>=raw_base+RS*H)
                        $fatal(1,"display started before input reader retired");read_stage<=3;
                end else $fatal(1,"unknown read owner");
            end
            if(commits!=0&&((case_id!=16&&input_ddr_crc!==input_oracle)||input_checked_bytes!==3*IW*IH))$fatal(1,"early display commit");
        end
    end
    task automatic restart;
        begin
            @(negedge clk);reset_n=0;pixel_reset_n=0;init_done=0;enabled=0;source_fault=0;overflow=0;pause_eof=0;
            hold_aw=0;hold_ar=0;hold_w=0;hold_r=0;bad_wid=0;bad_rid=0;bad_wlast=0;bad_rlast=0;x_read=0;inject_r=0;read_xor=0;
            repeat(6)@(negedge clk);reset_n=1;pixel_reset_n=1;
            repeat(20)@(negedge clk);if(arm_toggle||axi_awvalid||axi_arvalid||busy||done||capture_complete)$fatal(1,"activity before init");
            init_done=1;wait(arm_toggle);enabled=1;
        end
    endtask
    task automatic healthy;
        integer y,x,c;reg [31:0] a;
        begin
            wait(done||error);@(negedge clk);
            if(error||!done||busy||phase!==8'ha5||!capture_complete||!port_drained||requests!=1||arms!=1||frame_id!==1||capture_frame_id!==1||preprocess_version!==1||
                raw_base!==`VIDEO_FRAME_SLOT_A||preview_base!==(`VIDEO_FRAME_SLOT_A+`VIDEO_FRAME_PREVIEW_OFFSET)||input_base!==`VIDEO_INPUT_SLOT_A||commits!==1||completed_scans<2||underflows!==0||
                captured_pixels!==W*H||preview_pixels!==PW*PH||input_pixels!==IW*AH||source_crc!==raw_oracle||preview_crc!==preview_oracle||ddr_crc!==raw_oracle||preview_ddr_crc!==preview_oracle||
                input_ddr_crc!==input_oracle||input_checked_bytes!==3*IW*IH||fifo_peak!==37||read_stage!=3)
                $fatal(1,"engine healthy invariants code=%h phase=%h crc=%h/%h input=%h/%h",error_code,phase,ddr_crc,raw_oracle,input_ddr_crc,input_oracle);
            for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)for(c=0;c<3;c=c+1)begin
                a=raw_base-32'h80000000+y*RS+3*x+c;if(memory.byte_at(a)!==expected(0,y,x,c))$fatal(1,"raw native memory numerical oracle");
            end
            for(y=0;y<PH;y=y+1)for(x=0;x<PW;x=x+1)for(c=0;c<3;c=c+1)begin
                a=preview_base-32'h80000000+y*PS+3*x+c;if(memory.byte_at(a)!==expected(1,y,x,c))$fatal(1,"preview native memory numerical oracle");
            end
            for(c=0;c<3;c=c+1)for(y=0;y<IH;y=y+1)for(x=0;x<IW;x=x+1)begin
                a=input_base-32'h80000000+c*IP+y*IS+x;if(memory.byte_at(a)!==expected(2,y,x,2-c))$fatal(1,"BGR/padding native memory numerical oracle");
            end
            repeat(30)@(negedge clk);if(!done||requests!=1||arms!=1||commits!=1)$fatal(1,"auto-once result changed");tests=tests+1;
        end
    endtask
    task automatic failed(input integer code,input bit captured);
        reg [7:0] first;
        begin
            wait(error);@(negedge clk);first=error_code;
            if(first!==8'(code)||done||busy||phase!==8'he0||!cancel||capture_complete!==captured||commits!=0)$fatal(1,"engine fault expected=%h actual=%h",code,first);
            source_fault=1;overflow=1;repeat(80)@(negedge clk);
            if(!error||error_code!==first||done||commits!=0||capture_complete!==captured)$fatal(1,"first cause/sticky capture result");tests=tests+1;
            if(dut.capture.completion_valid&&!dut.capture.completion_ready)$fatal(1,"engine did not consume failed capture completion");
        end
    endtask
    reg [35:0] held_command;
    initial begin
        raw_oracle=oracle(0);preview_oracle=oracle(1);input_oracle=oracle(2);
        if($value$plusargs("CASE=%d",case_id))begin end
        restart();
        case(case_id)
            0:begin healthy();@(negedge clk);source_fault=1;wait(error);@(negedge clk);if(done||!capture_complete||error_code!==3)$fatal(1,"late source fault did not revoke done");end
            1:begin wait(sent>30);@(negedge clk);source_fault=1;failed(3,0);end
            2:begin wait(sent>30);@(negedge clk);overflow=1;failed(2,0);end
            3:begin pause_eof=1;wait(input_written_bytes==3*IW*IH&&raw_written_bytes==W*H*3&&preview_written_bytes==PW*PH*3);
                repeat(40)@(negedge clk);if(capture_complete||dut.arvalid||commits)$fatal(1,"missing EOF admitted readers");failed(7,0);end
            4:begin wait(capture_complete);@(negedge clk);read_xor=1;failed(8'h4b,1);end
            5:begin wait(capture_complete);@(negedge clk);bad_rid=1;failed(8'h86,1);end
            6:begin wait(capture_complete);@(negedge clk);bad_rlast=1;failed(8'h87,1);end
            7:begin wait(capture_complete);@(negedge clk);x_read=1;failed(8'h88,1);end
            8:begin wait(axi_awvalid);@(negedge clk);bad_wid=1;failed(8'h84,0);end
            9:begin wait(axi_awvalid);@(negedge clk);bad_wlast=1;failed(8'h85,0);end
            10:begin wait(capture_complete);@(negedge clk);hold_ar=1;wait(axi_arvalid);@(negedge clk);held_command={axi_araddr,axi_arlen,axi_aruser_id};source_fault=1;
                repeat(20)begin @(negedge clk);if(!axi_arvalid||{axi_araddr,axi_arlen,axi_aruser_id}!==held_command)$fatal(1,"fault withdrew native AR");end
                hold_ar=0;failed(3,1);wait(!axi_arvalid&&!memory.reading);end
            11:begin wait(capture_complete);@(negedge clk);hold_ar=1;wait(axi_arvalid);@(negedge clk);init_done=0;
                repeat(20)begin @(negedge clk);if(!axi_arvalid)$fatal(1,"init loss withdrew native AR");end hold_ar=0;failed(1,1);end
            12:begin healthy();@(negedge clk);init_done=0;wait(error);@(negedge clk);if(done||!capture_complete||error_code!==1)$fatal(1,"late init loss did not revoke done");end
            13:begin healthy();@(negedge clk);inject_r=1;wait(error);@(negedge clk);if(done||!capture_complete||error_code!==8'h83)$fatal(1,"late bridge fault did not revoke done");end
            14:begin wait(capture_complete);@(negedge clk);source_fault=1;failed(3,1);restart();healthy();end
            15:begin wait(sent>30);restart();healthy();end
            16:begin wait(capture_complete);wait(dut.input_reader.busy);@(negedge clk);read_xor=1;
                wait(dut.input_reader.result_valid);@(negedge clk);read_xor=0;
                if(!dut.input_reader.result_success)$fatal(1,"input checksum should not compare expected CRC");
                wait(done||error);if(error||input_ddr_crc===input_oracle)$fatal(1,"checksum did not expose changed input bytes");tests=tests+1;end
            17:begin @(negedge clk);hold_aw=1;wait(axi_awvalid);@(negedge clk);held_command={axi_awaddr,axi_awlen,axi_awuser_id};source_fault=1;
                repeat(20)begin @(negedge clk);if(!axi_awvalid||{axi_awaddr,axi_awlen,axi_awuser_id}!==held_command)$fatal(1,"source fault withdrew native AW");end
                hold_aw=0;failed(3,0);wait(!axi_awvalid&&!memory.writing);end
            18:begin @(negedge clk);hold_w=1;wait(memory.writing);@(negedge clk);source_fault=1;
                repeat(20)@(negedge clk);if(!memory.writing)$fatal(1,"source fault retired stalled native write");hold_w=0;failed(3,0);end
            19:begin wait(dut.input_reader.busy);@(negedge clk);source_fault=1;failed(3,1);end
            20:begin wait(dut.state==5);@(negedge clk);read_xor=1;failed(8'h4b,1);end
            21:begin wait(dut.state==9);@(negedge clk);source_fault=1;failed(3,1);end
            22:begin
                wait(dut.state==9);@(negedge clk);force dut.display.record_base=32'h87300001;
                failed(8'h69,1);
                if(dut.display.rejected_records!=1||dut.display.record_busy||dut.display.commits!=0||dut.display.error)
                    $fatal(1,"reject changed component fatal/record ownership");
                release dut.display.record_base;
            end
            23:begin
                wait(dut.state==9);@(negedge clk);hold_ar=1;
                wait(axi_arvalid&&dut.read_owner==2);@(negedge clk);
                held_command={axi_araddr,axi_arlen,axi_aruser_id};source_fault=1;
                repeat(20)begin @(negedge clk);if(!axi_arvalid||{axi_araddr,axi_arlen,axi_aruser_id}!==held_command)$fatal(1,"display fault withdrew native AR");end
                hold_ar=0;failed(3,1);wait(!axi_arvalid&&!memory.reading);
            end
            24:begin
                wait(dut.state==9);@(negedge clk);hold_r=1;
                wait(memory.reading&&dut.read_owner==2);@(negedge clk);source_fault=1;
                repeat(20)@(negedge clk);if(!memory.reading)$fatal(1,"display fault retired stalled native read");
                hold_r=0;failed(3,1);wait(!memory.reading);
            end
            default:$fatal(1,"unknown engine case");
        endcase
        $display("VIDEO_RAW_ENGINE_PASS W=%0d H=%0d PT=%0d PB=%0d case=%0d tests=%0d raw=%h preview=%h input=%h",W,H,PT,PB,case_id,tests,raw_oracle,preview_oracle,input_oracle);$finish;
    end
    initial begin repeat(TIMEOUT*3)@(posedge clk);$fatal(1,"three engine test timeout case=%0d",case_id);end
endmodule
`default_nettype wire
