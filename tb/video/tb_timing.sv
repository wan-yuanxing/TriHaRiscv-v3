`timescale 1ns/1ps

module tb_timing;
    // Independent specification values: do not derive the oracle from RTL.
    localparam integer H_ACTIVE = 800;
    localparam integer V_ACTIVE = 600;
    localparam integer H_TOTAL = 1056;
    localparam integer V_TOTAL = 628;
    localparam integer FRAME_PIXELS = H_TOTAL * V_TOTAL;

    reg pixel_clk = 1'b0;
    reg reset_n = 1'b1;
    wire [10:0] x;
    wire [10:0] y;
    wire hsync;
    wire vsync;
    wire de;
    wire frame_start;
    wire [23:0] rgb;
    wire core_hsync;
    wire core_vsync;
    wire core_de;
    wire core_frame_start;
    wire [23:0] core_rgb;
    integer sample;
    integer completed_frames = 0;

    always #12.5 pixel_clk = ~pixel_clk; // 40 MHz.

    video_timing timing_dut (
        .pixel_clk(pixel_clk),
        .reset_n(reset_n),
        .x(x),
        .y(y),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .frame_start(frame_start)
    );

    video_test_pattern pattern_dut (
        .x(x),
        .y(y),
        .de(de),
        .rgb(rgb)
    );

    // Exercise the portable synthesis boundary alongside direct unit checks.
    video_pattern_core core_dut (
        .pixel_clk(pixel_clk),
        .reset_n(reset_n),
        .hsync(core_hsync),
        .vsync(core_vsync),
        .de(core_de),
        .frame_start(core_frame_start),
        .rgb(core_rgb)
    );

    function automatic [23:0] expected_rgb;
        input integer expected_x;
        input integer expected_y;
        begin
            expected_rgb = 24'h000000;
            if (expected_x < H_ACTIVE && expected_y < V_ACTIVE) begin
                case (expected_x / 100)
                    0: expected_rgb = 24'hffffff;
                    1: expected_rgb = 24'hffff00;
                    2: expected_rgb = 24'h00ffff;
                    3: expected_rgb = 24'h00ff00;
                    4: expected_rgb = 24'hff00ff;
                    5: expected_rgb = 24'hff0000;
                    6: expected_rgb = 24'h0000ff;
                    7: expected_rgb = 24'h000000;
                    default: $fatal(1, "Reference bar index out of range");
                endcase
            end
        end
    endfunction

    task automatic check_pixel;
        input integer expected_x;
        input integer expected_y;
        reg expected_hsync;
        reg expected_vsync;
        reg expected_de;
        reg expected_frame_start;
        reg [23:0] color;
        begin
            expected_hsync = expected_x >= 840 && expected_x < 968;
            expected_vsync = expected_y >= 601 && expected_y < 605;
            expected_de = expected_x < H_ACTIVE && expected_y < V_ACTIVE;
            expected_frame_start = expected_x == 0 && expected_y == 0;
            color = expected_rgb(expected_x, expected_y);

            if (x !== expected_x[10:0] || y !== expected_y[10:0])
                $fatal(1, "Coordinate mismatch: got (%0d,%0d), expected (%0d,%0d)",
                       x, y, expected_x, expected_y);
            if ({hsync, vsync, de, frame_start} !==
                {expected_hsync, expected_vsync, expected_de, expected_frame_start})
                $fatal(1, "Control mismatch at (%0d,%0d): HS/VS/DE/SOF=%b, expected %b",
                       expected_x, expected_y, {hsync, vsync, de, frame_start},
                       {expected_hsync, expected_vsync, expected_de, expected_frame_start});
            if (rgb !== color)
                $fatal(1, "RGB mismatch at (%0d,%0d): got %h, expected %h",
                       expected_x, expected_y, rgb, color);
            if ({core_hsync, core_vsync, core_de, core_frame_start, core_rgb} !==
                {expected_hsync, expected_vsync, expected_de, expected_frame_start, color})
                $fatal(1, "Core wrapper mismatch at (%0d,%0d): HS/VS/DE/SOF=%b RGB=%h, expected %b %h",
                       expected_x, expected_y,
                       {core_hsync, core_vsync, core_de, core_frame_start}, core_rgb,
                       {expected_hsync, expected_vsync, expected_de, expected_frame_start}, color);
        end
    endtask

    task automatic check_reset;
        begin
            if ({x, y, hsync, vsync, de, frame_start, rgb} !== 50'b0)
                $fatal(1, "Reset must clear counters and suppress sync, DE, SOF and RGB");
            if ({core_hsync, core_vsync, core_de, core_frame_start, core_rgb} !== 28'b0)
                $fatal(1, "Core wrapper must suppress sync, DE, SOF and RGB during reset");
        end
    endtask

    // Call at a settled (0,0). Return at the following settled (0,0).
    // Falling-edge sampling stays clear of the DUT's rising-edge NBA updates.
    task automatic check_frame;
        input integer frame_number;
        integer pixel;
        integer expected_x;
        integer expected_y;
        integer active_pixels;
        integer blank_pixels;
        integer hsync_pixels;
        integer vsync_pixels;
        integer frame_starts;
        integer lines;
        integer bar;
        integer bar_pixels [0:7];
        begin
            active_pixels = 0;
            blank_pixels = 0;
            hsync_pixels = 0;
            vsync_pixels = 0;
            frame_starts = 0;
            lines = 0;
            for (bar = 0; bar < 8; bar = bar + 1)
                bar_pixels[bar] = 0;

            for (pixel = 0; pixel < FRAME_PIXELS; pixel = pixel + 1) begin
                expected_x = pixel % H_TOTAL;
                expected_y = pixel / H_TOTAL;
                check_pixel(expected_x, expected_y);
                if (de) begin
                    active_pixels = active_pixels + 1;
                    bar_pixels[expected_x / 100] = bar_pixels[expected_x / 100] + 1;
                end else begin
                    blank_pixels = blank_pixels + 1;
                end
                if (hsync) hsync_pixels = hsync_pixels + 1;
                if (vsync) vsync_pixels = vsync_pixels + 1;
                if (frame_start) frame_starts = frame_starts + 1;
                if (x == H_TOTAL - 1) lines = lines + 1;
                @(negedge pixel_clk);
                #1;
            end

            if (active_pixels != 480000 || blank_pixels != 183168 ||
                hsync_pixels != 80384 || vsync_pixels != 4224 ||
                frame_starts != 1 || lines != 628)
                $fatal(1, "Frame %0d count mismatch: active=%0d blank=%0d HS=%0d VS=%0d SOF=%0d lines=%0d",
                       frame_number, active_pixels, blank_pixels, hsync_pixels,
                       vsync_pixels, frame_starts, lines);
            for (bar = 0; bar < 8; bar = bar + 1)
                if (bar_pixels[bar] != 60000)
                    $fatal(1, "Frame %0d bar %0d has %0d pixels, expected 60000",
                           frame_number, bar, bar_pixels[bar]);
            check_pixel(0, 0);
            completed_frames = completed_frames + 1;
            $display("Checked frame %0d: %0d raster pixels, %0d active pixels",
                     frame_number, FRAME_PIXELS, active_pixels);
        end
    endtask

    initial begin
        // Assert away from a clock edge and verify before the next rising edge.
        #2;
        reset_n = 1'b0;
        #1;
        check_reset();
        repeat (3) begin
            @(negedge pixel_clk);
            #1;
            check_reset();
        end
        @(negedge pixel_clk);
        reset_n = 1'b1;
        #1;
        check_frame(1);
        check_frame(2);

        // Interrupt active video in the red bar, well away from a boundary.
        for (sample = 0; sample < 173 * H_TOTAL + 517; sample = sample + 1) begin
            check_pixel(sample % H_TOTAL, sample / H_TOTAL);
            @(negedge pixel_clk);
            #1;
        end
        check_pixel(517, 173);
        #3;
        reset_n = 1'b0;
        #1;
        check_reset();
        repeat (3) begin
            @(negedge pixel_clk);
            #1;
            check_reset();
        end
        @(negedge pixel_clk);
        reset_n = 1'b1;
        #1;
        check_frame(3);

        if (completed_frames != 3)
            $fatal(1, "Expected two continuous frames plus one complete recovery frame");
        $display("VIDEO_TIMING_PASS frames=%0d reset_recovery=1", completed_frames);
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "VIDEO_TIMING_TIMEOUT: test did not finish within 100 ms");
    end
endmodule
