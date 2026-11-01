/* TriHa paired-cache DDR transport.
 * One owned AXI transaction; fair I/D arbitration after completion.
 * Cache-side 8x32b refills become 2x128b; scalar D stores use exact lane strobes.
 * No MMIO widening: only the declared DDR window may reach this interface.
 * Protocol violations complete the owned request with error and quarantine
 * new traffic until coordinated reset. Ordinary SLVERR is recoverable.
 */
module triha_cpu_cache_axi (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         i_arvalid_i,
    input  wire [31:0]  i_araddr_i,
    input  wire [3:0]   i_arid_i,
    input  wire [7:0]   i_arlen_i,
    output wire         i_arready_o,
    output wire         i_rvalid_o,
    output wire [31:0]  i_rdata_o,
    output wire [1:0]   i_rresp_o,
    output wire [3:0]   i_rid_o,
    output wire         i_rlast_o,
    input  wire         i_rready_i,
    input  wire         d_rd_i,
    input  wire [3:0]   d_wr_i,
    input  wire [7:0]   d_len_i,
    input  wire [31:0]  d_addr_i,
    input  wire [31:0]  d_wdata_i,
    output wire         d_accept_o,
    output wire         d_ack_o,
    output wire         d_error_o,
    output wire [31:0]  d_rdata_o,
    output reg          protocol_fault_o,
    output wire         axi_awvalid_o,
    output wire [31:0]  axi_awaddr_o,
    output wire [3:0]   axi_awid_o,
    output wire [7:0]   axi_awlen_o,
    output wire [2:0]   axi_awsize_o,
    output wire [1:0]   axi_awburst_o,
    input  wire         axi_awready_i,
    output wire         axi_wvalid_o,
    output wire [127:0] axi_wdata_o,
    output wire [15:0]  axi_wstrb_o,
    output wire         axi_wlast_o,
    input  wire         axi_wready_i,
    input  wire         axi_bvalid_i,
    input  wire [1:0]   axi_bresp_i,
    input  wire [3:0]   axi_bid_i,
    output wire         axi_bready_o,
    output wire         axi_arvalid_o,
    output wire [31:0]  axi_araddr_o,
    output wire [3:0]   axi_arid_o,
    output wire [7:0]   axi_arlen_o,
    output wire [2:0]   axi_arsize_o,
    output wire [1:0]   axi_arburst_o,
    input  wire         axi_arready_i,
    input  wire         axi_rvalid_i,
    input  wire [127:0] axi_rdata_i,
    input  wire [1:0]   axi_rresp_i,
    input  wire [3:0]   axi_rid_i,
    input  wire         axi_rlast_i,
    output wire         axi_rready_o
);
    localparam [2:0] IDLE = 0, READ_ADDR = 1, READ_DATA = 2,
        EMIT = 3, WRITE = 4, STORE_RESPONSE = 5;
    reg [2:0] state_q;
    reg owner_i_q, last_owner_d_q;
    reg [31:0] address_q;
    reg [3:0] id_q;
    reg [2:0] last_word_q, emit_word_q;
    reg [1:0] scalar_lane_q;
    reg read_beat_q, last_read_beat_q, error_q;
    reg [255:0] line_q;
    reg [127:0] write_data_q;
    reg [15:0] write_strobe_q;
    reg aw_done_q, w_done_q;
    wire d_request_w = d_rd_i || |d_wr_i;
    wire choose_i_w = i_arvalid_i && (!d_request_w || last_owner_d_q);
    wire take_i_w = i_arvalid_i && i_arready_o;
    wire take_d_w = d_request_w && d_accept_o;
    wire [31:0] request_addr_w = choose_i_w ? i_araddr_i : d_addr_i;
    wire line_request_w = choose_i_w ? i_arlen_i == 7 : (d_rd_i && d_len_i == 7);
    wire legal_ddr_w = request_addr_w >= 32'h80000000 && request_addr_w < 32'h88000000;
    wire legal_request_w = legal_ddr_w && (choose_i_w ?
        ((i_arlen_i == 7 && i_araddr_i[4:0] == 0) || (i_arlen_i == 1 && i_araddr_i[2:0] == 0)) :
        (d_addr_i[1:0] == 0 && !(d_rd_i && |d_wr_i) &&
         ((d_rd_i && (d_len_i == 0 || (d_len_i == 7 && d_addr_i[4:0] == 0))) ||
          (|d_wr_i && d_len_i == 0))));
    assign i_arready_o = rst_ni && state_q == IDLE && !protocol_fault_o && choose_i_w;
    assign d_accept_o = rst_ni && state_q == IDLE && !protocol_fault_o && !choose_i_w;
    wire [2:0] response_word_w = last_word_q == 7 ? emit_word_q : ({1'b0, scalar_lane_q} + emit_word_q);
    assign i_rvalid_o = rst_ni && state_q == EMIT && owner_i_q;
    assign i_rdata_o = line_q[response_word_w*32 +: 32];
    assign i_rresp_o = error_q ? 2'b10 : 2'b00;
    assign i_rid_o = id_q;
    assign i_rlast_o = emit_word_q == last_word_q;
    assign d_ack_o = rst_ni && ((state_q == EMIT && !owner_i_q) || state_q == STORE_RESPONSE);
    assign d_error_o = error_q;
    assign d_rdata_o = line_q[response_word_w*32 +: 32];
    assign axi_awvalid_o = rst_ni && state_q == WRITE && !aw_done_q;
    assign axi_awaddr_o = address_q;
    assign axi_awid_o = id_q;
    assign axi_awlen_o = 0;
    assign axi_awsize_o = 3'd4;
    assign axi_awburst_o = 2'b01;
    assign axi_wvalid_o = rst_ni && state_q == WRITE && !w_done_q;
    assign axi_wdata_o = write_data_q;
    assign axi_wstrb_o = write_strobe_q;
    assign axi_wlast_o = 1'b1;
    assign axi_bready_o = rst_ni && state_q == WRITE && aw_done_q && w_done_q;
    assign axi_arvalid_o = rst_ni && state_q == READ_ADDR;
    assign axi_araddr_o = address_q;
    assign axi_arid_o = id_q;
    assign axi_arlen_o = {7'b0, last_read_beat_q};
    assign axi_arsize_o = 3'd4;
    assign axi_arburst_o = 2'b01;
    assign axi_rready_o = rst_ni && state_q == READ_DATA;
    wire read_fire_w = axi_rvalid_i && axi_rready_o;
    wire read_protocol_error_w = axi_rid_i != id_q || axi_rlast_i != (read_beat_q == last_read_beat_q);
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            owner_i_q <= 0; last_owner_d_q <= 1;
            address_q <= 0; id_q <= 0;
            last_word_q <= 0; emit_word_q <= 0; scalar_lane_q <= 0;
            read_beat_q <= 0; last_read_beat_q <= 0; error_q <= 0;
            line_q <= 0; write_data_q <= 0; write_strobe_q <= 0;
            aw_done_q <= 0; w_done_q <= 0; protocol_fault_o <= 0;
        end else begin
            case (state_q)
                IDLE: if (take_i_w || take_d_w) begin
                    owner_i_q <= choose_i_w;
                    last_owner_d_q <= !choose_i_w;
                    address_q <= {request_addr_w[31:4], 4'b0};
                    id_q <= choose_i_w ? i_arid_i : 4'd2;
                    scalar_lane_q <= request_addr_w[3:2];
                    last_word_q <= choose_i_w ? i_arlen_i[2:0] : line_request_w ? 3'd7 : 3'd0;
                    last_read_beat_q <= line_request_w;
                    read_beat_q <= 0; emit_word_q <= 0;
                    error_q <= !legal_request_w;
                    aw_done_q <= 0; w_done_q <= 0;
                    write_data_q <= {96'b0, d_wdata_i} << (d_addr_i[3:2]*32);
                    write_strobe_q <= {12'b0, d_wr_i} << (d_addr_i[3:2]*4);
                    if (!legal_request_w) state_q <= EMIT;
                    else if (!choose_i_w && |d_wr_i) state_q <= WRITE;
                    else state_q <= READ_ADDR;
                end
                READ_ADDR: if (axi_arready_i) state_q <= READ_DATA;
                READ_DATA: if (read_fire_w) begin
                    if (read_beat_q) line_q[255:128] <= axi_rdata_i;
                    else line_q[127:0] <= axi_rdata_i;
                    error_q <= error_q || axi_rresp_i != 0 || read_protocol_error_w;
                    if (read_protocol_error_w) protocol_fault_o <= 1;
                    if (read_beat_q == last_read_beat_q || axi_rlast_i) state_q <= EMIT;
                    else read_beat_q <= 1;
                end
                EMIT: if (!owner_i_q || i_rready_i) begin
                    if (emit_word_q == last_word_q) state_q <= IDLE;
                    else emit_word_q <= emit_word_q + 1'b1;
                end
                WRITE: begin
                    if (axi_awvalid_o && axi_awready_i) aw_done_q <= 1;
                    if (axi_wvalid_o && axi_wready_i) w_done_q <= 1;
                    if (axi_bvalid_i && axi_bready_o) begin
                        error_q <= axi_bresp_i != 0 || axi_bid_i != id_q;
                        if (axi_bid_i != id_q) protocol_fault_o <= 1;
                        state_q <= STORE_RESPONSE;
                    end
                end
                STORE_RESPONSE: state_q <= IDLE;
                default: begin state_q <= IDLE; protocol_fault_o <= 1; end
            endcase
        end
    end
endmodule
