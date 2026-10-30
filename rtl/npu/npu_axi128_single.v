`timescale 1ns/1ps

module npu_axi128_single (
    input wire clk_i,
    input wire rst_ni,
    input wire req_valid_i,
    input wire req_write_i,
    input wire [31:0] req_addr_i,
    input wire [127:0] req_wdata_i,
    input wire [15:0] req_wstrb_i,
    output wire req_ready_o,
    output reg rsp_valid_o,
    output reg [127:0] rsp_rdata_o,
    output reg rsp_error_o,
    output reg fault_o,
    output wire [3:0] m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [7:0] m_axi_arlen_o,
    output wire [2:0] m_axi_arsize_o,
    output wire [1:0] m_axi_arburst_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire [3:0] m_axi_rid_i,
    input wire [127:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,
    output wire [3:0] m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [7:0] m_axi_awlen_o,
    output wire [2:0] m_axi_awsize_o,
    output wire [1:0] m_axi_awburst_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [127:0] m_axi_wdata_o,
    output wire [15:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire [3:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o
);
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_READ_ADDRESS = 3'd1;
    localparam [2:0] STATE_READ_DATA = 3'd2;
    localparam [2:0] STATE_READ_DRAIN = 3'd3;
    localparam [2:0] STATE_WRITE_SEND = 3'd4;
    localparam [2:0] STATE_WRITE_RESPONSE = 3'd5;

    reg [2:0] state_q;
    reg [31:0] address_q;
    reg [127:0] write_data_q;
    reg [15:0] write_strobes_q;
    reg aw_pending_q;
    reg w_pending_q;

    wire request_legal;
    wire read_error;
    wire write_error;
    wire aw_complete;
    wire w_complete;

    // Alignment makes the final legal address 0x87fffff0; its entire 16-byte
    // beat is inside the 128 MiB window. Read commands do not use WSTRB.
    assign request_legal = (req_addr_i[31:27] == 5'b10000)
        && (req_addr_i[3:0] == 4'b0000)
        && (!req_write_i || (|req_wstrb_i));
    assign read_error = (m_axi_rid_i != 4'd0)
        || (m_axi_rresp_i != 2'b00) || !m_axi_rlast_i;
    assign write_error = (m_axi_bid_i != 4'd0) || (m_axi_bresp_i != 2'b00);
    assign aw_complete = !aw_pending_q || m_axi_awready_i;
    assign w_complete = !w_pending_q || m_axi_wready_i;

    assign req_ready_o = rst_ni && (state_q == STATE_IDLE) && !fault_o;
    assign m_axi_arid_o = 4'b0;
    assign m_axi_araddr_o = address_q;
    assign m_axi_arlen_o = 8'b0;
    assign m_axi_arsize_o = 3'd4;
    assign m_axi_arburst_o = 2'b01;
    assign m_axi_arvalid_o = (state_q == STATE_READ_ADDRESS);
    assign m_axi_rready_o = (state_q == STATE_READ_DATA) || (state_q == STATE_READ_DRAIN);
    assign m_axi_awid_o = 4'b0;
    assign m_axi_awaddr_o = address_q;
    assign m_axi_awlen_o = 8'b0;
    assign m_axi_awsize_o = 3'd4;
    assign m_axi_awburst_o = 2'b01;
    assign m_axi_awvalid_o = (state_q == STATE_WRITE_SEND) && aw_pending_q;
    assign m_axi_wdata_o = write_data_q;
    assign m_axi_wstrb_o = write_strobes_q;
    assign m_axi_wlast_o = 1'b1;
    assign m_axi_wvalid_o = (state_q == STATE_WRITE_SEND) && w_pending_q;
    assign m_axi_bready_o = (state_q == STATE_WRITE_RESPONSE);

    // All interfaces use clk_i. An error in the external AXI transaction
    // requires coordinated reset of both this master and its downstream peer.
    // There is deliberately no timeout: a READY or VALID wait is legal.
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= STATE_IDLE;
            address_q <= 32'b0;
            write_data_q <= 128'b0;
            write_strobes_q <= 16'b0;
            aw_pending_q <= 1'b0;
            w_pending_q <= 1'b0;
            rsp_valid_o <= 1'b0;
            rsp_rdata_o <= 128'b0;
            rsp_error_o <= 1'b0;
            fault_o <= 1'b0;
        end else begin
            rsp_valid_o <= 1'b0;
            case (state_q)
                STATE_IDLE: begin
                    if (req_valid_i && req_ready_o) begin
                        rsp_rdata_o <= 128'b0;
                        rsp_error_o <= 1'b0;
                        if (!request_legal) begin
                            // Local rejection has no uncompleted AXI transfer,
                            // so it reports an error without latching fault.
                            rsp_valid_o <= 1'b1;
                            rsp_error_o <= 1'b1;
                        end else begin
                            address_q <= req_addr_i;
                            if (req_write_i) begin
                                write_data_q <= req_wdata_i;
                                write_strobes_q <= req_wstrb_i;
                                aw_pending_q <= 1'b1;
                                w_pending_q <= 1'b1;
                                state_q <= STATE_WRITE_SEND;
                            end else begin
                                state_q <= STATE_READ_ADDRESS;
                            end
                        end
                    end
                end
                STATE_READ_ADDRESS: begin
                    if (m_axi_arready_i)
                        state_q <= STATE_READ_DATA;
                end
                STATE_READ_DATA: begin
                    if (m_axi_rvalid_i) begin
                        rsp_rdata_o <= m_axi_rdata_i;
                        if (read_error)
                            fault_o <= 1'b1;
                        if (m_axi_rlast_i) begin
                            rsp_error_o <= read_error;
                            rsp_valid_o <= 1'b1;
                            state_q <= STATE_IDLE;
                        end else begin
                            // Do not reuse the R channel after a malformed
                            // single beat until its actual LAST has arrived.
                            state_q <= STATE_READ_DRAIN;
                        end
                    end
                end
                STATE_READ_DRAIN: begin
                    if (m_axi_rvalid_i && m_axi_rlast_i) begin
                        rsp_error_o <= 1'b1;
                        rsp_valid_o <= 1'b1;
                        state_q <= STATE_IDLE;
                    end
                end
                STATE_WRITE_SEND: begin
                    if (m_axi_awready_i)
                        aw_pending_q <= 1'b0;
                    if (m_axi_wready_i)
                        w_pending_q <= 1'b0;
                    if (aw_complete && w_complete)
                        state_q <= STATE_WRITE_RESPONSE;
                end
                STATE_WRITE_RESPONSE: begin
                    if (m_axi_bvalid_i) begin
                        rsp_error_o <= write_error;
                        rsp_valid_o <= 1'b1;
                        if (write_error)
                            fault_o <= 1'b1;
                        state_q <= STATE_IDLE;
                    end
                end
                default: begin
                    state_q <= STATE_IDLE;
                    fault_o <= 1'b1;
                end
            endcase
        end
    end
endmodule
