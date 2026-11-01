`timescale 1ns/1ps
`default_nettype none
`include "test_config.vh"
// Production application and actual capture/B03/display. Only the camera input
// stimulus and the final native DDR byte store are simulation models.
module tb_face_system #(parameter integer BOARD_PROFILE=0,BOOT_LOAD=0,BOOT_ONLY=0);
    reg compute_clk_i=0;
    reg video_clk_i=0;
    reg pixel_clk=0;
    reg rst_ni=0;
    reg pixel_reset_n=0;
    reg init_done_i=0;
    reg model_sealed_i=0;
    reg boot_rx_valid_i=0;
    reg [7:0] boot_rx_data_i=0;
    reg boot_rx_error_i=0;
    wire boot_rx_ready_o;
    wire boot_tx_valid_o;
    wire [7:0] boot_tx_data_o;
    reg boot_tx_ready_i=1;
    wire model_sealed_o;
    reg [31:0] epoch_i=7;
    reg [31:0] addr_version_i=1;
    wire fault_o;
    wire recovery_request_o;
    wire npu_idle_o;
    wire compute_idle_o;
    wire ddr_idle_o;
    wire [7:0] npu_stage_o;
    wire [7:0] npu_op_o;
    wire [27:0] h_awaddr;
    wire [27:0] h_araddr;
    wire [3:0] h_awlen;
    wire [3:0] h_arlen;
    wire [3:0] h_awid;
    wire [3:0] h_arid;
    wire h_awvalid;
    wire h_arvalid;
    wire h_awready;
    wire h_arready;
    wire h_wready;
    reg h_rvalid=0;
    wire [255:0] h_wdata;
    wire [31:0] h_wstrb;
    reg [255:0] h_rdata=0;
    wire [3:0] h_wid;
    reg [3:0] h_rid=0;
    wire h_wlast;
    reg h_rlast=0;
    reg source_fault=0;
    reg overflow=0;
    reg src_valid=0;
    reg [47:0] src_data=0;
    wire src_ready;
    wire arm_toggle;
    wire cancel;
    wire capture_busy;
    wire capture_port_drained;
    reg [10:0] pixel_x=0;
    reg [10:0] pixel_y=0;
    reg pixel_de=0;
    reg pixel_hs=0;
    reg pixel_vs=0;
    reg pixel_frame_start=0;
    wire [23:0] out_rgb;
    wire out_de;
    wire out_hs;
    wire out_vs;
    wire [7:0] capture_code;
    wire [7:0] display_code;
    wire [31:0] raw_commits;
    wire [31:0] raw_scans;
    wire [31:0] underflows;
    wire [31:0] raw_frame;
    reg load_valid=0;
    wire load_ready;
    reg [31:0] load_base=0;
    reg [31:0] load_bytes=0;
    reg [31:0] load_asset_id=0;
    reg [31:0] load_generation=0;
    reg [31:0] expected_crc=0;
    wire result_valid;
    reg result_ready=1;
    wire result_success;
    wire [7:0] result_code;
    wire [31:0] result_asset_id;
    wire [31:0] result_generation;
    wire [31:0] checked_bytes;
    wire [31:0] crc;
    wire asset_ready;
    wire pixel_material_ready;
    wire [31:0] asset_id;
    wire [31:0] asset_generation;
    wire [31:0] words_written;
    wire raw_context_valid;
    wire [1:0] raw_slot;
    wire [31:0] raw_generation;
    wire [10:0] raw_x;
    wire [10:0] raw_y;
    wire [23:0] raw_rgb;
    wire raw_de;
    wire raw_hs;
    wire raw_vs;
    wire raw_sof;
    wire [10:0] out_x;
    wire [10:0] out_y;
    wire [31:0] out_frame;
    wire [31:0] out_generation;
    wire [31:0] out_seq;
    wire [1:0] out_slot;
    wire [1:0] out_mode;
    wire out_sof;
    wire out_box;
    wire out_point;
    wire out_avatar;
    wire out_fault;
    wire pixel_pending;
    wire [1:0] pending_mode;
    wire [1:0] pending_slot;
    wire [31:0] pending_frame;
    wire [31:0] pending_generation;
    wire [2:0] render_faults;
    wire [7:0] read_code;
    wire [7:0] material_code;
    wire [7:0] pixels_code;
    wire port_drained;
    wire [31:0] raw_grants;
    wire [31:0] asset_grants;
    wire asset_retire_valid;
    reg asset_retire_ready=1;
    wire [1:0] asset_retire_slot;
    wire [31:0] asset_retire_frame;
    wire [31:0] asset_retire_generation;
    wire [31:0] asset_retire_seq;
    wire [31:0] asset_retire_id;
    wire [31:0] asset_retire_generation_id;
    wire owner_error;
    wire link_error;
    wire raw_error;
    wire [7:0] link_code;
    wire [7:0] raw_code;
    always #(BOARD_PROFILE?4:5) compute_clk_i=~compute_clk_i;
    always #4 video_clk_i=~video_clk_i;
    always #12.5 pixel_clk=~pixel_clk;
    reg grs_n=0;GTP_GRS GRS_INST(.GRS_N(grs_n));
    triha_face_system #(.ENABLE_AVATAR(0),.ENABLE_MODEL_LOADER(BOOT_LOAD),
        .CACHE_ENABLE(BOARD_PROFILE?0:1),.MINIMAL_CONTROL_CPU(BOARD_PROFILE),
        .ENABLE_ROW_CACHE(BOARD_PROFILE?0:1),.ENABLE_MINIMAL_BOX(BOARD_PROFILE),
        .ENABLE_HARDWARE_POST(BOARD_PROFILE?0:1),.TRUSTED_MODEL(BOARD_PROFILE),
        .M_LANES(BOARD_PROFILE?2:16),.QUANTIZER_LANES(BOARD_PROFILE?1:2)) u_dut(
        .compute_clk_i(compute_clk_i),
        .video_clk_i(video_clk_i),
        .pixel_clk(pixel_clk),
        .rst_ni(rst_ni),
        .pixel_reset_n(pixel_reset_n),
        .init_done_i(init_done_i),
        .model_sealed_i(model_sealed_i),
        .boot_rx_valid_i(boot_rx_valid_i),
        .boot_rx_data_i(boot_rx_data_i),
        .boot_rx_error_i(boot_rx_error_i),
        .boot_rx_ready_o(boot_rx_ready_o),
        .boot_tx_valid_o(boot_tx_valid_o),
        .boot_tx_data_o(boot_tx_data_o),
        .boot_tx_ready_i(boot_tx_ready_i),
        .model_sealed_o(model_sealed_o),
        .epoch_i(epoch_i),
        .addr_version_i(addr_version_i),
        .fault_o(fault_o),
        .recovery_request_o(recovery_request_o),
        .npu_idle_o(npu_idle_o),
        .compute_idle_o(compute_idle_o),
        .ddr_idle_o(ddr_idle_o),
        .npu_stage_o(npu_stage_o),
        .npu_op_o(npu_op_o),
        .h_awaddr(h_awaddr),
        .h_araddr(h_araddr),
        .h_awlen(h_awlen),
        .h_arlen(h_arlen),
        .h_awid(h_awid),
        .h_arid(h_arid),
        .h_awvalid(h_awvalid),
        .h_arvalid(h_arvalid),
        .h_awready(h_awready),
        .h_arready(h_arready),
        .h_wready(h_wready),
        .h_rvalid(h_rvalid),
        .h_wdata(h_wdata),
        .h_wstrb(h_wstrb),
        .h_rdata(h_rdata),
        .h_wid(h_wid),
        .h_rid(h_rid),
        .h_wlast(h_wlast),
        .h_rlast(h_rlast),
        .source_fault(source_fault),
        .overflow(overflow),
        .src_valid(src_valid),
        .src_data(src_data),
        .src_ready(src_ready),
        .arm_toggle(arm_toggle),
        .cancel(cancel),
        .capture_busy(capture_busy),
        .capture_port_drained(capture_port_drained),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_de(pixel_de),
        .pixel_hs(pixel_hs),
        .pixel_vs(pixel_vs),
        .pixel_frame_start(pixel_frame_start),
        .out_rgb(out_rgb),
        .out_de(out_de),
        .out_hs(out_hs),
        .out_vs(out_vs),
        .capture_code(capture_code),
        .display_code(display_code),
        .raw_commits(raw_commits),
        .raw_scans(raw_scans),
        .underflows(underflows),
        .raw_frame(raw_frame),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_base(load_base),
        .load_bytes(load_bytes),
        .load_asset_id(load_asset_id),
        .load_generation(load_generation),
        .expected_crc(expected_crc),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_success(result_success),
        .result_code(result_code),
        .result_asset_id(result_asset_id),
        .result_generation(result_generation),
        .checked_bytes(checked_bytes),
        .crc(crc),
        .asset_ready(asset_ready),
        .pixel_material_ready(pixel_material_ready),
        .asset_id(asset_id),
        .asset_generation(asset_generation),
        .words_written(words_written),
        .raw_context_valid(raw_context_valid),
        .raw_slot(raw_slot),
        .raw_generation(raw_generation),
        .raw_x(raw_x),
        .raw_y(raw_y),
        .raw_rgb(raw_rgb),
        .raw_de(raw_de),
        .raw_hs(raw_hs),
        .raw_vs(raw_vs),
        .raw_sof(raw_sof),
        .out_x(out_x),
        .out_y(out_y),
        .out_frame(out_frame),
        .out_generation(out_generation),
        .out_seq(out_seq),
        .out_slot(out_slot),
        .out_mode(out_mode),
        .out_sof(out_sof),
        .out_box(out_box),
        .out_point(out_point),
        .out_avatar(out_avatar),
        .out_fault(out_fault),
        .pixel_pending(pixel_pending),
        .pending_mode(pending_mode),
        .pending_slot(pending_slot),
        .pending_frame(pending_frame),
        .pending_generation(pending_generation),
        .render_faults(render_faults),
        .read_code(read_code),
        .material_code(material_code),
        .pixels_code(pixels_code),
        .port_drained(port_drained),
        .raw_grants(raw_grants),
        .asset_grants(asset_grants),
        .asset_retire_valid(asset_retire_valid),
        .asset_retire_ready(asset_retire_ready),
        .asset_retire_slot(asset_retire_slot),
        .asset_retire_frame(asset_retire_frame),
        .asset_retire_generation(asset_retire_generation),
        .asset_retire_seq(asset_retire_seq),
        .asset_retire_id(asset_retire_id),
        .asset_retire_generation_id(asset_retire_generation_id),
        .owner_error(owner_error),
        .link_error(link_error),
        .raw_error(raw_error),
        .link_code(link_code),
        .raw_code(raw_code)    );
    wire ddr_clk=video_clk_i,ddr_rst=u_dut.video_reset_n,init_done=init_done_i;
    localparam [31:0] MEMORY_BASE=32'h82000000,MEMORY_END=32'h83800000;
    reg [255:0] memory[0:786431];reg [31:0] covered[0:294911];
    reg [7:0] golden_heads[0:26367];
    reg [23:0] source_rgb[0:479999];
    reg [7:0] source_input[0:307199];
    function automatic [7:0] capture_byte(input integer slot,input [31:0] address);
        reg [31:0] local_address;begin
            local_address=address-(32'h82000000+slot*32'h200000);
            if(local_address<1440000)capture_byte=source_rgb[local_address/3][(2-local_address%3)*8+:8];
            else begin
                local_address=address-(32'h82800000+slot*32'h50000);
                capture_byte=local_address<307200?source_input[local_address]:8'd0;
            end
        end
    endfunction
    reg writing=0,reading=0;reg [31:0] wa=0,ra=0;reg [3:0] wid=0,rid=0;
    integer ticks=0,wi=0,wn=0,ri=0,rn=0,lane,aw_count=0,ar_count=0,w_count=0,r_count=0;
    wire [31:0] aw_byte=32'h80000000+{2'b0,h_awaddr,2'b0};
    wire [31:0] ar_byte=32'h80000000+{2'b0,h_araddr,2'b0};
    assign h_awready=ddr_rst&&init_done&&!writing&&!reading&&!h_rvalid&&(ticks%5!=1);
    assign h_arready=ddr_rst&&init_done&&!writing&&!reading&&!h_rvalid&& !h_awvalid&&(ticks%7!=2);
    assign h_wready=ddr_rst&&writing&&(ticks%4!=0);
    assign h_wid=wid;assign h_wlast=wi==wn-1;
    function automatic integer capture_slot_of(input [31:0] address);
        integer s;reg [31:0] raw,inp;begin
            capture_slot_of=-1;
            for(s=0;s<3;s=s+1)begin
                raw=32'h82000000+s*32'h200000;inp=32'h82800000+s*32'h50000;
                if((address>=raw&&address<raw+1440000)||(address>=raw+32'h160000&&address<raw+32'h160000+360000)||
                    (address>=inp&&address<inp+307200))capture_slot_of=s;
            end
        end
    endfunction
    integer written[0:2],slot_frame[0:2],write_slot,offset;reg [2:0] display_lease=0,captured=0;
    always @(posedge ddr_clk)begin
        if(!ddr_rst)begin writing<=0;reading<=0;h_rvalid<=0;wi<=0;ri<=0;ticks<=0;end
        else begin
            ticks<=ticks+1;h_rvalid<=0;
            if(h_awvalid&&h_awready)begin
                if(aw_byte<MEMORY_BASE||{1'b0,aw_byte}+((h_awlen+1)<<5)>{1'b0,MEMORY_END})$fatal(1,"FACE_SYSTEM native write range %h",aw_byte);
                writing<=1;wa<=aw_byte;wid<=h_awid;wi<=0;wn<=h_awlen+1;aw_count<=aw_count+1;
            end
            if(writing&&h_wready)begin
                for(lane=0;lane<32;lane=lane+1)if(h_wstrb[lane])begin
                    memory[(wa-MEMORY_BASE)/32][lane*8+:8]<=h_wdata[lane*8+:8];
                    write_slot=capture_slot_of(wa+lane);
                    if(write_slot>=0)begin
                        if(display_lease[write_slot]||!slot_frame[write_slot]||h_wdata[lane*8+:8]!==capture_byte(write_slot,wa+lane))$fatal(1,"FACE_SYSTEM capture ownership/data slot=%0d address=%h",write_slot,wa+lane);
                        offset=(wa+lane-MEMORY_BASE)/32;
                        if(covered[offset][lane])$fatal(1,"FACE_SYSTEM duplicate capture byte %h",wa+lane);
                        covered[offset][lane]=1;written[write_slot]=written[write_slot]+1;
                    end else if(wa+lane<32'h82900000)$fatal(1,"FACE_SYSTEM write in capture guard gap %h",wa+lane);
                end
                wa<=wa+32;wi<=wi+1;w_count<=w_count+1;if(wi==wn-1)writing<=0;
            end
            if(h_arvalid&&h_arready)begin
                if(ar_byte<MEMORY_BASE||{1'b0,ar_byte}+((h_arlen+1)<<5)>{1'b0,MEMORY_END})$fatal(1,"FACE_SYSTEM native read range %h",ar_byte);
                reading<=1;ra<=ar_byte;rid<=h_arid;ri<=0;rn<=h_arlen+1;ar_count<=ar_count+1;
            end
            if(reading&&ticks%3!=0)begin
                h_rdata<=memory[(ra-MEMORY_BASE)/32];h_rid<=rid;h_rvalid<=1;h_rlast<=ri==rn-1;
                ra<=ra+32;ri<=ri+1;r_count<=r_count+1;if(ri==rn-1)reading<=0;
            end
        end
    end
    function automatic [7:0] byte_at(input [31:0] address);
        byte_at=memory[(address-MEMORY_BASE)/32][(address%32)*8+:8];
    endfunction
    function automatic [31:0] word_at(input [31:0] address);
        word_at={byte_at(address+3),byte_at(address+2),byte_at(address+1),byte_at(address)};
    endfunction
    function automatic [31:0] cpu_word(input [31:0] address);
        cpu_word=u_dut.u_compute.u_cpu.u_router.u_sram.memory[(address-32'h10000)/8][address[2]*32+:32];
    endfunction
    integer fd,uploads,index,count,preload_words;reg [31:0] load_address;string leaf;reg [31:0] seal[0:0];
    reg [255:0] boot_words[0:49151];
    reg [7:0] boot_reply[0:11];integer boot_ack_count=0,boot_offset,boot_byte,boot_check,boot_packets=0;
    reg [31:0] boot_crc;reg boot_done=0;
    function automatic [31:0] boot_crc_byte(input [31:0] c,input [7:0] value);
        integer n;reg [31:0] v;begin
            v=c^{24'd0,value};for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;
            boot_crc_byte=v;
        end
    endfunction
    task boot_send_byte(input [7:0] value);begin
        @(negedge video_clk_i);boot_rx_data_i=value;boot_rx_valid_i=1;
        @(posedge video_clk_i);while(!boot_rx_ready_o)@(posedge video_clk_i);
        @(negedge video_clk_i);boot_rx_valid_i=0;
    end endtask
    task boot_send_word(input [31:0] value);integer n;begin
        for(n=0;n<4;n=n+1)boot_send_byte(value[n*8+:8]);
    end endtask
    always @(posedge video_clk_i)if(BOOT_LOAD&&rst_ni&&boot_tx_valid_o&&boot_tx_ready_i)begin
        if(boot_ack_count>=12)$fatal(1,"FACE_BOOT reply overflow");
        boot_reply[boot_ack_count]<=boot_tx_data_o;boot_ack_count<=boot_ack_count+1;
    end
    initial begin
        $readmemh("source_rgb.hex",source_rgb);$readmemh("source_input.hex",source_input);
        for(index=0;index<786432;index=index+1)memory[index]=0;
        for(index=0;index<294912;index=index+1)begin memory[index]={32{8'ha5}};covered[index]=0;end
        for(index=0;index<3;index=index+1)begin written[index]=0;slot_frame[index]=0;end
        fd=$fopen("uploads.txt","r");if(!fd)$fatal(1,"FACE_SYSTEM uploads missing");
        count=$fscanf(fd,"%d\n",uploads);if(count!=1||uploads!=6)$fatal(1,"FACE_SYSTEM uploads count");
        for(index=0;index<uploads;index=index+1)begin
            count=$fscanf(fd,"%h %d %s\n",load_address,preload_words,leaf);
            if(count!=3||load_address<MEMORY_BASE||load_address+preload_words>MEMORY_END||load_address%32||preload_words%32)$fatal(1,"FACE_SYSTEM preload geometry");
            if(!BOOT_LOAD)$readmemh(leaf,memory,(load_address-MEMORY_BASE)/32,(load_address-MEMORY_BASE+preload_words)/32-1);
        end
        $fclose(fd);$readmemh("heads_golden.hex",golden_heads);$readmemh("preload_verified.txt",seal);
        if(seal[0]!==32'h54524948)$fatal(1,"FACE_SYSTEM asset SHA receipt missing");
        model_sealed_i=!BOOT_LOAD;grs_n=1;
        repeat(12)@(negedge video_clk_i);rst_ni=1;pixel_reset_n=1;
        repeat(12)@(negedge video_clk_i);init_done_i=1;
        if(BOOT_LOAD)begin
            fd=$fopen("uploads.txt","r");count=$fscanf(fd,"%d\n",uploads);
            for(index=0;index<uploads;index=index+1)begin
                count=$fscanf(fd,"%h %d %s\n",load_address,preload_words,leaf);
                if(count!=3||preload_words>1572864||preload_words%256)$fatal(1,"FACE_BOOT segment geometry");
                $readmemh(leaf,boot_words,0,preload_words/32-1);
                for(boot_offset=0;boot_offset<preload_words;boot_offset=boot_offset+256)begin
                    if(model_sealed_o)$fatal(1,"FACE_BOOT premature seal");
                    boot_crc=32'hffffffff;
                    for(boot_byte=0;boot_byte<256;boot_byte=boot_byte+1)
                        boot_crc=boot_crc_byte(boot_crc,boot_words[(boot_offset+boot_byte)/32][boot_byte%32*8+:8]);
                    boot_send_word(32'h31424854);boot_send_word(index);boot_send_word(boot_offset);boot_send_word(~boot_crc);
                    for(boot_byte=0;boot_byte<256;boot_byte=boot_byte+1)
                        boot_send_byte(boot_words[(boot_offset+boot_byte)/32][boot_byte%32*8+:8]);
                    wait(boot_ack_count==12);@(negedge video_clk_i);
                    if({boot_reply[3],boot_reply[2],boot_reply[1],boot_reply[0]}!==32'h31414854||boot_reply[4]!==0||
                        boot_reply[6]!==0||boot_reply[7]!==0||boot_reply[5]!==((boot_offset+256==preload_words)?index+1:index)||
                        {boot_reply[11],boot_reply[10],boot_reply[9],boot_reply[8]}!==((boot_offset+256==preload_words)?0:boot_offset+256))
                        $fatal(1,"FACE_BOOT ACK segment=%0d offset=%0d status=%0d",index,boot_offset,boot_reply[4]);
                    boot_ack_count=0;boot_packets=boot_packets+1;
                end
                for(boot_check=0;boot_check<preload_words/32;boot_check=boot_check+1)
                    if(memory[(load_address-MEMORY_BASE)/32+boot_check]!==boot_words[boot_check])$fatal(1,"FACE_BOOT DDR bytes differ");
                $display("FACE_BOOT_SEGMENT segment=%0d bytes=%0d packets=%0d",index,preload_words,boot_packets);
            end
            $fclose(fd);
            if(!model_sealed_o||writing||reading||h_rvalid)$fatal(1,"FACE_BOOT seal/debt");
            boot_done=1;
        end
    end
    always @*begin
        pixel_de=pixel_x<800&&pixel_y<600;pixel_hs=pixel_x>=840&&pixel_x<968;
        pixel_vs=pixel_y>=601&&pixel_y<605;pixel_frame_start=pixel_x==0&&pixel_y==0;
    end
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==1055)begin pixel_x<=0;if(pixel_y==627)pixel_y<=0;else pixel_y<=pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
    reg old_arm=0,source_enabled=0;integer sent=0;
    always @*begin
        src_valid=source_enabled&&sent<=480000;
        src_data=sent<480000?{2'b00,(sent%800==799),21'd0,source_rgb[sent]}:{2'b01,1'b0,1'b1,12'd37,`SOURCE_CRC};
    end
    `define V u_dut.u_video
    `define D u_dut.u_video.g_compact.u_display
    `define F u_dut.u_compute.u_npu.u_service.u_frame
    integer requests=0,completions=0,records=0,retires=0,feedbacks=0,reuses=0,j,s,addr;
    always @(posedge video_clk_i)if(u_dut.video_reset_n)begin
        if(BOOT_LOAD&&!model_sealed_o&&(`V.capture_req_valid_o||u_dut.u_compute.u_npu.start_valid))
            $fatal(1,"FACE_BOOT application admitted before model seal");
        old_arm<=arm_toggle;
        if(old_arm!=arm_toggle)begin source_enabled<=1;sent<=0;end
        if(src_valid&&src_ready)begin sent<=sent+1;if(sent==480000)source_enabled<=0;end
        if(`V.capture_req_valid_o&&`V.capture_req_ready_i)begin
            s=`V.capture_req_slot_o;
            if(display_lease[s]||!u_dut.u_video.g_compact.u_display.g_full_mmio.u_mmio.slot_free[s])$fatal(1,"FACE_SYSTEM reused display reference slot=%0d",s);
            if(slot_frame[s])begin
                if(cpu_word(`APP_BASE+`OFF_RELEASES)==0)$fatal(1,"FACE_SYSTEM reuse before CPU release ACK");
                reuses=reuses+1;
            end
            slot_frame[s]=`V.capture_req_frame_id_o;captured[s]=0;written[s]=0;requests=requests+1;
            for(j=0;j<65536;j=j+1)covered[s*65536+j]=0;
            for(j=0;j<10240;j=j+1)covered[(32'h800000+s*32'h50000)/32+j]=0;
            $display("FACE_SYSTEM_CAPTURE_START slot=%0d frame=%0d",s,slot_frame[s]);
        end
        if(`V.completion_valid_i&&`V.completion_ready_o)begin
            s=`V.capture_slot_i;
            // Minimal BOX omits the 400x300 preview branch; RAW and NCHW remain.
            if(!`V.completion_success_i||!capture_port_drained||written[s]!=(1747200+(BOARD_PROFILE?0:360000)))$fatal(1,"FACE_SYSTEM capture completion code=%0d bytes=%0d",`V.completion_code_i,written[s]);
            for(j=0;j<307200;j=j+1)if(byte_at(32'h82800000+s*32'h50000+j)!==source_input[j])$fatal(1,"FACE_SYSTEM input byte slot=%0d index=%0d",s,j);
            captured[s]=1;completions=completions+1;$display("FACE_SYSTEM_CAPTURE_DONE slot=%0d frame=%0d bytes=%0d",s,slot_frame[s],written[s]);
        end
        if(`D.record_valid&&`D.record_ready)begin
            s=`D.record_slot;
            if(display_lease[s]||!captured[s]||slot_frame[s]!=`D.record_frame)$fatal(1,"FACE_SYSTEM present identity");
            if(`D.cmd_mode!=1||`D.cmd_data[9*32+:32]!=(`EXPECTED_FACES?17:3)||`D.cmd_data[12*32+:32]!=`EXPECTED_FACES||`D.cmd_data[13*32+:32]!=0)
                $fatal(1,"FACE_SYSTEM BOX flags/mask/primary");
            if(`EXPECTED_FACES)begin
                if(`D.cmd_data[32*32+:32]!=(`EXPECTED_X|(`EXPECTED_Y<<16))||
                    `D.cmd_data[33*32+:32]!=((`EXPECTED_X+`EXPECTED_W)|((`EXPECTED_Y+`EXPECTED_H)<<16))||
                    `D.cmd_data[34*32+:4032]!=0)$fatal(1,"FACE_SYSTEM nonempty BOX coordinates");
            end else if(`D.cmd_data[32*32+:4096]!=0)$fatal(1,"FACE_SYSTEM empty BOX data");
            display_lease[s]=1;records=records+1;$display("FACE_SYSTEM_PRESENT frame=%0d slot=%0d",`D.record_frame,s);
        end
        if(`D.feedback_valid&&`D.feedback_ready)feedbacks=feedbacks+1;
        if(`D.retire_valid&&`D.retire_ready)begin
            s=`D.retire_slot;if(!display_lease[s])$fatal(1,"FACE_SYSTEM retire without reference");
            display_lease[s]=0;retires=retires+1;$display("FACE_SYSTEM_RELEASE frame=%0d slot=%0d",`D.retire_frame,s);
        end
    end
    integer pixels[0:2];reg [2:0] full_pixels=0;reg [2:0] pixel_open=0;integer f;
    reg expected_edge;reg [23:0] expected_rgb;
    initial begin pixels[0]=0;pixels[1]=0;pixels[2]=0;end
    always @(posedge pixel_clk)if(pixel_reset_n)begin
        #1;
        if(out_de&&out_mode==1&&out_frame>=1&&out_frame<=2)begin
            f=out_frame;
            expected_edge=`EXPECTED_FACES&&out_x>=`EXPECTED_X&&out_x<`EXPECTED_X+`EXPECTED_W&&
                out_y>=`EXPECTED_Y&&out_y<`EXPECTED_Y+`EXPECTED_H&&
                (out_x<`EXPECTED_X+2||out_x>=`EXPECTED_X+`EXPECTED_W-2||out_y<`EXPECTED_Y+2||out_y>=`EXPECTED_Y+`EXPECTED_H-2);
            expected_rgb=expected_edge?24'hff0000:source_rgb[out_y*800+out_x];
            if(out_rgb!==expected_rgb||out_box!==expected_edge||out_point||out_avatar||out_fault||out_generation!=7||out_slot!=f-1||out_seq!=f)$fatal(1,"FACE_SYSTEM pixel data/identity frame=%0d xy=%0d,%0d actual=%h expected=%h",f,out_x,out_y,out_rgb,expected_rgb);
            if(out_sof)begin pixels[f]=0;pixel_open[f]=1;end
            if(pixel_open[f])begin
                if(out_x!=pixels[f]%800||out_y!=pixels[f]/800)$fatal(1,"FACE_SYSTEM pixel coordinate sequence");
                pixels[f]=pixels[f]+1;
                if(pixels[f]==480000)begin full_pixels[f]=1;pixel_open[f]=0;end
            end
        end
    end
    integer cycles=0,starts=0,model_ops=0,preflights=0,verified=0,cpu_reads=0;
    integer head_file,result_file,b;reg [31:0] base,software_results;
    task automatic verify_result(input integer number);
        begin
            if(model_ops<(number+1)*79||preflights<(number+1)*79)$fatal(1,"FACE_SYSTEM result before real graph");
            base=32'h82900000+number*32'h40000;
            head_file=$fopen($sformatf("heads_actual_%0d.hex",number),"w");
            for(b=0;b<26368;b=b+1)begin
                if(byte_at(base+b)!==golden_heads[b])$fatal(1,"FACE_SYSTEM HEAD mismatch frame=%0d byte=%0d",number+1,b);
                $fdisplay(head_file,"%02x",byte_at(base+b));
            end
            $fclose(head_file);result_file=$fopen($sformatf("result_actual_%0d.hex",number),"w");
            for(b=0;b<128;b=b+1)begin
                if(BOARD_PROFILE&&byte_at(base+32'h8000+b)!==0)$fatal(1,"CPU-post wrote hardware result region");
                $fdisplay(result_file,"%02x",byte_at(base+32'h8000+b));
            end
            if(BOARD_PROFILE&&(cpu_word(`APP_BASE+`OFF_RESULT_VALID)!=1||
               cpu_word(`APP_BASE+`OFF_RESULT_FACES)!=`EXPECTED_FACES||cpu_word(`APP_BASE+`OFF_RESULT_DISPLAY)!=`EXPECTED_FACES))
                $fatal(1,"CPU-post frame result mismatch");
            $fclose(result_file);verified=verified+1;$display("FACE_SYSTEM_NPU_CPU_RESULT frame=%0d reads=%0d cycles=%0d",number+1,cpu_reads,cycles);
        end
    endtask
    always @(posedge compute_clk_i)begin
        cycles<=cycles+1;
        if(cycles>100000000)$fatal(1,"FACE_SYSTEM watchdog stage=%0d op=%0d",npu_stage_o,npu_op_o);
        if(u_dut.compute_reset_n)begin
            if(BOARD_PROFILE&&`F.select_post)$fatal(1,"board profile enabled hardware POST");
            if(fault_o||out_fault||underflows)$fatal(1,"FACE_SYSTEM hardware fault cap=%h display=%h read=%h raw=%h link=%h stage=%0d op=%0d",capture_code,display_code,read_code,raw_code,link_code,npu_stage_o,npu_op_o);
            if(cpu_word(`FACE_AVATAR_RUN_STATUS)>1)$fatal(1,"FACE_SYSTEM firmware stopped status=%h cause=%h pc=%h val=%h",cpu_word(`FACE_AVATAR_RUN_STATUS),cpu_word(`FACE_AVATAR_TRAP_CAUSE),cpu_word(`FACE_AVATAR_TRAP_PC),cpu_word(`FACE_AVATAR_TRAP_VALUE));
            if(u_dut.u_compute.u_npu.start_valid&&u_dut.u_compute.u_npu.start_ready)begin starts=starts+1;$display("FACE_SYSTEM_NPU_START frame=%0d",starts);end
            if(`F.l_start&&`F.l_start_ready&&`F.l_preflight)preflights=preflights+1;
            if(`F.l_done&&`F.l_done_ready&&!`F.l_preflight)begin
                if(`F.l_status)$fatal(1,"FACE_SYSTEM model operator error");
                model_ops=model_ops+1;if(`F.l_done_opid%10==0)$display("FACE_SYSTEM_OP frame=%0d op=%0d cycles=%0d",starts,`F.l_done_opid,cycles);
            end
            if(u_dut.u_compute.cpu_arvalid&&u_dut.u_compute.cpu_arready)cpu_reads=cpu_reads+1;
            software_results=cpu_word(`APP_BASE+`OFF_RESULTS);
            if(BOOT_ONLY&&boot_done&&requests>=1)begin
                if(cpu_word(`FACE_AVATAR_RUN_STATUS)!==1||fault_o)$fatal(1,"FACE_BOOT CPU did not enter application");
                $display("FACE_BOOT_PASS segments=6 packets=%0d application_admitted=1 cycles=%0d",boot_packets,cycles);$finish;
            end
            if(verified<2&&software_results>verified)verify_result(verified);
            if(cycles%1000000==0)$display("FACE_SYSTEM_PROGRESS cycles=%0d captures=%0d results=%0d records=%0d commits=%0d releases=%0d",cycles,completions,verified,records,cpu_word(`APP_BASE+`OFF_DISPLAY_COMMITS),cpu_word(`APP_BASE+`OFF_RELEASES));
            if(verified==2&&full_pixels[1]&&full_pixels[2]&&retires>=1&&reuses>=1&&
                cpu_word(`APP_BASE+`OFF_RELEASES)>=1&&cpu_word(`APP_BASE+`OFF_DISPLAY_COMMITS)>=2)begin
                if(requests<4||completions<3||cpu_reads<64||cpu_word(`APP_BASE+`OFF_NO_FREE)==0)$fatal(1,"FACE_SYSTEM missing long-inference/three-slot coverage");
                $display("FACE_SYSTEM_PASS captures=%0d requests=%0d results=%0d records=%0d commits=%0d releases=%0d reuses=%0d full_pixel_frames=2 cpu_reads=%0d nativeAW=%0d nativeAR=%0d cycles=%0d",completions,requests,verified,records,cpu_word(`APP_BASE+`OFF_DISPLAY_COMMITS),retires,reuses,cpu_reads,aw_count,ar_count,cycles);
                $finish;
            end
        end
    end
    `undef V
    `undef D
    `undef F
endmodule
`default_nettype wire
