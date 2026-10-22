`timescale 1ns/1ps
`default_nettype none
`include "video_capture_v2.vh"
`include "video_display.vh"
// Same-clock AXI-Lite decoder: lane 0 ABI2 capture, lane 1 display.
// One read and one write may proceed independently. Reset is coordinated with
// all masters/endpoints; it cannot cancel a published transaction in isolation.
module video_axil_decode (
    input wire clk_i,
    input wire rst_ni,
    input wire [31:0] s_axi_awaddr_i,
    output wire [63:0] m_axi_awaddr_o,
    input wire [2:0] s_axi_awprot_i,
    output wire [5:0] m_axi_awprot_o,
    input wire s_axi_awvalid_i,
    output wire [1:0] m_axi_awvalid_o,
    output wire s_axi_awready_o,
    input wire [1:0] m_axi_awready_i,
    input wire [31:0] s_axi_wdata_i,
    output wire [63:0] m_axi_wdata_o,
    input wire [3:0] s_axi_wstrb_i,
    output wire [7:0] m_axi_wstrb_o,
    input wire s_axi_wvalid_i,
    output wire [1:0] m_axi_wvalid_o,
    output wire s_axi_wready_o,
    input wire [1:0] m_axi_wready_i,
    output wire [1:0] s_axi_bresp_o,
    input wire [3:0] m_axi_bresp_i,
    output wire s_axi_bvalid_o,
    input wire [1:0] m_axi_bvalid_i,
    input wire s_axi_bready_i,
    output wire [1:0] m_axi_bready_o,
    input wire [31:0] s_axi_araddr_i,
    output wire [63:0] m_axi_araddr_o,
    input wire [2:0] s_axi_arprot_i,
    output wire [5:0] m_axi_arprot_o,
    input wire s_axi_arvalid_i,
    output wire [1:0] m_axi_arvalid_o,
    output wire s_axi_arready_o,
    input wire [1:0] m_axi_arready_i,
    output wire [31:0] s_axi_rdata_o,
    input wire [63:0] m_axi_rdata_i,
    output wire [1:0] s_axi_rresp_o,
    input wire [3:0] m_axi_rresp_i,
    output wire s_axi_rvalid_o,
    input wire [1:0] m_axi_rvalid_i,
    input wire s_axi_rready_i,
    output wire [1:0] m_axi_rready_o
);
    localparam [1:0] COLLECT = 2'd0, ISSUE = 2'd1, RESPONSE = 2'd2;
    localparam [1:0] MISS = 2'd2;
    reg [1:0] write_state, read_state, write_route, read_route;
    reg aw_full, w_full, aw_sent, w_sent;
    reg [31:0] awaddr, wdata, araddr;
    reg [2:0] awprot, arprot;
    reg [3:0] wstrb;

    function [1:0] decode;
        input [31:0] address;
        begin
            decode = MISS;
            if ((^address) !== 1'bx && address[1:0] === 2'b00) begin
                if (address >= `VCAP_MMIO_BASE &&
                    {32'd0,address} < (64'd0 + `VCAP_MMIO_BASE + `VCAP_MMIO_BYTES))
                    decode = 2'd0;
                else if (address >= `VDISP_BASE &&
                    {32'd0,address} < (64'd0 + `VDISP_BASE + `VDISP_REGION_BYTES))
                    decode = 2'd1;
            end
        end
    endfunction
    wire [1:0] write_select = write_route == 0 ? 2'b01 : write_route == 1 ? 2'b10 : 2'b00;
    wire [1:0] read_select = read_route == 0 ? 2'b01 : read_route == 1 ? 2'b10 : 2'b00;
    assign s_axi_awready_o = rst_ni && write_state == COLLECT && !aw_full;
    assign s_axi_wready_o = rst_ni && write_state == COLLECT && !w_full;
    assign s_axi_arready_o = rst_ni && read_state == COLLECT;
    assign m_axi_awaddr_o = {2{awaddr}};
    assign m_axi_awprot_o = {2{awprot}};
    assign m_axi_wdata_o = {2{wdata}};
    assign m_axi_wstrb_o = {2{wstrb}};
    assign m_axi_araddr_o = {2{araddr}};
    assign m_axi_arprot_o = {2{arprot}};
    assign m_axi_awvalid_o = write_select & {2{rst_ni && write_state == ISSUE && !aw_sent}};
    assign m_axi_wvalid_o = write_select & {2{rst_ni && write_state == ISSUE && !w_sent}};
    assign m_axi_bready_o = write_select & {2{rst_ni && write_state == RESPONSE && s_axi_bready_i}};
    assign m_axi_arvalid_o = read_select & {2{rst_ni && read_state == ISSUE}};
    assign m_axi_rready_o = read_select & {2{rst_ni && read_state == RESPONSE && s_axi_rready_i}};
    assign s_axi_bvalid_o = rst_ni && write_state == RESPONSE &&
        (write_route == MISS || |(m_axi_bvalid_i & write_select));
    assign s_axi_bresp_o = write_route == MISS ? 2'b11 : m_axi_bresp_i[write_route*2+:2];
    assign s_axi_rvalid_o = rst_ni && read_state == RESPONSE &&
        (read_route == MISS || |(m_axi_rvalid_i & read_select));
    assign s_axi_rdata_o = read_route == MISS ? 32'd0 : m_axi_rdata_i[read_route*32+:32];
    assign s_axi_rresp_o = read_route == MISS ? 2'b11 : m_axi_rresp_i[read_route*2+:2];

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            write_state <= COLLECT; read_state <= COLLECT;
            write_route <= MISS; read_route <= MISS;
            aw_full <= 1'b0; w_full <= 1'b0; aw_sent <= 1'b0; w_sent <= 1'b0;
            awaddr <= 32'd0; wdata <= 32'd0; araddr <= 32'd0;
            awprot <= 3'd0; arprot <= 3'd0; wstrb <= 4'd0;
        end else begin
            if (s_axi_awvalid_i && s_axi_awready_o) begin
                aw_full <= 1'b1; awaddr <= s_axi_awaddr_i; awprot <= s_axi_awprot_i;
            end
            if (s_axi_wvalid_i && s_axi_wready_o) begin
                w_full <= 1'b1; wdata <= s_axi_wdata_i; wstrb <= s_axi_wstrb_i;
            end
            case (write_state)
                COLLECT: if (aw_full && w_full) begin
                    write_route <= decode(awaddr); aw_sent <= 1'b0; w_sent <= 1'b0;
                    write_state <= decode(awaddr) == MISS ? RESPONSE : ISSUE;
                end
                ISSUE: begin
                    if (|(m_axi_awvalid_o & m_axi_awready_i)) aw_sent <= 1'b1;
                    if (|(m_axi_wvalid_o & m_axi_wready_i)) w_sent <= 1'b1;
                    if ((aw_sent || |(m_axi_awvalid_o & m_axi_awready_i)) &&
                        (w_sent || |(m_axi_wvalid_o & m_axi_wready_i))) write_state <= RESPONSE;
                end
                RESPONSE: if (s_axi_bvalid_o && s_axi_bready_i) begin
                    write_state <= COLLECT; aw_full <= 1'b0; w_full <= 1'b0;
                end
                default: write_state <= COLLECT;
            endcase
            case (read_state)
                COLLECT: if (s_axi_arvalid_i && s_axi_arready_o) begin
                    araddr <= s_axi_araddr_i; arprot <= s_axi_arprot_i;
                    read_route <= decode(s_axi_araddr_i);
                    read_state <= decode(s_axi_araddr_i) == MISS ? RESPONSE : ISSUE;
                end
                ISSUE: if (|(m_axi_arvalid_o & m_axi_arready_i)) read_state <= RESPONSE;
                RESPONSE: if (s_axi_rvalid_o && s_axi_rready_i) read_state <= COLLECT;
                default: read_state <= COLLECT;
            endcase
        end
    end
endmodule
`default_nettype wire
