`timescale 1ns/1ps
// Explicit DIGITAL DDR substitute and forced candidate frontend metadata.
// Existing RX/I2C/PLL tests exercise real frontend behavior separately.
module tb_video_mode_board;
    reg mode_button_n=1;
    reg sys_clk=0,ref_clk_p=0,rst_in=0,pixclk_in=0;
    wire ref_clk_n=~ref_clk_p;
    reg hs_in=0,vs_in=0,de_in=0;
    reg [7:0] r_in=0,g_in=0,b_in=0;
    wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,uart_tx;
    wire rstn_out,hd_scl,pix_clk,hs_out,vs_out,de_out;
    wire [7:0] r_out,g_out,b_out;
    tri1 hd_sda;
    wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_ras_n,mem_cas_n,mem_we_n,mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    tri [3:0] mem_dqs,mem_dqs_n;
    tri [31:0] mem_dq;
    wire [3:0] mem_dm;
    always #18.5185185 sys_clk=~sys_clk;
    always #4 ref_clk_p=~ref_clk_p;
    always #12.5 pixclk_in=~pixclk_in;
    reg [7:0] pad_sequence=0;
    always @(posedge pixclk_in)begin
        #1;pad_sequence=pad_sequence+1'b1;
        r_in=pad_sequence;g_in=~pad_sequence;b_in=pad_sequence^8'h96;
        hs_in=pad_sequence[0];vs_in=pad_sequence[1];de_in=pad_sequence[2];
    end
    reg [26:0] expected_capture;
    reg capture_enabled;
    always @(negedge pixclk_in)begin
        capture_enabled=dut.rx_reset_n;
        expected_capture={hs_in,vs_in,de_in,r_in,g_in,b_in};
        #1;
        if(capture_enabled && dut.rx_reset_n && dut.rx_capture!==expected_capture)
            $fatal(1,"HDMI capture pad bundle must use falling PCLK");
    end
    `ifndef VIDEO_MODE_BOARD_DUT
    `define VIDEO_MODE_BOARD_DUT video_mode_board_top
    `endif
    `VIDEO_MODE_BOARD_DUT #(.STARTUP_CYCLES(8),.INIT_TIMEOUT_CYCLES(1000),
        .CORE_TIMEOUT_CYCLES(64),.HEARTBEAT_CYCLES(16),.UART_BAUD(2_700_000),
        .UART_INTERVAL_CYCLES(20),.FRAME_WIDTH(10),.FRAME_HEIGHT(10),.PAD_TOP(1),.PAD_BOTTOM(1),
        .CAPTURE_TIMEOUT_CYCLES(20000),.RX_WARMUP_FRAMES(2),.MODE_CLOCK_HZ(1000),.MODE_STABLE_MS(2)) dut(.*);
    defparam dut.clocks.STARTUP_CYCLES=8;
    reg protect_hdmi_link=0;
    initial begin wait(rstn_out);protect_hdmi_link=1;end
    always @(negedge rstn_out)
        if(protect_hdmi_link && dut.locked)$fatal(1,"KEY0 must preserve the running HDMI link");

    // Independent shortened OUTPUT raster for integration. Default-mode raster
    // and per-pixel visual oracle are exercised by the display component TB.
    reg [10:0] scan_x=0,scan_y=0;
    always @(posedge pix_clk)begin
        if(!dut.pixel_reset_n)begin scan_x<=0;scan_y<=0;end
        else if(scan_x==23)begin scan_x<=0;if(scan_y==15)scan_y<=0;else scan_y<=scan_y+1'b1;end
        else scan_x<=scan_x+1'b1;
    end
    wire scan_hs=scan_x>=18&&scan_x<21;
    wire scan_vs=scan_y>=13&&scan_y<15;
    wire scan_de=scan_x<10&&scan_y<10;
    wire scan_start=scan_x==0&&scan_y==0;
    initial begin
        force dut.display_x=scan_x;force dut.display_y=scan_y;
        force dut.hs=scan_hs;force dut.vs=scan_vs;
        force dut.de=scan_de;force dut.frame_start=scan_start;
    end
    reg source_variant=0;
    function automatic [23:0] source_pixel(input integer x,y);
        source_pixel={8'(8'h93^x),8'(8'h65^y),8'(8'hb7+x+y)} ^ (source_variant?24'h5a3cc3:24'd0);
    endfunction
    function automatic [7:0] oracle_byte(input integer branch,row,x,c);
        integer sx,sy,wx,wy,t,b,total;
        reg [23:0] p0,p1,p2,p3;
        begin
            if(branch==0)begin p0=source_pixel(x,row);oracle_byte=8'(p0>>(16-8*c));end
            else if(branch==1)begin
                p0=source_pixel(2*x,2*row);p1=source_pixel(2*x+1,2*row);
                p2=source_pixel(2*x,2*row+1);p3=source_pixel(2*x+1,2*row+1);
                total=int'(8'(p0>>(16-8*c)))+int'(8'(p1>>(16-8*c)))+int'(8'(p2>>(16-8*c)))+int'(8'(p3>>(16-8*c)));
                oracle_byte=8'((total+2)/4);
            end else if(row==0||row==5)oracle_byte=0;
            else begin
                sx=(5*x+1)/2;sy=(5*(row-1)+1)/2;wx=x%2==0?1:3;wy=(row-1)%2==0?1:3;
                p0=source_pixel(sx,sy);p1=source_pixel(sx+1,sy);p2=source_pixel(sx,sy+1);p3=source_pixel(sx+1,sy+1);
                t=wx*int'(8'(p0>>(16-8*c)))+(4-wx)*int'(8'(p1>>(16-8*c)));
                b=wx*int'(8'(p2>>(16-8*c)))+(4-wx)*int'(8'(p3>>(16-8*c)));
                oracle_byte=8'((wy*t/4+(4-wy)*b/4+2)/4);
            end
        end
    endfunction
    // MSB-first CRC independent of the RTL recurrence; BGR planar input.
    function automatic [31:0] crc_oracle(input integer branch);
        reg [31:0] crc,result_crc;reg [7:0] value;integer row,col,c,n,k;
        begin
            crc=32'hffffffff;
            if(branch<2)begin
                for(row=0;row<(branch==0?10:5);row=row+1)for(col=0;col<(branch==0?10:5);col=col+1)for(c=0;c<3;c=c+1)begin
                    value=oracle_byte(branch,row,col,c);
                    for(n=0;n<8;n=n+1)crc=(crc<<1)^((crc[31]^value[n])?32'h04c11db7:0);
                end
            end else begin
                for(c=2;c>=0;c=c-1)for(row=0;row<6;row=row+1)for(col=0;col<4;col=col+1)begin
                    value=oracle_byte(2,row,col,c);
                    for(n=0;n<8;n=n+1)crc=(crc<<1)^((crc[31]^value[n])?32'h04c11db7:0);
                end
            end
            for(k=0;k<32;k=k+1)result_crc[k]=~crc[31-k];crc_oracle=result_crc;
        end
    endfunction
    reg [24:0] pad_meta[0:15];
    wire [10:0] x2=pad_meta[15][24:14],y2=pad_meta[15][13:3];
    wire d2=pad_meta[15][2],h2=pad_meta[15][1],v2=pad_meta[15][0];
    integer delay_index,current_mode;
    integer mode_rasters[0:2];
    integer valid_pipe=0,checked_rasters=0,checked_pixels=0,rr,cc;
    reg [23:0] raster[0:99];
    reg [23:0] want_rgb;
    reg raster_started=0,raster_has_image=0;
    // A complete raster is checked after commit has crossed into the core.
    // This includes (0,0), before the commit notification reaches the core.
    always @(posedge pix_clk)begin
        if(!dut.display_pixel_reset_n)begin valid_pipe=0;raster_started=0;raster_has_image=0;end
        else begin
            pad_meta[0]<={scan_x,scan_y,scan_de,scan_hs,scan_vs};
            for(delay_index=1;delay_index<16;delay_index=delay_index+1)pad_meta[delay_index]<=pad_meta[delay_index-1];
            valid_pipe=valid_pipe+1;
            #1;
            if(valid_pipe>18)begin
                if({de_out,hs_out,vs_out}!=={d2,h2,v2})$fatal(1,"raw board pad sync latency");
                if(x2==0&&y2==0)begin raster_started=1;raster_has_image=dut.bist.commits==1;end
                if(d2)raster[y2*10+x2]={r_out,g_out,b_out};
                if(raster_started&&raster_has_image&&x2==23&&y2==15&&!dut.bist.error&&!dut.board_error)begin
                    for(rr=0;rr<10;rr=rr+1)for(cc=0;cc<10;cc=cc+1)begin
                        current_mode=dut.mode_state[4]?dut.mode_state[3:2]:0;
                        want_rgb=effect(current_mode,cc,rr);
                        if(raster[rr*10+cc]!==want_rgb)
                            $fatal(1,"raw board full image pixel x=%0d y=%0d got=%h expected=%h",cc,rr,raster[rr*10+cc],want_rgb);
                    end
                    checked_rasters=checked_rasters+1;checked_pixels=checked_pixels+100;mode_rasters[current_mode]=mode_rasters[current_mode]+1;
                end
            end
        end
    end
    function automatic [23:0] effect(input integer mode_value,x,y);
        integer left,top,right,bottom,sx,sy,r,g,b,a,c,v,px,py,k;
        reg hit,primary,point_hit;
        reg [23:0] back,result_rgb;
        begin
            back=source_pixel(x,y);result_rgb=back;hit=0;primary=0;point_hit=0;
            if(mode_value==1)begin
                // Independent sets for diagnostic boxes: [2,7)x[2,7) and [1,5)x[1,5).
                for(k=0;k<2;k=k+1)begin
                    left=k==0?2:1;top=k==0?2:1;right=k==0?7:5;bottom=k==0?7:5;
                    if(x>=left&&x<right&&y>=top&&y<bottom&&
                       (x-left<2||right-1-x<2||y-top<2||bottom-1-y<2))begin
                        hit=1;if(k==0)primary=1;
                    end
                end
                for(k=0;k<5;k=k+1)begin
                    px=k==2?5:(k==1||k==4?6:3);
                    py=k==2?5:(k>=3?6:3);
                    if(x>=px-2&&x<=px+2&&y>=py-2&&y<=py+2)point_hit=1;
                end
                if(point_hit)result_rgb=24'hffff00;
                else if(hit)result_rgb=primary?24'hff0000:24'h00ff00;
            end else if(mode_value==2&&x>=2&&x<7&&y>=2&&y<7)begin
                sx=(x-2)*256/5;sy=(y-2)*256/5;
                r=(37*sx+13*sy+17)&255;g=(sx^(sy*7))&255;
                b=(255-sx+11*sy)&255;a=(sx+3*sy)&255;
                result_rgb=0;
                for(c=0;c<3;c=c+1)begin
                    v=(a*(c==0?r:c==1?g:b)+(255-a)*((back>>(16-8*c))&255)+127)/255;
                    result_rgb=result_rgb|(v<<(16-8*c));
                end
            end
            effect=result_rgb;
        end
    endfunction
    task automatic press_mode;
        integer before_count;
        begin
            before_count=dut.mode_request_count;
            @(negedge dut.core_clk);mode_button_n=0;
            repeat(8)@(negedge dut.core_clk);
            mode_button_n=1;repeat(8)@(negedge dut.core_clk);
            check(dut.mode_request_count==before_count+1,"one MODE request per press");
        end
    endtask
    task automatic wait_mode(input integer value);
        integer count_wait;
        begin
            count_wait=0;
            while(!(dut.mode_state[4]&&dut.mode_state[3:2]==value&&!dut.mode_state[5]))begin
                @(negedge dut.core_clk);count_wait=count_wait+1;
                if(count_wait>10000)$fatal(1,"board MODE commit timeout");
            end
            check(!dut.mode_error,"board overlay/control error");
        end
    endtask
    task automatic exercise_modes;
        reg [31:0] raw_crc_before,input_crc_before;
        reg arm_before;
        integer before_box,before_avatar,before_raw;
        begin
            wait(dut.mode_asset_ready);wait_mode(0);
            raw_crc_before=dut.source_crc;input_crc_before=dut.input_ddr_crc;arm_before=dut.arm_toggle;
            before_box=mode_rasters[1];press_mode();wait_mode(1);wait(mode_rasters[1]>=before_box+2);
            before_avatar=mode_rasters[2];press_mode();wait_mode(2);wait(mode_rasters[2]>=before_avatar+2);
            before_raw=mode_rasters[0];press_mode();wait_mode(0);wait(mode_rasters[0]>=before_raw+2);
            check(dut.bist.commits==1&&dut.capture_frame_id==1&&dut.source_crc==raw_crc_before&&
                  dut.input_ddr_crc==input_crc_before&&!dut.bist_busy&&dut.arm_toggle==arm_before,
                  "MODE changed capture/raw identity or activity");
            check(rstn_out&&dut.ip_init_done&&!hdmi_int_led,"MODE restarted HDMI or DDR");
            $display("MODE_INDEPENDENCE_PASS raw_commits=%0d frame_id=%0d",dut.bist.commits,dut.capture_frame_id);
        end
    endtask
    reg cv=0,fb=0,fe=0,fg=0;
    reg [10:0] cx=0,cy=0;
    reg [23:0] crgb=0;
    integer i,j,passed=0;
    task automatic check(input bit ok,input string why);
        if(ok!==1'b1)$fatal(1,"RAW BOARD: %s",why);
    endtask
    task automatic reset_board;
        begin
            seen_kinds=0;source_variant=~source_variant;
            @(negedge sys_clk);rst_in=0;
            repeat(6)@(negedge sys_clk);rst_in=1;
            wait(dut.core_reset_n && dut.ingress_pixel_reset_n);
        end
    endtask
    task automatic send_source_frame(input bit startup_black);
        begin
            repeat(20)@(negedge pixclk_in);
            for(j=0;j<10;j=j+1)begin
                for(i=0;i<10;i=i+1)begin
                    @(negedge pixclk_in);cv=1;fb=(i==0&&j==0);cx=i;cy=j;
                    crgb=startup_black?24'd0:source_pixel(i,j);
                end
                @(negedge pixclk_in);cv=0;fb=0;
                repeat(8)@(negedge pixclk_in);
            end
            @(negedge pixclk_in);fe=1;fg=1;
            @(negedge pixclk_in);fe=0;fg=0;
        end
    endtask
    task automatic source_frame;
        begin
            send_source_frame(1);
            check(dut.ingress.pixel_count==0,"startup frames must not enter capture FIFO");
            send_source_frame(1);
            check(dut.ingress.pixel_count==0,"last startup frame must retire before capture");
            send_source_frame(0);
        end
    endtask
    task automatic receive_capture_packet;
        begin
            // Consume complete rotation; type8 is required in every healthy epoch.
            receive_packet(1);receive_packet(1);receive_packet(1);receive_packet(1);
            check(seen_kinds==4'b1111,"four coherent UART types required");
        end
    endtask
    initial begin
        force dut.tx_done=1;force dut.rx_done=1;force dut.rx_configured=1;
        force dut.tx_error=0;force dut.rx_error=0;force dut.mode_good_cfg=1;
        force dut.geometry_locked=1;force dut.timing_locked=1;
        force dut.candidate=cv;force dut.frame_begin=fb;force dut.frame_end=fe;force dut.frame_good=fg;
        force dut.candidate_x=cx;force dut.candidate_y=cy;force dut.candidate_rgb=crgb;
    end
    reg [7:0] packet[0:36];
    reg [7:0] value,checksum;
    integer n,k;
    reg [3:0] seen_kinds=0;
    task automatic receive_packet(input bit success);
        begin
            wait(!dut.uart.busy);
            for(n=0;n<37;n=n+1)begin
                @(negedge uart_tx);#555.555555;value=0;
                for(k=0;k<8;k=k+1)begin value[k]=uart_tx;#370.370370;end
                check(uart_tx===1'b1,"UART stop");packet[n]=value;
            end
            check({packet[0],packet[1],packet[2],packet[3]}==32'h54525631,"magic");
            checksum=0;for(n=0;n<36;n=n+1)checksum=checksum^packet[n];
            check(checksum==packet[36] && (packet[4]==6||packet[4]==9||packet[4]==8||packet[4]==10),"preview checksum/type");
            if(success)begin
                check(packet[5]==8'h75 && packet[6]==8'ha5 && packet[7]==0,"PASS healthy flags");
                seen_kinds[(packet[4]==10?3:packet[4]==9?1:packet[4]==8?2:0)]=1;
                if(packet[4]==6)begin
                    check({packet[11],packet[10],packet[9],packet[8]}==100,"raw pixel count");
                    check({packet[15],packet[14],packet[13],packet[12]}==25,"preview pixel count");
                    check({packet[19],packet[18],packet[17],packet[16]}==
                          {packet[23],packet[22],packet[21],packet[20]},"raw source/read CRC");
                    // Independent RGB byte oracle for the 10x10 source above;
                    // transport equality alone would also accept a black frame.
                    check({packet[19],packet[18],packet[17],packet[16]}==crc_oracle(0),
                          "captured source pattern after startup black frames");
                    check({packet[27],packet[26],packet[25],packet[24]}==
                          {packet[31],packet[30],packet[29],packet[28]},"preview source/read CRC");
                    check({packet[27],packet[26],packet[25],packet[24]}==crc_oracle(1),
                          "preview pattern independent oracle");
                end else if(packet[4]==9)begin
                    check({packet[11],packet[10],packet[9],packet[8]}==1,"display frame_id");
                    check({packet[15],packet[14],packet[13],packet[12]}==1,"single commit");
                    check({packet[19],packet[18],packet[17],packet[16]}>=2,"completed scans");
                    check({packet[23],packet[22],packet[21],packet[20]}==0,"no underflow");
                end else if(packet[4]==10)begin
                    check(packet[8][4]&&!packet[8][5],"mode active/actual feedback");
                    check(!packet[9][1]&&!packet[9][2]&&!packet[9][3]&&!packet[9][6]&&!packet[9][7],"mode faults clear");
                end else begin
                    check({packet[11],packet[10],packet[9],packet[8]}==1,"capture frame_id");
                    check({packet[15],packet[14],packet[13],packet[12]}==1,"preprocess version");
                    check({packet[19],packet[18],packet[17],packet[16]}==16,"active input pixels");
                    check({packet[23],packet[22],packet[21],packet[20]}==72,"input bytes written");
                    check({packet[27],packet[26],packet[25],packet[24]}==72,"input bytes checked");
                    check({packet[31],packet[30],packet[29],packet[28]}==crc_oracle(2),"independent padded BGR input CRC");
                end
            end else check(packet[5][3] && !packet[5][2],"error masks stale PASS");
        end
    endtask
    initial begin
        for(i=0;i<3;i=i+1)mode_rasters[i]=0;
        dut.I_ips_ddr_top.model_core_enable=0;dut.I_ips_ddr_top.model_init_enable=0;
        repeat(6)@(negedge sys_clk);rst_in=1;
        repeat(1200)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx,"no core/init independently reported");receive_packet(0);
        dut.I_ips_ddr_top.model_core_enable=1;dut.I_ips_ddr_top.model_init_enable=1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"capture/CRC with digital frontend");receive_capture_packet;passed=passed+1;exercise_modes();
        reset_board;source_frame;wait(dut.bist.capture_complete);
        @(negedge dut.core_clk);force dut.tx_error=1;
        repeat(120)@(negedge sys_clk);
        check(dut.board_error_code==8'he5&&dut.bist.error&&dut.bist.commits==0,
              "board health fault must reach engine before display submission");
        repeat(300)@(negedge sys_clk);
        check(dut.bist.commits==0&&!init_over_rx&&hdmi_int_led,"sticky board fault cannot commit later");
        force dut.tx_error=0;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"KEY0 recovers after board health fault");receive_capture_packet;passed=passed+1;
        force dut.locked=0;
        #1;check(dut.ingress_pixel_reset_n,"HDMI PLL loss must not clear FIFO ownership");
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.board_error_code==8'he6,"HDMI PLL loss masks PASS");
        release dut.locked;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led&&!init_over_rx,"HDMI fault remains sticky");
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"coordinated reset after HDMI fault");receive_capture_packet;passed=passed+1;
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        repeat(100)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.board_error_code==8'he4,"core stop masks prior PASS");
        dut.I_ips_ddr_top.model_core_enable=1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"KEY0 recaptures");receive_capture_packet;passed=passed+1;
        dut.I_ips_ddr_top.model_drop_lock=1;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led&&!init_over_rx,"DDR PLL loss masks prior PASS");
        dut.I_ips_ddr_top.model_drop_lock=0;
        reset_board;source_frame;wait(dut.bist.capture_complete);
        @(negedge dut.core_clk);force dut.source_fault=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.bist.error_code==3,"sticky source fault during CRC rejects display");
        receive_packet(0);release dut.source_fault;passed=passed+1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"reset recovers after source fault");receive_capture_packet;
        @(negedge dut.core_clk);force dut.source_fault=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.bist.error_code==3,"source fault revokes held PASS");
        release dut.source_fault;passed=passed+1;
        check(checked_rasters>=8&&checked_pixels>=800,"complete raw rasters before/after KEY0");
        $display("MODE_BOARD_PIXEL_ORACLE rasters=%0d pixels=%0d",checked_rasters,checked_pixels);
        $display("VIDEO_MODE_BOARD_PASS tests=%0d digital_only=1 forced_frontend=1 uart=1 reset=1",passed);$finish;
    end
    initial begin #15000000;$fatal(1,"HDMI capture board watchdog");end
endmodule
