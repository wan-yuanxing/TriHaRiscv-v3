`timescale 1ns/1ps
module tb_video_capture_ingress;
    parameter integer TEST_WIDTH = 5;
    parameter integer TEST_HEIGHT = 3;
    parameter integer TEST_FIFO_ADDR_WIDTH = 4;
    parameter integer PIXEL_HALF = 7;
    parameter integer CORE_HALF = 3;
    parameter integer CORE_PHASE = 1;
    localparam integer PIXELS = TEST_WIDTH * TEST_HEIGHT;
    localparam integer DEPTH = 1 << TEST_FIFO_ADDR_WIDTH;
    reg pixel_clk = 0, core_clk = 0, pixel_run = 1, core_run = 1;
    always #(PIXEL_HALF) if (pixel_run) pixel_clk = ~pixel_clk;
    initial begin #(CORE_PHASE); forever #(CORE_HALF) if (core_run) core_clk = ~core_clk; end
    reg pixel_reset_n = 0, core_reset_n = 0;
    reg pixel_valid = 0;
    reg [23:0] pixel_rgb = 0;
    reg [10:0] pixel_x = 0, pixel_y = 0;
    reg frame_start = 0, frame_end = 0, frame_good = 1, mode_good = 1, rx_ready = 1;
    reg arm_toggle = 0, cancel = 0, m_ready = 0;
    wire m_valid, source_fault, overflow;
    wire [47:0] m_data;
    video_capture_ingress #(.FRAME_WIDTH(TEST_WIDTH), .FRAME_HEIGHT(TEST_HEIGHT),
        .FIFO_ADDR_WIDTH(TEST_FIFO_ADDR_WIDTH)) dut (.*);
    integer got_pixels = 0, got_eof = 0, expected_tag = 0;
    integer expected_pixels = PIXELS, expected_good = 1, read_mode = 0;
    integer last_peak = 0, accepted_before_cancel = 0;
    reg [31:0] observed_crc = 0, rng = 32'h12345678;
    reg stalled = 0;
    reg [47:0] held;
    function [23:0] rgb_at(input integer tag, input integer index);
        reg [7:0] r,g,b;
        begin r=tag*29+index*17+3; g=tag*13+index*7+5; b=tag*31+index*19+11; rgb_at={r,g,b}; end
    endfunction
    // Independent polynomial orientation: left-shift CRC with 04c11db7,
    // consume input bits LSB first, then reverse/final-complement the state.
    function [31:0] oracle_byte(input [31:0] state, input [7:0] value);
        reg [31:0] c; integer j;
        begin c=state; for(j=0;j<8;j=j+1) c=(c<<1)^((c[31]^value[j])?32'h04c11db7:0); oracle_byte=c; end
    endfunction
    function [31:0] reverse32(input [31:0] value);
        integer j; begin for(j=0;j<32;j=j+1) reverse32[j]=value[31-j]; end
    endfunction
    function [31:0] frame_crc(input integer tag, input integer count);
        reg [31:0] c; reg [23:0] rgb; integer j;
        begin
            c=32'hffffffff;
            for(j=0;j<count;j=j+1) begin
                rgb=rgb_at(tag,j); c=oracle_byte(c,rgb[23:16]);
                c=oracle_byte(c,rgb[15:8]); c=oracle_byte(c,rgb[7:0]);
            end
            frame_crc=~reverse32(c);
        end
    endfunction
    always @(negedge core_clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        m_ready=core_reset_n && (read_mode==1 || (read_mode==2 && rng[2:0]>2));
    end
    always @(posedge core_clk) begin
        if (!core_reset_n) stalled=0;
        else begin
            if(stalled && (!m_valid || m_data!==held)) $fatal(1,"ingress output changed under stall");
            if(m_valid && m_ready) begin
                case(m_data[47:46])
                    2'b00: begin
                        if(got_eof || got_pixels>=expected_pixels) $fatal(1,"extra/late pixel");
                        if(m_data[23:0]!==rgb_at(expected_tag,got_pixels) || m_data[44:24]!==0 ||
                            m_data[45]!==((got_pixels%TEST_WIDTH)==TEST_WIDTH-1))
                            $fatal(1,"PIX mismatch tag=%0d index=%0d word=%h",expected_tag,got_pixels,m_data);
                        got_pixels=got_pixels+1;
                    end
                    2'b01: begin
                        if(got_eof || got_pixels!=expected_pixels || m_data[45] || m_data[44]!==expected_good[0])
                            $fatal(1,"bad EOF framing word=%h pixels=%0d",m_data,got_pixels);
                        if(m_data[31:0]!==frame_crc(expected_tag,expected_pixels)) $fatal(1,"CRC mismatch got=%h expected=%h",m_data[31:0],frame_crc(expected_tag,expected_pixels));
                        if(m_data[43:32]<1 || m_data[43:32]>DEPTH) $fatal(1,"invalid conservative RAM peak");
                        observed_crc=m_data[31:0]; last_peak=m_data[43:32]; got_eof=got_eof+1;
                    end
                    default: $fatal(1,"illegal token");
                endcase
            end
            stalled=m_valid&&!m_ready; held=m_data;
        end
    end
    task idle_pixel;
        begin @(negedge pixel_clk); pixel_valid=0; frame_start=0; frame_end=0; end
    endtask
    task reset_epoch(input integer tag);
        begin
            pixel_run=1; core_run=1; pixel_reset_n=0; core_reset_n=0;
            pixel_valid=0; frame_start=0; frame_end=0; arm_toggle=0; cancel=0;
            mode_good=1; rx_ready=1; frame_good=1; read_mode=0;
            repeat(6) @(negedge pixel_clk);
            got_pixels=0; got_eof=0; expected_tag=tag; expected_good=1; expected_pixels=PIXELS; last_peak=0;
            pixel_reset_n=1; core_reset_n=1;
            repeat(6) @(negedge pixel_clk);
            if(m_valid||source_fault||overflow) $fatal(1,"reset epoch retained stale state");
        end
    endtask
    task arm;
        begin @(negedge core_clk); arm_toggle=~arm_toggle; repeat(5) @(negedge pixel_clk); end
    endtask
    task send_pixel(input integer tag, input integer index, input integer start_bit, input integer end_bit, input integer badcoord);
        begin
            @(negedge pixel_clk); pixel_valid=1; pixel_rgb=rgb_at(tag,index);
            pixel_x=(index%TEST_WIDTH)+badcoord; pixel_y=index/TEST_WIDTH;
            frame_start=start_bit; frame_end=end_bit;
        end
    endtask
    task send_frame(input integer tag, input integer end_with_pixel);
        integer j;
        begin
            for(j=0;j<PIXELS;j=j+1) send_pixel(tag,j,j==0,end_with_pixel&&j==PIXELS-1,0);
            idle_pixel();
            if(!end_with_pixel) begin frame_end=1; @(negedge pixel_clk); frame_end=0; end
        end
    endtask
    task await_eof;
        integer timeout_count;
        begin
            timeout_count=0;
            while(!got_eof && timeout_count<10000) begin @(negedge core_clk); timeout_count=timeout_count+1; end
            if(!got_eof) $fatal(1,"EOF timeout pixels=%0d fault=%b overflow=%b",got_pixels,source_fault,overflow);
            repeat(10) @(negedge core_clk);
        end
    endtask
    task expect_fault(input integer expect_overflow);
        begin
            repeat(12) @(negedge core_clk);
            if(!source_fault || overflow!==expect_overflow[0]) $fatal(1,"fault synchronization mismatch fault=%b overflow=%b",source_fault,overflow);
        end
    endtask
    task ensure_stopped;
        integer before_count;
        begin
            read_mode=1; repeat(100) @(negedge core_clk); before_count=got_pixels;
            send_frame(expected_tag,1); repeat(100) @(negedge core_clk);
            if(got_pixels!=before_count || got_eof) $fatal(1,"error/cancel resumed source without reset");
        end
    endtask
    integer j; reg [31:0] known_crc;
    initial begin
        known_crc=32'hffffffff;
        for(j=0;j<9;j=j+1) known_crc=oracle_byte(known_crc,8'h31+j);
        if((~reverse32(known_crc))!==32'hcbf43926) $fatal(1,"oracle check vector failed");
        if($test$plusargs("normal_only")) begin
            reset_epoch(100); read_mode=2; arm(); send_frame(100,1); await_eof();
            if(source_fault||overflow) $fatal(1,"bounded normal trace faulted");
            $display("VIDEO_CAPTURE_INGRESS_PASS width=%0d height=%0d depth=%0d pixels=%0d crc=%h peak=%0d",TEST_WIDTH,TEST_HEIGHT,DEPTH,got_pixels,observed_crc,last_peak);
            $finish;
        end
        reset_epoch(1); read_mode=2;
        // Arm during an already-running frame: no tail may be admitted.
        send_pixel(99,0,1,0,0); @(negedge core_clk); arm_toggle=1;
        for(j=1;j<PIXELS;j=j+1) send_pixel(99,j,0,j==PIXELS-1,0);
        idle_pixel(); repeat(6) @(negedge pixel_clk);
        if(got_pixels) $fatal(1,"midframe arm admitted frame tail");
        send_frame(1,1); await_eof();
        if(source_fault||overflow) $fatal(1,"normal frame faulted");
        arm(); send_frame(77,0); repeat(50) @(negedge core_clk);
        if(got_pixels!=PIXELS||got_eof!=1) $fatal(1,"repeat arm selected second frame");
        mode_good=0; rx_ready=0; repeat(10) @(negedge pixel_clk); repeat(10) @(negedge core_clk);
        if(source_fault||overflow) $fatal(1,"later source loss invalidated completed frame");

        reset_epoch(2); read_mode=1; arm(); send_frame(2,0); await_eof();
        // Peak oracle with core stopped before selection: every pixel stays in RAM.
        if(PIXELS<DEPTH) begin
            reset_epoch(3); arm(); @(negedge core_clk); core_run=0;
            send_frame(3,1); repeat(5) @(negedge pixel_clk); core_run=1; read_mode=1; await_eof();
            if(last_peak!=PIXELS) $fatal(1,"RAM peak excludes last pixel expected=%0d got=%0d",PIXELS,last_peak);
        end
        // EOF is allowed to wait behind a completely full RAM/output capacity.
        if(PIXELS==DEPTH+1) begin
            reset_epoch(4); arm(); send_frame(4,1); repeat(30) @(negedge pixel_clk);
            if(source_fault||overflow||got_eof) $fatal(1,"pending EOF treated as overflow");
            read_mode=1; await_eof(); if(last_peak!=DEPTH) $fatal(1,"full EOF peak mismatch");
        end
        reset_epoch(5); read_mode=1; arm();
        send_pixel(5,0,1,0,1); idle_pixel(); expect_fault(0); ensure_stopped();
        reset_epoch(6); read_mode=1; arm();
        send_pixel(6,0,1,0,0); send_pixel(6,1,0,0,0); idle_pixel(); rx_ready=0;
        expect_fault(0); rx_ready=1; ensure_stopped();
        reset_epoch(7); read_mode=1; arm(); send_pixel(7,0,1,0,0); idle_pixel(); mode_good=0;
        expect_fault(0); mode_good=1; ensure_stopped();
        reset_epoch(8); read_mode=1; arm(); expected_good=0; frame_good=0;
        send_frame(8,1); await_eof(); expect_fault(0);
        reset_epoch(9); arm();
        for(j=0;j<DEPTH+3 && j<PIXELS;j=j+1) send_pixel(9,j,j==0,0,0);
        idle_pixel();
        if(PIXELS>DEPTH+1) begin expect_fault(1); ensure_stopped(); end
        // Cancellation preserves queued valid data and forbids later selection.
        reset_epoch(10); arm(); send_pixel(10,0,1,0,0); idle_pixel();
        repeat(10) @(negedge core_clk); @(negedge core_clk); cancel=1;
        repeat(6) @(negedge pixel_clk); ensure_stopped();
        // Source clock stop cannot disturb the core output or create a fault.
        reset_epoch(11); arm(); send_pixel(11,0,1,0,0); idle_pixel();
        @(negedge pixel_clk); pixel_run=0; repeat(80) @(negedge core_clk);
        if(!m_valid||source_fault||overflow) $fatal(1,"source stop corrupted held core output");
        pixel_run=1; read_mode=1;
        for(j=1;j<PIXELS;j=j+1) send_pixel(11,j,0,j==PIXELS-1,0);
        idle_pixel(); await_eof();
        // Reset/retry also follows previously aborted and full epochs.
        reset_epoch(12); read_mode=2; arm(); send_frame(12,1); await_eof();
        reset_epoch(13); read_mode=1; arm();
        send_pixel(13,0,1,0,0); send_pixel(13,1,0,0,1); idle_pixel();
        expect_fault(0); ensure_stopped();
        if(TEST_HEIGHT>1) begin
            reset_epoch(14); read_mode=1; arm();
            for(j=0;j<TEST_WIDTH;j=j+1) send_pixel(14,j,j==0,0,0);
            send_pixel(14,TEST_WIDTH,0,0,0); pixel_y=0; idle_pixel();
            expect_fault(0); ensure_stopped();
        end
        reset_epoch(15); read_mode=1; arm();
        for(j=0;j<PIXELS;j=j+1) send_pixel(15,j,j==0,0,0);
        send_pixel(15,0,0,1,0); idle_pixel(); expect_fault(0); ensure_stopped();
        reset_epoch(16); read_mode=1; arm(); expected_pixels=2; expected_good=0;
        send_pixel(16,0,1,0,0); send_pixel(16,1,0,1,0); idle_pixel();
        await_eof(); expect_fault(0);
        // Unqualified frame starts while waiting are ignored; the next good
        // start remains the first candidate and contributes its first pixel.
        reset_epoch(17); read_mode=1; arm(); mode_good=0;
        send_frame(99,1); repeat(8) @(negedge core_clk);
        if(source_fault||got_pixels) $fatal(1,"unselected bad frame created a source fault");
        mode_good=1; send_frame(17,1); await_eof();
        reset_epoch(18); read_mode=1; @(negedge core_clk); cancel=1;
        repeat(5) @(negedge pixel_clk); arm(); send_frame(18,1);
        repeat(50) @(negedge core_clk);
        if(got_pixels||got_eof||source_fault||overflow) $fatal(1,"cancelled idle epoch admitted a frame");
        reset_epoch(19); read_mode=1; arm(); send_pixel(19,0,1,0,0); idle_pixel();
        reset_epoch(20); read_mode=2; arm(); send_frame(20,1); await_eof();
        // A start on the first edge that observes the synchronized arm is
        // already eligible; waiting for another frame would miss this one.
        reset_epoch(21); read_mode=1;
        @(negedge pixel_clk); arm_toggle=1;
        repeat(2) @(posedge pixel_clk);
        send_frame(21,1); await_eof();
        $display("VIDEO_CAPTURE_INGRESS_PASS width=%0d height=%0d depth=%0d pixel_half=%0d core_half=%0d crc=%h",TEST_WIDTH,TEST_HEIGHT,DEPTH,PIXEL_HALF,CORE_HALF,observed_crc);
        $finish;
    end
    initial begin #10000000; $fatal(1,"ingress watchdog"); end
endmodule
