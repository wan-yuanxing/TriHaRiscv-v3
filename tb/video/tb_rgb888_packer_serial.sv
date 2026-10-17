`timescale 1ns/1ps
`default_nettype none

// The oracle is a queue of bytes accepted at the public pixel interface. It
// does not inspect DUT state or reproduce its reservoir insertion algorithm.
module packer_checker #(
    parameter integer MODE = 0
)(output reg done = 0);
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0, flush = 0;
    reg pixel_valid = 0, pixel_last = 0;
    reg [23:0] pixel_rgb = 0;
    wire pixel_ready, s_valid, s_row_last;
    wire [127:0] s_data;
    wire [15:0] s_keep;
    reg s_ready = 0;
    rgb888_packer #(.ALLOW_SIMULTANEOUS_TRANSFER(MODE)) dut(.*);

    // Explicit mode 1 and omitted/default mode must match the frozen source
    // for the whole visible waveform, including invalid and blocked cycles.
    generate if (MODE == 1) begin : g_equivalence
        wire original_pixel_ready, original_s_valid, original_s_row_last;
        wire [127:0] original_s_data;
        wire [15:0] original_s_keep;
        wire default_pixel_ready, default_s_valid, default_s_row_last;
        wire [127:0] default_s_data;
        wire [15:0] default_s_keep;
        rgb888_packer_legacy_model original(
            .clk(clk), .reset_n(reset_n), .flush(flush),
            .pixel_valid(pixel_valid), .pixel_rgb(pixel_rgb), .pixel_last(pixel_last),
            .pixel_ready(original_pixel_ready), .s_valid(original_s_valid),
            .s_data(original_s_data), .s_keep(original_s_keep),
            .s_row_last(original_s_row_last), .s_ready(s_ready)
        );
        rgb888_packer default_mode(
            .clk(clk), .reset_n(reset_n), .flush(flush),
            .pixel_valid(pixel_valid), .pixel_rgb(pixel_rgb), .pixel_last(pixel_last),
            .pixel_ready(default_pixel_ready), .s_valid(default_s_valid),
            .s_data(default_s_data), .s_keep(default_s_keep),
            .s_row_last(default_s_row_last), .s_ready(s_ready)
        );
        always @(negedge clk) begin
            #2;
            if ({pixel_ready,s_valid,s_data,s_keep,s_row_last} !==
                {original_pixel_ready,original_s_valid,original_s_data,original_s_keep,original_s_row_last})
                $fatal(1,"DEFAULT_EXPLICIT_WAVEFORM_MISMATCH cycle=%0d",cycle);
            if ({default_pixel_ready,default_s_valid,default_s_data,default_s_keep,default_s_row_last} !==
                {original_pixel_ready,original_s_valid,original_s_data,original_s_keep,original_s_row_last})
                $fatal(1,"DEFAULT_OMITTED_WAVEFORM_MISMATCH cycle=%0d",cycle);
        end
        always @(posedge clk) begin
            #1;
            if ({dut.reservoir,dut.count,dut.ending} !==
                {original.reservoir,original.count,original.ending})
                $fatal(1,"DEFAULT_REGISTER_WAVEFORM_MISMATCH cycle=%0d",cycle);
            if ({default_mode.reservoir,default_mode.count,default_mode.ending} !==
                {original.reservoir,original.count,original.ending})
                $fatal(1,"DEFAULT_REGISTER_OMITTED_MISMATCH cycle=%0d",cycle);
        end
    end endgenerate

    reg [7:0] bytes [0:4095];
    integer written = 0, consumed = 0, rows = 0;
    integer total_pixels = 0, total_bytes = 0, total_rows = 0;
    integer cycle = 0, concurrent_transfers = 0, blocked_cycles = 0;
    integer count_before, k, beat_bytes;
    reg row_closed = 0;
    reg blocked = 0;
    reg [144:0] held = 0;
    reg [15:0] expected_keep;
    reg expected_valid, expected_ready;
    reg auto_ready = 0;
    reg [31:0] rng = 32'h53a8c41f ^ (32'(MODE) << 16);
    reg [18:0] occupancy_seen = 0, flush_seen = 0, reset_seen = 0;
    reg [2:0] full_ready_probe_seen = 0;
    reg red_ready = 0, red_concurrency = 0;
    reg full_phase = 0;
    reg full_phase_armed = 0;
    integer full_cycles = 0, full_inputs = 0, full_outputs = 0;

    always @(negedge clk) begin
        rng = {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if (auto_ready) s_ready = (rng[3:0] > 4'd4);
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        count_before = written - consumed;
        if (!reset_n || flush) begin
            if (pixel_ready !== 1'b0 || s_valid !== 1'b0)
                $fatal(1,"CANCEL_HANDSHAKE_NOT_GATED mode=%0d",MODE);
            written = 0; consumed = 0; rows = 0; row_closed = 0; blocked = 0;
        end else begin
            if (count_before < 0 || count_before > 18)
                $fatal(1,"ORACLE_OCCUPANCY_RANGE mode=%0d count=%0d",MODE,count_before);
            occupancy_seen[count_before] = 1'b1;
            expected_valid = (count_before >= 16 || (row_closed && count_before != 0));
            expected_ready = !row_closed && (count_before <= 15 ||
                             (MODE != 0 && expected_valid && s_ready));
            expected_keep = count_before >= 16 ? 16'hffff :
                            16'((17'h00001 << count_before) - 17'h00001);
            if (s_valid !== expected_valid || s_keep !== expected_keep ||
                s_row_last !== (row_closed && count_before <= 16))
                $fatal(1,"PUBLIC_CONTROL_ORACLE mode=%0d cycle=%0d count=%0d",MODE,cycle,count_before);
            if (!(red_ready || red_concurrency) && pixel_ready !== expected_ready)
                $fatal(1,"PIXEL_READY_ORACLE mode=%0d cycle=%0d count=%0d",MODE,cycle,count_before);
            if (blocked && (!s_valid || {s_data,s_keep,s_row_last} !== held))
                $fatal(1,"BLOCKED_PAYLOAD_CHANGED mode=%0d cycle=%0d",MODE,cycle);
            blocked = s_valid && !s_ready;
            held = {s_data,s_keep,s_row_last};
            if (blocked) blocked_cycles = blocked_cycles + 1;
            if (pixel_valid && pixel_ready && s_valid && s_ready) begin
                concurrent_transfers = concurrent_transfers + 1;
                if (MODE == 0) $fatal(1,"SERIAL_CONCURRENT_TRANSFERS cycle=%0d count=%0d",cycle,count_before);
            end
            if (full_phase) begin
                full_cycles = full_cycles + 1;
                if (pixel_valid && pixel_ready) full_inputs = full_inputs + 1;
                if (s_valid && s_ready) full_outputs = full_outputs + 1;
            end
            if (s_valid && s_ready) begin
                beat_bytes = 0;
                for (k = 0; k < 16; k = k + 1) if (s_keep[k]) begin
                    if (consumed >= written || s_data[k*8+:8] !== bytes[consumed % 4096])
                        $fatal(1,"BYTE_ORACLE mode=%0d cycle=%0d byte=%0d actual=%02x expected=%02x",MODE,cycle,consumed,s_data[k*8+:8],bytes[consumed % 4096]);
                    consumed = consumed + 1;
                    total_bytes = total_bytes + 1;
                    beat_bytes = beat_bytes + 1;
                end
                if (beat_bytes == 0) $fatal(1,"EMPTY_BEAT mode=%0d",MODE);
                if (s_row_last) begin
                    if (!row_closed || consumed != written)
                        $fatal(1,"ROW_BOUNDARY_ORACLE mode=%0d",MODE);
                    row_closed = 0; rows = rows + 1; total_rows = total_rows + 1;
                end else if (s_keep !== 16'hffff)
                    $fatal(1,"PARTIAL_INTERIOR_BEAT mode=%0d",MODE);
            end
            if (pixel_valid && pixel_ready) begin
                if (row_closed) $fatal(1,"INPUT_CROSSED_ROW mode=%0d",MODE);
                bytes[written % 4096] = pixel_rgb[23:16];
                bytes[(written+1) % 4096] = pixel_rgb[15:8];
                bytes[(written+2) % 4096] = pixel_rgb[7:0];
                written = written + 3;
                total_pixels = total_pixels + 1;
                if (pixel_last) row_closed = 1;
            end
        end
    end

    function automatic [23:0] color(input integer index, input integer tag);
        color = {8'(index*7+tag),8'(index*13+tag+37),8'(index*29+tag+101)};
    endfunction

    task automatic send_pixels(input integer width, input integer tag, input bit close_row);
        integer index;
        begin
            for (index = 0; index < width; index = index + 1) begin
                @(negedge clk);
                if (full_phase_armed) begin full_phase = 1; full_phase_armed = 0; end
                pixel_valid = 1; pixel_last = close_row && index == width-1;
                pixel_rgb = color(index,tag);
                @(posedge clk);
                while (!pixel_ready) @(posedge clk);
            end
            @(negedge clk); pixel_valid = 0; pixel_last = 0;
        end
    endtask

    task automatic send_row(input integer width, input integer tag);
        integer expected_rows;
        begin
            expected_rows = rows + 1;
            send_pixels(width,tag,1'b1);
            wait (rows == expected_rows);
            #1;
            if (consumed != written) $fatal(1,"ROW_NOT_DRAINED mode=%0d",MODE);
        end
    endtask

    task automatic cancel_at_count(input integer target, input bit use_reset);
        integer limit;
        begin
            auto_ready = 0;
            limit = 0;
            while (written-consumed != target) begin
                @(negedge clk);
                s_ready = written-consumed >= 16;
                pixel_valid = !s_ready; pixel_last = 0; pixel_rgb = color(limit,target+19);
                @(posedge clk); #1;
                limit = limit + 1;
                if (limit > 100) $fatal(1,"TARGET_OCCUPANCY_UNREACHABLE mode=%0d target=%0d",MODE,target);
            end
            @(negedge clk);
            pixel_valid = 1; pixel_last = 1; s_ready = 0;
            if (target >= 16) begin
                #1; ready_low = pixel_ready; s_ready = 1; #1;
                if (MODE == 0 && (ready_low !== 1'b0 || pixel_ready !== ready_low))
                    $fatal(1,"SERIAL_READY_DEPENDENCE_COUNT count=%0d",target);
                full_ready_probe_seen[target-16] = 1'b1;
                s_ready = 0;
            end
            if (use_reset) begin reset_seen[target] = 1'b1; reset_n = 0; end
            else begin flush_seen[target] = 1'b1; flush = 1; end
            #1;
            if (s_valid !== 1'b0 || pixel_ready !== 1'b0)
                $fatal(1,"CANCEL_IMMEDIATE_GATING mode=%0d target=%0d",MODE,target);
            if (use_reset && s_data !== 128'b0)
                $fatal(1,"ASYNC_RESET_DATA mode=%0d target=%0d",MODE,target);
            @(posedge clk); #1;
            if (s_data !== 128'b0 || s_keep !== 16'b0 || s_row_last !== 1'b0)
                $fatal(1,"CANCEL_REGISTER_CLEAR mode=%0d target=%0d",MODE,target);
            @(negedge clk);
            pixel_valid = 0; pixel_last = 0; flush = 0; reset_n = 1; s_ready = 1;
            send_row(target+1,target+53);
        end
    endtask

    integer width, row, target;
    reg ready_low;
    initial begin
        red_ready = $test$plusargs("RED_READY");
        red_concurrency = $test$plusargs("RED_CONCURRENCY");
        repeat (3) @(negedge clk);
        reset_n = 1;
        // Reach 18 bytes without draining, then probe downstream READY between
        // clock edges. Both red runs compile the old implementation successfully.
        send_pixels(6,3,1'b0);
        @(negedge clk); pixel_valid = 1; pixel_rgb = 24'h7192b3;
        s_ready = 0; #1; ready_low = pixel_ready; s_ready = 1; #1;
        if (MODE == 0 && !red_concurrency && pixel_ready !== ready_low)
            $fatal(1,"SERIAL_READY_DEPENDENCE count=18 ready0=%0b ready1=%0b",ready_low,pixel_ready);
        @(posedge clk); #1;
        @(negedge clk); pixel_valid = 0; flush = 1;
        @(negedge clk); flush = 0;
        if (red_ready || red_concurrency) begin done = 1; end
        else begin
            auto_ready = 1;
            for (width = 1; width <= 19; width = width + 1) begin
                send_row(width,11+width);
                send_row(width,47+width);
            end
            send_row(400,91); send_row(800,109);
            auto_ready = 0;
            for (target = 0; target <= 18; target = target + 1) begin
                cancel_at_count(target,1'b0);
                cancel_at_count(target,1'b1);
            end
            @(negedge clk); s_ready = 1; full_phase_armed = 1;
            for (row = 0; row < 600; row = row + 1) send_row(800,row+123);
            full_phase = 0;
            if (full_inputs != 480000 || full_outputs != 90000)
                $fatal(1,"FULL_FRAME_TRANSFER_COUNTS mode=%0d inputs=%0d outputs=%0d",MODE,full_inputs,full_outputs);
            if (MODE == 0 && full_cycles != 570000)
                $fatal(1,"SERIAL_FULL_FRAME_CYCLES actual=%0d expected=570000",full_cycles);
            if (occupancy_seen !== 19'h7ffff || flush_seen !== 19'h7ffff || reset_seen !== 19'h7ffff)
                $fatal(1,"OCCUPANCY_COVERAGE mode=%0d seen=%h flush=%h reset=%h",MODE,occupancy_seen,flush_seen,reset_seen);
            if (full_ready_probe_seen !== 3'b111)
                $fatal(1,"FULL_READY_PROBE_COVERAGE mode=%0d seen=%h",MODE,full_ready_probe_seen);
            if (blocked_cycles == 0 || (MODE == 1 && concurrent_transfers == 0))
                $fatal(1,"TRANSFER_COVERAGE mode=%0d",MODE);
            $display("PACKER_MODE_PASS mode=%0d pixels=%0d bytes=%0d rows=%0d stalls=%0d concurrent=%0d occupancy=%h flush=%h reset=%h full_inputs=%0d full_outputs=%0d full_cycles=%0d",MODE,total_pixels,total_bytes,total_rows,blocked_cycles,concurrent_transfers,occupancy_seen,flush_seen,reset_seen,full_inputs,full_outputs,full_cycles);
            done = 1;
        end
    end
endmodule

module tb_rgb888_packer_serial;
    wire done0, done1;
    packer_checker #(.MODE(0)) serial_mode(.done(done0));
    packer_checker #(.MODE(1)) concurrent_mode(.done(done1));
    initial begin
        wait(done0 && done1);
        $display("RGB888_PACKER_SERIAL_PASS");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"PACKER_PROTOTYPE_WATCHDOG");
    end
endmodule
`default_nettype wire
