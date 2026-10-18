`timescale 1ns/1ps
`default_nettype none
module tb_video_rx_image_probe;
    localparam integer W=8,H=6;
    reg clk=0,reset_n=0,pixel_valid=0,frame_start=0,frame_end=0,frame_good=0;
    reg [10:0] x=0,y=0;
    reg [23:0] rgb=0;
    wire [31:0] frame_sequence,pixels,nonzero,x_bounds,y_bounds,crc;
    wire [31:0] crc_frame128,crc_frame129,last_change_frame,crc_before_change;
    wire [23:0] q0,q1,q2,q3;
    video_rx_image_probe #(.WIDTH(W),.HEIGHT(H)) dut(.*);
    always #5 clk=~clk;
    integer tests=0,px,py,nz,mnx,mxx,mny,mxy,n;
    reg [31:0] oracle_crc;
    reg [23:0] expected_q[0:3];
    reg [23:0] value;
    function automatic [31:0] byte_crc(input [31:0] seed,input [7:0] v);
        integer b;reg [31:0] c;
        begin
            c=seed;
            for(b=0;b<8;b=b+1)begin
                if(c[0]^v[b])c=(c>>1)^32'hedb88320;else c=c>>1;
            end
            byte_crc=c;
        end
    endfunction
    function automatic [23:0] pattern(input integer col,row,kind);
        begin
            case(kind)
                0:pattern=0;
                1:pattern={8'(col*21+7),8'(row*33+9),8'(col+row*W+1)};
                2:pattern=(col>=1&&col<=4&&row>=2&&row<=3)?24'h123456:24'd0;
                3:pattern=(col==W-1&&row==H-1)?24'hffffff:24'd0;
                default:pattern=24'h010203;
            endcase
        end
    endfunction
    task automatic restart;
        begin
            @(negedge clk);reset_n=0;pixel_valid=0;frame_start=0;frame_end=0;frame_good=0;
            repeat(3)@(negedge clk);reset_n=1;#1;
            if(frame_sequence!==0||pixels!==0||nonzero!==0||crc!==0)
                $fatal(1,"probe reset did not clear published epoch");
        end
    endtask
    task automatic frame(input integer kind,input bit good,input integer omit);
        reg [31:0] old_sequence;
        begin
            old_sequence=frame_sequence;nz=0;mnx=65535;mny=65535;mxx=0;mxy=0;oracle_crc=32'hffffffff;
            for(px=0;px<4;px=px+1)expected_q[px]=0;
            for(py=0;py<H;py=py+1)for(px=0;px<W;px=px+1)begin
                value=pattern(px,py,kind);
                @(negedge clk);pixel_valid=!(omit&&px==3&&py==2);
                frame_start=px==0&&py==0;frame_end=0;frame_good=0;x=px;y=py;rgb=value;
                if(pixel_valid)begin
                    oracle_crc=byte_crc(byte_crc(byte_crc(oracle_crc,value[23:16]),value[15:8]),value[7:0]);
                    if(value!=0)begin
                        nz=nz+1;if(px<mnx)mnx=px;if(px>mxx)mxx=px;if(py<mny)mny=py;if(py>mxy)mxy=py;
                    end
                end
                if(px==W/4&&py==H/4)expected_q[0]=value;
                if(px==3*W/4&&py==H/4)expected_q[1]=value;
                if(px==W/4&&py==3*H/4)expected_q[2]=value;
                if(px==3*W/4&&py==3*H/4)expected_q[3]=value;
                @(posedge clk);#1;
                if(frame_sequence!==old_sequence)$fatal(1,"partial frame published");
            end
            @(negedge clk);pixel_valid=0;frame_start=0;frame_end=1;frame_good=good;
            @(posedge clk);#1;
            if(good&&!omit)begin
                if(nz==0)begin mxx=65535;mxy=65535;end
                if(frame_sequence!==old_sequence+1||pixels!==W*H||nonzero!==nz||
                   x_bounds!=={16'(mxx),16'(mnx)}||y_bounds!=={16'(mxy),16'(mny)}||
                   crc!==(oracle_crc^32'hffffffff)||q0!==expected_q[0]||q1!==expected_q[1]||
                   q2!==expected_q[2]||q3!==expected_q[3])
                    $fatal(1,"probe result kind=%0d seq=%0d pixels=%0d nz=%0d bbox=%h/%h crc=%h expected=%h",
                        kind,frame_sequence,pixels,nonzero,x_bounds,y_bounds,crc,oracle_crc^32'hffffffff);
            end else if(frame_sequence!==old_sequence)$fatal(1,"bad or short frame published");
            @(negedge clk);frame_end=0;frame_good=0;tests=tests+1;
        end
    endtask
    initial begin
        restart();frame(1,1,0);frame(0,1,0);frame(2,1,0);frame(3,1,0);
        frame(1,0,0);frame(1,1,1);frame(2,1,0);
        @(negedge clk);frame_start=1;pixel_valid=1;x=0;y=0;rgb=24'habcdef;
        repeat(3)@(negedge clk);restart();
        @(negedge clk);frame_end=1;frame_good=1;
        @(posedge clk);#1;if(frame_sequence!==0)$fatal(1,"EOF after reset published stale frame");
        @(negedge clk);frame_end=0;frame_good=0;
        frame(1,1,0);
        restart();
        for(n=0;n<128;n=n+1)frame(0,1,0);
        if(crc_frame128!==crc||last_change_frame!==1)$fatal(1,"128-frame history missing");
        frame(1,1,0);
        if(crc_frame129!==crc||last_change_frame!==129||crc_before_change!==crc_frame128)
            $fatal(1,"129-frame content change history missing");
        frame(1,1,0);
        if(last_change_frame!==129)$fatal(1,"unchanged content advanced history");
        $display("VIDEO_RX_IMAGE_PROBE_PASS tests=%0d black_accepted=1 partial_rejected=1 crc_oracle=1",tests);
        $finish;
    end
    initial begin #100000;$fatal(1,"probe watchdog");end
endmodule
`default_nettype wire
