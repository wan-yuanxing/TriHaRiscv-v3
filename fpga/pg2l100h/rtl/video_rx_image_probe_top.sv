`timescale 1ns/1ps
`default_nettype none
// Independent RX image distribution diagnostic; output remains local colorbars.
module video_rx_image_probe_top(
    input wire sys_clk,rst_in,pixclk_in,hs_in,vs_in,de_in,
    input wire[7:0]r_in,g_in,b_in,
    output wire rstn_out,hd_scl,pix_clk,
    inout wire hd_sda,
    output reg hs_out,vs_out,de_out,
    output reg[7:0]r_out,g_out,b_out,
    output wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,
    output wire uart_tx
);
    wire cfg_clk,locked,pixel_reset_n,cfg_reset_n;
    video_clock_reset clocks(.sys_clk(sys_clk),.reset_n(rst_in),.pixel_clk(pix_clk),
        .cfg_clk(cfg_clk),.locked(locked),.pixel_reset_n(pixel_reset_n),
        .cfg_reset_n(cfg_reset_n),.tx_reset_n(rstn_out));
    wire tx_scl,rx_scl,tx_done,tx_error,rx_done,rx_error,rx_configured;
    wire[31:0]raw_status;
    hdmi_tx_init tx(.clk_cfg(cfg_clk),.reset_n(rstn_out),.iic_scl(tx_scl),
        .iic_sda(hd_sda),.init_done(tx_done),.init_error(tx_error));
    hdmi_rx_init rx(.clk_cfg(cfg_clk),.reset_n(rstn_out&&tx_done),.iic_scl(rx_scl),
        .iic_sda(hd_sda),.init_done(rx_done),.link_configured(rx_configured),
        .init_error(rx_error),.status_word(raw_status));
    // Each SDA is open drain and releases while inactive. Only one push-pull
    // SCL owns the pin; TX's successful stop precedes this ownership transfer.
    assign hd_scl=tx_done?rx_scl:tx_scl;
    wire hs,vs,de,frame_start;
    wire[23:0]rgb;
    video_pattern_core pattern(.pixel_clk(pix_clk),.reset_n(pixel_reset_n),
        .hsync(hs),.vsync(vs),.de(de),.frame_start(frame_start),.rgb(rgb));
    always @(posedge pix_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin hs_out<=0;vs_out<=0;de_out<=0;r_out<=0;g_out<=0;b_out<=0;end
        else begin hs_out<=hs;vs_out<=vs;de_out<=de;r_out<=rgb[23:16];g_out<=rgb[15:8];b_out<=rgb[7:0];end
    end
    (* syn_preserve=1 *)reg[1:0] rx_reset_release,rx_enable_sync;
    always @(posedge pixclk_in or negedge cfg_reset_n)begin
        if(!cfg_reset_n)begin rx_reset_release<=0;rx_enable_sync<=0;end
        else begin rx_reset_release<={rx_reset_release[0],1'b1};rx_enable_sync<={rx_enable_sync[0],rx_done&&!rx_error};end
    end
    wire rx_reset_n=cfg_reset_n&&rx_reset_release[1];
    // Capture the parallel converter bus on the opposite PCLK edge, before
    // rising-edge consumers. The initial rising capture showed one-clock HS
    // ambiguity on hardware; this centers sampling within the SDR interval.
    // All timing and geometry consumers see the same sampled HS/VS/DE/RGB.
    // External pad setup/hold remains a separate board AC qualification.
    (* syn_preserve=1 *)reg[26:0]rx_capture;
    always @(negedge pixclk_in or negedge rx_reset_n)begin
        if(!rx_reset_n)rx_capture<=0;
        else rx_capture<={hs_in,vs_in,de_in,r_in,g_in,b_in};
    end
    wire geometry_locked,timing_locked,timing_error;
    wire[15:0]ha,va,ht,vt,hw,vw,hf,hb,vf,vb;
    wire[31:0]good,bad;
    wire candidate,frame_begin,frame_end,frame_good;
    wire [10:0] candidate_x,candidate_y;
    wire[23:0]candidate_rgb;
    video_rx geometry(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .rx_ready(rx_enable_sync[1]),.hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),
        .rgb_in(rx_capture[23:0]),.mode_locked(geometry_locked),.pixel_valid(candidate),
        .rgb_out(candidate_rgb),.frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),.x(candidate_x),.y(candidate_y));
    reg[15:0]signature_accum,frame_signature;
    wire[15:0]pixel_signature=candidate_rgb[23:8]^{8'd0,candidate_rgb[7:0]};
    always @(posedge pixclk_in or negedge rx_reset_n)begin
        if(!rx_reset_n)begin signature_accum<=0;frame_signature<=0;end
        else begin
            if(candidate)signature_accum<=(frame_begin?16'd0:{signature_accum[14:0],signature_accum[15]})^pixel_signature;
            if(frame_end)frame_signature<=signature_accum;
        end
    end
    video_rx_measure measure(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),.timing_locked(timing_locked),.mode_error(timing_error),
        .h_active(ha),.v_active(va),.h_total(ht),.v_total(vt),.h_sync(hw),.v_sync(vw),
        .h_front(hf),.h_back(hb),.v_front(vf),.v_back(vb),.good_frames(good),.bad_frames(bad));
    wire[31:0]vs_high_clocks,vs_period_clocks,hs_rises,hs_falls,vs_rises,vs_falls,de_rises;
    video_rx_probe probe(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),
        .vs_high_clocks(vs_high_clocks),.vs_period_clocks(vs_period_clocks),
        .hs_rises(hs_rises),.hs_falls(hs_falls),.vs_rises(vs_rises),.vs_falls(vs_falls),.de_rises(de_rises));
    wire [31:0] image_sequence,image_pixels,image_nonzero,image_x_bounds,image_y_bounds,image_crc;
    wire [31:0] image_crc128,image_crc129,image_last_change,image_before_change;
    wire [23:0] image_q0,image_q1,image_q2,image_q3;
    video_rx_image_probe image_probe(.clk(pixclk_in),.reset_n(rx_reset_n),
        .pixel_valid(candidate),.frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),
        .x(candidate_x),.y(candidate_y),.rgb(candidate_rgb),.frame_sequence(image_sequence),
        .pixels(image_pixels),.nonzero(image_nonzero),.x_bounds(image_x_bounds),.y_bounds(image_y_bounds),
        .crc(image_crc),.crc_frame128(image_crc128),.crc_frame129(image_crc129),
        .last_change_frame(image_last_change),.crc_before_change(image_before_change),.q0(image_q0),.q1(image_q1),.q2(image_q2),.q3(image_q3));
    wire[855:0]status_now={image_before_change,image_last_change,image_crc129,image_crc128,image_crc,image_y_bounds,image_x_bounds,image_nonzero,image_pixels,image_sequence,
        image_q3,image_q2,image_q1,image_q0,de_rises,vs_falls,vs_rises,hs_falls,hs_rises,vs_period_clocks,vs_high_clocks,
        frame_signature,6'd0,timing_error,geometry_locked&&timing_locked,bad[15:0],good[15:0],vb,vf,hb,hf,vw,hw,vt,ht,va,ha};
    wire[855:0]snapshot;
    wire[31:0]hz;
    wire fresh,alive,freq_good;
    video_rx_telemetry #(.STATUS_WIDTH(856))telemetry(.cfg_clk(cfg_clk),.pixel_clk(pixclk_in),
        .reset_n(cfg_reset_n),.pixel_status(status_now),.snapshot(snapshot),.snapshot_valid(fresh),
        .pixel_hz(hz),.clock_alive(alive),.frequency_good(freq_good));
    wire mode_good=fresh&&freq_good&&snapshot[192]&&rx_done&&rx_configured&&!rx_error;
    wire[7:0]flags={mode_good,freq_good,fresh,rx_configured,rx_error,rx_done,tx_error,tx_done};
    reg[23:0]heartbeat;
    always @(posedge cfg_clk or negedge cfg_reset_n)begin
        if(!cfg_reset_n)heartbeat<=0;
        else heartbeat<=heartbeat+1'b1;
    end
    reg [2:0] packet_kind;
    reg uart_busy_q;
    wire uart_busy;
    reg [415:0] image_hold;
    always @(posedge cfg_clk or negedge cfg_reset_n)begin
        if(!cfg_reset_n)begin packet_kind<=0;uart_busy_q<=0;image_hold<=0;end
        else begin
            uart_busy_q<=uart_busy;
            if(uart_busy_q&&!uart_busy)begin
                packet_kind<=packet_kind==4?3'd0:packet_kind+1'b1;
                if(packet_kind==1)image_hold<=snapshot[855:440];
            end
        end
    end
    reg [255:0] payload;
    always @* case(packet_kind)
        0:payload={snapshot[191:160],hz,snapshot[159:0],snapshot[215:200],flags,8'd1};
        1:payload={snapshot[439:216],16'd0,flags,8'd3};
        2:payload={{8'd0,image_hold[47:24]},{8'd0,image_hold[23:0]},image_hold[255:224],
                   image_hold[223:192],image_hold[191:160],image_hold[159:128],image_hold[127:96],
                   8'd0,8'd1,flags,8'd8};
        3:payload={32'd0,32'd0,32'd0,image_hold[287:256],{8'd0,image_hold[95:72]},
                   {8'd0,image_hold[71:48]},image_hold[127:96],8'd0,8'd1,flags,8'd9};
        4:payload={32'd0,image_hold[287:256],image_hold[415:384],image_hold[383:352],
                   image_hold[351:320],image_hold[319:288],image_hold[127:96],8'd0,8'd1,flags,8'd10};
        default:payload=0;
    endcase
    video_diag_uart diagnostic(.clk(cfg_clk),.reset_n(cfg_reset_n),.payload(payload),.tx(uart_tx),.busy(uart_busy));
    assign heart_beat_led=heartbeat[23];
    assign ddr_init_done=locked; // Legacy LED1 name, no DDR in this target.
    assign init_over_rx=mode_good; // LED2: current supported input mode.
    assign hdmi_int_led=tx_error||rx_error; // LED3: sticky initialization error.
endmodule
`default_nettype wire
