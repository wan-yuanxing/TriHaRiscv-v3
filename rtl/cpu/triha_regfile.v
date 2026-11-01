//-----------------------------------------------------------------
//                         biRISC-V CPU
//                            V0.8.1
//                     Ultra-Embedded.com
//                     Copyright 2019-2020
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------
/*
 * TriHa register file: asynchronous distributed RAM for single issue.
 * Single issue uses two read copies. The isolated dual-native experiment
 * uses two writer banks, four read replicas and a written/live-bank table.
 * Reset masks preserve synchronous zero-on-reset without resetting RAM.
 * The explicit vendor configuration remains available. See the diagnostic
 * manifest and ADAPTATIONS.json for provenance and admission boundaries.
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
    output wire [31:0] rb1_value_o,
    output wire ra0_zero_o,rb0_zero_o,ra1_zero_o,rb1_zero_o
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

            assign ra0_zero_o=(ra0_value_o==32'b0);
            assign rb0_zero_o=(rb0_value_o==32'b0);
            assign ra1_zero_o=(ra1_value_o==32'b0);
            assign rb1_zero_o=(rb1_value_o==32'b0);

            // synthesis translate_off
            always @(posedge clk_i) begin
                if (!rst_i && rd1_i !== 5'b0)
                    $fatal(1, "REGFILE_FAIL single_issue_secondary_write");
            end
            // synthesis translate_on
        end else if(SUPPORT_DUAL_ISSUE && !SUPPORT_REGFILE_XILINX) begin : g_dual_native
            // Two writer banks and a live-value table reuse the existing
            // dual-bank storage topology, with current port0 priority.
            reg [31:1] written_q,source_q;
            reg [31:1] zero_q;
            wire [31:0] written_w={written_q,1'b0};
            wire [31:0] source_w={source_q,1'b0};
            wire [31:0] bank0_data[0:3];
            wire [31:0] bank1_data[0:3];
            reg reset_active_r;
            always @* begin
                reset_active_r=1'b0;
                if(rst_i) reset_active_r=1'b1;
            end
            // Preserve the old exact case/default0 behavior for X/Z addresses.
            function known_register;
                input [4:0] address;
                begin
                    known_register=1'b0;
                    case(address)
                        5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,
                        5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15,5'd16,
                        5'd17,5'd18,5'd19,5'd20,5'd21,5'd22,5'd23,5'd24,
                        5'd25,5'd26,5'd27,5'd28,5'd29,5'd30,5'd31: known_register=1'b1;
                        default: known_register=1'b0;
                    endcase
                end
            endfunction
            genvar register_index,bank,read_port,bit_pair,write_bit;
            for(register_index=1;register_index<32;register_index=register_index+1) begin:g_live
                always @(posedge clk_i) begin
                    if(rst_i) begin
                        written_q[register_index]<=1'b0;
                        source_q[register_index]<=1'b0;
                        zero_q[register_index]<=1'b1;
                    end else if(rd0_i==register_index) begin
                        written_q[register_index]<=1'b1;
                        source_q[register_index]<=1'b0;
                        zero_q[register_index]<=(rd0_value_i==32'b0);
                    end else if(rd1_i==register_index) begin
                        written_q[register_index]<=1'b1;
                        source_q[register_index]<=1'b1;
                        zero_q[register_index]<=(rd1_value_i==32'b0);
                    end
                end
            end
            for(bank=0;bank<2;bank=bank+1) begin:g_bank
                wire [4:0] raw_address_w=bank==0 ? rd0_i : rd1_i;
                wire [31:0] raw_data_w=bank==0 ? rd0_value_i : rd1_value_i;
                wire address_known_w=known_register(raw_address_w);
                wire write_w=address_known_w && !reset_active_r;
                (* syn_keep=1 *) wire [31:0] data_delay_w,data_w;
                (* syn_keep=1 *) wire [4:0] address_delay_w,address_w;
                for(write_bit=0;write_bit<32;write_bit=write_bit+1) begin:g_data_hold
                    (* syn_keep=1 *) GTP_LUT6 #(.INIT(64'h8888888888888888)) u_first (
                        .I0(raw_data_w[write_bit]),.I1(address_known_w),.I2(1'b0),.I3(1'b0),
                        .I4(1'b0),.I5(1'b0),.Z(data_delay_w[write_bit]));
                    (* syn_keep=1 *) GTP_LUT6 #(.INIT(64'h2222222222222222)) u_second (
                        .I0(data_delay_w[write_bit]),.I1(reset_active_r),.I2(1'b0),.I3(1'b0),
                        .I4(1'b0),.I5(1'b0),.Z(data_w[write_bit]));
                end
                for(write_bit=0;write_bit<5;write_bit=write_bit+1) begin:g_address_hold
                    (* syn_keep=1 *) GTP_LUT6 #(.INIT(64'h8888888888888888)) u_first (
                        .I0(raw_address_w[write_bit]),.I1(address_known_w),.I2(1'b0),.I3(1'b0),
                        .I4(1'b0),.I5(1'b0),.Z(address_delay_w[write_bit]));
                    (* syn_keep=1 *) GTP_LUT6 #(.INIT(64'h2222222222222222)) u_second (
                        .I0(address_delay_w[write_bit]),.I1(reset_active_r),.I2(1'b0),.I3(1'b0),
                        .I4(1'b0),.I5(1'b0),.Z(address_w[write_bit]));
                end
                for(read_port=0;read_port<4;read_port=read_port+1) begin:g_read
                    wire [4:0] read_address_w=read_port==0 ? ra0_i :
                        read_port==1 ? rb0_i : read_port==2 ? ra1_i : rb1_i;
                    wire [31:0] data_read_w;
                    for(bit_pair=0;bit_pair<16;bit_pair=bit_pair+1) begin:g_pair
                        GTP_RAM32X2DP #(.INIT_0(32'b0),.INIT_1(32'b0)) u_ram (
                            .DO(data_read_w[2*bit_pair +: 2]),.DI(data_w[2*bit_pair +: 2]),
                            .RADDR(read_address_w),.WADDR(address_w),.WCLK(clk_i),.WE(write_w));
                    end
                    if(bank==0)assign bank0_data[read_port]=data_read_w;
                    else assign bank1_data[read_port]=data_read_w;
                end
            end
            // Capture the scalar property at the unchanged RF write edge.
            // Preserve original read qualification and unknown-skip behavior.
            reg ra0_zero_r,rb0_zero_r,ra1_zero_r,rb1_zero_r;
            always @* begin
                ra0_zero_r=1'b1;rb0_zero_r=1'b1;ra1_zero_r=1'b1;rb1_zero_r=1'b1;
                if(known_register(ra0_i) && written_w[ra0_i])
                    ra0_zero_r=zero_q[ra0_i];
                if(known_register(rb0_i) && written_w[rb0_i])
                    rb0_zero_r=zero_q[rb0_i];
                if(known_register(ra1_i) && written_w[ra1_i])
                    ra1_zero_r=zero_q[ra1_i];
                if(known_register(rb1_i) && written_w[rb1_i])
                    rb1_zero_r=zero_q[rb1_i];
            end
            assign ra0_zero_o=ra0_zero_r;
            assign rb0_zero_o=rb0_zero_r;
            assign ra1_zero_o=ra1_zero_r;
            assign rb1_zero_o=rb1_zero_r;
            reg [31:0] ra0_value_r,rb0_value_r,ra1_value_r,rb1_value_r;
            always @* begin
                ra0_value_r=0;rb0_value_r=0;ra1_value_r=0;rb1_value_r=0;
                if(known_register(ra0_i) && written_w[ra0_i])
                    ra0_value_r=source_w[ra0_i] ? bank1_data[0] : bank0_data[0];
                if(known_register(rb0_i) && written_w[rb0_i])
                    rb0_value_r=source_w[rb0_i] ? bank1_data[1] : bank0_data[1];
                if(known_register(ra1_i) && written_w[ra1_i])
                    ra1_value_r=source_w[ra1_i] ? bank1_data[2] : bank0_data[2];
                if(known_register(rb1_i) && written_w[rb1_i])
                    rb1_value_r=source_w[rb1_i] ? bank1_data[3] : bank0_data[3];
            end
            assign ra0_value_o=ra0_value_r;assign rb0_value_o=rb0_value_r;
            assign ra1_value_o=ra1_value_r;assign rb1_value_o=rb1_value_r;
        end else begin : g_existing
            assign ra0_zero_o=(ra0_value_o==32'b0);
            assign rb0_zero_o=(rb0_value_o==32'b0);
            assign ra1_zero_o=(ra1_value_o==32'b0);
            assign rb1_zero_o=(rb1_value_o==32'b0);
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
