`timescale 1ns/1ps
module tb_early_branch_target #(parameter LOAD_BYPASS=1, parameter MUL_BYPASS=1);
    reg clk=0,rst=1;
    always #5 clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1), .SUPPORT_LOAD_BYPASS(LOAD_BYPASS), .SUPPORT_MUL_BYPASS(MUL_BYPASS), .SUPPORT_SUPER(0), .SUPPORT_MMU(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(1'b0), .reset_vector_i(32'h80000000), .cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1), .mem_i_valid_i(1'b0), .mem_i_error_i(1'b0), .mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0), .mem_d_accept_i(1'b1), .mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0), .mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(), .mem_i_pc_o(), .mem_i_flush_o(), .mem_i_invalidate_o(),
        .mem_d_addr_o(), .mem_d_data_wr_o(), .mem_d_rd_o(), .mem_d_wr_o(), .mem_d_req_tag_o(),
        .mem_d_cacheable_o(), .mem_d_invalidate_o(), .mem_d_writeback_o(), .mem_d_flush_o()
    );



    reg [31:0] pc=0,op=0;
    reg valid=0,accept=0,stall=0,squash=0,own_squash=0,interrupt=0;
    wire [31:0] pc1=~pc,op1=op^32'ha5a5a5a5;
    integer i,checks=0;
    wire [31:0] actual0,actual1;
`ifdef HAS_EARLY_BRANCH_TARGET
    assign actual0=u_dut.u_issue.u_pipe0_ctrl.conditional_pc_e1_o;
    assign actual1=u_dut.u_issue.u_pipe1_ctrl.conditional_pc_e1_o;
`else
    assign actual0=0;
    assign actual1=0;
`endif
    function [31:0] target;
        input [31:0] p,o;
        begin target=p+{{19{o[31]}},o[31],o[7],o[30:25],o[11:8],1'b0};end
    endfunction
    function four;
        input integer v;
        begin case(v%4)0:four=0;1:four=1;2:four=1'bx;3:four=1'bz;endcase end
    endfunction
    task check;
        begin
            #1;
            if(actual0!==target(u_dut.u_issue.u_pipe0_ctrl.pc_e1_q,u_dut.u_issue.u_pipe0_ctrl.opcode_e1_q) ||
               actual1!==target(u_dut.u_issue.u_pipe1_ctrl.pc_e1_q,u_dut.u_issue.u_pipe1_ctrl.opcode_e1_q))
                $fatal(1,"EARLY_TARGET_FAIL checks=%0d",checks);
            checks=checks+1;
        end
    endtask
    initial begin
        force u_dut.u_issue.u_pipe0_ctrl.issue_pc_i=pc;
        force u_dut.u_issue.u_pipe0_ctrl.issue_opcode_i=op;
        force u_dut.u_issue.u_pipe0_ctrl.issue_valid_i=valid;
        force u_dut.u_issue.u_pipe0_ctrl.issue_accept_i=accept;
        force u_dut.u_issue.u_pipe0_ctrl.issue_stall_i=stall;
        force u_dut.u_issue.u_pipe0_ctrl.squash_e1_e2_i=squash;
        force u_dut.u_issue.u_pipe0_ctrl.take_interrupt_i=interrupt;
        force u_dut.u_issue.u_pipe0_ctrl.squash_e1_e2_o=own_squash;
        force u_dut.u_issue.u_pipe1_ctrl.issue_pc_i=pc1;
        force u_dut.u_issue.u_pipe1_ctrl.issue_opcode_i=op1;
        force u_dut.u_issue.u_pipe1_ctrl.issue_valid_i=valid;
        force u_dut.u_issue.u_pipe1_ctrl.issue_accept_i=accept;
        force u_dut.u_issue.u_pipe1_ctrl.issue_stall_i=stall;
        force u_dut.u_issue.u_pipe1_ctrl.squash_e1_e2_i=squash;
        force u_dut.u_issue.u_pipe1_ctrl.take_interrupt_i=interrupt;
        force u_dut.u_issue.u_pipe1_ctrl.squash_e1_e2_o=own_squash;
`ifdef HAS_EARLY_BRANCH_TARGET
        if($test$plusargs("FAULT_TARGET"))force u_dut.u_issue.u_pipe0_ctrl.conditional_pc_e1_o=0;
`endif
        #2;rst=0;#1;rst=1;#4;rst=0;
        @(negedge clk);pc=32'h80001234;op=32'hfe008ee3;valid=1;accept=1;
        @(posedge clk);check;
        for(i=0;i<16384;i=i+1)begin
            @(negedge clk);pc=$random;op=$random;
            valid=four(i);accept=four(i/4);stall=four(i/16);squash=four(i/64);interrupt=four(i/256);own_squash=four(i/1024);rst=four(i/4096);
            if(i%13==0)pc[i%32]=1'bx;
            if(i%17==0)op[i%32]=1'bz;
            @(posedge clk);check;
        end
        rst=0;valid=1;accept=1;stall=0;squash=0;own_squash=0;interrupt=0;
        for(i=0;i<8192;i=i+1)begin
            @(negedge clk);pc=$random;op=$random;
            op[31]=i[12];op[7]=i[11];op[30:25]=i[10:5];op[11:8]=i[4:1];
            @(posedge clk);check;
        end
        $display("EARLY_TARGET_PASS checks=%0d",checks);$finish;
    end
endmodule
