`timescale 1ns/1ps

module tb_video_rx;
    // Independent DMT oracle; intentionally neither includes video_cfg.vh nor
    // instantiates the transmitter/timing generator under test elsewhere.
    localparam integer H_ACTIVE = 800;
    localparam integer V_ACTIVE = 600;
    localparam integer H_TOTAL = 1056;
    localparam integer V_TOTAL = 628;

    reg pixel_clk = 1'b0;
    reg reset_n = 1'b1;
    reg enable = 1'b1;
    reg rx_ready = 1'b1;
    reg hs_in = 1'b0;
    reg vs_in = 1'b0;
    reg de_in = 1'b0;
    reg [23:0] rgb_in = 24'd0;
    wire pixel_valid;
    wire [23:0] rgb_out;
    wire [10:0] x, y;
    wire frame_start, frame_end, frame_good, mode_locked;
    wire [10:0] active_width, active_height, h_total, v_total;
    wire mode_error;

    integer good_frames = 0;
    integer ended_frames = 0;
    integer started_frames = 0;
    integer passed_pixels = 0;
    integer saved_good;
    integer saved_end;
    integer saved_start;
    integer saved_pixels;
    reg require_pixels = 1'b0;
    reg suppress_pixels = 1'b0;
    reg allow_good = 1'b0;
    reg previous_vs = 1'b0;
    reg previous_start = 1'b0;
    reg previous_end = 1'b0;
    reg lock_earned = 1'b0;

    always #12.5 pixel_clk = ~pixel_clk;

    video_rx dut (
        .pixel_clk(pixel_clk), .reset_n(reset_n), .enable(enable),
        .rx_ready(rx_ready), .hs_in(hs_in), .vs_in(vs_in), .de_in(de_in),
        .rgb_in(rgb_in), .pixel_valid(pixel_valid), .rgb_out(rgb_out),
        .x(x), .y(y), .frame_start(frame_start), .frame_end(frame_end),
        .frame_good(frame_good), .mode_locked(mode_locked),
        .active_width(active_width), .active_height(active_height),
        .h_total(h_total), .v_total(v_total), .mode_error(mode_error)
    );

    // Every byte changes, including the bits lost by RGB565/RGB666 conversion.
    function automatic [23:0] color_at;
        input integer px;
        input integer py;
        reg [7:0] red, green, blue;
        begin
            red = (px * 37 + py * 13 + 8'h93) & 255;
            green = (px * 19 + py * 29 + 8'h65) & 255;
            blue = (px * 11 + py * 43 + 8'hb7) & 255;
            color_at = {red, green, blue};
        end
    endfunction

    task automatic sample_pixel;
        input integer px;
        input integer py;
        input integer row_width;
        input integer missing_row;
        begin
            @(negedge pixel_clk);
            hs_in = px >= 840 && px < 968;
            vs_in = py >= 601 && py < 605;
            de_in = px < row_width && py < V_ACTIVE && py != missing_row;
            rgb_in = color_at(px, py);
            @(posedge pixel_clk);
            #1;
            if (pixel_valid === 1'b1) begin
                if (!reset_n || !enable || !rx_ready || !de_in || suppress_pixels)
                    $fatal(1, "Unexpected candidate at source (%0d,%0d)", px, py);
                if (x !== px[10:0] || y !== py[10:0])
                    $fatal(1, "Coordinate mismatch: got (%0d,%0d), expected (%0d,%0d)",
                           x, y, px, py);
                if (rgb_out !== color_at(px, py))
                    $fatal(1, "RGB888 changed at (%0d,%0d): got %06h expected %06h",
                           px, py, rgb_out, color_at(px, py));
                passed_pixels = passed_pixels + 1;
            end else if (pixel_valid !== 1'b0) begin
                $fatal(1, "Unknown pixel_valid");
            end else if (require_pixels && de_in && reset_n && enable && rx_ready) begin
                $fatal(1, "Missing candidate pixel at (%0d,%0d)", px, py);
            end
            if (!pixel_valid && {x, y, rgb_out} !== 46'd0)
                $fatal(1, "Blank outputs retain coordinates or RGB");
            if (frame_start) begin
                if (!pixel_valid || x != 0 || y != 0 || previous_start)
                    $fatal(1, "frame_start must accompany only candidate (0,0)");
                started_frames = started_frames + 1;
            end
            if (frame_end) begin
                if (!vs_in || previous_vs || previous_end || pixel_valid)
                    $fatal(1, "frame_end must be a single pulse at positive VS boundary");
                ended_frames = ended_frames + 1;
            end
            if (frame_good) begin
                if (!allow_good || !frame_end || !mode_locked)
                    $fatal(1, "Unqualified frame_good");
                if ({active_width, active_height, h_total, v_total} !==
                    {11'd800, 11'd600, 11'd1056, 11'd628})
                    $fatal(1, "Accepted incorrect geometry: %0dx%0d total %0dx%0d",
                           active_width, active_height, h_total, v_total);
                good_frames = good_frames + 1;
                lock_earned = 1'b1;
            end
            if (!mode_locked)
                lock_earned = 1'b0;
            else if (!lock_earned)
                $fatal(1, "mode_locked asserted before a complete qualified frame");
            if ((!reset_n || !enable || !rx_ready) &&
                (pixel_valid || frame_start || frame_end || frame_good || mode_locked))
                $fatal(1, "Control loss failed to blank/abort the current frame");
            previous_vs = vs_in;
            previous_start = frame_start;
            previous_end = frame_end;
        end
    endtask

    task automatic reset_monitor;
        begin
            require_pixels = 1'b0;
            suppress_pixels = 1'b0;
            allow_good = 1'b0;
            reset_n = 1'b0;
            sample_pixel(0, 610, 0, -1);
            sample_pixel(1, 610, 0, -1);
            if (mode_error !== 1'b0)
                $fatal(1, "Reset did not clear sticky mode_error");
            reset_n = 1'b1;
        end
    endtask

    // Drive a partial active frame before the first usable VS boundary. It must
    // not be silently relabeled as a complete frame, even with correct DE.
    task automatic startup_midframe;
        integer row, col;
        begin
            suppress_pixels = 1'b1;
            for (row = 200; row < 601; row = row + 1)
                for (col = (row == 200 ? 400 : 0); col < H_TOTAL; col = col + 1)
                    sample_pixel(col, row, H_ACTIVE, -1);
            sample_pixel(0, 601, H_ACTIVE, -1);
            suppress_pixels = 1'b0;
            if (good_frames != 0 || started_frames != 0 || ended_frames != 0 || mode_locked)
                $fatal(1, "Startup partial frame was accepted or associated");
        end
    endtask

    // The previous call already drove (0,601), the opening VS edge. Start at
    // its next pixel and close this interval at the next (0,601). Fault kinds:
    // 0 good; 1 one short active row; 2 one short HS period; 3 missing active row;
    // 4 no DE; 5 ready loss; 6 disable; 7 reset; 8 one omitted blank row;
    // 9 one overwide active row; 10 multiple DE runs in one otherwise 800px row.
    task automatic drive_interval;
        input integer fault_kind;
        integer offset, row, col, width, total, missing;
        begin
            require_pixels = fault_kind == 0;
            allow_good = fault_kind == 0;
            suppress_pixels = 1'b0;
            for (offset = 0; offset < V_TOTAL; offset = offset + 1) begin
                row = (601 + offset) % V_TOTAL;
                total = (fault_kind == 2 && row == 250) ? 1055 : H_TOTAL;
                width = H_ACTIVE;
                if (fault_kind == 1 && row == 100)
                    width = 799;
                if (fault_kind == 9 && row == 100)
                    width = 801;
                if (fault_kind == 4)
                    width = 0;
                missing = fault_kind == 3 ? 300 : -1;
                if (!(fault_kind == 8 && row == 627)) begin
                    for (col = (offset == 0 ? 1 : 0); col < total; col = col + 1) begin
                        if (row == 100 && col == 200 && fault_kind >= 5 && fault_kind <= 7) begin
                            suppress_pixels = 1'b1;
                            if (fault_kind == 5) rx_ready = 1'b0;
                            if (fault_kind == 6) enable = 1'b0;
                            if (fault_kind == 7) reset_n = 1'b0;
                        end
                        if (row == 100 && col == 203 && fault_kind >= 5 && fault_kind <= 7) begin
                            rx_ready = 1'b1;
                            enable = 1'b1;
                            reset_n = 1'b1;
                        end
                        // A hole plus one extra trailing pixel preserves total
                        // DE count, so a width-only monitor cannot catch this.
                        if (fault_kind == 10 && row == 100 && col == 400)
                            sample_pixel(col, row, 0, missing);
                        else if (fault_kind == 10 && row == 100)
                            sample_pixel(col, row, 801, missing);
                        else
                            sample_pixel(col, row, width, missing);
                    end
                end
            end
            sample_pixel(0, 601, H_ACTIVE, -1);
            require_pixels = 1'b0;
            suppress_pixels = 1'b0;
        end
    endtask

    task automatic expect_good_interval;
        begin
            saved_good = good_frames;
            saved_start = started_frames;
            saved_pixels = passed_pixels;
            drive_interval(0);
            if (good_frames != saved_good + 1 || !mode_locked)
                $fatal(1, "Complete supported frame failed to lock/qualify");
            if (passed_pixels != saved_pixels + H_ACTIVE * V_ACTIVE)
                $fatal(1, "Good frame did not pass exactly 480000 candidate pixels");
            if (started_frames != saved_start + 1)
                $fatal(1, "Good frame did not emit exactly one frame_start");
        end
    endtask

    task automatic expect_bad_interval;
        input integer fault_kind;
        begin
            saved_good = good_frames;
            saved_end = ended_frames;
            drive_interval(fault_kind);
            if (good_frames != saved_good || mode_locked || !mode_error)
                $fatal(1, "Fault %0d did not reject/unlock/latch error", fault_kind);
            if (ended_frames != saved_end + 1)
                $fatal(1, "Bad geometry must close exactly one rejected monitor interval");
            $display("CHECK RX rejected geometry fault %0d", fault_kind);
        end
    endtask

    initial begin
        // 40 million cycles is a hard bound even if an event is never produced.
        #1000000000;
        $fatal(1, "RX testbench watchdog expired");
    end

    initial begin
        reset_monitor();
        startup_midframe();
        expect_good_interval();
        if (mode_error)
            $fatal(1, "Clean startup asserted mode_error");
        expect_good_interval();
        $display("CHECK RX two supported RGB888 frames and startup rejection");

        expect_bad_interval(1);
        expect_good_interval();
        if (!mode_error)
            $fatal(1, "Geometry recovery cleared the sticky error");
        expect_bad_interval(2);
        expect_good_interval();
        expect_bad_interval(3);
        expect_good_interval();
        expect_bad_interval(4);
        expect_good_interval();
        expect_bad_interval(8);
        if (v_total !== 11'd627)
            $fatal(1, "Measured shortened vertical total was %0d", v_total);
        expect_good_interval();
        expect_bad_interval(9);
        expect_good_interval();
        expect_bad_interval(10);
        expect_good_interval();

        saved_good = good_frames;
        saved_end = ended_frames;
        drive_interval(5);
        if (good_frames != saved_good || ended_frames != saved_end || mode_locked || !mode_error)
            $fatal(1, "Readiness loss retained a partial-frame association");
        expect_good_interval();
        $display("CHECK RX readiness loss discards frame and recovers");

        saved_good = good_frames;
        saved_end = ended_frames;
        drive_interval(6);
        if (good_frames != saved_good || ended_frames != saved_end || mode_locked)
            $fatal(1, "Disable retained a partial-frame association");
        expect_good_interval();

        saved_good = good_frames;
        saved_end = ended_frames;
        drive_interval(7);
        if (good_frames != saved_good || ended_frames != saved_end || mode_locked || mode_error)
            $fatal(1, "Reset retained an old frame or error");
        expect_good_interval();
        if (mode_error)
            $fatal(1, "Reset recovery asserted mode_error");
        $display("VIDEO_RX_PASS: %0d good frames, %0d closed intervals, %0d RGB888 pixels",
                 good_frames, ended_frames, passed_pixels);
        $finish;
    end
endmodule
