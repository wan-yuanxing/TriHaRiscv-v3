`timescale 1ns/1ps

// Same-clock, one-outstanding CPU native to Video AXI-Lite control adapter.
// Native byte lanes are already aligned by the LSU. Reset is coordinated with
// the CPU and AXI endpoint; it is not an in-flight transaction abort protocol.
module cpu_native_axil (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [31:0] cpu_addr_i,
    input  wire [31:0] cpu_wdata_i,
    input  wire        cpu_re_i,
    input  wire [3:0]  cpu_wstrb_i,
    input  wire        cpu_cacheable_i,
    input  wire [10:0] cpu_req_tag_i,
    input  wire        cpu_invalidate_i,
    input  wire        cpu_writeback_i,
    input  wire        cpu_flush_i,
    output reg  [31:0] cpu_rdata_o,
    output wire        cpu_accept_o,
    output reg         cpu_ack_o,
    output reg         cpu_error_o,
    output reg  [10:0] cpu_resp_tag_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [2:0]  m_axi_awprot_o,
    output wire        m_axi_awvalid_o,
    input  wire        m_axi_awready_i,
    output wire [31:0] m_axi_wdata_o,
    output wire [3:0]  m_axi_wstrb_o,
    output wire        m_axi_wvalid_o,
    input  wire        m_axi_wready_i,
    input  wire [1:0]  m_axi_bresp_i,
    input  wire        m_axi_bvalid_i,
    output wire        m_axi_bready_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [2:0]  m_axi_arprot_o,
    output wire        m_axi_arvalid_o,
    input  wire        m_axi_arready_i,
    input  wire [31:0] m_axi_rdata_i,
    input  wire [1:0]  m_axi_rresp_i,
    input  wire        m_axi_rvalid_i,
    output wire        m_axi_rready_o
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_READ_ADDR = 3'd1;
    localparam [2:0] ST_READ_DATA = 3'd2;
    localparam [2:0] ST_WRITE = 3'd3;
    localparam [2:0] ST_WRITE_RESP = 3'd4;
    localparam [2:0] ST_RESPONSE = 3'd5;

    reg [2:0] state_q;
    reg [31:0] addr_q;
    reg [31:0] wdata_q;
    reg [3:0] wstrb_q;
    reg [10:0] tag_q;
    reg aw_done_q;
    reg w_done_q;
    reg request_present;
    reg request_error;
    reg [10:0] request_tag;
    reg read_response_error;
    reg write_response_error;

    assign cpu_accept_o = rst_ni && state_q == ST_IDLE;
    assign m_axi_awaddr_o = addr_q;
    assign m_axi_awprot_o = 3'b000;
    assign m_axi_awvalid_o = state_q == ST_WRITE && !aw_done_q;
    assign m_axi_wdata_o = wdata_q;
    assign m_axi_wstrb_o = wstrb_q;
    assign m_axi_wvalid_o = state_q == ST_WRITE && !w_done_q;
    assign m_axi_bready_o = state_q == ST_WRITE_RESP;
    assign m_axi_araddr_o = addr_q;
    assign m_axi_arprot_o = 3'b000;
    assign m_axi_arvalid_o = state_q == ST_READ_ADDR;
    assign m_axi_rready_o = state_q == ST_READ_DATA;

    always @* begin
        request_present = cpu_re_i || (|cpu_wstrb_i) || cpu_invalidate_i ||
                          cpu_writeback_i || cpu_flush_i;
        request_error = cpu_addr_i[31:16] != 16'h2001 ||
                        cpu_addr_i[1:0] != 2'b00 || cpu_cacheable_i ||
                        (cpu_re_i && (|cpu_wstrb_i)) || cpu_invalidate_i ||
                        cpu_writeback_i || cpu_flush_i;
        request_tag = cpu_req_tag_i;
        read_response_error = m_axi_rresp_i != 2'b00;
        write_response_error = m_axi_bresp_i != 2'b00;

        // Indeterminate simulation inputs fail locally. These checks do not
        // describe silicon X detection and are omitted by synthesis.
        // synthesis translate_off
        if (cpu_re_i !== 1'b0 || cpu_wstrb_i !== 4'b0000 ||
            cpu_invalidate_i !== 1'b0 || cpu_writeback_i !== 1'b0 ||
            cpu_flush_i !== 1'b0)
            request_present = 1'b1;
        if ((^{cpu_addr_i, cpu_re_i, cpu_wstrb_i, cpu_cacheable_i,
                cpu_invalidate_i, cpu_writeback_i, cpu_flush_i}) === 1'bx)
            request_error = 1'b1;
        if (cpu_wstrb_i !== 4'b0000 && (^cpu_wdata_i) === 1'bx)
            request_error = 1'b1;
        if ((^cpu_req_tag_i) === 1'bx) begin
            request_error = 1'b1;
            request_tag = 11'b0;
        end
        if (m_axi_rresp_i !== 2'b00 || (^m_axi_rdata_i) === 1'bx)
            read_response_error = 1'b1;
        if (m_axi_bresp_i !== 2'b00)
            write_response_error = 1'b1;
        // synthesis translate_on
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE;
            addr_q <= 32'b0;
            wdata_q <= 32'b0;
            wstrb_q <= 4'b0;
            tag_q <= 11'b0;
            aw_done_q <= 1'b0;
            w_done_q <= 1'b0;
            cpu_rdata_o <= 32'b0;
            cpu_ack_o <= 1'b0;
            cpu_error_o <= 1'b0;
            cpu_resp_tag_o <= 11'b0;
        end else begin
            cpu_ack_o <= 1'b0;
            cpu_error_o <= 1'b0;
            case (state_q)
                ST_IDLE: begin
                    if (request_present) begin
                        addr_q <= cpu_addr_i;
                        wdata_q <= cpu_wdata_i;
                        wstrb_q <= cpu_wstrb_i;
                        tag_q <= request_tag;
                        aw_done_q <= 1'b0;
                        w_done_q <= 1'b0;
                        if (request_error) begin
                            cpu_rdata_o <= 32'b0;
                            cpu_ack_o <= 1'b1;
                            cpu_error_o <= 1'b1;
                            cpu_resp_tag_o <= request_tag;
                            state_q <= ST_RESPONSE;
                        end else if (cpu_re_i) begin
                            state_q <= ST_READ_ADDR;
                        end else begin
                            state_q <= ST_WRITE;
                        end
                    end
                end
                ST_READ_ADDR: begin
                    if (m_axi_arready_i)
                        state_q <= ST_READ_DATA;
                end
                ST_READ_DATA: begin
                    if (m_axi_rvalid_i) begin
                        cpu_rdata_o <= read_response_error ? 32'b0 : m_axi_rdata_i;
                        cpu_ack_o <= 1'b1;
                        cpu_error_o <= read_response_error;
                        cpu_resp_tag_o <= tag_q;
                        state_q <= ST_RESPONSE;
                    end
                end
                ST_WRITE: begin
                    if (m_axi_awready_i)
                        aw_done_q <= 1'b1;
                    if (m_axi_wready_i)
                        w_done_q <= 1'b1;
                    if ((aw_done_q || m_axi_awready_i) &&
                        (w_done_q || m_axi_wready_i))
                        state_q <= ST_WRITE_RESP;
                end
                ST_WRITE_RESP: begin
                    if (m_axi_bvalid_i) begin
                        cpu_rdata_o <= 32'b0;
                        cpu_ack_o <= 1'b1;
                        cpu_error_o <= write_response_error;
                        cpu_resp_tag_o <= tag_q;
                        state_q <= ST_RESPONSE;
                    end
                end
                ST_RESPONSE: begin
                    state_q <= ST_IDLE;
                end
                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
