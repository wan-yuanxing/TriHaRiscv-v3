`timescale 1ns/1ps
module tb_video_async_fifo;
    parameter integer TEST_ADDR_WIDTH = 3;
    parameter integer WR_HALF = 5;
    parameter integer RD_HALF = 7;
    parameter integer RD_PHASE = 2;
    localparam integer DEPTH = 1 << TEST_ADDR_WIDTH;
    reg wr_clk = 0, rd_clk = 0;
    always #(WR_HALF) wr_clk = ~wr_clk;
    initial begin #(RD_PHASE); forever #(RD_HALF) rd_clk = ~rd_clk; end
    reg wr_reset_n = 0, rd_reset_n = 0;
    reg wr_valid = 0, rd_ready = 0;
    reg [47:0] wr_data = 0;
    wire wr_ready, rd_valid;
    wire [47:0] rd_data;
    wire [TEST_ADDR_WIDTH:0] wr_occupancy;
    video_async_fifo #(.DATA_WIDTH(48), .ADDR_WIDTH(TEST_ADDR_WIDTH)) dut (.*);

    // Independent FIFO oracle: the accepted stream is a plain unbounded queue.
    reg [47:0] expected [0:199999];
    integer pushed = 0, popped = 0, sequence_id = 0;
    integer mode = 0, read_mode = 0, cycles = 0, full_hits = 0;
    reg [31:0] rng_w = 32'h13579bdf, rng_r = 32'h89abcdef;
    reg was_stalled = 0;
    reg [47:0] stalled_data;
    function [31:0] prng(input [31:0] s);
        prng = {s[30:0], s[31]^s[21]^s[1]^s[0]};
    endfunction
    always @(negedge wr_clk) begin
        rng_w = prng(rng_w);
        wr_valid = wr_reset_n && ((mode == 1) || (mode == 2 && rng_w[1:0] != 0));
        wr_data = {16'hcafe, sequence_id[31:0]};
    end
    always @(negedge rd_clk) begin
        rng_r = prng(rng_r);
        rd_ready = rd_reset_n && ((read_mode == 1) || (read_mode == 2 && rng_r[2:0] > 2));
    end
    always @(posedge wr_clk) begin
        if (wr_reset_n) begin
            if (wr_occupancy > DEPTH) $fatal(1,"RAM occupancy exceeds capacity");
            if (wr_valid && !wr_ready) full_hits = full_hits + 1;
            if (wr_valid && wr_ready) begin
                expected[pushed] = wr_data;
                pushed = pushed + 1;
                sequence_id = sequence_id + 1;
            end
        end
    end
    always @(posedge rd_clk) begin
        if (!rd_reset_n) was_stalled = 0;
        else begin
            if (was_stalled && (!rd_valid || rd_data !== stalled_data))
                $fatal(1,"stalled output changed");
            if (rd_valid && rd_ready) begin
                if (popped >= pushed) $fatal(1,"unexpected FIFO output");
                if (rd_data !== expected[popped])
                    $fatal(1,"queue mismatch index=%0d got=%h expected=%h",popped,rd_data,expected[popped]);
                popped = popped + 1;
            end
            was_stalled = rd_valid && !rd_ready;
            stalled_data = rd_data;
        end
    end
    task coordinated_reset;
        begin
            mode = 0; read_mode = 0;
            wr_reset_n = 0; rd_reset_n = 0;
            repeat (5) @(negedge wr_clk);
            pushed = 0; popped = 0; sequence_id = 0;
            wr_reset_n = 1; rd_reset_n = 1;
            repeat (5) @(negedge wr_clk);
            if (rd_valid || wr_occupancy != 0 || !wr_ready) $fatal(1,"reset did not empty FIFO");
        end
    endtask
    task drain;
        integer timeout_count;
        begin
            mode = 0;
            @(negedge wr_clk);
            read_mode = 1;
            timeout_count = 0;
            while ((popped != pushed || rd_valid) && timeout_count < 20000) begin
                @(negedge rd_clk); timeout_count = timeout_count + 1;
            end
            repeat (6) @(negedge rd_clk);
            if (popped != pushed || rd_valid) $fatal(1,"FIFO drain timed out");
        end
    endtask
    initial begin
        coordinated_reset();
        mode = 1; read_mode = 0;
        repeat (DEPTH * 8 + 30) @(negedge wr_clk);
        if (pushed != DEPTH + 1 || wr_ready || !rd_valid)
            $fatal(1,"capacity expected RAM+held word=%0d got=%0d ready=%b valid=%b", DEPTH+1,pushed,wr_ready,rd_valid);
        drain();
        mode = 2; read_mode = 2;
        repeat (DEPTH*40 > 6000 ? DEPTH*40 : 6000) @(negedge wr_clk);
        drain();
        if (sequence_id < DEPTH * 10 || full_hits == 0) $fatal(1,"insufficient wrap/full coverage");
        // Coordinated reset with both RAM and output occupied discards the old epoch.
        mode = 1; read_mode = 0;
        repeat (DEPTH * 4 + 20) @(negedge wr_clk);
        coordinated_reset();
        mode = 2; read_mode = 2;
        repeat (1500) @(negedge wr_clk);
        drain();
        $display("VIDEO_ASYNC_FIFO_PASS depth=%0d wr_half=%0d rd_half=%0d phase=%0d accepted=%0d",DEPTH,WR_HALF,RD_HALF,RD_PHASE,pushed);
        $finish;
    end
    initial begin #5000000; $fatal(1,"FIFO watchdog"); end
endmodule
