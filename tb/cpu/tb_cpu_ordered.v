/* Each execution owns its image, response timing and fault injection.
 * The host compares ordered completion payloads/stores/synchronous exceptions.
 * IRQ entry timing is intentionally checked separately, not trace-compared.
 */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
`ifndef CPU_TEST_MODULE
`define CPU_TEST_MODULE triha_cpu
`endif
module tb_cpu_ordered #(
    parameter integer DUAL_ISSUE=0,
    parameter integer IRQ_TEST=0,
    parameter integer BROKEN=0,
    parameter integer CHECK_BRANCH_PAIR=0
);
    reg clk=0, rst=1, irq=0;
    reg [7:0] image [0:131071];
    reg [4095:0] image_path, trace_prefix;
    reg [31:0] rng, fetch_fault_pc;
    integer ignored, file_handle, image_size, index, byte_lane;
    integer cycles=0, retired=0, stores=0, delayed=0, i_stalls=0, d_stalls=0;
    integer branch_lsu_pairs=0, irq_fetch_pending=0;
    integer wb_file, store_file, exception_file;
    reg [8:0] trap_mask=0;
    reg fetch_fault_seen=0;
    reg i_pending=0, d_pending=0;
    integer i_delay=0, d_delay=0;
    reg i_valid=0, i_error=0, d_ack=0, d_error=0;
    reg [63:0] i_data=0, saved_i_data=0;
    reg [31:0] d_data=0, saved_d_data=0;
    reg saved_i_error=0, saved_d_error=0;
    reg [10:0] d_tag=0, saved_d_tag=0;
    wire [31:0] d_addr, d_wdata, i_pc;
    wire d_rd, i_rd;
    wire [3:0] d_wr;
    wire [10:0] request_tag;
    wire i_accept=!i_pending && (rng[0] || rng[1]);
    wire d_accept=!d_pending && (rng[2] || rng[3]);
    wire bad_data=d_addr==32'h8001fff0 || d_addr==32'h8001fff4;
    always #5 clk=~clk;
    `CPU_TEST_MODULE #(
        .SUPPORT_DUAL_ISSUE(DUAL_ISSUE), .SUPPORT_BRANCH_PREDICTION(1),
        .SUPPORT_MULDIV(1), .SUPPORT_SUPER(0), .SUPPORT_MMU(0),
        .SUPPORT_LOAD_BYPASS(1), .SUPPORT_MUL_BYPASS(1),
        .SUPPORT_REGFILE_XILINX(0), .EXTRA_DECODE_STAGE(0)
    ) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(irq),
        .reset_vector_i(32'h80000000), .cpu_id_i(32'b0),
        .mem_i_accept_i(i_accept), .mem_i_valid_i(i_valid),
        .mem_i_error_i(i_error), .mem_i_inst_i(i_data),
        .mem_i_rd_o(i_rd), .mem_i_pc_o(i_pc),
        .mem_i_flush_o(), .mem_i_invalidate_o(),
        .mem_d_data_rd_i(d_data), .mem_d_accept_i(d_accept), .mem_d_ack_i(d_ack),
        .mem_d_error_i(d_error), .mem_d_resp_tag_i(d_tag),
        .mem_d_addr_o(d_addr), .mem_d_data_wr_o(d_wdata),
        .mem_d_rd_o(d_rd), .mem_d_wr_o(d_wr), .mem_d_req_tag_o(request_tag),
        .mem_d_cacheable_o(), .mem_d_invalidate_o(), .mem_d_writeback_o(), .mem_d_flush_o()
    );
    initial begin
        if (!$value$plusargs("MEM_IMAGE=%s",image_path) ||
            !$value$plusargs("FETCH_FAULT_PC=%h",fetch_fault_pc) ||
            !$value$plusargs("TRACE_PREFIX=%s",trace_prefix)) $fatal(1,"CPU_ORDER_FAIL inputs");
        rng=1;
        ignored=$value$plusargs("SEED=%d",rng);
        file_handle=$fopen(image_path,"rb");
        if (file_handle==0) $fatal(1,"CPU_ORDER_FAIL image_open");
        image_size=$fread(image,file_handle);
        $fclose(file_handle);
        if (image_size!=131072) $fatal(1,"CPU_ORDER_FAIL image_size");
        wb_file=$fopen({trace_prefix,".wb.log"},"w");
        store_file=$fopen({trace_prefix,".store.log"},"w");
        exception_file=$fopen({trace_prefix,".exception.log"},"w");
        if (!wb_file || !store_file || !exception_file) $fatal(1,"CPU_ORDER_FAIL trace_open");
        repeat(5) @(negedge clk);
        rst=0;
    end
    // Fault-detection negative changes real load data, not a host expectation.
    wire [31:0] read_xor=(BROKEN!=0) ? 32'h1 : 32'h0;
    always @(posedge clk) if (!rst) begin
        if(irq && i_pending) irq_fetch_pending=irq_fetch_pending+1;
        if(CHECK_BRANCH_PAIR && u_dut.u_issue.dual_issue_w &&
           u_dut.u_issue.issue_a_branch_w && u_dut.u_issue.issue_b_lsu_w)
            branch_lsu_pairs=branch_lsu_pairs+1;
        rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        i_valid<=0;
        d_ack<=0;
        if (i_rd && i_accept) begin
            if (i_pc[31:17]!=15'h4000 || i_pc[2:0]!=0) $fatal(1,"CPU_ORDER_FAIL fetch_address %h",i_pc);
            i_pending<=1;
            i_delay<=rng[5:4];
            saved_i_error<=((i_pc & 32'hfffffff8)==fetch_fault_pc) && !fetch_fault_seen;
            for (byte_lane=0;byte_lane<8;byte_lane=byte_lane+1)
                saved_i_data[byte_lane*8+:8]<=image[i_pc[16:0]+byte_lane];
        end else if (i_pending) begin
            if (i_delay==0) begin
                i_pending<=0;
                i_valid<=1;
                i_data<=saved_i_data;
                i_error<=saved_i_error;
            end else begin
                i_delay<=i_delay-1;
                delayed=delayed+1;
            end
        end
        if ((d_rd || |d_wr) && d_accept) begin
            if (d_addr[31:17]!=15'h4000) $fatal(1,"CPU_ORDER_FAIL data_address %h",d_addr);
            d_pending<=1;
            d_delay<=rng[7:6];
            saved_d_tag<=request_tag;
            saved_d_error<=bad_data;
            for (byte_lane=0;byte_lane<4;byte_lane=byte_lane+1) begin
                saved_d_data[byte_lane*8+:8]<=image[{d_addr[16:2],2'b0}+byte_lane] ^ read_xor[byte_lane*8+:8];
                if (d_wr[byte_lane] && !bad_data)
                    image[{d_addr[16:2],2'b0}+byte_lane]<=d_wdata[byte_lane*8+:8];
            end
            if (|d_wr) begin
                stores=stores+1;
                // Normalize bytes outside the active strobes.
                $fwrite(store_file,"%08h %h %08h %b\n",d_addr,d_wr,
                    d_wdata & {{8{d_wr[3]}},{8{d_wr[2]}},{8{d_wr[1]}},{8{d_wr[0]}}},bad_data);
                if (d_addr==32'h8001ffe0 && IRQ_TEST!=0) irq<=1;
            end
        end else if (d_pending) begin
            if (d_delay==0) begin
                d_pending<=0;
                d_ack<=1;
                d_data<=saved_d_data;
                d_tag<=saved_d_tag;
                d_error<=saved_d_error;
            end else begin
                d_delay<=d_delay-1;
                delayed=delayed+1;
            end
        end
        if (u_dut.u_csr.u_csrfile.csr_mcause_q==1) fetch_fault_seen<=1;
        if (u_dut.u_csr.u_csrfile.csr_mcause_q[31]) irq<=0;
    end
    function allowed;
        input [5:0] exception;
        begin
            case (exception)
                6'd0, `EXCEPTION_FENCE, `EXCEPTION_ERET_U, `EXCEPTION_ERET_S, `EXCEPTION_ERET_M: allowed=1;
                default: allowed=0;
            endcase
        end
    endfunction
    task observe;
        input [31:0] pc, opcode, value;
        input [4:0] rd;
        begin
            retired=retired+1;
            $fwrite(wb_file,"%08h %08h %02h %08h\n",pc,opcode,rd,rd!=0 ? value : 32'b0);
        end
    endtask
    // Capture the event seen on the upcoming active edge, before NBA updates.
    always @(posedge clk) if (!rst) begin
        if (u_dut.u_issue.pipe0_valid_wb_w && allowed(u_dut.u_issue.pipe0_exception_wb_w))
            observe(u_dut.u_issue.pipe0_pc_wb_w,u_dut.u_issue.pipe0_opc_wb_w,
                u_dut.u_issue.pipe0_result_wb_w,u_dut.u_issue.pipe0_rd_wb_w);
        if (u_dut.u_issue.pipe1_valid_wb_w && allowed(u_dut.u_issue.pipe1_exception_wb_w))
            observe(u_dut.u_issue.pipe1_pc_wb_w,u_dut.u_issue.pipe1_opc_wb_w,
                u_dut.u_issue.pipe1_result_wb_w,u_dut.u_issue.pipe1_rd_wb_w);
        if (u_dut.csr_writeback_exception_w!=0)
            $fwrite(exception_file,"%02h %08h %08h\n",u_dut.csr_writeback_exception_w,
                u_dut.csr_writeback_exception_pc_w,u_dut.csr_writeback_exception_addr_w);
    end
    always @(negedge clk) if (!rst) begin
        cycles=cycles+1;
        if (cycles>200000) $fatal(1,"CPU_ORDER_FAIL timeout");
        if (i_rd && !i_accept) i_stalls=i_stalls+1;
        if ((d_rd || |d_wr) && !d_accept) d_stalls=d_stalls+1;
        case (u_dut.u_csr.u_csrfile.csr_mcause_q)
            32'd1: trap_mask[0]=1;
            32'd2: trap_mask[1]=1;
            32'd3: trap_mask[2]=1;
            32'd4: trap_mask[3]=1;
            32'd5: trap_mask[4]=1;
            32'd6: trap_mask[5]=1;
            32'd7: trap_mask[6]=1;
            32'd11: trap_mask[7]=1;
            32'h8000000b: trap_mask[8]=1;
        endcase
        if (u_dut.u_csr.u_csrfile.csr_waddr_i==`CSR_SIM_CTRL && u_dut.u_csr.u_csrfile.exception_i==0) begin
            if (u_dut.u_csr.u_csrfile.csr_wdata_i!=0) $fatal(1,"CPU_ORDER_FAIL program_exit");
            if (trap_mask!=(IRQ_TEST!=0 ? 9'h1ff : 9'h0ff) ||
                i_stalls==0 || d_stalls==0 || delayed==0 || stores<90 || retired<800)
                $fatal(1,"CPU_ORDER_FAIL coverage traps=%h retired=%0d stores=%0d",trap_mask,retired,stores);
            $fclose(wb_file);
            $fclose(store_file);
            $fclose(exception_file);
            if(CHECK_BRANCH_PAIR && branch_lsu_pairs<4)
                    $fatal(1,"CPU_ORDER_FAIL missing_branch_lsu_pair_coverage pairs=%0d",branch_lsu_pairs);
                $display("CPU_PAIR_COVERAGE branch_lsu_pairs=%0d irq_fetch_pending_cycles=%0d",branch_lsu_pairs,irq_fetch_pending);
                $display("CPU_ORDER_PASS dual=%0d cycles=%0d traps=%0d retired=%0d stores=%0d delayed=%0d",
                DUAL_ISSUE,cycles,trap_mask,retired,stores,delayed);
            $finish;
        end
    end
endmodule
