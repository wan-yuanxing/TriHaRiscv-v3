`timescale 1ns/1ps
`default_nettype none
// Independent address-derived byte-memory BFM and output raster oracle.
module tb_preview_display;
    parameter integer FULL = 0;
    parameter integer INVALID_WINDOW = 0;
    localparam integer W = FULL ? 400 : 8;
    localparam integer H = FULL ? 300 : 4;
    localparam integer WY = INVALID_WINDOW ? 2147483647 : (FULL ? 150 : 3);
    localparam integer HA = W*2;
    localparam integer VA = FULL ? 600 : 12;
    localparam integer HT = FULL ? 1056 : 30;
    localparam integer VT = FULL ? 628 : 18;
    localparam integer STRIDE = ((W*3+15)/16)*16;
    localparam [31:0] BASE_A = 32'h87300ff0;
    localparam [31:0] BASE_B = 32'h87460000;
    reg core_clk=0, pixel_clk=0;
    integer core_half=4;
    real pixel_half=12.5;
    always begin #(core_half) core_clk=~core_clk; end
    initial begin #3; forever begin #(pixel_half) pixel_clk=~pixel_clk; end end
    reg core_reset_n=0,pixel_reset_n=0,ddr_ready=1;
    reg record_valid=0;
    wire record_ready;
    reg [31:0] record_base=BASE_A,record_stride=STRIDE,record_frame_id=17;
    reg [1:0] record_slot=1;
    wire commit_valid,release_valid;
    reg commit_ready=1,release_ready=1;
    wire [31:0] commit_frame_id,release_frame_id;
    wire [1:0] commit_slot,release_slot;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire pixel_de=(pixel_x<HA && pixel_y<VA);
    wire pixel_hs=(pixel_x>=HA+2 && pixel_x<HA+4);
    wire pixel_vs=(pixel_y>=VA+1 && pixel_y<VA+3);
    wire pixel_frame_start=(pixel_x==0 && pixel_y==0);
    wire [23:0] out_rgb;
    wire out_de,out_hs,out_vs,error;
    wire [7:0] error_code;
    wire [31:0] commits,completed_scans,read_lines,underflows,frame_id;
    wire [3:0] m_axi_arid;
    wire [31:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid,m_axi_rready;
    reg m_axi_arready=0,m_axi_rvalid=0,m_axi_rlast=0;
    reg [3:0] m_axi_rid=0;
    reg [1:0] m_axi_rresp=0;
    reg [127:0] m_axi_rdata=0;
    preview_display #(.PREVIEW_WIDTH(W),.PREVIEW_HEIGHT(H),.WINDOW_Y(WY),
        .TIMEOUT_CYCLES(FULL ? 100000 : 10000)) dut (.*);

    function automatic [7:0] memory_byte(input [31:0] address);
        memory_byte=(address*13) ^ (address>>8) ^ (address>>16);
    endfunction
    function automatic [23:0] expected_pixel(input [31:0] base,input integer row,input integer col);
        reg [31:0] addr;
        begin
            addr=base+row*STRIDE+col*3;
            expected_pixel={memory_byte(addr),memory_byte(addr+1),memory_byte(addr+2)};
        end
    endfunction
    integer cycle=0,burst_count=0,beat_count=0,beats_left=0;
    integer mode=0,delay_until=0,inject_burst=0,error_age=0;
    reg [31:0] read_address=0;
    reg bfm_active=0;
    integer lane;
    always @(posedge core_clk) begin
        cycle<=cycle+1;
        if (!core_reset_n) begin
            m_axi_arready<=0;m_axi_rvalid<=0;bfm_active<=0;beats_left<=0;
            burst_count<=0;beat_count<=0;
        end else begin
            m_axi_arready<=!bfm_active && (cycle%7!=2) && (mode!=13 || cycle>12000);
            if (m_axi_arvalid && m_axi_arready) begin
                if (bfm_active) $fatal(1,"more than one outstanding read");
                if(seen_releases!=0 && m_axi_araddr>=BASE_A && m_axi_araddr<BASE_A+H*STRIDE)
                    $fatal(1,"old slot accessed after its release/reuse boundary");
                if (m_axi_arid!==0 || m_axi_arsize!==4 || m_axi_arburst!==1 ||
                    m_axi_araddr[3:0]!==0 || m_axi_arlen>15 ||
                    ({1'b0,m_axi_araddr[11:0]}+(m_axi_arlen+1)*16)>4096)
                    $fatal(1,"invalid AXI read advertisement");
                read_address<=m_axi_araddr; beats_left<=m_axi_arlen+1;
                bfm_active<=1;burst_count<=burst_count+1;
                m_axi_arready<=0;
                if (mode==1 && burst_count==0) delay_until<=cycle+HT*VT*pixel_half/core_half*2;
                if (mode==2 && burst_count==2) delay_until<=cycle+HT*VT*pixel_half/core_half*4;
                if (mode==10 && burst_count==0) delay_until<=cycle+12000;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid<=0;read_address<=read_address+16;
                beats_left<=beats_left-1;beat_count<=beat_count+1;
                if (beats_left==1) bfm_active<=0;
            end
            if (bfm_active && !m_axi_rvalid && cycle>=delay_until && cycle%5!=1) begin
                m_axi_rvalid<=1;m_axi_rid<=0;m_axi_rresp<=0;m_axi_rlast<=(beats_left==1);
                for (lane=0;lane<16;lane=lane+1) m_axi_rdata[lane*8+:8]<=memory_byte(read_address+lane);
                if (burst_count==inject_burst) begin
                    case(mode)
                    3:m_axi_rid<=4'h3;
                    4:m_axi_rresp<=2'b10;
                    5:m_axi_rlast<=~(beats_left==1);
                    6:m_axi_rlast<=1'bx;
                    7:m_axi_rid<=4'bx;
                    8:m_axi_rresp<=2'bx;
                    default:begin end
                    endcase
                end
            end
        end
    end
    always @(posedge pixel_clk) begin
        if (!pixel_reset_n) begin pixel_x<=0;pixel_y<=0; end
        else if (pixel_x==HT-1) begin
            pixel_x<=0;
            if (pixel_y==VT-1) pixel_y<=0;else pixel_y<=pixel_y+1'b1;
        end else pixel_x<=pixel_x+1'b1;
    end
    integer expected_id=0,seen_commits=0,seen_releases=0,checked_pixels=0;
    integer scan_starts=0,first_commit_scan=0,warmup=0;
    reg [31:0] expected_base=0;
    reg second_accepted=0;
    reg ar_stalled=0;
    reg [48:0] held_ar=0;
    reg commit_stalled=0,release_stalled=0;
    reg [33:0] held_commit=0,held_release=0;
    always @(posedge core_clk) begin
        if (core_reset_n) begin
            if(commit_stalled && (!commit_valid || {commit_frame_id,commit_slot}!==held_commit))
                $fatal(1,"published commit changed while consumer stalled");
            if(release_stalled && (!release_valid || {release_frame_id,release_slot}!==held_release))
                $fatal(1,"published release changed while consumer stalled");
            commit_stalled<=commit_valid && !commit_ready;
            release_stalled<=release_valid && !release_ready;
            held_commit<={commit_frame_id,commit_slot};held_release<={release_frame_id,release_slot};
            if(ar_stalled && {m_axi_arid,m_axi_araddr,m_axi_arlen,m_axi_arsize,m_axi_arburst}!==held_ar)
                $fatal(1,"AR payload changed while stalled");
            if(ar_stalled && !m_axi_arvalid) $fatal(1,"ARVALID withdrawn while stalled");
            ar_stalled<=m_axi_arvalid && !m_axi_arready;
            held_ar<={m_axi_arid,m_axi_araddr,m_axi_arlen,m_axi_arsize,m_axi_arburst};
            // Publication reports the already committed pixel-domain record.
            // Its consumer can defer the event handshake for whole rasters.
            if(commit_valid) begin
                expected_id<=commit_frame_id;
                expected_base<=(commit_frame_id==17 ? BASE_A : BASE_B);
            end
            if(commit_valid && commit_ready) begin
                seen_commits<=seen_commits+1;
                if (seen_commits==0) begin
                    first_commit_scan<=scan_starts;
                    if(commit_frame_id!==17 || commit_slot!==1) $fatal(1,"record not frozen");
                end else if(commit_frame_id!==29 || commit_slot!==2) $fatal(1,"second commit metadata");
            end
            if(release_valid && release_ready) begin
                seen_releases<=seen_releases+1;
                if(release_frame_id!==17 || release_slot!==1 || !second_accepted)
                    $fatal(1,"unsafe release metadata");
                if (bfm_active && read_address<BASE_B) $fatal(1,"release while old DMA is in flight");
            end
        end else begin ar_stalled<=0;commit_stalled<=0;release_stalled<=0;end
    end
    reg [10:0] x0=0,x1=0,y0=0,y1=0;
    reg de0=0,de1=0,hs0=0,hs1=0,vs0=0,vs1=0;
    reg valid0=0,valid1=0;
    reg [23:0] oracle_rgb;
    always @(posedge pixel_clk) begin
        if (!pixel_reset_n) begin valid0<=0;valid1<=0;scan_starts<=0;warmup<=0;error_age<=0; end
        else begin
            warmup<=warmup+1;
            if(error) error_age<=error_age+1;else error_age<=0;
            if(pixel_frame_start) scan_starts<=scan_starts+1;
            x0<=pixel_x;y0<=pixel_y;de0<=pixel_de;hs0<=pixel_hs;vs0<=pixel_vs;
            x1<=x0;y1<=y0;de1<=de0;hs1<=hs0;vs1<=vs0;
            valid0<=1;valid1<=valid0;
            #1;
            if(valid1 && warmup>4) begin
                if ({out_de,out_hs,out_vs} !== {de1,hs1,vs1})
                    $fatal(1,"timing latency mismatch at x=%0d y=%0d",x1,y1);
                if(mode>=2 && error_age>6 && out_rgb!==24'h101820)
                    $fatal(1,"error/underflow did not produce deterministic background");
                if(mode==0 || mode==1 || mode==11 || mode>=23) begin
                    oracle_rgb=24'h101820;
                    if(expected_id!=0 && de1 && x1<HA && y1>=WY && y1<WY+H)
                        oracle_rgb=expected_pixel(expected_base,y1-WY,x1%W);
                    if(out_rgb!==oracle_rgb)
                        $fatal(1,"pixel x=%0d y=%0d frame=%0d got=%h expected=%h",x1,y1,expected_id,out_rgb,oracle_rgb);
                    if(expected_id!=0 && de1 && y1>=WY && y1<WY+H) checked_pixels<=checked_pixels+1;
                end
            end
        end
    end
    task automatic submit(input [31:0] base,input [31:0] id,input [1:0] slot);
        begin
            @(negedge core_clk);record_base=base;record_frame_id=id;record_slot=slot;record_valid=1;
            do @(posedge core_clk); while(!record_ready);
            @(negedge core_clk);record_valid=0;record_base=32'hdead0000;record_frame_id=999;record_slot=3;
        end
    endtask
    initial begin
        if($value$plusargs("CASE=%d",mode)) begin end
        if($value$plusargs("CORE_HALF=%d",core_half)) begin end
        if($value$plusargs("PIXEL_HALF=%f",pixel_half)) begin end
        inject_burst=2;
        repeat(8) @(posedge core_clk);core_reset_n=1;
        repeat(4) @(posedge pixel_clk);pixel_reset_n=1;
        if(mode==12) ddr_ready=0;
        if(mode==16) record_stride=32'hfffffff0;
        if(mode==20) record_stride=16;
        if(mode==22) record_stride=32'bx;
        case(mode)
        14:submit(32'h7ffffff0,17,1);
        15:submit(32'h87fffff0,17,1);
        17:submit(BASE_A+1,17,1);
        18:submit(BASE_A,32'bx,1);
        19:submit(BASE_A,17,2'bx);
        21:submit(32'bx,17,1);
        default:submit(BASE_A,17,1);
        endcase
        if(INVALID_WINDOW) begin
            repeat(20)@(negedge core_clk);
            if(!error||error_code!==1||burst_count!=0||m_axi_arvalid)
                $fatal(1,"Overflowing WINDOW_Y accepted or accessed AXI");
            $display("PASS preview_display rejects overflowing window parameter before AXI");$finish;
        end else if(mode==26) begin
            // Seed only the diagnostic counter, then let a real publication
            // wrap it. Active ownership must not depend on a counter value.
            force dut.commits=32'hffffffff;
            @(negedge core_clk);release dut.commits;
            wait(seen_commits==1);wait(!bfm_active&&!m_axi_arvalid);
            @(negedge core_clk);
            if(commits!==0)$fatal(1,"counter wrap fixture did not publish");
            ddr_ready=0;repeat(12)@(negedge core_clk);
            if(!error||error_code!==5)$fatal(1,"counter wrap masked active DDR loss");
            $display("PASS preview_display active ownership survives diagnostic counter wrap");$finish;
        end else if(mode>=3 && mode<=8) begin
            wait(error);wait(!bfm_active);repeat(12) @(posedge core_clk);
            if(commits!=0 || beat_count==0) $fatal(1,"bad metadata did not drain before first commit");
            $display("PASS preview_display malformed mode=%0d code=%0d drained=%0d",mode,error_code,beat_count);$finish;
        end else if(mode>=14 && mode<=22) begin
            wait(error);repeat(20) @(posedge core_clk);
            if(error_code!==1 || m_axi_arvalid || burst_count!=0 || commits!=0)
                $fatal(1,"invalid descriptor accessed AXI mode=%0d",mode);
            $display("PASS preview_display invalid descriptor mode=%0d",mode);$finish;
        end else if(mode==12) begin
            wait(error);repeat(12) @(posedge core_clk);
            if(error_code!==5 || m_axi_arvalid || commits!=0) $fatal(1,"initialization loss not latched safely");
            $display("PASS preview_display initialization not ready");$finish;
        end else if(mode==9 || mode==10 || mode==13) begin
            if(mode==9) begin wait(bfm_active);@(negedge core_clk);ddr_ready=0;end
            wait(error);wait(burst_count>0);wait(!bfm_active);repeat(20) @(posedge core_clk);
            if(error_code!==(mode==9 ? 8'd5 : 8'd4) || completed_scans!=0)
                $fatal(1,"online-loss/timeout status mode=%0d code=%0d",mode,error_code);
            $display("PASS preview_display drain mode=%0d code=%0d beats=%0d",mode,error_code,beat_count);$finish;
        end else if(mode==11) begin
            wait(bfm_active);@(negedge core_clk);core_reset_n=0;pixel_reset_n=0;
            repeat(6) @(posedge core_clk);
            @(negedge core_clk);core_reset_n=1;
            @(negedge pixel_clk);pixel_reset_n=1;
            repeat(HT*VT) @(posedge pixel_clk);
            if(commits!=0 || completed_scans!=0 || read_lines!=0 || error || m_axi_arvalid)
                $fatal(1,"coordinated reset retained DMA/record state");
            submit(BASE_A,17,1);wait(completed_scans==1);
            if(error || commits!=1 || read_lines!=H) $fatal(1,"reset recovery failed");
            $display("PASS preview_display coordinated reset during DMA and resubmission");$finish;
        end else if(mode==2) begin
            wait(underflows!=0);wait(!bfm_active);
            if(!error || completed_scans!=0) $fatal(1,"underflow accounting");
            repeat(HT*VT) @(posedge pixel_clk);
            if(completed_scans!=0) $fatal(1,"failed scan counted complete");
            $display("PASS preview_display underflow background and drain");$finish;
        end else begin
            wait(completed_scans>=1);
            if(read_lines!=H) $fatal(1,"row fetched more than once per scan: %0d != %0d",read_lines,H);
            @(negedge core_clk);record_base=BASE_A;record_slot=1;
            @(negedge core_clk);if(record_ready) $fatal(1,"active slot/address reusable before release");
            record_base=BASE_B;
            @(negedge core_clk);if(record_ready) $fatal(1,"active slot reusable with different address");
            record_base=BASE_A;record_slot=2;
            @(negedge core_clk);if(record_ready) $fatal(1,"active address reusable with different slot");
            record_base=32'hdead0000;record_slot=3;
            wait(pixel_y==WY+1 && pixel_x==2);
            commit_ready=(mode==24);release_ready=(mode==23);
            submit(BASE_B,29,2);second_accepted=1;
            wait(commit_valid && commit_frame_id==29);
            if(mode>=23) begin
                // Keep each event combination stalled across two full rasters.
                // The active record must continue displaying on both scans.
                repeat(HT*VT*2) @(posedge pixel_clk);
                if(record_ready || error || underflows!=0 || completed_scans<4)
                    $fatal(1,"long event stall interrupted active scan mode=%0d scans=%0d",mode,completed_scans);
                if(!commit_ready && (!commit_valid || commit_frame_id!==29 || commit_slot!==2))
                    $fatal(1,"long-stalled commit lost identity");
                if(!release_ready && (!release_valid || release_frame_id!==17 || release_slot!==1))
                    $fatal(1,"long-stalled release lost identity");
            end else begin
                repeat(23) @(posedge core_clk);
                if(record_ready || commit_frame_id!==29 || !release_valid || release_frame_id!==17)
                    $fatal(1,"event backpressure did not hold identity");
            end
            commit_ready=1;release_ready=1;
            wait(seen_commits==2 && seen_releases==1);
            @(negedge core_clk);record_base=BASE_A;record_slot=1;
            repeat(3) @(negedge core_clk);
            if(!record_ready) $fatal(1,"released old slot/address did not become reusable");
            wait(completed_scans>=3);
            if(error || underflows!=0 || commits!=2 || frame_id!=29 || checked_pixels<H*HA*3)
                $fatal(1,"normal display status err=%b code=%d commits=%0d scans=%0d pixels=%0d",error,error_code,commits,completed_scans,checked_pixels);
            if(mode==1 && first_commit_scan<3) $fatal(1,"delayed first line committed too early");
            $display("PASS preview_display FULL=%0d mode=%0d commits=%0d scans=%0d lines=%0d pixels=%0d",FULL,mode,commits,completed_scans,read_lines,checked_pixels);$finish;
        end
    end
    initial begin
        repeat(HT*VT*18) @(posedge pixel_clk);
        $display("debug mode=%0d error=%b code=%0d commits=%0d scans=%0d lines=%0d underflows=%0d bursts=%0d active=%b",mode,error,error_code,commits,completed_scans,read_lines,underflows,burst_count,bfm_active);
        $fatal(1,"preview_display timeout: missing commit/scan/retirement behavior");
    end
endmodule
`default_nettype wire
