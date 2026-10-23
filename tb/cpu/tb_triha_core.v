/*
 * @file       tb_triha_core.v
 * @brief      ModelSim 自校验 CPU 冒烟、固件与完成事件观察
 * @details
 * - TCM加载固定冒烟或本机GCC编译的固件；地址仅用于测试
 * - 检查真实 SIM_CTRL 退出、发射配置和周期上限
 * - issue不代替退休；WB完成事件仅在定向验证范围内计算观察IPC
 */

`timescale 1ns / 1ps
`include "biriscv_defs.v"

module tb_triha_core #(
    parameter integer DUAL_ISSUE = 0,
    parameter integer PROGRAM_FAIL = 0,
    parameter integer MAX_CYCLES = 100000,
    parameter integer FIRMWARE_MODE = 0
);
    reg clk;
    reg rst_ni;
    reg [7:0] image [0:131071];
    reg [4095:0] image_path;
    integer image_file;
    integer image_size;
    integer index;
    integer cycles;
    integer issued;
    integer pairs;
    integer exit_code;
    reg [63:0] retired_total;
    reg [63:0] retired_start;
    reg [63:0] retired_window;
    reg [31:0] cycle_start;
    reg [31:0] cycle_window;
    reg [31:0] probe_start;
    reg [31:0] probe_end;
    integer cycle_reads;
    integer probe_enabled;
    integer probe_expected;
    integer probe_retired;
    integer trace_file;
    integer ignored_plusarg;

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
        .DUAL_ISSUE(DUAL_ISSUE)
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

    // 上游测试模型只有测试用途；128KiB/复用地址不定义正式 SoC 地址图。
    tcm_mem u_mem (
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

    // 只观察已经通过WB停顿门控的完成事件，store/branch也必须计数。
    function retirement_allowed;
        input [5:0] exception;
        begin
            case (exception)
                6'd0, `EXCEPTION_FENCE, `EXCEPTION_ERET_U,
                `EXCEPTION_ERET_S, `EXCEPTION_ERET_M:
                    retirement_allowed = 1'b1;
                default: retirement_allowed = 1'b0;
            endcase
        end
    endfunction

    task observe_retirement;
        input [31:0] pc;
        input [31:0] instruction;
        input integer lane;
        begin
            retired_total = retired_total + 64'd1;
            if (probe_enabled && pc >= probe_start && pc < probe_end)
                probe_retired = probe_retired + 1;
            if (trace_file != 0)
                $fwrite(trace_file, "%0t %0d %08h %08h\n", $time, lane, pc, instruction);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_ni) begin
            retired_total = 64'd0;
            retired_start = 64'd0;
            retired_window = 64'd0;
            cycle_start = 32'd0;
            cycle_window = 32'd0;
            cycle_reads = 0;
            probe_retired = 0;
        end else begin
            // 读取0xc00的实际E1采样边沿，区间为[start,stop)。
            if (u_dut.u_cpu.u_csr.u_csrfile.csr_ren_i &&
                u_dut.u_cpu.u_csr.u_csrfile.csr_raddr_i == 12'hc00) begin
                if (cycle_reads == 0) begin
                    cycle_start = u_dut.u_cpu.u_csr.u_csrfile.csr_mcycle_q;
                    retired_start = retired_total;
                end else if (cycle_reads == 1) begin
                    cycle_window = u_dut.u_cpu.u_csr.u_csrfile.csr_mcycle_q - cycle_start;
                    retired_window = retired_total - retired_start;
                end
                cycle_reads = cycle_reads + 1;
            end
            if (u_dut.u_cpu.u_issue.pipe0_valid_wb_w &&
                retirement_allowed(u_dut.u_cpu.u_issue.pipe0_exception_wb_w))
                observe_retirement(u_dut.u_cpu.u_issue.pipe0_pc_wb_w,
                                   u_dut.u_cpu.u_issue.pipe0_opc_wb_w, 0);
            if (u_dut.u_cpu.u_issue.pipe1_valid_wb_w &&
                retirement_allowed(u_dut.u_cpu.u_issue.pipe1_exception_wb_w))
                observe_retirement(u_dut.u_cpu.u_issue.pipe1_pc_wb_w,
                                   u_dut.u_cpu.u_issue.pipe1_opc_wb_w, 1);
        end
    end

    task write_word;
        input [31:0] address;
        input [31:0] value;
        integer lane;
        begin
            for (lane = 0; lane < 4; lane = lane + 1)
                u_mem.write(address + lane, value[lane * 8 +: 8]);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_ni = 1'b0;
        cycles = 0;
        issued = 0;
        pairs = 0;
        exit_code = -1;
        probe_start = 32'd0;
        probe_end = 32'd0;
        probe_expected = 14;
        trace_file = 0;
        probe_enabled = $value$plusargs("PROBE_START=%h", probe_start);
        if (probe_enabled && !$value$plusargs("PROBE_END=%h", probe_end)) begin
            $display("CPU_SMOKE_FAIL reason=missing_probe_end");
            $finish;
        end
        ignored_plusarg = $value$plusargs("PROBE_EXPECTED=%d", probe_expected);
        if ($test$plusargs("TRACE_RETIRE")) begin
            if (DUAL_ISSUE == 0)
                trace_file = $fopen("retire-single.log", "w");
            else
                trace_file = $fopen("retire-dual.log", "w");
        end
        if (!$value$plusargs("MEM_IMAGE=%s", image_path)) begin
            $display("CPU_SMOKE_FAIL reason=missing_image");
            $finish;
        end
        image_file = $fopen(image_path, "rb");
        if (image_file == 0) begin
            $display("CPU_SMOKE_FAIL reason=image_open");
            $finish;
        end
        image_size = $fread(image, image_file);
        $fclose(image_file);
        if (image_size != 131072) begin
            $display("CPU_SMOKE_FAIL reason=image_size actual=%0d", image_size);
            $finish;
        end
        for (index = 0; index < 131072; index = index + 1)
            u_mem.write(index, image[index]);
        if (PROGRAM_FAIL != 0) begin
            // 实际执行返回1的程序，不能只修改宿主期望值。
            write_word(32'd0, 32'h00100513);
            write_word(32'd4, 32'h8b251073);
            write_word(32'd8, 32'h0000006f);
        end
        repeat (5) @(negedge clk);
        #1 rst_ni = 1'b1;
    end

    // Decode source roles independently for the same-packet hazard assertion.
    // Immediates/upper immediates are not register operands.
    wire [6:0] pair_b_major = u_dut.u_cpu.u_issue.opcode_b_r[6:0];
    wire pair_b_rs1 = pair_b_major != 7'h37 && pair_b_major != 7'h17 && pair_b_major != 7'h6f;
    wire pair_b_rs2 = pair_b_major == 7'h33 || pair_b_major == 7'h23 || pair_b_major == 7'h63;
    // 负边沿采样在下一上升沿被核接纳的实际 CSR 和 issue 控制。
    always @(negedge clk) begin
        if (rst_ni) begin
            cycles = cycles + 1;
            if (cycles > MAX_CYCLES) begin
                $display("CPU_SMOKE_FAIL reason=timeout cycles=%0d", cycles);
                $finish;
            end
            if (u_dut.u_cpu.u_issue.single_issue_w === 1'b1)
                issued = issued + 1;
            if (u_dut.u_cpu.u_issue.dual_issue_w === 1'b1) begin
                issued = issued + 2;
                pairs = pairs + 1;
                if ((DUAL_ISSUE == 0) ||
                    (u_dut.u_cpu.u_issue.opcode_a_accept_r !== 1'b1)) begin
                    $display("CPU_SMOKE_FAIL reason=invalid_pair");
                    $finish;
                end
                if (u_dut.u_cpu.u_issue.issue_a_sb_alloc_w &&
                    (u_dut.u_cpu.u_issue.issue_a_rd_idx_w != 5'd0) &&
                    ((pair_b_rs1 && u_dut.u_cpu.u_issue.issue_a_rd_idx_w == u_dut.u_cpu.u_issue.issue_b_ra_idx_w) ||
                     (pair_b_rs2 && u_dut.u_cpu.u_issue.issue_a_rd_idx_w == u_dut.u_cpu.u_issue.issue_b_rb_idx_w) ||
                     (u_dut.u_cpu.u_issue.issue_b_sb_alloc_w && u_dut.u_cpu.u_issue.issue_a_rd_idx_w == u_dut.u_cpu.u_issue.issue_b_rd_idx_w))) begin
                    $display("CPU_SMOKE_FAIL reason=pair_dependency");
                    $finish;
                end
            end
            if (((u_dut.u_cpu.u_csr.u_csrfile.csr_waddr_i == `CSR_SIM_CTRL) ||
                 (u_dut.u_cpu.u_csr.u_csrfile.csr_waddr_i == `CSR_DSCRATCH)) &&
                (u_dut.u_cpu.u_csr.u_csrfile.exception_i == 6'd0)) begin
                case (u_dut.u_cpu.u_csr.u_csrfile.csr_wdata_i & 32'hff000000)
                    `CSR_SIM_CTRL_PUTC:
                        $write("%c", u_dut.u_cpu.u_csr.u_csrfile.csr_wdata_i[7:0]);
                    `CSR_SIM_CTRL_EXIT: begin
                        exit_code = u_dut.u_cpu.u_csr.u_csrfile.csr_wdata_i[7:0];
                        $display("CPU_PROGRAM_EXIT code=%0d", exit_code);
                        $display("CPU_MEASURE cycles=%0d retired=%0d reads=%0d",
                                 cycle_window, retired_window, cycle_reads);
                        if (probe_enabled)
                            $display("CPU_RETIRE_PROBE count=%0d expected=%0d", probe_retired, probe_expected);
                        if (probe_enabled && probe_retired != probe_expected) begin
                            $display("CPU_SMOKE_FAIL reason=retire_count");
                        end else if ((exit_code == 0) &&
                            ((DUAL_ISSUE == 0) || (pairs > 0))) begin
                            if (FIRMWARE_MODE != 0)
                                $display("CPU_FIRMWARE_PASS dual=%0d cycles=%0d issued=%0d pairs=%0d",
                                         DUAL_ISSUE, cycles, issued, pairs);
                            else
                                $display("CPU_SMOKE_PASS dual=%0d cycles=%0d issued=%0d pairs=%0d",
                                         DUAL_ISSUE, cycles, issued, pairs);
                        end else begin
                            $display("CPU_SMOKE_FAIL reason=program_exit_or_no_pair code=%0d", exit_code);
                        end
                        if (trace_file != 0)
                            $fclose(trace_file);
                        $finish;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
