/* TriHa uncached 64-bit fetch adapter. One accepted request is always
 * completed; front-end redirects own cancellation of its architectural use.
 * FENCE.I needs no cache action here. Lower transport still drains responses.
 */
module triha_ifetch_uncached (
    input wire clk_i,
    input wire rst_ni,
    input wire req_rd_i,
    input wire [31:0] req_pc_i,
    output wire req_accept_o,
    output wire req_valid_o,
    output wire req_error_o,
    output wire [63:0] req_inst_o,
    output wire arvalid_o,
    output wire [31:0] araddr_o,
    input wire arready_i,
    input wire rvalid_i,
    input wire [31:0] rdata_i,
    input wire [1:0] rresp_i,
    input wire rlast_i,
    output wire rready_o
);
    localparam [1:0] IDLE = 0, ADDRESS = 1, READ = 2, RESPONSE = 3;
    reg [1:0] state_q;
    reg [31:0] address_q;
    reg [63:0] data_q;
    reg error_q, word_q;
    assign req_accept_o = rst_ni && state_q == IDLE;
    assign req_valid_o = rst_ni && state_q == RESPONSE;
    assign req_error_o = error_q;
    assign req_inst_o = data_q;
    assign arvalid_o = rst_ni && state_q == ADDRESS;
    assign araddr_o = address_q;
    assign rready_o = rst_ni && state_q == READ;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE; address_q <= 0; data_q <= 0; error_q <= 0; word_q <= 0;
        end else begin
            case (state_q)
                IDLE: if (req_rd_i) begin
                    address_q <= {req_pc_i[31:3], 3'b0};
                    word_q <= 0; error_q <= 0; state_q <= ADDRESS;
                end
                ADDRESS: if (arready_i) state_q <= READ;
                READ: if (rvalid_i) begin
                    if (word_q) data_q[63:32] <= rdata_i;
                    else data_q[31:0] <= rdata_i;
                    error_q <= error_q || rresp_i != 0 || rlast_i != word_q;
                    if (word_q || rlast_i) state_q <= RESPONSE;
                    else word_q <= 1;
                end
                RESPONSE: state_q <= IDLE;
            endcase
        end
    end
endmodule
