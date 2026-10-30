`timescale 1ns/1ps
`include "npu_regs.vh"

module npu_operator_mmio (
    input wire clk_i,
    input wire rst_ni,
    input wire [31:0] s_axi_awaddr_i,
    input wire s_axi_awvalid_i,
    output wire s_axi_awready_o,
    input wire [31:0] s_axi_wdata_i,
    input wire [3:0] s_axi_wstrb_i,
    input wire s_axi_wvalid_i,
    output wire s_axi_wready_o,
    output reg [1:0] s_axi_bresp_o,
    output reg s_axi_bvalid_o,
    input wire s_axi_bready_i,
    input wire [31:0] s_axi_araddr_i,
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output reg [31:0] s_axi_rdata_o,
    output reg [1:0] s_axi_rresp_o,
    output reg s_axi_rvalid_o,
    input wire s_axi_rready_i,
    input wire engine_busy_i,
    input wire engine_done_i,
    input wire engine_error_i,
    input wire [7:0] engine_error_code_i,
    input wire [31:0] engine_total_cycles_i,
    input wire [31:0] engine_compute_cycles_i,
    input wire [31:0] engine_dma_wait_cycles_i,
    input wire platform_fault_i,
    output reg start_o,
    output wire irq_o,
    output wire [31:0] frame_id_o,
    output wire [31:0] generation_o,
    output wire [31:0] op_tag_o,
    output wire [31:0] cfg_input_base_o,
    output wire [31:0] cfg_weight_base_o,
    output wire [31:0] cfg_bias_base_o,
    output wire [31:0] cfg_requant_base_o,
    output wire [31:0] cfg_output_base_o,
    output wire [15:0] cfg_input_width_o,
    output wire [15:0] cfg_input_height_o,
    output wire [15:0] cfg_output_width_o,
    output wire [15:0] cfg_output_height_o,
    output wire [15:0] cfg_input_channels_o,
    output wire [15:0] cfg_output_channels_o,
    output wire [1:0] cfg_kernel_o,
    output wire [1:0] cfg_stride_o,
    output wire [1:0] cfg_padding_o,
    output wire cfg_depthwise_o,
    output wire cfg_input_signed_o,
    output wire [1:0] cfg_output_format_o
);
    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;

    reg aw_full;
    reg w_full;
    reg [31:0] aw_addr;
    reg [31:0] w_data;
    reg [3:0] w_strb;
    reg active;
    reg [1:0] irq_status;
    reg [1:0] irq_enable;
    reg [7:0] error_code;
    reg [31:0] total_cycles;
    reg [31:0] compute_cycles;
    reg [31:0] dma_wait_cycles;
    reg [31:0] frame_id;
    reg [31:0] generation;
    reg [31:0] op_tag;
    reg [31:0] input_base;
    reg [31:0] weight_base;
    reg [31:0] bias_base;
    reg [31:0] requant_base;
    reg [31:0] output_base;
    reg [31:0] input_wh;
    reg [31:0] channels;
    reg [31:0] output_wh;
    reg [31:0] ksp;
    reg [31:0] format;

    wire busy = active | engine_busy_i;
    wire shadow_locked = busy | (|irq_status);
    wire write_execute = aw_full && w_full && !s_axi_bvalid_o;
    wire [31:0] write_offset = aw_addr - `NPU_MMIO_BASE;
    wire [31:0] read_offset = s_axi_araddr_i - `NPU_MMIO_BASE;
    wire [31:0] write_byte_mask = {{8{w_strb[3]}}, {8{w_strb[2]}},
                                   {8{w_strb[1]}}, {8{w_strb[0]}}};
    reg [1:0] write_response;
    reg [1:0] read_response;
    reg [31:0] read_data;
    reg [1:0] irq_next;

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobes;
        reg [31:0] mask;
        begin
            mask = {{8{strobes[3]}}, {8{strobes[2]}},
                    {8{strobes[1]}}, {8{strobes[0]}}};
            merge_bytes = (old_value & ~mask) | (new_value & mask);
        end
    endfunction

    function valid_address;
        input [31:0] address;
        begin
            valid_address = address >= `NPU_MMIO_BASE &&
                            (address - `NPU_MMIO_BASE) < `NPU_MMIO_BYTES &&
                            address[1:0] == 2'b00;
        end
    endfunction

    assign s_axi_awready_o = rst_ni && !aw_full && !s_axi_bvalid_o;
    assign s_axi_wready_o = rst_ni && !w_full && !s_axi_bvalid_o;
    assign s_axi_arready_o = rst_ni && !s_axi_rvalid_o;
    assign irq_o = |(irq_status & irq_enable);
    assign frame_id_o = frame_id;
    assign generation_o = generation;
    assign op_tag_o = op_tag;
    assign cfg_input_base_o = input_base;
    assign cfg_weight_base_o = weight_base;
    assign cfg_bias_base_o = bias_base;
    assign cfg_requant_base_o = requant_base;
    assign cfg_output_base_o = output_base;
    assign cfg_input_width_o = input_wh[15:0];
    assign cfg_input_height_o = input_wh[31:16];
    assign cfg_output_width_o = output_wh[15:0];
    assign cfg_output_height_o = output_wh[31:16];
    assign cfg_input_channels_o = channels[15:0];
    assign cfg_output_channels_o = channels[31:16];
    assign cfg_kernel_o = ksp[1:0];
    assign cfg_stride_o = ksp[9:8];
    assign cfg_padding_o = ksp[17:16];
    assign cfg_depthwise_o = ksp[24];
    assign cfg_input_signed_o = format[0];
    assign cfg_output_format_o = format[9:8];

    // The buffered address and data are independently accepted. Decode only
    // once both halves exist; a write response blocks another transaction.
    always @* begin
        write_response = RESP_OKAY;
        if (!valid_address(aw_addr)) begin
            write_response = RESP_DECERR;
        end else begin
            case (write_offset)
                `NPU_REG_CONTROL: begin
                    if (w_strb != 4'b1111 || w_data != `NPU_CONTROL_START_MASK ||
                        shadow_locked || platform_fault_i)
                        write_response = RESP_SLVERR;
                end
                `NPU_REG_IRQ_STATUS: begin
                    if (|(w_data & write_byte_mask & ~`NPU_REG_IRQ_STATUS_VALID_MASK))
                        write_response = RESP_SLVERR;
                end
                `NPU_REG_IRQ_ENABLE: begin
                    if (|(merge_bytes({30'b0, irq_enable}, w_data, w_strb) &
                          ~`NPU_REG_IRQ_ENABLE_VALID_MASK))
                        write_response = RESP_SLVERR;
                end
                `NPU_REG_OP_TAG, `NPU_REG_FRAME_ID, `NPU_REG_GENERATION,
                `NPU_REG_INPUT_BASE, `NPU_REG_WEIGHT_BASE, `NPU_REG_BIAS_BASE,
                `NPU_REG_REQUANT_BASE, `NPU_REG_OUTPUT_BASE, `NPU_REG_INPUT_WH,
                `NPU_REG_CHANNELS, `NPU_REG_OUTPUT_WH: begin
                    if (shadow_locked) write_response = RESP_SLVERR;
                end
                `NPU_REG_KSP: begin
                    if (shadow_locked ||
                        |(merge_bytes(ksp, w_data, w_strb) & ~`NPU_REG_KSP_VALID_MASK))
                        write_response = RESP_SLVERR;
                end
                `NPU_REG_FORMAT: begin
                    if (shadow_locked ||
                        |(merge_bytes(format, w_data, w_strb) & ~`NPU_REG_FORMAT_VALID_MASK))
                        write_response = RESP_SLVERR;
                end
                `NPU_REG_ID_VERSION, `NPU_REG_CAPS, `NPU_REG_STATUS,
                `NPU_REG_ERROR_CODE, `NPU_REG_TOTAL_CYCLES,
                `NPU_REG_COMPUTE_CYCLES, `NPU_REG_DMA_WAIT_CYCLES:
                    write_response = RESP_SLVERR;
                default: write_response = RESP_DECERR;
            endcase
        end
    end

    // W1C applies first; an event observed on this edge always remains pending.
    always @* begin
        irq_next = irq_status;
        if (write_execute && write_response == RESP_OKAY &&
            write_offset == `NPU_REG_IRQ_STATUS)
            irq_next = irq_status & ~(w_data[1:0] & write_byte_mask[1:0]);
        if (engine_done_i)
            irq_next = irq_next | (engine_error_i ? 2'b10 : 2'b01);
    end

    always @* begin
        read_data = 0;
        read_response = RESP_OKAY;
        if (!valid_address(s_axi_araddr_i)) begin
            read_response = RESP_DECERR;
        end else begin
            case (read_offset)
                `NPU_REG_ID_VERSION: read_data = `NPU_ID_VERSION;
                `NPU_REG_CAPS: read_data = `NPU_CAPS;
                `NPU_REG_CONTROL: read_data = 0;
                `NPU_REG_STATUS: read_data = {27'b0, platform_fault_i, irq_status[1],
                                              irq_status[0], busy, !busy};
                `NPU_REG_IRQ_STATUS: read_data = {30'b0, irq_status};
                `NPU_REG_IRQ_ENABLE: read_data = {30'b0, irq_enable};
                `NPU_REG_ERROR_CODE: read_data = {24'b0, error_code};
                `NPU_REG_OP_TAG: read_data = op_tag;
                `NPU_REG_FRAME_ID: read_data = frame_id;
                `NPU_REG_TOTAL_CYCLES: read_data = total_cycles;
                `NPU_REG_COMPUTE_CYCLES: read_data = compute_cycles;
                `NPU_REG_DMA_WAIT_CYCLES: read_data = dma_wait_cycles;
                `NPU_REG_GENERATION: read_data = generation;
                `NPU_REG_INPUT_BASE: read_data = input_base;
                `NPU_REG_WEIGHT_BASE: read_data = weight_base;
                `NPU_REG_BIAS_BASE: read_data = bias_base;
                `NPU_REG_REQUANT_BASE: read_data = requant_base;
                `NPU_REG_OUTPUT_BASE: read_data = output_base;
                `NPU_REG_INPUT_WH: read_data = input_wh;
                `NPU_REG_CHANNELS: read_data = channels;
                `NPU_REG_OUTPUT_WH: read_data = output_wh;
                `NPU_REG_KSP: read_data = ksp;
                `NPU_REG_FORMAT: read_data = format;
                default: read_response = RESP_DECERR;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_full <= 0;
            w_full <= 0;
            aw_addr <= 0;
            w_data <= 0;
            w_strb <= 0;
            s_axi_bvalid_o <= 0;
            s_axi_bresp_o <= RESP_OKAY;
            s_axi_rvalid_o <= 0;
            s_axi_rdata_o <= 0;
            s_axi_rresp_o <= RESP_OKAY;
            start_o <= 0;
            active <= 0;
            irq_status <= `NPU_REG_IRQ_STATUS_RESET;
            irq_enable <= `NPU_REG_IRQ_ENABLE_RESET;
            error_code <= 0;
            total_cycles <= 0;
            compute_cycles <= 0;
            dma_wait_cycles <= 0;
            frame_id <= `NPU_REG_FRAME_ID_RESET;
            generation <= `NPU_REG_GENERATION_RESET;
            op_tag <= `NPU_REG_OP_TAG_RESET;
            input_base <= `NPU_REG_INPUT_BASE_RESET;
            weight_base <= `NPU_REG_WEIGHT_BASE_RESET;
            bias_base <= `NPU_REG_BIAS_BASE_RESET;
            requant_base <= `NPU_REG_REQUANT_BASE_RESET;
            output_base <= `NPU_REG_OUTPUT_BASE_RESET;
            input_wh <= `NPU_REG_INPUT_WH_RESET;
            channels <= `NPU_REG_CHANNELS_RESET;
            output_wh <= `NPU_REG_OUTPUT_WH_RESET;
            ksp <= `NPU_REG_KSP_RESET;
            format <= `NPU_REG_FORMAT_RESET;
        end else begin
            start_o <= 0;
            irq_status <= irq_next;
            if (s_axi_awvalid_i && s_axi_awready_o) begin
                aw_full <= 1;
                aw_addr <= s_axi_awaddr_i;
            end
            if (s_axi_wvalid_i && s_axi_wready_o) begin
                w_full <= 1;
                w_data <= s_axi_wdata_i;
                w_strb <= s_axi_wstrb_i;
            end
            if (s_axi_bvalid_o && s_axi_bready_i) s_axi_bvalid_o <= 0;
            if (write_execute) begin
                aw_full <= 0;
                w_full <= 0;
                s_axi_bvalid_o <= 1;
                s_axi_bresp_o <= write_response;
                if (write_response == RESP_OKAY) begin
                    case (write_offset)
                        `NPU_REG_CONTROL: begin
                            start_o <= 1;
                            active <= 1;
                            error_code <= 0;
                            total_cycles <= 0;
                            compute_cycles <= 0;
                            dma_wait_cycles <= 0;
                        end
                        `NPU_REG_IRQ_ENABLE:
                            irq_enable <= merge_bytes({30'b0, irq_enable}, w_data, w_strb);
                        `NPU_REG_OP_TAG: op_tag <= merge_bytes(op_tag, w_data, w_strb);
                        `NPU_REG_FRAME_ID: frame_id <= merge_bytes(frame_id, w_data, w_strb);
                        `NPU_REG_GENERATION: generation <= merge_bytes(generation, w_data, w_strb);
                        `NPU_REG_INPUT_BASE: input_base <= merge_bytes(input_base, w_data, w_strb);
                        `NPU_REG_WEIGHT_BASE: weight_base <= merge_bytes(weight_base, w_data, w_strb);
                        `NPU_REG_BIAS_BASE: bias_base <= merge_bytes(bias_base, w_data, w_strb);
                        `NPU_REG_REQUANT_BASE: requant_base <= merge_bytes(requant_base, w_data, w_strb);
                        `NPU_REG_OUTPUT_BASE: output_base <= merge_bytes(output_base, w_data, w_strb);
                        `NPU_REG_INPUT_WH: input_wh <= merge_bytes(input_wh, w_data, w_strb);
                        `NPU_REG_CHANNELS: channels <= merge_bytes(channels, w_data, w_strb);
                        `NPU_REG_OUTPUT_WH: output_wh <= merge_bytes(output_wh, w_data, w_strb);
                        `NPU_REG_KSP: ksp <= merge_bytes(ksp, w_data, w_strb);
                        `NPU_REG_FORMAT: format <= merge_bytes(format, w_data, w_strb);
                        default: begin end
                    endcase
                end
            end
            if (engine_done_i) begin
                active <= 0;
                error_code <= engine_error_i ? engine_error_code_i : 8'b0;
                total_cycles <= engine_total_cycles_i;
                compute_cycles <= engine_compute_cycles_i;
                dma_wait_cycles <= engine_dma_wait_cycles_i;
            end
            if (s_axi_rvalid_o && s_axi_rready_i) s_axi_rvalid_o <= 0;
            if (s_axi_arvalid_i && s_axi_arready_o) begin
                s_axi_rvalid_o <= 1;
                s_axi_rdata_o <= read_data;
                s_axi_rresp_o <= read_response;
            end
        end
    end
endmodule
