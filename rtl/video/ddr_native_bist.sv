`timescale 1ns/1ps
// Finite, destructive, single-owner native HMIC acceptance test. Addresses are
// physical 32-bit word offsets; a 256-bit beat advances the address by eight.
// Default coverage is two 1 MiB windows plus address sentinels, NOT a 1 GiB
// device sweep. There is no AXI B channel, WVALID, RREADY, or visibility fence.
// A final WREADY proves acceptance by this port, not physical write completion.
// After init loss, reset this engine AND the controller before recalibration.
module ddr_native_bist #(
    parameter integer TIMEOUT_CYCLES = 125_000_000,
    parameter integer WINDOW_BEATS = 32768,
    parameter integer BURST_BEATS = 16
) (
    input wire clk, reset_n, init_done,
    output reg busy, done, error,
    output wire [7:0] phase, error_code,
    output reg [31:0] compared_beats,
    output reg [27:0] first_error_addr,
    output reg [255:0] first_error_xor,
    output wire [27:0] axi_awaddr,
    output wire axi_awvalid,
    output wire [3:0] axi_awlen, axi_awuser_id,
    output wire axi_awuser_ap,
    input wire axi_awready, axi_wready,
    input wire [3:0] axi_wusero_id,
    input wire axi_wusero_last,
    output wire [255:0] axi_wdata,
    output wire [31:0] axi_wstrb,
    output wire [27:0] axi_araddr,
    output wire axi_arvalid,
    output wire [3:0] axi_arlen, axi_aruser_id,
    output wire axi_aruser_ap,
    input wire axi_arready,
    input wire [255:0] axi_rdata,
    input wire [3:0] axi_rid,
    input wire axi_rlast, axi_rvalid
);
    // State values are also useful in portable simulation diagnostics.
    localparam [3:0] IDLE=0, PREPARE=1, AW=2, WRITE=3, AR=4, READ=5,
                     ADVANCE=6, FINISHED=7, FAILED=8;
    localparam integer WATCHDOG_WIDTH = (TIMEOUT_CYCLES > 1) ? $clog2(TIMEOUT_CYCLES) : 1;
    localparam [27:0] HIGH_BASE = 28'h0000000 - WINDOW_BEATS*8;
    reg [3:0] state;
    reg started;
    reg [5:0] stage; // 0 sentinels, 1..8 full patterns, 9..46 independent masks.
    reg [1:0] subpass; // write seed, optional masked write, then read all bytes.
    reg high_window;
    reg [31:0] window_offset;
    reg [4:0] sentinel_index;
    reg [27:0] command_addr;
    reg [4:0] command_beats, beat_index;
    reg [3:0] command_id;
    reg [31:0] command_mask;
    // PDS select_ram is its documented distributed-RAM attribute. Keep this
    // shallow cache in LUT RAM with an external read register, avoiding the
    // large block-RAM clock-to-output delay on the native compare path.
    (* syn_ramstyle="select_ram" *)reg [255:0] burst_data [0:15];
    reg [4:0] preload_index;
    reg [255:0] preload_word,native_data_hold;
    reg [WATCHDOG_WIDTH-1:0] watchdog;
    reg [7:0] saved_error_code;
    wire masked_stage = stage >= 9;
    wire read_pass = masked_stage ? subpass == 2 : subpass == 1;
    wire [27:0] beat_addr = command_addr + (beat_index << 3);
    wire active_write = (state == WRITE) || (state == AW && axi_awready);
    wire active_read = (state == READ) || (state == AR && axi_arready);
    wire consumed_write = active_write && axi_wready;
    wire consumed_read = active_read && axi_rvalid;
    wire progress = consumed_write || consumed_read ||
                    (state == AW && axi_awready) || (state == AR && axi_arready);
    wire waiting = state == AW || state == WRITE || state == AR || state == READ;
    wire [255:0] expected_data;
    reg [7:0] detected_error;
    reg [27:0] detected_addr;
    reg [255:0] detected_xor;
    reg [27:0] next_addr;
    integer next_beats;

    // Native status codes: 01 init lost; 02/03 W ID/LAST; 04/05 R ID/LAST;
    // 06 data XOR; 07 unsolicited/extra R; 10/11/12/13 AW/W/AR/R timeout.
    assign error_code = saved_error_code;
    assign phase = stage == 0 ? 8'h01 : stage < 9 ? 8'h0f + stage : 8'h17 + stage;
    assign axi_awaddr = command_addr;
    assign axi_araddr = command_addr;
    assign axi_awlen = command_beats[3:0] - 1'b1;
    assign axi_arlen = command_beats[3:0] - 1'b1;
    assign axi_awuser_id = command_id;
    assign axi_aruser_id = command_id;
    assign axi_awuser_ap = 1'b0;
    assign axi_aruser_ap = 1'b0;
    assign axi_awvalid = state == AW && init_done && !error;
    assign axi_arvalid = state == AR && init_done && !error;
    assign axi_wdata = native_data_hold;
    assign axi_wstrb = command_mask;

    function automatic [27:0] sentinel_address(input [4:0] index);
        begin
            case (index)
                0: sentinel_address = 28'h0000000;
                1: sentinel_address = 28'hffffff8; // final physical 32-byte beat
                2: sentinel_address = 28'h1fffff8; // final beat of the 128 MiB spec window
                28: sentinel_address = 28'h1fffc00; // final 4 KiB page of spec window
                default: sentinel_address = 28'h1 << index; // bits 3..27
            endcase
        end
    endfunction

    function automatic [31:0] mask_for_stage(input [5:0] which);
        begin
            case (which)
                9: mask_for_stage = 32'h00000000;
                10: mask_for_stage = 32'hffffffff;
                11: mask_for_stage = 32'haaaaaaaa;
                12: mask_for_stage = 32'h55555555;
                13: mask_for_stage = 32'h0000ffff;
                14: mask_for_stage = 32'hffff0000;
                default: mask_for_stage = 32'h1 << (which-15);
            endcase
        end
    endfunction

    function automatic [255:0] pattern(input [27:0] address, input [5:0] which);
        reg [31:0] lane_word, random_word;
        integer lane;
        begin
            pattern = 0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                random_word = 32'hc001d00d ^ {4'b0000,address} ^ (32'h9e3779b9 * (lane+1));
                random_word = random_word ^ (random_word << 13);
                random_word = random_word ^ (random_word >> 17);
                random_word = random_word ^ (random_word << 5);
                case (which)
                    0: lane_word = {4'ha,address} ^ (32'h10204081 * lane) ^ 32'h68acf135;
                    1: lane_word = {4'h5,address} + 32'h9e3779b9 * (lane+1);
                    2: lane_word = 32'h00000000;
                    3: lane_word = 32'hffffffff;
                    4: lane_word = address[3] ? 32'haa55aa55 : 32'h55aa55aa;
                    5: lane_word = address[3] ? 32'h55aa55aa : 32'haa55aa55;
                    6: lane_word = 32'h1 << ((address[7:3] + lane*4) % 32);
                    7: lane_word = ~(32'h1 << ((address[7:3] + lane*4) % 32));
                    default: lane_word = random_word;
                endcase
                pattern[lane*32 +: 32] = lane_word;
            end
        end
    endfunction

    function automatic [255:0] expected_pattern(input [27:0] address, input [5:0] which);
        reg [255:0] seed;
        reg [31:0] mask;
        integer byte_index;
        begin
            seed = pattern(address, which);
            mask = mask_for_stage(which);
            expected_pattern = seed;
            if (which >= 9)
                for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1)
                    if (mask[byte_index]) expected_pattern[byte_index*8 +: 8] = ~seed[byte_index*8 +: 8];
        end
    endfunction
    // Read commands reuse the burst cache for their complete expected data.
    // Address/pattern arithmetic then runs before AR, outside the unstalled
    // read-return path; the independent memory oracle still checks its values.
    assign expected_data = native_data_hold;

    // Serialize cache preparation to one entry per cycle, allowing distributed
    // RAM and sharing the pattern generator. No native command is exposed
    // until all16 entries are filled. Registered preparation separates pattern
    // arithmetic from RAM timing; registered output removes RAM from compare
    // and native-WDATA paths. The first/next beat is prefetched before use.
    // Reset/fault may discard a partial fill; the next run overwrites all16.
    wire [27:0] preload_addr=next_addr+{20'd0,preload_index,3'b000};
    wire [3:0] cache_fill_index=preload_index[3:0]-4'd1;
    wire [3:0] next_beat_index=beat_index[3:0]+4'd1;
    always @(posedge clk)begin
        if(state==PREPARE)begin
            if(preload_index<16)
                preload_word<=read_pass?expected_pattern(preload_addr,stage):
                    (masked_stage&&subpass==1)?
                    ~pattern(preload_addr,stage):pattern(preload_addr,stage);
            if(preload_index!=0)burst_data[cache_fill_index]<=preload_word;
            if(preload_index==16)native_data_hold<=burst_data[0];
        end else if(consumed_write||consumed_read)native_data_hold<=burst_data[next_beat_index];
    end

    always @* begin
        next_addr = stage == 0 ? sentinel_address(sentinel_index) :
                    (high_window ? HIGH_BASE : 28'h0) + (window_offset << 3);
        next_beats = BURST_BEATS;
        if (next_beats > WINDOW_BEATS - window_offset) next_beats = WINDOW_BEATS - window_offset;
        // Native bursts wrap within the 1024-word column; split first.
        if (next_beats > 128 - next_addr[9:3]) next_beats = 128 - next_addr[9:3];
        if (stage == 0) next_beats = 1;
    end

    // This check sees all unbackpressured returns, including extra beats after
    // the final expected RLAST and returns while waiting for another command.
    always @* begin
        detected_error = 0; detected_addr = beat_addr; detected_xor = 0;
        if (started && !init_done) detected_error = 8'h01;
        else if ((started || init_done) && axi_rvalid && !active_read) detected_error = 8'h07;
        // Case comparisons also prevent X-valued protected-model returns from
        // manufacturing a simulation PASS; hardware equality is unchanged.
        else if (consumed_write && axi_wusero_id !== command_id) detected_error = 8'h02;
        else if (consumed_write && axi_wusero_last !== (beat_index == command_beats-1)) detected_error = 8'h03;
        else if (consumed_read && axi_rid !== command_id) detected_error = 8'h04;
        else if (consumed_read && axi_rlast !== (beat_index == command_beats-1)) detected_error = 8'h05;
        else if (consumed_read && axi_rdata !== expected_data) begin
            detected_error = 8'h06; detected_xor = axi_rdata ^ expected_data;
        end else if (waiting && !progress && watchdog == TIMEOUT_CYCLES-1) begin
            case (state)
                AW: detected_error = 8'h10;
                WRITE: detected_error = 8'h11;
                AR: detected_error = 8'h12;
                READ: detected_error = 8'h13;
                default: detected_error = 0;
            endcase
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE; started <= 0;
            busy <= 0; done <= 0; error <= 0; saved_error_code <= 0;
            compared_beats <= 0; first_error_addr <= 0; first_error_xor <= 0;
            stage <= 0; subpass <= 0; high_window <= 0; window_offset <= 0; sentinel_index <= 0;
            command_addr <= 0; command_beats <= 1; beat_index <= 0; command_id <= 0;
            command_mask <= 0; watchdog <= 0;
            preload_index <= 0;
        end else if (!error) begin
            if (detected_error != 0) begin
                state <= FAILED; busy <= 0; done <= 0; error <= 1;
                saved_error_code <= detected_error;
                first_error_addr <= detected_addr; first_error_xor <= detected_xor;
            end else begin
                if (!waiting || progress) watchdog <= 0;
                else watchdog <= watchdog + 1'b1;
                case (state)
                    IDLE: if (init_done) begin
                        started <= 1; busy <= 1; state <= PREPARE;
                    end
                    PREPARE: begin
                        if(preload_index==16)begin
                            command_addr <= next_addr;
                            command_beats <= next_beats;
                            beat_index <= 0;
                            command_id <= command_id + 1'b1;
                            command_mask <= (masked_stage && subpass == 1) ? mask_for_stage(stage) : 32'hffffffff;
                            state <= read_pass ? AR : AW;
                        end else preload_index<=preload_index+1'b1;
                    end
                    AW: if (axi_awready) begin
                        if (axi_wready) begin
                            if (command_beats == 1) state <= ADVANCE;
                            else begin beat_index <= 1; state <= WRITE; end
                        end else state <= WRITE;
                    end
                    WRITE: if (axi_wready) begin
                        if (beat_index == command_beats-1) state <= ADVANCE;
                        else beat_index <= beat_index + 1'b1;
                    end
                    AR: if (axi_arready) begin
                        if (axi_rvalid) begin
                            compared_beats <= compared_beats + 1'b1;
                            if (command_beats == 1) state <= ADVANCE;
                            else begin beat_index <= 1; state <= READ; end
                        end else state <= READ;
                    end
                    READ: if (axi_rvalid) begin
                        compared_beats <= compared_beats + 1'b1;
                        if (beat_index == command_beats-1) state <= ADVANCE;
                        else beat_index <= beat_index + 1'b1;
                    end
                    ADVANCE: begin
                        state <= PREPARE;
                        preload_index<=0;
                        if (stage == 0) begin
                            if (sentinel_index != 28) sentinel_index <= sentinel_index + 1'b1;
                            else begin
                                sentinel_index <= 0;
                                if (subpass == 0) subpass <= 1;
                                else begin stage <= 1; subpass <= 0; end
                            end
                        end else if (window_offset + command_beats < WINDOW_BEATS)
                            window_offset <= window_offset + command_beats;
                        else begin
                            window_offset <= 0;
                            if (!high_window) high_window <= 1;
                            else begin
                                high_window <= 0;
                                if (!read_pass) subpass <= subpass + 1'b1;
                                else begin
                                    subpass <= 0;
                                    if (stage == 46) state <= FINISHED;
                                    else stage <= stage + 1'b1;
                                end
                            end
                        end
                    end
                    FINISHED: begin busy <= 0; done <= 1; end
                    default: state <= FAILED;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (TIMEOUT_CYCLES < 1 || WINDOW_BEATS < 1 || WINDOW_BEATS > 4194304 ||
            BURST_BEATS < 1 || BURST_BEATS > 16)
            $fatal(1, "Invalid native BIST parameters");
    end
`endif
endmodule
