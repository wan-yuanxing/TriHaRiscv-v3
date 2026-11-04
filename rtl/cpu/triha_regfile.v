/*
 * TriHa register file: asynchronous distributed RAM for single issue.
 * Two copies provide the existing two simultaneous read ports. A resettable
 * written mask preserves synchronous zero-on-reset without resetting RAM.
 * The single-issue integration has no secondary write. Dual issue retains
 * the existing implementation. See ADAPTATIONS.json for provenance.
 */
`timescale 1ns / 1ps
module triha_regfile #(
    parameter SUPPORT_REGFILE_XILINX = 0,
    parameter SUPPORT_DUAL_ISSUE = 1
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire [4:0]  rd0_i,
    input  wire [4:0]  rd1_i,
    input  wire [31:0] rd0_value_i,
    input  wire [31:0] rd1_value_i,
    input  wire [4:0]  ra0_i,
    input  wire [4:0]  rb0_i,
    input  wire [4:0]  ra1_i,
    input  wire [4:0]  rb1_i,
    output wire [31:0] ra0_value_o,
    output wire [31:0] rb0_value_o,
    output wire [31:0] ra1_value_o,
    output wire [31:0] rb1_value_o
);
    generate
        if (!SUPPORT_DUAL_ISSUE && !SUPPORT_REGFILE_XILINX) begin : g_single
            reg [31:1] written_q;
            wire [31:0] known_w = {written_q, 1'b0};
            wire write_w = !rst_i && (|rd0_i);
            wire [31:0] ra_data_w;
            wire [31:0] rb_data_w;
            // Keep the write-data minimum delay above the native RAM hold
            // requirement even when WB FF and RAM are packed beside each other.
            // Enabled writes have a valid address and reset released, so the
            // two data gates preserve exactly the value that RAM may capture.
            // Plain identity LUTs are bypassed by ADS even with kept net names.
            (* syn_keep = 1 *) wire [31:0] write_delay_w;
            (* syn_keep = 1 *) wire [31:0] write_data_w;
            genvar write_bit;
            for (write_bit=0; write_bit<32; write_bit=write_bit+1) begin: g_write_hold
                (* syn_keep = 1 *) GTP_LUT6 #(.INIT(64'h8888888888888888)) u_first (
                    .I0(rd0_value_i[write_bit]), .I1(|rd0_i), .I2(1'b0), .I3(1'b0),
                    .I4(1'b0), .I5(1'b0), .Z(write_delay_w[write_bit])
                );
                (* syn_keep = 1 *) GTP_LUT6 #(.INIT(64'h2222222222222222)) u_second (
                    .I0(write_delay_w[write_bit]), .I1(rst_i), .I2(1'b0), .I3(1'b0),
                    .I4(1'b0), .I5(1'b0), .Z(write_data_w[write_bit])
                );
            end

            always @(posedge clk_i) begin
                if (rst_i)
                    written_q <= 31'b0;
                else if (|rd0_i)
                    written_q[rd0_i] <= 1'b1;
            end

            genvar bit_pair;
            for (bit_pair=0; bit_pair<16; bit_pair=bit_pair+1) begin : g_pair
                GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ra (
                    .DO(ra_data_w[2*bit_pair +: 2]),
                    .DI(write_data_w[2*bit_pair +: 2]),
                    .RADDR(ra0_i), .WADDR(rd0_i), .WCLK(clk_i), .WE(write_w)
                );
                GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_rb (
                    .DO(rb_data_w[2*bit_pair +: 2]),
                    .DI(write_data_w[2*bit_pair +: 2]),
                    .RADDR(rb0_i), .WADDR(rd0_i), .WCLK(clk_i), .WE(write_w)
                );
            end

            assign ra0_value_o = known_w[ra0_i] ? ra_data_w : 32'b0;
            assign rb0_value_o = known_w[rb0_i] ? rb_data_w : 32'b0;
            assign ra1_value_o = 32'b0;
            assign rb1_value_o = 32'b0;

            // synthesis translate_off
            always @(posedge clk_i) begin
                if (!rst_i && rd1_i !== 5'b0)
                    $fatal(1, "REGFILE_FAIL single_issue_secondary_write");
            end
            // synthesis translate_on
        end else begin : g_existing
            biriscv_regfile #(
                .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX),
                .SUPPORT_DUAL_ISSUE(SUPPORT_DUAL_ISSUE)
            ) u_regfile (
                .clk_i(clk_i), .rst_i(rst_i),
                .rd0_i(rd0_i), .rd1_i(rd1_i),
                .rd0_value_i(rd0_value_i), .rd1_value_i(rd1_value_i),
                .ra0_i(ra0_i), .rb0_i(rb0_i), .ra1_i(ra1_i), .rb1_i(rb1_i),
                .ra0_value_o(ra0_value_o), .rb0_value_o(rb0_value_o),
                .ra1_value_o(ra1_value_o), .rb1_value_o(rb1_value_o)
            );
        end
    endgenerate
endmodule
