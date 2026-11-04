/*
 * @file       tb_triha_isa_official.v
 * @brief      Official RV32 ISA test adapter for the current six-stage core.
 * @details
 * - Loads one ELF-derived image into a 256 KiB test-only memory.
 * - Uses the official tohost store as the pass/fail observation point.
 * - Does not change the CPU or the production memory map.
 */

`timescale 1ns / 1ps

module tb_triha_isa_official #(
    parameter [31:0] TOHOST_ADDR = 32'h8000_8000,
    parameter integer MAX_CYCLES = 2000000,
    parameter integer DUAL_ISSUE = 0,
    parameter integer MINIMAL_CONTROL_CPU = 0
)(
);
    localparam integer IMAGE_BYTES = 262144;

    reg clk;
    reg rst_ni;
    reg [7:0] image [0:IMAGE_BYTES-1];
    reg [4095:0] image_path;
    integer image_file;
    integer image_size;
    integer index;
    integer cycles;
    integer failed;
    integer second_issue_count = 0;
    reg tohost_store_q;
    reg [31:0] tohost_value_q;

    wire inst_req;
    wire inst_flush;
    wire inst_invalidate;
    wire [31:0] inst_addr;
    wire inst_accept;
    wire inst_valid;
    wire inst_error;
    wire [63:0] inst_rdata;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire data_re;
    wire [3:0] data_wstrb;
    wire data_cacheable;
    wire [10:0] data_req_tag;
    wire data_invalidate;
    wire data_writeback;
    wire data_flush;
    wire [31:0] data_rdata;
    wire data_accept;
    wire data_ack;
    wire data_error;
    wire [10:0] data_resp_tag;

    triha_core #(
        .DUAL_ISSUE(DUAL_ISSUE),
        .MINIMAL_CONTROL_CPU(MINIMAL_CONTROL_CPU)
    ) u_dut (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .external_irq_i(1'b0),
        .inst_req_o(inst_req),
        .inst_flush_o(inst_flush),
        .inst_invalidate_o(inst_invalidate),
        .inst_addr_o(inst_addr),
        .inst_accept_i(inst_accept),
        .inst_valid_i(inst_valid),
        .inst_error_i(inst_error),
        .inst_rdata_i(inst_rdata),
        .data_addr_o(data_addr),
        .data_wdata_o(data_wdata),
        .data_re_o(data_re),
        .data_wstrb_o(data_wstrb),
        .data_cacheable_o(data_cacheable),
        .data_req_tag_o(data_req_tag),
        .data_invalidate_o(data_invalidate),
        .data_writeback_o(data_writeback),
        .data_flush_o(data_flush),
        .data_rdata_i(data_rdata),
        .data_accept_i(data_accept),
        .data_ack_i(data_ack),
        .data_error_i(data_error),
        .data_resp_tag_i(data_resp_tag)
    );

    triha_isa_mem #(
        .IMAGE_BYTES(IMAGE_BYTES)
    ) u_mem (
        .clk_i(clk),
        .rst_i(!rst_ni),
        .mem_i_rd_i(inst_req),
        .mem_i_flush_i(inst_flush),
        .mem_i_invalidate_i(inst_invalidate),
        .mem_i_pc_i(inst_addr),
        .mem_d_addr_i(data_addr),
        .mem_d_data_wr_i(data_wdata),
        .mem_d_rd_i(data_re),
        .mem_d_wr_i(data_wstrb),
        .mem_d_cacheable_i(data_cacheable),
        .mem_d_req_tag_i(data_req_tag),
        .mem_d_invalidate_i(data_invalidate),
        .mem_d_writeback_i(data_writeback),
        .mem_d_flush_i(data_flush),
        .mem_i_accept_o(inst_accept),
        .mem_i_valid_o(inst_valid),
        .mem_i_error_o(inst_error),
        .mem_i_inst_o(inst_rdata),
        .mem_d_data_rd_o(data_rdata),
        .mem_d_accept_o(data_accept),
        .mem_d_ack_o(data_ack),
        .mem_d_error_o(data_error),
        .mem_d_resp_tag_o(data_resp_tag)
    );

    always #5 clk = ~clk;

    always @(posedge clk) if (rst_ni) begin
        if (!DUAL_ISSUE && u_dut.u_cpu.u_issue.opcode_b_issue_r !== 1'b0) begin
            $display("RV32_ISA_FAIL reason=unexpected_second_issue");
            $fatal(1, "single-issue configuration issued a second instruction");
        end
        if (u_dut.u_cpu.u_issue.opcode_b_issue_r)
            second_issue_count = second_issue_count + 1;
    end

    always @(posedge clk) begin
        if (!rst_ni) begin
            tohost_store_q <= 1'b0;
            tohost_value_q <= 32'd0;
        end else begin
            tohost_store_q <= data_accept && (data_wstrb == 4'b1111) &&
                              (data_addr == TOHOST_ADDR);
            tohost_value_q <= data_wdata;
        end
    end

    initial begin
        clk = 1'b0;
        rst_ni = 1'b0;
        cycles = 0;
        failed = 0;
        if (!$value$plusargs("MEM_IMAGE=%s", image_path)) begin
            $display("RV32_ISA_FAIL reason=missing_image");
            $finish;
        end
        image_file = $fopen(image_path, "rb");
        if (image_file == 0) begin
            $display("RV32_ISA_FAIL reason=image_open");
            $finish;
        end
        image_size = $fread(image, image_file);
        $fclose(image_file);
        if (image_size != IMAGE_BYTES) begin
            $display("RV32_ISA_FAIL reason=image_size actual=%0d expected=%0d",
                     image_size, IMAGE_BYTES);
            $finish;
        end
        for (index = 0; index < IMAGE_BYTES; index = index + 1)
            u_mem.write_index(index, image[index]);
        repeat (5) @(negedge clk);
        rst_ni = 1'b1;
    end

    always @(negedge clk) begin
        if (rst_ni) begin
            cycles = cycles + 1;
            if (tohost_store_q && data_ack && !data_error) begin
                if (tohost_value_q == 32'd1) begin
                    $display("RV32_ISA_PASS tohost=%08h cycles=%0d second_issue=%0d", tohost_value_q, cycles, second_issue_count);
                end else begin
                    $display("RV32_ISA_FAIL tohost=%08h cycles=%0d", tohost_value_q, cycles);
                end
                $finish;
            end
            if (cycles > MAX_CYCLES) begin
                $display("RV32_ISA_FAIL reason=timeout cycles=%0d", cycles);
                $finish;
            end
        end
    end
endmodule

module triha_isa_mem #(
    parameter integer IMAGE_BYTES = 262144
)(
    input clk_i,
    input rst_i,
    input mem_i_rd_i,
    input mem_i_flush_i,
    input mem_i_invalidate_i,
    input [31:0] mem_i_pc_i,
    input [31:0] mem_d_addr_i,
    input [31:0] mem_d_data_wr_i,
    input mem_d_rd_i,
    input [3:0] mem_d_wr_i,
    input mem_d_cacheable_i,
    input [10:0] mem_d_req_tag_i,
    input mem_d_invalidate_i,
    input mem_d_writeback_i,
    input mem_d_flush_i,
    output mem_i_accept_o,
    output mem_i_valid_o,
    output mem_i_error_o,
    output [63:0] mem_i_inst_o,
    output [31:0] mem_d_data_rd_o,
    output mem_d_accept_o,
    output mem_d_ack_o,
    output mem_d_error_o,
    output [10:0] mem_d_resp_tag_o
);
    localparam integer RAM_WORDS = IMAGE_BYTES / 4;
    reg [31:0] ram [0:RAM_WORDS-1];
    reg [63:0] inst_read_q;
    reg [31:0] data_read_q;
    reg inst_valid_q;
    reg data_ack_q;
    reg inst_error_q;
    reg data_error_q;
    reg [10:0] data_tag_q;
    wire [15:0] inst_word_addr = {mem_i_pc_i[17:3],1'b0};
    wire [15:0] data_word_addr = mem_d_addr_i[17:2];
    wire inst_mapped = mem_i_pc_i >= 32'h80000000 &&
                       mem_i_pc_i < 32'h80000000 + IMAGE_BYTES;
    wire data_mapped = mem_d_addr_i >= 32'h80000000 &&
                       mem_d_addr_i < 32'h80000000 + IMAGE_BYTES;
    wire uart_mapped = mem_d_addr_i == 32'h10000000 ||
                       mem_d_addr_i == 32'h10000004;

    integer word;
    task write_index;
        input integer byte_index;
        input [7:0] value;
        begin
            word = byte_index >> 2;
            case (byte_index[1:0])
                2'd0: ram[word][7:0]   = value;
                2'd1: ram[word][15:8]  = value;
                2'd2: ram[word][23:16] = value;
                2'd3: ram[word][31:24] = value;
            endcase
        end
    endtask

    always @(posedge clk_i) begin
        if (rst_i) begin
            inst_valid_q <= 1'b0;
            data_ack_q <= 1'b0;
            inst_error_q <= 1'b0;
            data_error_q <= 1'b0;
            data_tag_q <= 11'b0;
        end else begin
            inst_valid_q <= mem_i_rd_i;
            inst_error_q <= mem_i_rd_i && !inst_mapped;
            data_ack_q <= (mem_d_rd_i || (mem_d_wr_i != 4'b0) ||
                           mem_d_flush_i || mem_d_invalidate_i || mem_d_writeback_i);
            data_error_q <= (mem_d_rd_i || (mem_d_wr_i != 4'b0)) &&
                            !data_mapped && !uart_mapped;
            if (mem_d_rd_i || (mem_d_wr_i != 4'b0) || mem_d_flush_i ||
                mem_d_invalidate_i || mem_d_writeback_i)
                data_tag_q <= mem_d_req_tag_i;
            inst_read_q <= {ram[inst_word_addr+1'b1],ram[inst_word_addr]};
            data_read_q <= data_mapped ? ram[data_word_addr] :
                           (mem_d_addr_i == 32'h10000004 ? 32'd1 : 32'd0);
            if (data_mapped) begin
                if (mem_d_wr_i[0]) ram[data_word_addr][7:0]   <= mem_d_data_wr_i[7:0];
                if (mem_d_wr_i[1]) ram[data_word_addr][15:8]  <= mem_d_data_wr_i[15:8];
                if (mem_d_wr_i[2]) ram[data_word_addr][23:16] <= mem_d_data_wr_i[23:16];
                if (mem_d_wr_i[3]) ram[data_word_addr][31:24] <= mem_d_data_wr_i[31:24];
            end
            if (mem_d_addr_i == 32'h10000000 && mem_d_wr_i[0])
                $write("%c", mem_d_data_wr_i[7:0]);
        end
    end

    assign mem_i_accept_o = 1'b1;
    assign mem_i_valid_o = inst_valid_q;
    assign mem_i_error_o = inst_error_q;
    assign mem_i_inst_o = inst_read_q;
    assign mem_d_data_rd_o = data_read_q;
    assign mem_d_accept_o = 1'b1;
    assign mem_d_ack_o = data_ack_q;
    assign mem_d_error_o = data_error_q;
    assign mem_d_resp_tag_o = data_tag_q;
endmodule
