`timescale 1ns/1ps
// Full-dimension scalar-client diagnostic. No internal DUT state is accessed.
module tb_npu_layer;
    reg clk_i = 0, rst_ni = 0, start_i = 0;
    always #5 clk_i = ~clk_i;
    reg [31:0] cfg [0:31];
    reg [127:0] input_mem [0:32767];
    reg [127:0] weight_mem [0:4095];
    reg [127:0] bias_mem [0:63];
    reg [127:0] requant_mem [0:63];
    reg [127:0] expected_mem [0:32767];
    reg [127:0] actual_mem [0:32767];
    reg [15:0] seen [0:32767];
    wire busy_o, done_o, error_o;
    wire [7:0] error_code_o;
    wire [31:0] total_cycles_o, compute_cycles_o, dma_wait_cycles_o;
    wire req_valid, req_write;
    wire [31:0] req_addr;
    wire [127:0] req_wdata;
    wire [15:0] req_wstrb;
    wire req_ready;
    reg rsp_valid = 0;
    reg [127:0] rsp_data = 0;
    npu_scalar_conv u_dut (
        .clk_i(clk_i), .rst_ni(rst_ni), .start_i(start_i),
        .cfg_input_base_i(cfg[0]), .cfg_weight_base_i(cfg[1]),
        .cfg_bias_base_i(cfg[2]), .cfg_requant_base_i(cfg[3]), .cfg_output_base_i(cfg[4]),
        .cfg_input_width_i(cfg[5][15:0]), .cfg_input_height_i(cfg[6][15:0]),
        .cfg_input_channels_i(cfg[7][15:0]), .cfg_output_channels_i(cfg[8][15:0]),
        .cfg_output_width_i(cfg[9][15:0]), .cfg_output_height_i(cfg[10][15:0]),
        .cfg_kernel_i(cfg[11][1:0]), .cfg_stride_i(cfg[12][1:0]), .cfg_padding_i(cfg[13][1:0]),
        .cfg_depthwise_i(cfg[14][0]), .cfg_input_signed_i(cfg[15][0]), .cfg_output_format_i(cfg[16][1:0]),
        .busy_o(busy_o), .done_o(done_o), .error_o(error_o), .error_code_o(error_code_o),
        .total_cycles_o(total_cycles_o), .compute_cycles_o(compute_cycles_o),
        .dma_wait_cycles_o(dma_wait_cycles_o),
        .mem_req_valid_o(req_valid), .mem_req_write_o(req_write), .mem_req_addr_o(req_addr),
        .mem_req_wdata_o(req_wdata), .mem_req_wstrb_o(req_wstrb), .mem_req_ready_i(req_ready),
        .mem_rsp_valid_i(rsp_valid), .mem_rsp_rdata_i(rsp_data), .mem_rsp_error_i(1'b0)
    );

    function automatic reg in_segment(input [31:0] address, base, bytes);
        in_segment = address >= base && {1'b0, address} < {1'b0, base} + ((bytes + 15) & 32'hfffffff0);
    endfunction
    function automatic [127:0] read_line(input [31:0] address);
        begin
            if (in_segment(address, cfg[0], cfg[17])) read_line = input_mem[(address-cfg[0])>>4];
            else if (in_segment(address, cfg[1], cfg[18])) read_line = weight_mem[(address-cfg[1])>>4];
            else if (in_segment(address, cfg[2], cfg[19])) read_line = bias_mem[(address-cfg[2])>>4];
            else if (in_segment(address, cfg[3], cfg[20])) read_line = requant_mem[(address-cfg[3])>>4];
            else begin $fatal(1, "NPU_LAYER_FAIL unexpected read %h", address); read_line = 0; end
        end
    endfunction

    reg pending = 0, write_q = 0;
    reg [31:0] address_q;
    reg [127:0] data_q;
    reg [15:0] strobe_q;
    integer delay_q = 0, final_delay = 3, stall_cycles = 0;
    integer reads = 0, writes = 0, written_bytes = 0;
    integer lane, index, line_index, offset, strobe_count, first_lane, element_bytes;
    reg [7:0] observed;
    reg corrupt = 0, corrupted = 0;
    assign req_ready = !pending;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            pending <= 0; rsp_valid <= 0; reads <= 0; writes <= 0; written_bytes <= 0;
        end else begin
            rsp_valid <= 0;
            if (req_valid && req_ready) begin
                if (pending || req_addr[3:0] != 0)
                    $fatal(1, "NPU_LAYER_FAIL invalid client request");
                pending <= 1; write_q <= req_write; address_q <= req_addr;
                data_q <= req_wdata; strobe_q <= req_wstrb; delay_q <= stall_cycles;
                if (req_write) begin
                    if (!in_segment(req_addr, cfg[4], cfg[21]) || req_wstrb == 0)
                        $fatal(1, "NPU_LAYER_FAIL unexpected write %h/%h", req_addr, req_wstrb);
                    if (req_addr == cfg[4] + ((cfg[21]-1) & 32'hfffffff0) &&
                            req_wstrb[(cfg[21]-1)&15]) delay_q <= final_delay;
                end else begin
                    rsp_data <= read_line(req_addr);
                    reads <= reads + 1;
                end
            end
            if (pending) begin
                if (delay_q != 0) delay_q <= delay_q - 1;
                else begin
                    pending <= 0; rsp_valid <= 1;
                    if (write_q) begin
                        strobe_count = 0; first_lane = -1; element_bytes = cfg[16] == 3 ? 2 : 1;
                        for (lane = 0; lane < 16; lane = lane + 1) begin
                            if (strobe_q[lane]) begin
                                if (first_lane == -1) first_lane = lane;
                                strobe_count = strobe_count + 1;
                                offset = address_q - cfg[4] + lane;
                                line_index = offset >> 4;
                                if (offset >= cfg[21] || seen[line_index][lane])
                                    $fatal(1, "NPU_LAYER_FAIL out-of-range or repeated output byte %0d", offset);
                                observed = data_q[lane*8+:8];
                                if (corrupt && !corrupted) begin observed = observed ^ 8'h01; corrupted = 1; end
                                if (observed !== expected_mem[line_index][lane*8+:8])
                                    $fatal(1, "NPU_LAYER_FAIL byte %0d got=%h expected=%h", offset,
                                           observed, expected_mem[line_index][lane*8+:8]);
                                actual_mem[line_index][lane*8+:8] = observed;
                                seen[line_index][lane] = 1;
                            end
                        end
                        if (strobe_count != element_bytes || first_lane < 0 ||
                                first_lane % element_bytes != 0 ||
                                strobe_q != (((16'h0001 << element_bytes)-1) << first_lane))
                            $fatal(1, "NPU_LAYER_FAIL wrong element strobe %h", strobe_q);
                        written_bytes <= written_bytes + strobe_count;
                        writes <= writes + 1;
                    end
                end
            end
        end
    end

    string folder;
    longint unsigned cycles = 0, max_cycles = 0;
    integer ignored;
    initial begin
        if (!$value$plusargs("CASE_DIR=%s", folder)) $fatal(1, "NPU_LAYER_FAIL CASE_DIR missing");
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles) || max_cycles == 0)
            $fatal(1, "NPU_LAYER_FAIL MAX_CYCLES missing");
        ignored = $value$plusargs("FINAL_DELAY=%d", final_delay);
        ignored = $value$plusargs("STALL_CYCLES=%d", stall_cycles);
        corrupt = $test$plusargs("CORRUPT_OUTPUT");
        $readmemh({folder, "/config.hex"}, cfg);
        if (cfg[17] == 0 || cfg[17] > 524288 || cfg[18] == 0 || cfg[18] > 65536 ||
                cfg[19] == 0 || cfg[19] > 1024 || cfg[20] == 0 || cfg[20] > 1024 ||
                cfg[21] == 0 || cfg[21] > 524288)
            $fatal(1, "NPU_LAYER_FAIL fixture segment capacity");
        $readmemh({folder, "/input.hex"}, input_mem, 0, (cfg[17]+15)/16-1);
        $readmemh({folder, "/weight.hex"}, weight_mem, 0, (cfg[18]+15)/16-1);
        $readmemh({folder, "/bias.hex"}, bias_mem, 0, (cfg[19]+15)/16-1);
        $readmemh({folder, "/requant.hex"}, requant_mem, 0, (cfg[20]+15)/16-1);
        $readmemh({folder, "/expected.hex"}, expected_mem, 0, (cfg[21]+15)/16-1);
        for (index = 0; index < (cfg[21]+15)/16; index = index + 1) begin
            actual_mem[index] = {16{8'ha5}}; seen[index] = 0;
        end
        repeat (4) @(negedge clk_i);
        rst_ni = 1;
        @(negedge clk_i); start_i = 1;
        @(negedge clk_i); start_i = 0;
        while (!done_o && cycles < max_cycles) begin @(negedge clk_i); cycles = cycles + 1; end
        if (!done_o) $fatal(1, "NPU_LAYER_FAIL timeout cycles=%0d", cycles);
        if (error_o || error_code_o != 0) $fatal(1, "NPU_LAYER_FAIL engine error %0d", error_code_o);
        if (busy_o || pending) $fatal(1, "NPU_LAYER_FAIL early completion");
        if (written_bytes != cfg[21]) $fatal(1, "NPU_LAYER_FAIL missing output bytes %0d/%0d", written_bytes, cfg[21]);
        for (index = 0; index < cfg[21]; index = index + 1)
            if (!seen[index>>4][index&15]) $fatal(1, "NPU_LAYER_FAIL unwritten output byte %0d", index);
        if (compute_cycles_o == 0 || dma_wait_cycles_o == 0 || total_cycles_o == 0)
            $fatal(1, "NPU_LAYER_FAIL missing counters");
        $writememh({folder, "/actual.hex"}, actual_mem, 0, (cfg[21]+15)/16-1);
        $display("NPU_LAYER_PASS cycles=%0d compute=%0d reads=%0d writes=%0d bytes=%0d",
                 cycles, compute_cycles_o, reads, writes, written_bytes);
        $finish;
    end
endmodule
