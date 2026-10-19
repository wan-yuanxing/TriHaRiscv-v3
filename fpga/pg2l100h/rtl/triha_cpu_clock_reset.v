/* Board reference clock and coordinated asynchronous-assert/synchronous-release reset. */
module triha_cpu_clock_reset (
    input  wire ref_clk_pi,
    input  wire ref_clk_ni,
    input  wire rst_ni,
    output wire cpu_clk_o,
    output wire pll_locked_o,
    output wire cpu_rst_no
);
    wire reference_clk;
    GTP_INBUFDS u_reference (.I(ref_clk_pi), .IB(ref_clk_ni), .O(reference_clk));
    cpu_board_pll u_pll (.clkin1(reference_clk), .clkout0(cpu_clk_o), .lock(pll_locked_o));

    wire async_ready = rst_ni && pll_locked_o;
    (* syn_preserve = 1 *) reg [2:0] release_q;
    always @(posedge cpu_clk_o or negedge async_ready) begin
        if (!async_ready)
            release_q <= 3'b000;
        else
            release_q <= {release_q[1:0], 1'b1};
    end
    assign cpu_rst_no = async_ready && release_q[2];
endmodule
