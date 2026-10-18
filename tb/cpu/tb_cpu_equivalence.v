/* Directed cycle differential test, shared TCM, backpressure and real faults. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
module tb_cpu_equivalence #(parameter integer DUAL_ISSUE=0, parameter integer BROKEN_DUAL=0);
    reg clk=0, rst=1, irq=0;
    reg [31:0] rng;
    reg [4095:0] image_path;
    reg [7:0] image [0:131071];
    reg [31:0] fetch_fault_pc;
    reg fetch_injected=0, instruction_error=0, data_error=0;
    reg [8:0] trap_mask=0;
    integer ignored, image_file, image_size, index;
    integer cycles=0, i_stalls=0, d_stalls=0;
    always #5 clk=~clk;
    wire [ 31:0] mem_d_data_rd_i;
    wire  mem_d_accept_i;
    wire  mem_d_ack_i;
    wire  mem_d_error_i;
    wire [ 10:0] mem_d_resp_tag_i;
    wire  mem_i_accept_i;
    wire  mem_i_valid_i;
    wire  mem_i_error_i;
    wire [ 63:0] mem_i_inst_i;
    wire [ 31:0] old_mem_d_addr_o;
    wire [ 31:0] new_mem_d_addr_o;
    wire [ 31:0] old_mem_d_data_wr_o;
    wire [ 31:0] new_mem_d_data_wr_o;
    wire  old_mem_d_rd_o;
    wire  new_mem_d_rd_o;
    wire [  3:0] old_mem_d_wr_o;
    wire [  3:0] new_mem_d_wr_o;
    wire  old_mem_d_cacheable_o;
    wire  new_mem_d_cacheable_o;
    wire [ 10:0] old_mem_d_req_tag_o;
    wire [ 10:0] new_mem_d_req_tag_o;
    wire  old_mem_d_invalidate_o;
    wire  new_mem_d_invalidate_o;
    wire  old_mem_d_writeback_o;
    wire  new_mem_d_writeback_o;
    wire  old_mem_d_flush_o;
    wire  new_mem_d_flush_o;
    wire  old_mem_i_rd_o;
    wire  new_mem_i_rd_o;
    wire  old_mem_i_flush_o;
    wire  new_mem_i_flush_o;
    wire  old_mem_i_invalidate_o;
    wire  new_mem_i_invalidate_o;
    wire [ 31:0] old_mem_i_pc_o;
    wire [ 31:0] new_mem_i_pc_o;
    riscv_core #(
        .SUPPORT_DUAL_ISSUE(DUAL_ISSUE), .SUPPORT_BRANCH_PREDICTION(1),
        .SUPPORT_MULDIV(1), .SUPPORT_SUPER(0), .SUPPORT_MMU(0),
        .SUPPORT_LOAD_BYPASS(1), .SUPPORT_MUL_BYPASS(1),
        .SUPPORT_REGFILE_XILINX(0), .EXTRA_DECODE_STAGE(0)
    ) u_old (
        .clk_i(clk),
        .rst_i(rst),
        .mem_d_data_rd_i(mem_d_data_rd_i),
        .mem_d_accept_i(mem_d_accept_i),
        .mem_d_ack_i(mem_d_ack_i),
        .mem_d_error_i(mem_d_error_i),
        .mem_d_resp_tag_i(mem_d_resp_tag_i),
        .mem_i_accept_i(mem_i_accept_i),
        .mem_i_valid_i(mem_i_valid_i),
        .mem_i_error_i(mem_i_error_i),
        .mem_i_inst_i(mem_i_inst_i),
        .intr_i(irq),
        .reset_vector_i(32'h80000000),
        .cpu_id_i(32'd0),
        .mem_d_addr_o(old_mem_d_addr_o),
        .mem_d_data_wr_o(old_mem_d_data_wr_o),
        .mem_d_rd_o(old_mem_d_rd_o),
        .mem_d_wr_o(old_mem_d_wr_o),
        .mem_d_cacheable_o(old_mem_d_cacheable_o),
        .mem_d_req_tag_o(old_mem_d_req_tag_o),
        .mem_d_invalidate_o(old_mem_d_invalidate_o),
        .mem_d_writeback_o(old_mem_d_writeback_o),
        .mem_d_flush_o(old_mem_d_flush_o),
        .mem_i_rd_o(old_mem_i_rd_o),
        .mem_i_flush_o(old_mem_i_flush_o),
        .mem_i_invalidate_o(old_mem_i_invalidate_o),
        .mem_i_pc_o(old_mem_i_pc_o)
    );
    triha_cpu #(
        .SUPPORT_DUAL_ISSUE(DUAL_ISSUE), .SUPPORT_BRANCH_PREDICTION(1),
        .SUPPORT_MULDIV(1), .SUPPORT_SUPER(0), .SUPPORT_MMU(0),
        .SUPPORT_LOAD_BYPASS(1), .SUPPORT_MUL_BYPASS(1),
        .SUPPORT_REGFILE_XILINX(0), .EXTRA_DECODE_STAGE(0)
    ) u_new (
        .clk_i(clk),
        .rst_i(rst),
        .mem_d_data_rd_i(mem_d_data_rd_i),
        .mem_d_accept_i(mem_d_accept_i),
        .mem_d_ack_i(mem_d_ack_i),
        .mem_d_error_i(mem_d_error_i),
        .mem_d_resp_tag_i(mem_d_resp_tag_i),
        .mem_i_accept_i(mem_i_accept_i),
        .mem_i_valid_i(mem_i_valid_i),
        .mem_i_error_i(mem_i_error_i),
        .mem_i_inst_i(mem_i_inst_i),
        .intr_i(irq),
        .reset_vector_i(32'h80000000),
        .cpu_id_i(32'd0),
        .mem_d_addr_o(new_mem_d_addr_o),
        .mem_d_data_wr_o(new_mem_d_data_wr_o),
        .mem_d_rd_o(new_mem_d_rd_o),
        .mem_d_wr_o(new_mem_d_wr_o),
        .mem_d_cacheable_o(new_mem_d_cacheable_o),
        .mem_d_req_tag_o(new_mem_d_req_tag_o),
        .mem_d_invalidate_o(new_mem_d_invalidate_o),
        .mem_d_writeback_o(new_mem_d_writeback_o),
        .mem_d_flush_o(new_mem_d_flush_o),
        .mem_i_rd_o(new_mem_i_rd_o),
        .mem_i_flush_o(new_mem_i_flush_o),
        .mem_i_invalidate_o(new_mem_i_invalidate_o),
        .mem_i_pc_o(new_mem_i_pc_o)
    );
    wire i_allow = rng[0] | rng[1];
    wire d_allow = rng[2] | rng[3];
    wire bad_data_address = new_mem_d_addr_o == 32'h8001fff0 || new_mem_d_addr_o == 32'h8001fff4;
    wire data_request = new_mem_d_rd_o || (|new_mem_d_wr_o);
    wire [63:0] instruction_data;
    wire [31:0] data_read;
    wire instruction_valid, data_ack;
    wire [10:0] response_tag;
    tcm_mem u_mem (
        .clk_i(clk), .rst_i(rst), .mem_i_rd_i(new_mem_i_rd_o && i_allow),
        .mem_i_flush_i(new_mem_i_flush_o), .mem_i_invalidate_i(new_mem_i_invalidate_o), .mem_i_pc_i(new_mem_i_pc_o),
        .mem_d_addr_i(new_mem_d_addr_o), .mem_d_data_wr_i(new_mem_d_data_wr_o),
        .mem_d_rd_i(d_allow && (new_mem_d_rd_o || (bad_data_address && (|new_mem_d_wr_o)))),
        .mem_d_wr_i(new_mem_d_wr_o & {4{d_allow && !bad_data_address}}),
        .mem_d_cacheable_i(new_mem_d_cacheable_o), .mem_d_req_tag_i(new_mem_d_req_tag_o),
        .mem_d_invalidate_i(new_mem_d_invalidate_o && d_allow),
        .mem_d_writeback_i(new_mem_d_writeback_o && d_allow), .mem_d_flush_i(new_mem_d_flush_o && d_allow),
        .mem_i_accept_o(), .mem_i_valid_o(instruction_valid), .mem_i_error_o(), .mem_i_inst_o(instruction_data),
        .mem_d_data_rd_o(data_read), .mem_d_accept_o(), .mem_d_ack_o(data_ack),
        .mem_d_error_o(), .mem_d_resp_tag_o(response_tag)
    );
    assign mem_i_accept_i = i_allow;
    assign mem_i_valid_i = instruction_valid;
    assign mem_i_error_i = instruction_error;
    assign mem_i_inst_i = instruction_data;
    assign mem_d_accept_i = d_allow;
    assign mem_d_ack_i = data_ack;
    assign mem_d_error_i = data_error;
    assign mem_d_data_rd_i = data_read;
    assign mem_d_resp_tag_i = response_tag;
    initial begin
        if (!$value$plusargs("MEM_IMAGE=%s",image_path) || !$value$plusargs("FETCH_FAULT_PC=%h",fetch_fault_pc))
            $fatal(1,"CPU_EQ_FAIL missing_inputs");
        rng=1;
        ignored=$value$plusargs("SEED=%d",rng);
        image_file=$fopen(image_path,"rb");
        if (image_file==0) $fatal(1,"CPU_EQ_FAIL image_open");
        image_size=$fread(image,image_file);
        $fclose(image_file);
        if (image_size!=131072) $fatal(1,"CPU_EQ_FAIL image_size");
        for (index=0;index<131072;index=index+1) u_mem.write(index,image[index]);
        repeat (5) @(negedge clk);
        rst=0;
    end
    initial if (BROKEN_DUAL!=0) force u_new.writeback_exec1_value_w=32'b0;
    always @(posedge clk) if (!rst) begin
        rng <= {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        // A speculative prefetch may be flushed; fault every request until observed.
        instruction_error <= new_mem_i_rd_o && i_allow &&
            ((new_mem_i_pc_o & 32'hfffffff8)==fetch_fault_pc) &&
            (u_old.u_csr.u_csrfile.csr_mcause_q!=32'd1);
        if (new_mem_i_rd_o && i_allow && ((new_mem_i_pc_o & 32'hfffffff8)==fetch_fault_pc)) fetch_injected<=1;
        data_error <= data_request && d_allow && bad_data_address;
        if (data_request && d_allow && new_mem_d_addr_o==32'h8001ffe0 && (|new_mem_d_wr_o)) irq<=1;
        if (u_old.u_csr.u_csrfile.csr_mcause_q[31]) irq<=0;
    end
    always @(negedge clk) if (!rst) begin
        cycles=cycles+1;
        if (cycles>200000) $fatal(1,"CPU_EQ_FAIL timeout");
        if (new_mem_i_rd_o && !i_allow) i_stalls=i_stalls+1;
        if (data_request && !d_allow) d_stalls=d_stalls+1;

        if ((1'b1) && {new_mem_d_addr_o,new_mem_d_data_wr_o,new_mem_d_rd_o,new_mem_d_wr_o,new_mem_d_cacheable_o,new_mem_d_req_tag_o,new_mem_d_invalidate_o,new_mem_d_writeback_o,new_mem_d_flush_o,new_mem_i_rd_o,new_mem_i_flush_o,new_mem_i_invalidate_o,new_mem_i_pc_o} !==
            {old_mem_d_addr_o,old_mem_d_data_wr_o,old_mem_d_rd_o,old_mem_d_wr_o,old_mem_d_cacheable_o,old_mem_d_req_tag_o,old_mem_d_invalidate_o,old_mem_d_writeback_o,old_mem_d_flush_o,old_mem_i_rd_o,old_mem_i_flush_o,old_mem_i_invalidate_o,old_mem_i_pc_o}) $fatal(1,"CPU_EQ_FAIL bus cycle=%0d",cycles);
        if ((1'b1) && {u_new.u_issue.pipe0_valid_wb_w} !==
            {u_old.u_issue.pipe0_valid_wb_w}) $fatal(1,"CPU_EQ_FAIL valid0 cycle=%0d",cycles);
        if ((u_new.u_issue.pipe0_valid_wb_w) && {u_new.u_issue.pipe0_pc_wb_w,u_new.u_issue.pipe0_opc_wb_w,u_new.u_issue.pipe0_rd_wb_w} !==
            {u_old.u_issue.pipe0_pc_wb_w,u_old.u_issue.pipe0_opc_wb_w,u_old.u_issue.pipe0_rd_wb_w}) $fatal(1,"CPU_EQ_FAIL retire0 cycle=%0d",cycles);
        if (((|u_new.u_issue.pipe0_rd_wb_w)) && {u_new.u_issue.pipe0_result_wb_w} !==
            {u_old.u_issue.pipe0_result_wb_w}) $fatal(1,"CPU_EQ_FAIL writeback0 cycle=%0d",cycles);
        if ((1'b1) && {u_new.u_issue.pipe1_valid_wb_w} !==
            {u_old.u_issue.pipe1_valid_wb_w}) $fatal(1,"CPU_EQ_FAIL valid1 cycle=%0d",cycles);
        if ((u_new.u_issue.pipe1_valid_wb_w) && {u_new.u_issue.pipe1_pc_wb_w,u_new.u_issue.pipe1_opc_wb_w,u_new.u_issue.pipe1_rd_wb_w} !==
            {u_old.u_issue.pipe1_pc_wb_w,u_old.u_issue.pipe1_opc_wb_w,u_old.u_issue.pipe1_rd_wb_w}) $fatal(1,"CPU_EQ_FAIL retire1 cycle=%0d",cycles);
        if (((|u_new.u_issue.pipe1_rd_wb_w)) && {u_new.u_issue.pipe1_result_wb_w} !==
            {u_old.u_issue.pipe1_result_wb_w}) $fatal(1,"CPU_EQ_FAIL writeback1 cycle=%0d",cycles);
        if ((1'b1) && {u_new.branch_info_request_w,u_new.branch_info_is_taken_w,u_new.branch_info_is_not_taken_w,u_new.branch_info_is_call_w,u_new.branch_info_is_ret_w,u_new.branch_info_is_jmp_w,u_new.branch_info_source_w,u_new.branch_info_pc_w} !==
            {u_old.branch_info_request_w,u_old.branch_info_is_taken_w,u_old.branch_info_is_not_taken_w,u_old.branch_info_is_call_w,u_old.branch_info_is_ret_w,u_old.branch_info_is_jmp_w,u_old.branch_info_source_w,u_old.branch_info_pc_w}) $fatal(1,"CPU_EQ_FAIL predictor cycle=%0d",cycles);
        if ((1'b1) && {u_new.u_csr.u_csrfile.csr_mepc_q,u_new.u_csr.u_csrfile.csr_mcause_q,u_new.u_csr.u_csrfile.csr_mtval_q,u_new.u_csr.u_csrfile.csr_sr_q,u_new.u_csr.u_csrfile.csr_mpriv_q,u_new.u_csr.u_csrfile.csr_mie_q,u_new.u_csr.u_csrfile.csr_mip_q,u_new.u_csr.u_csrfile.csr_mtvec_q,u_new.u_csr.u_csrfile.csr_mcycle_q,u_new.u_csr.u_csrfile.csr_mcycle_h_q,u_new.u_csr.u_csrfile.csr_mscratch_q} !==
            {u_old.u_csr.u_csrfile.csr_mepc_q,u_old.u_csr.u_csrfile.csr_mcause_q,u_old.u_csr.u_csrfile.csr_mtval_q,u_old.u_csr.u_csrfile.csr_sr_q,u_old.u_csr.u_csrfile.csr_mpriv_q,u_old.u_csr.u_csrfile.csr_mie_q,u_old.u_csr.u_csrfile.csr_mip_q,u_old.u_csr.u_csrfile.csr_mtvec_q,u_old.u_csr.u_csrfile.csr_mcycle_q,u_old.u_csr.u_csrfile.csr_mcycle_h_q,u_old.u_csr.u_csrfile.csr_mscratch_q}) $fatal(1,"CPU_EQ_FAIL csr_state cycle=%0d",cycles);
        if (DUAL_ISSUE==0 &&
            {u_old.exec1_opcode_valid_w,u_old.u_issue.pipe1_valid_wb_w,
             u_old.u_issue.pipe1_rd_e1_w,u_old.u_issue.pipe1_rd_e2_w,u_old.u_issue.pipe1_rd_wb_w,
             u_old.u_issue.pipe1_branch_e1_w,u_old.u_issue.pipe1_load_e1_w,u_old.u_issue.pipe1_mul_e1_w} !== 20'b0)
            $fatal(1,"CPU_EQ_FAIL inactive_lane_control");
        case (u_old.u_csr.u_csrfile.csr_mcause_q)
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
        if (u_new.u_csr.u_csrfile.csr_waddr_i==`CSR_SIM_CTRL && u_new.u_csr.u_csrfile.exception_i==0 &&
            (u_new.u_csr.u_csrfile.csr_wdata_i & 32'hff000000)==`CSR_SIM_CTRL_EXIT) begin
            if (u_new.u_csr.u_csrfile.csr_wdata_i[7:0]!=0)
                $fatal(1,"CPU_EQ_FAIL program_exit pc=%h cause=%h",u_new.opcode0_pc_w,u_new.u_csr.u_csrfile.csr_mcause_q);
            if (trap_mask!=9'h1ff || i_stalls==0 || d_stalls==0) $fatal(1,"CPU_EQ_FAIL coverage traps=%h",trap_mask);
            $display("CPU_EQ_PASS dual=%0d cycles=%0d traps=%0d i_stalls=%0d d_stalls=%0d",DUAL_ISSUE,cycles,trap_mask,i_stalls,d_stalls);
            $finish;
        end
    end
endmodule
