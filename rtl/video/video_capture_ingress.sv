`timescale 1ns/1ps
// Default: one selected frame per coordinated reset. Opt-in rearm accepts a
// subsequent arm only after a healthy EOF was published. FIFO pointers persist.
module video_capture_ingress #(
    parameter integer FRAME_WIDTH = 800,
    parameter integer FRAME_HEIGHT = 600,
    parameter integer FIFO_ADDR_WIDTH = 11,
    parameter integer ENABLE_REARM = 0
) (
    input  wire        pixel_clk,
    input  wire        pixel_reset_n,
    input  wire        core_clk,
    input  wire        core_reset_n,
    input  wire        pixel_valid,
    input  wire [23:0] pixel_rgb,
    input  wire [10:0] pixel_x,
    input  wire [10:0] pixel_y,
    input  wire        frame_start,
    input  wire        frame_end,
    input  wire        frame_good,
    input  wire        mode_good,
    input  wire        rx_ready,
    input  wire        arm_toggle,
    input  wire        cancel,
    output wire        m_valid,
    output wire [47:0] m_data,
    input  wire        m_ready,
    output wire        source_fault,
    output wire        overflow
);
    localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    // The public coordinates are 11 bits; EOF reserves 12 bits for a RAM
    // occupancy count including the full 2048-word supported maximum.
    // Sanitize the unused invalid branch's FIFO width so elaboration reaches
    // the explicit diagnostic even for zero/negative parameter values.
    localparam integer RAM_ADDR_WIDTH = (FIFO_ADDR_WIDTH>=1 && FIFO_ADDR_WIDTH<=11) ? FIFO_ADDR_WIDTH : 1;
    generate
        if (FIFO_ADDR_WIDTH<1 || FIFO_ADDR_WIDTH>11 || FRAME_WIDTH<1 || FRAME_WIDTH>2048 || FRAME_HEIGHT<1 || FRAME_HEIGHT>2048) begin : invalid_parameters
            initial $fatal(1,"video_capture_ingress requires FIFO_ADDR_WIDTH 1..11 and FRAME_WIDTH/FRAME_HEIGHT 1..2048");
        end
    endgenerate
    localparam [2:0] WAIT_ARM=0, WAIT_START=1, CAPTURE=2, EOF_WAIT=3, STOPPED=4;
    reg [2:0] state;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg arm_sync1, arm_sync2;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg cancel_sync1, cancel_sync2;
    reg arm_seen;
    reg fault_pixel, overflow_pixel;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg fault_core_sync1, fault_core_sync2;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg overflow_core_sync1, overflow_core_sync2;
    reg [31:0] pixel_count, crc_state;
    reg [10:0] expected_x, expected_y;
    reg [11:0] peak_ram;
    reg [47:0] eof_word;
    wire fifo_ready, fifo_valid;
    wire [47:0] fifo_data;
    wire [RAM_ADDR_WIDTH:0] fifo_occupancy;
    wire arm_arrived = state==WAIT_ARM && arm_sync2!=arm_seen;
    wire first_pixel = (state==WAIT_START || arm_arrived) && frame_start && pixel_valid && mode_good && rx_ready;
    wire candidate = first_pixel || (state==CAPTURE && pixel_valid);
    wire coordinate_good = pixel_count < FRAME_PIXELS && pixel_x==expected_x && pixel_y==expected_y;
    wire source_bad = state==CAPTURE && (!mode_good || !rx_ready || (pixel_valid && frame_start));
    wire pixel_bad = candidate && !coordinate_good;
    wire publish_pixel = candidate && !source_bad && !pixel_bad && !cancel_sync2;
    wire pixel_fire = publish_pixel && fifo_ready;
    wire [31:0] count_after_pixel = pixel_count + (pixel_fire ? 32'd1 : 32'd0);
    wire [RAM_ADDR_WIDTH:0] occupancy_after_pixel = fifo_occupancy + {{RAM_ADDR_WIDTH{1'b0}},pixel_fire};
    // Every supported RAM occupancy is exactly representable in EOF's field.
    wire [11:0] observed_peak = occupancy_after_pixel;
    wire [11:0] peak_after_pixel = observed_peak > peak_ram ? observed_peak : peak_ram;
    function automatic [31:0] crc_byte(input [31:0] crc, input [7:0] value);
        reg [31:0] c; integer bit_index;
        begin
            c = crc ^ {24'b0,value};
            for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                c = (c >> 1) ^ (c[0] ? 32'hedb88320 : 32'b0);
            crc_byte = c;
        end
    endfunction
    wire [31:0] pixel_crc = crc_byte(crc_byte(crc_byte(crc_state,pixel_rgb[23:16]),pixel_rgb[15:8]),pixel_rgb[7:0]);
    wire [31:0] crc_after_pixel = pixel_fire ? pixel_crc : crc_state;
    assign fifo_valid = !cancel_sync2 && ((state==EOF_WAIT) || publish_pixel);
    assign fifo_data = state==EOF_WAIT ? eof_word : {2'b00,(pixel_x==FRAME_WIDTH-1),21'b0,pixel_rgb};
    assign source_fault = fault_core_sync2;
    assign overflow = overflow_core_sync2;
    video_async_fifo #(.DATA_WIDTH(48),.ADDR_WIDTH(RAM_ADDR_WIDTH)) fifo (
        .wr_clk(pixel_clk), .wr_reset_n(pixel_reset_n), .wr_valid(fifo_valid),
        .wr_data(fifo_data), .wr_ready(fifo_ready), .wr_occupancy(fifo_occupancy),
        .rd_clk(core_clk), .rd_reset_n(core_reset_n), .rd_valid(m_valid),
        .rd_data(m_data), .rd_ready(m_ready)
    );
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            arm_sync1<=0; arm_sync2<=0; cancel_sync1<=0; cancel_sync2<=0;
        end else begin
            arm_sync1<=arm_toggle; arm_sync2<=arm_sync1;
            cancel_sync1<=cancel; cancel_sync2<=cancel_sync1;
        end
    end
    always @(posedge core_clk or negedge core_reset_n) begin
        if (!core_reset_n) begin
            fault_core_sync1<=0; fault_core_sync2<=0;
            overflow_core_sync1<=0; overflow_core_sync2<=0;
        end else begin
            fault_core_sync1<=fault_pixel; fault_core_sync2<=fault_core_sync1;
            overflow_core_sync1<=overflow_pixel; overflow_core_sync2<=overflow_core_sync1;
        end
    end
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            state<=WAIT_ARM; arm_seen<=0;
            fault_pixel<=0; overflow_pixel<=0;
            pixel_count<=0; expected_x<=0; expected_y<=0;
            crc_state<=32'hffffffff; peak_ram<=0; eof_word<=0;
        end else if (cancel_sync2) begin
            state<=STOPPED;
        end else begin
            case (state)
                WAIT_ARM, WAIT_START, CAPTURE: begin
                    if (arm_arrived) begin
                        arm_seen<=arm_sync2;
                        state<=WAIT_START;
                    end
                    if (source_bad || pixel_bad) begin
                        fault_pixel<=1;
                        state<=STOPPED;
                    end else if (publish_pixel && !fifo_ready) begin
                        overflow_pixel<=1; fault_pixel<=1;
                        state<=STOPPED;
                    end else if (state==CAPTURE || first_pixel) begin
                        if (pixel_fire) begin
                            state<=CAPTURE;
                            pixel_count<=count_after_pixel;
                            crc_state<=pixel_crc;
                            peak_ram<=peak_after_pixel;
                            if (expected_x==FRAME_WIDTH-1) begin
                                expected_x<=0; expected_y<=expected_y+1'b1;
                            end else expected_x<=expected_x+1'b1;
                        end
                        if (frame_end) begin
                            // Last PIX may be accepted on the frame_end edge.
                            // Metadata waits in this source register, never
                            // turning an EOF-only stall into pixel overflow.
                            eof_word <= {2'b01,1'b0,
                                (frame_good && mode_good && rx_ready && count_after_pixel==FRAME_PIXELS),
                                peak_after_pixel,~crc_after_pixel};
                            if (!frame_good || count_after_pixel!=FRAME_PIXELS) fault_pixel<=1;
                            state<=EOF_WAIT;
                        end
                    end
                end
                EOF_WAIT: if (fifo_ready) state<=STOPPED;
                STOPPED: if (ENABLE_REARM && !fault_pixel && !overflow_pixel && arm_sync2!=arm_seen) begin
                    // The controller may toggle only after consuming good EOF
                    // and retiring the old job. Never reset either FIFO port.
                    // Skip a coincident frame_start: old counters still belong
                    // to the preceding frame on this rearm edge.
                    arm_seen<=arm_sync2; state<=WAIT_START;
                    pixel_count<=0; expected_x<=0; expected_y<=0;
                    crc_state<=32'hffffffff; peak_ram<=0; eof_word<=0;
                end
                default: state<=STOPPED;
            endcase
        end
    end
endmodule
