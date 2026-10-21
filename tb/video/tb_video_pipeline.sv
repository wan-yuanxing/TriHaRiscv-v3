`timescale 1ns/1ps
`default_nettype none
// Live native C commands are read from stdin. No completion/commit/release
// can be injected by this protocol; every R/W sees the real control endpoint.
module tb_video_pipeline #(parameter integer H=600,CASE_ID=0,GAPS=1,QUOTA=4);
    localparam integer N=800*H,HT=1056,VT=H+28;
    reg clk_i=0,rst_ni=0,pixel_clk=0,pixel_reset_n=0,online=0,display_urgent=1;
    always #4 clk_i=~clk_i;initial begin #3;forever #12.5 pixel_clk=~pixel_clk;end
    reg source_fault=0,overflow=0;wire arm_toggle,cancel,capture_busy,capture_port_drained;
    reg src_valid=0;reg [47:0] src_data=0;wire src_ready;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire pixel_de=pixel_x<800&&pixel_y<H,pixel_hs=pixel_x>=840&&pixel_x<968,pixel_vs=pixel_y>=H+1&&pixel_y<H+5;
    wire pixel_frame_start=pixel_x==0&&pixel_y==0;
    wire [23:0] out_rgb;wire out_de,out_hs,out_vs,irq_capture,irq_display;
    wire [2:0] faults;wire [7:0] capture_code,display_code,memory_code;
    wire [31:0] raw_commits,raw_scans,underflows,raw_frame,read_grants,write_grants;
    wire [27:0] h_awaddr,h_araddr;wire [3:0] h_awlen,h_arlen,h_awid,h_arid,h_wid,h_rid;
    wire h_awvalid,h_arvalid,h_awready,h_arready,h_wready,h_rvalid,h_wlast,h_rlast;
    wire [255:0] h_wdata,h_rdata;wire [31:0] h_wstrb;
    // AXI-Lite declarations are inserted here by the test source preparation.
    reg [31:0] c_s_axi_awaddr_i=0,c_s_axi_wdata_i=0,c_s_axi_araddr_i=0;
    reg [2:0] c_s_axi_awprot_i=0,c_s_axi_arprot_i=0;reg [3:0] c_s_axi_wstrb_i=15;
    reg c_s_axi_awvalid_i=0,c_s_axi_wvalid_i=0,c_s_axi_bready_i=1,c_s_axi_arvalid_i=0,c_s_axi_rready_i=1;
    wire c_s_axi_awready_o,c_s_axi_wready_o,c_s_axi_bvalid_o,c_s_axi_arready_o,c_s_axi_rvalid_o;
    wire [1:0] c_s_axi_bresp_o,c_s_axi_rresp_o;wire [31:0] c_s_axi_rdata_o;
    reg [31:0] d_s_axi_awaddr_i=0,d_s_axi_wdata_i=0,d_s_axi_araddr_i=0;
    reg [2:0] d_s_axi_awprot_i=0,d_s_axi_arprot_i=0;reg [3:0] d_s_axi_wstrb_i=15;
    reg d_s_axi_awvalid_i=0,d_s_axi_wvalid_i=0,d_s_axi_bready_i=1,d_s_axi_arvalid_i=0,d_s_axi_rready_i=1;
    wire d_s_axi_awready_o,d_s_axi_wready_o,d_s_axi_bvalid_o,d_s_axi_arready_o,d_s_axi_rvalid_o;
    wire [1:0] d_s_axi_bresp_o,d_s_axi_rresp_o;wire [31:0] d_s_axi_rdata_o;
    video_pipeline #(.FRAME_HEIGHT(H),.MAX_READ_BURSTS(QUOTA),.TIMEOUT_CYCLES(10000000)) dut(.*);
    reg [95:0] slot_tags=0;integer written,read_beats,aw_commands,ar_commands;
    video_pipeline_memory #(.H(H),.GAPS(GAPS),.CORRUPT(CASE_ID==2)) memory(
        .clk(clk_i),.reset_n(rst_ni),.slot_tags(slot_tags),
        .h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),.h_rvalid(h_rvalid),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),.h_wlast(h_wlast),.h_rlast(h_rlast),
        .write_bytes(written),.read_beats(read_beats),.aw_commands(aw_commands),.ar_commands(ar_commands));
    function automatic [7:0] source_byte(input integer x,y,c,tag);
        source_byte=8'(37*x+19*y+83*c+((x*y)>>3)+tag*43+tag*x);
    endfunction
    reg [31:0] crcs[0:4];string crc_path;
    reg old_arm=0,enabled=0;integer sent=0;
    always @* begin
        src_valid=enabled&&sent<=N;
        if(sent<N)src_data={2'b00,(sent%800==799),21'd0,source_byte(sent%800,sent/800,0,int'(dut.capture_frame_id_i)),
            source_byte(sent%800,sent/800,1,int'(dut.capture_frame_id_i)),source_byte(sent%800,sent/800,2,int'(dut.capture_frame_id_i))};
        else src_data={2'b01,1'b0,(CASE_ID!=1),12'd37,crcs[dut.capture_frame_id_i]};
    end
    reg [2:0] display_lease=0,completed_slot=0;reg [31:0] slot_frames[0:2];
    integer capture_requests=0,completions=0,records=0,feedbacks=0,retires=0,overlap=0,held_release_capture=0,contested=0,ticks=0;
    integer outstanding_reads=0,read_slot=0;reg [31:0] visible_frame=0;
    always @(posedge clk_i)if(rst_ni)begin
        ticks=ticks+1;
        if(CASE_ID==0&&faults!=0)$fatal(1,"PIPELINE_FAULT sources=%b codes=%h/%h/%h",faults,capture_code,display_code,memory_code);
        if(old_arm!=arm_toggle)begin enabled<=1;sent<=0;end old_arm<=arm_toggle;
        if(src_valid&&src_ready)begin sent<=sent+1;if(sent==N)enabled<=0;end
        if(dut.capture_req_valid_o&&dut.capture_req_ready_i)begin
            if(display_lease[dut.capture_req_slot_o]||!dut.u_display.u_mmio.slot_free[dut.capture_req_slot_o])$fatal(1,"PIPELINE_REQUEST_REUSED_REFERENCE");
            slot_tags[dut.capture_req_slot_o*32+:32]=dut.capture_req_frame_id_o;
            slot_frames[dut.capture_req_slot_o]=dut.capture_req_frame_id_o;completed_slot[dut.capture_req_slot_o]=0;
            capture_requests=capture_requests+1;
        end
        if(dut.completion_valid_i&&dut.completion_ready_o)begin
            if(dut.completion_success_i)begin
                if(!capture_port_drained||dut.c_bvalid)$fatal(1,"PIPELINE_COMPLETION_BEFORE_B");
                completed_slot[dut.capture_slot_i]=1;completions=completions+1;
            end
        end
        if(dut.c_awvalid&&dut.c_awready&&(!dut.u_display.u_mmio.slot_free[dut.capture_slot_i]||display_lease[dut.capture_slot_i]))
            $fatal(1,"PIPELINE_CAPTURE_OVERWROTE_DISPLAY");
        if(dut.u_display.record_valid&&dut.u_display.record_ready)begin
            if(display_lease[dut.u_display.record_slot]||!completed_slot[dut.u_display.record_slot]||
                slot_frames[dut.u_display.record_slot]!==dut.u_display.record_frame)$fatal(1,"PIPELINE_PRESENT_BEFORE_QUALIFIED_CAPTURE");
            display_lease[dut.u_display.record_slot]=1;records=records+1;
        end
        if(dut.u_display.raw_commit_valid)visible_frame=dut.u_display.raw_commit_frame;
        if(dut.u_display.feedback_valid_i&&dut.u_display.feedback_ready_o)feedbacks=feedbacks+1;
        if(dut.u_display.retire_valid_i&&dut.u_display.retire_ready_o)retires=retires+1;
        if(dut.u_display.raw_release_valid&&dut.u_display.raw_release_ready)begin
            if(outstanding_reads!=0&&read_slot==dut.u_display.raw_release_slot)$fatal(1,"PIPELINE_RELEASE_WITH_READ");
            if(!display_lease[dut.u_display.raw_release_slot])$fatal(1,"PIPELINE_RELEASE_UNOWNED");
            display_lease[dut.u_display.raw_release_slot]=0;
        end
        if(dut.d_arvalid&&dut.d_arready)begin
            read_slot=int'((dut.d_araddr-32'h82000000)/32'h200000);
            if(outstanding_reads!=0||read_slot<0||read_slot>2||!display_lease[read_slot])$fatal(1,"PIPELINE_SCAN_READ_AFTER_RELEASE");
            outstanding_reads=int'(dut.d_arlen)+1;
        end
        if(dut.d_rvalid&&dut.d_rready)outstanding_reads=outstanding_reads-1;
        if(capture_busy&&raw_frame!=0)overlap=overlap+1;
        if(capture_busy&&dut.u_display.u_mmio.release_valid)held_release_capture=held_release_capture+1;
        if(dut.c_awvalid&&dut.d_arvalid)contested=contested+1;
        if(ticks%1000000==0)begin $display("PIPELINE_PROGRESS ticks=%0d requests=%0d completed=%0d records=%0d scans=%0d pixels=%0d",ticks,capture_requests,completions,records,raw_scans,checked_pixels);$fflush();end
    end
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==HT-1)begin pixel_x<=0;if(pixel_y==VT-1)pixel_y<=0;else pixel_y<=pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
    reg [10:0] x0=0,x1=0,y0=0,y1=0;reg de0=0,de1=0,hs0=0,hs1=0,vs0=0,vs1=0,armed=0;
    reg [23:0] raster[0:N-1],wanted;integer col,row;
    integer warmup=0,checked_pixels=0,rasters=0,checked_by_frame[0:4];
    always @(posedge pixel_clk)if(pixel_reset_n)begin
        x0<=pixel_x;x1<=x0;y0<=pixel_y;y1<=y0;de0<=pixel_de;de1<=de0;hs0<=pixel_hs;hs1<=hs0;vs0<=pixel_vs;vs1<=vs0;warmup=warmup+1;#1;
        if(warmup>4)begin
            if(x1==0&&y1==0)armed=1;
            if({out_de,out_hs,out_vs}!=={de1,hs1,vs1})$fatal(1,"PIPELINE_PIXEL_ALIGNMENT");
            if(de1)raster[y1*800+x1]=out_rgb;
            else if(out_rgb!==24'h101820)$fatal(1,"PIPELINE_BLANKING");
            // Actual commit returns to core after the pixel boundary. Verify
            // the saved complete raster once that identity has crossed back.
            if(armed&&x1==HT-1&&y1==VT-1)begin
                for(row=0;row<H;row=row+1)for(col=0;col<800;col=col+1)begin
                    wanted=visible_frame==0?24'h101820:{source_byte(col,row,0,int'(visible_frame)),source_byte(col,row,1,int'(visible_frame)),source_byte(col,row,2,int'(visible_frame))};
                    if(raster[row*800+col]!==wanted)$fatal(1,"PIPELINE_PIXEL_ORACLE frame=%0d x=%0d y=%0d got=%h wanted=%h",visible_frame,col,row,raster[row*800+col],wanted);
                end
                if(visible_frame!=0)begin
                    rasters=rasters+1;checked_pixels=checked_pixels+N;checked_by_frame[visible_frame]=checked_by_frame[visible_frame]+1;
                end
            end
        end
    end
    task automatic bus_read(input bit disp,input [31:0] off,output reg [31:0] value);
        begin
            @(negedge clk_i);
            if(disp)begin d_s_axi_araddr_i=32'h20011000+off;d_s_axi_arvalid_i=1;end
            else begin c_s_axi_araddr_i=32'h20012000+off;c_s_axi_arvalid_i=1;end
            do @(posedge clk_i);while(!(disp?d_s_axi_arready_o:c_s_axi_arready_o));
            @(negedge clk_i);if(disp)d_s_axi_arvalid_i=0;else c_s_axi_arvalid_i=0;
            while(!(disp?d_s_axi_rvalid_o:c_s_axi_rvalid_o))@(negedge clk_i);
            if((disp?d_s_axi_rresp_o:c_s_axi_rresp_o)!==0)$fatal(1,"PIPELINE_RPC_READ_ERROR");
            value=disp?d_s_axi_rdata_o:c_s_axi_rdata_o;@(negedge clk_i);
        end
    endtask
    task automatic bus_write(input bit disp,input [31:0] off,value,output reg [31:0] response);
        begin
            @(negedge clk_i);
            if(disp)begin d_s_axi_awaddr_i=32'h20011000+off;d_s_axi_wdata_i=value;d_s_axi_awvalid_i=1;d_s_axi_wvalid_i=1;end
            else begin c_s_axi_awaddr_i=32'h20012000+off;c_s_axi_wdata_i=value;c_s_axi_awvalid_i=1;c_s_axi_wvalid_i=1;end
            do @(posedge clk_i);while(!(disp?(d_s_axi_awready_o&&d_s_axi_wready_o):(c_s_axi_awready_o&&c_s_axi_wready_o)));
            @(negedge clk_i);if(disp)begin d_s_axi_awvalid_i=0;d_s_axi_wvalid_i=0;end else begin c_s_axi_awvalid_i=0;c_s_axi_wvalid_i=0;end
            while(!(disp?d_s_axi_bvalid_o:c_s_axi_bvalid_o))@(negedge clk_i);
            response={30'd0,(disp?d_s_axi_bresp_o:c_s_axi_bresp_o)};@(negedge clk_i);
        end
    endtask
    reg [7:0] op,target;reg [31:0] a,b,result;integer rc,loops,i,commands=0;
    initial begin
        for(i=0;i<5;i=i+1)checked_by_frame[i]=0;
        for(i=0;i<3;i=i+1)slot_frames[i]=0;
        if(!$value$plusargs("CRC=%s",crc_path))$fatal(1,"PIPELINE_CRC_REQUIRED");$readmemh(crc_path,crcs);
        repeat(8)@(negedge clk_i);rst_ni=1;pixel_reset_n=1;online=1;
        $display("PIPELINE_RPC_READY");$fflush();
        forever begin
            rc=$fscanf(32'h80000000,"%s %s %h %h",op,target,a,b);
            if(rc!=4)$fatal(1,"PIPELINE_RPC_FORMAT %0d",rc);commands=commands+1;result=0;
            case(op)
                "R":bus_read(target=="D",a,result);
                "W":bus_write(target=="D",a,b,result);
                "F":@(negedge clk_i);
                "A","S":begin
                    loops=0;
                    do begin
                        bus_read(target=="D",op=="S"?'hc:target=="D"?'h14:'h14,result);
                        if(op=="S"?(result&a)==b:(result&a)==a)loops=100000;
                        else begin repeat(1024)@(posedge clk_i);loops=loops+1;end
                    end while(loops<100000);
                    if(op=="S"?(result&a)!=b:(result&a)!=a)$fatal(1,"PIPELINE_RPC_WAIT_TIMEOUT %s %h",target,result);
                end
                "T":repeat(a)@(posedge clk_i);
                "V":begin
                    if(!capture_port_drained||dut.c_bvalid||memory.raw_by_frame[a]!=2400*H||memory.preview_by_frame[a]!=600*H||
                        memory.input_by_frame[a]!=960*(H*2/5+80))$fatal(1,"PIPELINE_NATIVE_COMPLETION_COUNTS frame=%0d",a);
                end
                "E":begin
                    if(a==0)begin
                        wait(checked_by_frame[4]>0);
                        if(H!=600||capture_requests!=4||completions!=4||records!=4||feedbacks!=5||retires!=3||
                            underflows!=0||faults!=0||overlap==0||held_release_capture==0||read_grants==0||write_grants==0)
                            $fatal(1,"PIPELINE_FINAL_COVERAGE requests=%0d completed=%0d records=%0d feedbacks=%0d retires=%0d overlap=%0d held=%0d",capture_requests,completions,records,feedbacks,retires,overlap,held_release_capture);
                    end else if(faults==0||completions!=0||records!=0||!capture_port_drained)$fatal(1,"PIPELINE_FAILURE_NOT_CONSERVATIVE");
                    $display("VIDEO_PIPELINE_RTL_PASS case=%0d requests=%0d captures=%0d records=%0d feedbacks=%0d retires=%0d bytes=%0d pixels=%0d rasters=%0d overlap=%0d held=%0d contested=%0d Rgrants=%0d Wgrants=%0d underflows=%0d commands=%0d",CASE_ID,capture_requests,completions,records,feedbacks,retires,written,checked_pixels,rasters,overlap,held_release_capture,contested,read_grants,write_grants,underflows,commands);
                    $display("RPC_REPLY 00000000");$fflush();$finish;
                end
                default:$fatal(1,"PIPELINE_RPC_UNKNOWN %s",op);
            endcase
            $display("RPC_REPLY %08x",result);$fflush();
        end
    end
    initial begin #2000000000;$fatal(1,"PIPELINE_WATCHDOG");end
endmodule
`default_nettype wire
