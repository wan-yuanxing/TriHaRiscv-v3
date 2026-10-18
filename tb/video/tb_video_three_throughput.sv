`timescale 1ns/1ps
`default_nettype none
// Candidate frontend at the real 800x600/1056x628 40MHz rate. The ingress,
// FIFO, register, three-branch pipeline and HMIC bridge are actual RTL.
// Native timing is a delayed DIGITAL model, not physical DDR training.
module tb_video_three_throughput;
    reg clk=0,pixel_clk=0,reset_n=0,init_done=0,req_valid=0;
    always #4 clk=~clk;
    initial begin #1;forever #12.5 pixel_clk=~pixel_clk;end
    reg pixel_valid=0,frame_start=0,frame_end=0,frame_good=0;
    reg [23:0] pixel_rgb=0;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire arm_toggle,cancel,source_fault,overflow,fifo_valid,fifo_ready,m_valid,m_ready;
    wire [47:0] fifo_data,m_data;
    video_capture_ingress ingress(
        .pixel_clk(pixel_clk),.pixel_reset_n(reset_n),.core_clk(clk),.core_reset_n(reset_n),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .frame_start(frame_start),.frame_end(frame_end),.frame_good(frame_good),
        .mode_good(1'b1),.rx_ready(1'b1),.arm_toggle(arm_toggle),.cancel(cancel),
        .m_valid(fifo_valid),.m_data(fifo_data),.m_ready(fifo_ready),.source_fault(source_fault),.overflow(overflow));
    video_stream_register #(.DATA_WIDTH(48)) stream_register(
        .clk(clk),.reset_n(reset_n),.s_valid(fifo_valid),.s_ready(fifo_ready),.s_data(fifo_data),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data));
    wire req_ready,busy,port_drained,accepted_valid,completion_valid,completion_success,error;
    wire [7:0] completion_code,error_code;
    wire [31:0] frame_id,preprocess_version,raw_base,preview_base,input_base;
    wire [1:0] slot;
    wire [31:0] captured_pixels,preview_pixels,input_pixels,source_crc,preview_crc,fifo_peak;
    wire [31:0] raw_written_bytes,preview_written_bytes,input_written_bytes;
    wire [3:0] awid,bid;wire [31:0] awaddr;wire [7:0] awlen;wire [2:0] awsize;
    wire [1:0] awburst,bresp;wire awvalid,awready,wlast,wvalid,wready,bvalid,bready;
    wire [127:0] wdata;wire [15:0] wstrb;
    video_three_branch_capture capture(
        .clk(clk),.reset_n(reset_n),.init_done(init_done),.abort(1'b0),.req_valid(req_valid),.req_ready(req_ready),
        .req_slot(2'd0),.req_frame_id(32'd1),.req_preprocess_version(32'd1),
        .m_valid(m_valid),.m_data(m_data),.m_ready(m_ready),.source_fault(source_fault),.overflow(overflow),
        .arm_toggle(arm_toggle),.cancel(cancel),.busy(busy),.port_drained(port_drained),
        .accepted_valid(accepted_valid),.accepted_ready(1'b1),.completion_valid(completion_valid),
        .completion_ready(1'b0),.completion_success(completion_success),.completion_code(completion_code),
        .error(error),.error_code(error_code),.frame_id(frame_id),.preprocess_version(preprocess_version),
        .raw_base(raw_base),.preview_base(preview_base),.input_base(input_base),.slot(slot),
        .captured_pixels(captured_pixels),.preview_pixels(preview_pixels),.input_pixels(input_pixels),
        .source_crc(source_crc),.preview_crc(preview_crc),.fifo_peak(fifo_peak),
        .raw_written_bytes(raw_written_bytes),.preview_written_bytes(preview_written_bytes),.input_written_bytes(input_written_bytes),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
    wire [27:0] h_awaddr;wire [3:0] h_awlen,h_awid;
    wire h_awvalid,h_awready,h_wready,h_wlast;wire [3:0] h_wid;
    wire [255:0] h_wdata;wire [31:0] h_wstrb;
    wire [27:0] h_araddr;wire [3:0] h_arlen,h_arid;wire h_arvalid,h_arready;
    reg [255:0] h_rdata=0;reg [3:0] h_rid=0;reg h_rlast=0,h_rvalid=0;
    wire bridge_fault;wire [7:0] bridge_code;
    axi128_hmic256 bridge(
        .clk(clk),.rst_n(reset_n),.init_done(init_done),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .arid(4'd0),.araddr(32'd0),.arlen(8'd0),.arsize(3'd4),.arburst(2'b01),.arvalid(1'b0),.arready(),
        .rid(),.rdata(),.rresp(),.rlast(),.rvalid(),.rready(1'b1),.fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(h_awaddr),.h_awlen(h_awlen),.h_awid(h_awid),.h_awvalid(h_awvalid),.h_awready(h_awready),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_wready(h_wready),.h_wid(h_wid),.h_wlast(h_wlast),
        .h_araddr(h_araddr),.h_arlen(h_arlen),.h_arid(h_arid),.h_arvalid(h_arvalid),.h_arready(h_arready),
        .h_rdata(h_rdata),.h_rid(h_rid),.h_rlast(h_rlast),.h_rvalid(h_rvalid));
    function automatic [7:0] source_byte(input integer x,y,c);
        source_byte=8'((37*x+19*y+83*c+((x*y)>>3))%256);
    endfunction
    function automatic [7:0] expected(input integer branch,offset);
        integer x,y,c,dx,dy,total,sx,sy,wx,wy,upper,lower;
        begin
            if(branch==0)expected=source_byte((offset%2400)/3,offset/2400,offset%3);
            else if(branch==1)begin
                x=(offset%1200)/3;y=offset/1200;c=offset%3;total=0;
                for(dy=0;dy<2;dy=dy+1)for(dx=0;dx<2;dx=dx+1)
                    total=total+int'(source_byte(2*x+dx,2*y+dy,c));
                expected=8'((total+2)/4);
            end else begin
                c=2-offset/102400;y=(offset%102400)/320;x=offset%320;
                if(y<40||y>=280)expected=0;
                else begin
                    y=y-40;sx=(10*x+3)/4;sy=(10*y+3)/4;
                    wx=x%2==0?3:1;wy=y%2==0?3:1;
                    upper=(4-wx)*int'(source_byte(sx,sy,c))+wx*int'(source_byte(sx+1,sy,c));
                    lower=(4-wx)*int'(source_byte(sx,sy+1,c))+wx*int'(source_byte(sx+1,sy+1,c));
                    expected=8'(((4-wy)*upper/4+wy*lower/4+2)/4);
                end
            end
        end
    endfunction
    integer ticks=0,beat_index=0,write_length=0,native_commands=0;
    integer raw_count=0,preview_count=0,input_count=0,accepted_count=0;
    reg writing=0,reading=0;reg [27:0] native_address,read_address;reg [3:0] native_id,read_id;
    integer read_index=0,read_length=0;
    wire accept_aw=h_awvalid&&h_awready;
    assign h_awready=reset_n&&!writing&&!reading&&ticks%5==1;
    assign h_arready=reset_n&&!writing&&!reading&&ticks%7==2;
    assign h_wready=reset_n&&(writing||accept_aw)&&(!writing||ticks%4!=0);
    assign h_wid=writing?native_id:h_awid;
    assign h_wlast=writing?(beat_index==write_length):(h_awlen==0);
    reg seen[0:2107199];reg [7:0] memory[0:2107199];
    function automatic [255:0] stored(input [27:0] address);
        integer l,idx;reg [31:0] a;
        begin
            stored=0;
            for(l=0;l<32;l=l+1)begin
                a=32'h80000000+({4'd0,address}<<2)+l;idx=-1;
                if(a>=32'h82000000&&a<32'h82000000+1440000)idx=a-32'h82000000;
                else if(a>=32'h82160000&&a<32'h82160000+360000)idx=1440000+a-32'h82160000;
                else if(a>=32'h82800000&&a<32'h82800000+307200)idx=1800000+a-32'h82800000;
                if(idx>=0)if(seen[idx]===1'b1)stored[l*8+:8]=memory[idx];
            end
        end
    endfunction
    integer lane,branch,offset,index;
    reg [31:0] byte_address;
    always @(posedge clk)begin
        if(reset_n)begin
            ticks<=ticks+1;
            h_rvalid<=0;
            if(h_arvalid&&h_arready)begin
                reading<=1;read_address<=h_araddr;read_length<=h_arlen;read_id<=h_arid;read_index<=0;
            end
            if(reading&&ticks%3!=0)begin
                h_rvalid<=1;h_rdata<=stored(read_address+read_index*8);h_rid<=read_id;
                h_rlast<=read_index==read_length;
                if(read_index==read_length)reading<=0;else read_index<=read_index+1;
            end
            if(accepted_valid)accepted_count=accepted_count+1;
            if(error||source_fault||overflow||bridge_fault)begin
                $display("RATE_DIAG source=%0d accepted=%0d preview=%0d input=%0d fifo=%0d ready=%b/%b/%b nchw_state=%0d row=%0d plane=%0d written=%0d",
                    ingress.pixel_count,captured_pixels,preview_pixels,input_pixels,ingress.fifo_occupancy,
                    capture.raw_pixel_ready,capture.preview_input_ready,capture.input_input_ready,
                    capture.u_input_dma.state,capture.u_input_dma.row_index,capture.u_input_dma.plane,capture.u_input_dma.written_bytes);
                $fatal(1,"40MHz capture fault core=%h bridge=%h overflow=%b",error_code,bridge_code,overflow);
            end
            if(accept_aw)begin
                if(h_awaddr[2:0]!=0||h_awaddr[9:0]+(h_awlen+1)*8>1024)
                    $fatal(1,"native alignment/page violation");
                native_address<=h_awaddr;native_id<=h_awid;write_length<=h_awlen;
                beat_index<=0;writing<=1;native_commands=native_commands+1;
            end
            if(h_wready)begin
                for(lane=0;lane<32;lane=lane+1)if(h_wstrb[lane])begin
                    byte_address=32'h80000000+({4'd0,(writing?native_address:h_awaddr)}<<2)+
                        (writing?beat_index:0)*32+lane;
                    if(byte_address>=32'h82000000&&byte_address<32'h82000000+1440000)begin
                        branch=0;offset=byte_address-32'h82000000;index=offset;raw_count=raw_count+1;
                    end else if(byte_address>=32'h82160000&&byte_address<32'h82160000+360000)begin
                        branch=1;offset=byte_address-32'h82160000;index=1440000+offset;preview_count=preview_count+1;
                    end else if(byte_address>=32'h82800000&&byte_address<32'h82800000+307200)begin
                        branch=2;offset=byte_address-32'h82800000;index=1800000+offset;input_count=input_count+1;
                    end else $fatal(1,"write outside allocated valid planes %h",byte_address);
                    if(seen[index]===1'b1)$fatal(1,"duplicate native byte %h",byte_address);
                    seen[index]=1;
                    memory[index]=h_wdata[lane*8+:8];
                    if(h_wdata[lane*8+:8]!==expected(branch,offset))
                        $fatal(1,"native byte oracle mismatch branch=%0d offset=%0d",branch,offset);
                end
                if(h_wlast)begin writing<=0;beat_index<=0;end
                else begin writing<=1;beat_index<=writing?beat_index+1:1;end
            end
        end
    end
    integer x,y,fd;
    string dump;
    initial begin
        repeat(8)@(negedge clk);reset_n=1;init_done=1;req_valid=1;
        @(posedge clk);@(negedge clk);req_valid=0;
        wait(arm_toggle);repeat(20)@(negedge pixel_clk);
        for(y=0;y<628;y=y+1)for(x=0;x<1056;x=x+1)begin
            @(negedge pixel_clk);pixel_x=x;pixel_y=y;
            pixel_valid=x<800&&y<600;frame_start=x==0&&y==0;
            frame_end=x==0&&y==600;frame_good=frame_end;
            pixel_rgb={source_byte(x,y,0),source_byte(x,y,1),source_byte(x,y,2)};
        end
        @(negedge pixel_clk);pixel_valid=0;frame_start=0;frame_end=0;frame_good=0;
        wait(completion_valid);@(negedge clk);
        if(!completion_success||completion_code!=0||!port_drained||accepted_count!=1||
            captured_pixels!=480000||preview_pixels!=120000||input_pixels!=76800||
            raw_written_bytes!=1440000||preview_written_bytes!=360000||input_written_bytes!=307200||
            raw_count!=1440000||preview_count!=360000||input_count!=307200||fifo_peak<1||fifo_peak>2048)
            $fatal(1,"full physical-rate geometry/retirement/coverage failure");
        if($value$plusargs("DUMP=%s",dump))begin
            fd=$fopen(dump,"w");if(!fd)$fatal(1,"dump open failed");
            for(x=0;x<307200;x=x+1)$fdisplay(fd,"%02h",memory[1800000+x]);$fclose(fd);
        end
        $display("VIDEO_THREE_THROUGHPUT_PASS raw=%0d preview=%0d input=%0d fifo_peak=%0d native_commands=%0d digital_native=1",
            raw_count,preview_count,input_count,fifo_peak,native_commands);$finish;
    end
    initial begin #60000000;$fatal(1,"physical-rate simulation watchdog");end
endmodule
`default_nettype wire
