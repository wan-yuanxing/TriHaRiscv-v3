/* The complete predictor training event must cross one registered boundary. */
`timescale 1ns / 1ps
module tb_predictor_training;
    reg clk=0, rst=1;
    reg [69:0] packet=0;
    localparam [69:0] EVENT_A={1'b1,1'b1,1'b0,32'h80001000,1'b1,1'b0,1'b0,32'h80002000};
    localparam [69:0] EVENT_B={1'b0,1'b0,1'b1,32'h80003000,1'b0,1'b0,1'b0,32'h80004000};
    localparam [69:0] EVENT_C={1'b1,1'b1,1'b0,32'h80005000,1'b0,1'b1,1'b0,32'h80006000};
    localparam [69:0] EVENT_D={1'b1,1'b1,1'b0,32'h80007000,1'b0,1'b0,1'b1,32'h80008000};
    always #5 clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(0), .SUPPORT_SUPER(0), .SUPPORT_MMU(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(1'b0), .reset_vector_i(32'h80000000), .cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1), .mem_i_valid_i(1'b0), .mem_i_error_i(1'b0), .mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0), .mem_d_accept_i(1'b1), .mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0), .mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(), .mem_i_pc_o(), .mem_i_flush_o(), .mem_i_invalidate_o(),
        .mem_d_addr_o(), .mem_d_data_wr_o(), .mem_d_rd_o(), .mem_d_wr_o(), .mem_d_req_tag_o(),
        .mem_d_cacheable_o(), .mem_d_invalidate_o(), .mem_d_writeback_o(), .mem_d_flush_o()
    );
    wire [69:0] observed={u_dut.u_frontend.u_npc.branch_request_i,
        u_dut.u_frontend.u_npc.branch_is_taken_i,u_dut.u_frontend.u_npc.branch_is_not_taken_i,
        u_dut.u_frontend.u_npc.branch_source_i,u_dut.u_frontend.u_npc.branch_is_call_i,
        u_dut.u_frontend.u_npc.branch_is_ret_i,u_dut.u_frontend.u_npc.branch_is_jmp_i,
        u_dut.u_frontend.u_npc.branch_pc_i};
    initial begin
        force {u_dut.u_frontend.branch_info_request_i,u_dut.u_frontend.branch_info_is_taken_i,
            u_dut.u_frontend.branch_info_is_not_taken_i,u_dut.u_frontend.branch_info_source_i,
            u_dut.u_frontend.branch_info_is_call_i,u_dut.u_frontend.branch_info_is_ret_i,
            u_dut.u_frontend.branch_info_is_jmp_i,u_dut.u_frontend.branch_info_pc_i}=packet;
        repeat(5) @(negedge clk);
        rst=0;
        packet=EVENT_A;
        #1;
        if(observed!==0) $fatal(1,"TRAINING_FAIL combinational_event");
        @(negedge clk);
        if(observed!==EVENT_A) $fatal(1,"TRAINING_FAIL tuple_a");
        packet=EVENT_B;
        #1;
        if(observed!==EVENT_A) $fatal(1,"TRAINING_FAIL combinational_bht_update");
        @(negedge clk);
        if(observed!==EVENT_B) $fatal(1,"TRAINING_FAIL tuple_b");
        packet=EVENT_C;
        @(negedge clk);
        if(observed!==EVENT_C) $fatal(1,"TRAINING_FAIL tuple_c_return");
        packet=EVENT_D;
        @(negedge clk);
        if(observed!==EVENT_D) $fatal(1,"TRAINING_FAIL tuple_d_jump");
        packet=0;
        @(negedge clk);
        if(observed!==0) $fatal(1,"TRAINING_FAIL stale_event");
        $display("TRAINING_PASS coherent_miss_and_nonmiss_events");
        $finish;
    end
endmodule
