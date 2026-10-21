/* Independent free-clock DDR/PLL supervision. Only KEY0 clears the first fault.
 * DDR faults never reset a live controller or CPU. CPU PLL loss starts a
 * coordinated CPU/cache/CDC/controller epoch, with the free-domain error held. */
`default_nettype none
module triha_cpu_ddr_supervisor #(
    parameter integer STARTUP_CYCLES = 27000,
    parameter integer INIT_TIMEOUT_CYCLES = 135000000,
    parameter integer CLOCK_TIMEOUT_CYCLES = 27000000
) (
    input wire clk_i,
    input wire rst_ni,
    input wire cpu_pll_locked_i,
    input wire ddr_clk_i,
    input wire [7:0] ddr_status_i,
    output wire epoch_no,
    output wire free_reset_no,
    output wire ddr_reset_no,
    output wire ready_o,
    output reg fault_o,
    output reg [7:0] fault_code_o
);
    localparam integer SW = STARTUP_CYCLES > 1 ? $clog2(STARTUP_CYCLES) : 1;
    localparam integer IW = INIT_TIMEOUT_CYCLES > 1 ? $clog2(INIT_TIMEOUT_CYCLES) : 1;
    localparam integer CW = CLOCK_TIMEOUT_CYCLES > 1 ? $clog2(CLOCK_TIMEOUT_CYCLES) : 1;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [1:0] free_release_q;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [1:0] ddr_release_q;
    reg [SW-1:0] startup_count_q;
    reg startup_done_q;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [8:0] status_meta_q, status_sync_q;
    reg [7:0] ddr_count_q;
    wire ddr_beat_w = ddr_count_q[7];
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg beat_meta_q, beat_sync_q;
    reg beat_last_q, online_seen_q, cpu_seen_q;
    reg [IW-1:0] init_age_q;
    reg [CW-1:0] beat_age_q;
    wire free_reset_n = free_release_q[1];
    wire online_w = (&status_sync_q[5:0]) && !(|status_sync_q[7:6]);
    assign epoch_no = free_reset_n && startup_done_q && cpu_pll_locked_i;
    assign free_reset_no = free_reset_n;
    assign ddr_reset_no = ddr_release_q[1];
    assign ready_o = online_w && !fault_o;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) free_release_q <= 0;
        else free_release_q <= {free_release_q[0],1'b1};
    end
    always @(posedge ddr_clk_i or negedge epoch_no) begin
        if (!epoch_no) ddr_release_q <= 0;
        else ddr_release_q <= {ddr_release_q[0],1'b1};
    end
    always @(posedge ddr_clk_i or negedge ddr_reset_no) begin
        if (!ddr_reset_no) ddr_count_q <= 0;
        else ddr_count_q <= ddr_count_q+1'b1;
    end
    always @(posedge clk_i or negedge free_reset_n) begin
        if (!free_reset_n) begin
            startup_count_q <= 0; startup_done_q <= 0;
            status_meta_q <= 0; status_sync_q <= 0;
            beat_meta_q <= 0; beat_sync_q <= 0; beat_last_q <= 0;
            online_seen_q <= 0; cpu_seen_q <= 0;
            init_age_q <= 0; beat_age_q <= 0;
            fault_o <= 0; fault_code_o <= 0;
        end else begin
            status_meta_q <= {cpu_pll_locked_i,ddr_status_i};
            status_sync_q <= status_meta_q;
            beat_meta_q <= ddr_beat_w; beat_sync_q <= beat_meta_q; beat_last_q <= beat_sync_q;
            if (!startup_done_q) begin
                if (startup_count_q == STARTUP_CYCLES-1) startup_done_q <= 1;
                else startup_count_q <= startup_count_q+1'b1;
            end
            if (status_sync_q[8]) cpu_seen_q <= 1;
            if (online_w) online_seen_q <= 1;
            if (startup_done_q && !online_seen_q && init_age_q < INIT_TIMEOUT_CYCLES-1)
                init_age_q <= init_age_q+1'b1;
            if (!online_seen_q || beat_sync_q != beat_last_q) beat_age_q <= 0;
            else if (beat_age_q < CLOCK_TIMEOUT_CYCLES-1) beat_age_q <= beat_age_q+1'b1;
            if (!fault_o) begin
                if (cpu_seen_q && !status_sync_q[8]) begin fault_o <= 1; fault_code_o <= 8'he5; end
                else if (status_sync_q[6]) begin fault_o <= 1; fault_code_o <= 8'he2; end
                else if (status_sync_q[7]) begin fault_o <= 1; fault_code_o <= 8'he3; end
                else if (online_seen_q && !online_w) begin fault_o <= 1; fault_code_o <= 8'he1; end
                else if (!online_seen_q && startup_done_q && init_age_q == INIT_TIMEOUT_CYCLES-1) begin
                    fault_o <= 1; fault_code_o <= 8'he0;
                end else if (online_seen_q && beat_sync_q == beat_last_q && beat_age_q == CLOCK_TIMEOUT_CYCLES-1) begin
                    fault_o <= 1; fault_code_o <= 8'he4;
                end
            end
        end
    end
endmodule
`default_nettype wire
