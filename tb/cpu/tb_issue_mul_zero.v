`timescale 1ns/1ps
module tb_issue_mul_zero;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1), .SUPPORT_SUPER(0), .SUPPORT_MMU(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(1'b0), .reset_vector_i(32'h80000000), .cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1), .mem_i_valid_i(1'b0), .mem_i_error_i(1'b0), .mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0), .mem_d_accept_i(1'b1), .mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0), .mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(), .mem_i_pc_o(), .mem_i_flush_o(), .mem_i_invalidate_o(),
        .mem_d_addr_o(), .mem_d_data_wr_o(), .mem_d_rd_o(), .mem_d_wr_o(), .mem_d_req_tag_o(),
        .mem_d_cacheable_o(), .mem_d_invalidate_o(), .mem_d_writeback_o(), .mem_d_flush_o()
    );


    reg [31:0] a=0,b=0,e0=0,e1=0;
    reg select0=0,select1=0,hold=0;
    integer checks=0,i,j;
    initial begin
        force u_dut.u_mul.opcode_ra_operand_i=a;
        force u_dut.u_mul.opcode_rb_operand_i=b;
        force u_dut.u_mul.hold_i=hold;
        force u_dut.u_issue.pipe0_early_mul_w=select0;
        force u_dut.u_issue.pipe1_early_mul_w=select1;
        force u_dut.u_issue.writeback_exec0_value_i=e0;
        force u_dut.u_issue.writeback_exec1_value_i=e1;
        if($test$plusargs("FAULT_SIDEBAND"))force u_dut.u_mul.early_zero_e1_q=1'b0;
        #2;rst=0;#1;rst=1;#4;rst=0;
        @(negedge clk);a=1;b=1;e0=2;e1=2;
        @(posedge clk);#1;select0=1'bx;select1=1'bz;#0.1;
        if(u_dut.u_issue.raw_source_zero_w[4]!==1'bx || u_dut.u_issue.raw_source_zero_w[5]!==1'bx)
            $fatal(1,"ISSUE_MUL_ZERO_FAIL scalar mux lost vector merge");
        for(i=0;i<2000;i=i+1)begin
            @(negedge clk);
            a=$random;b=$random;e0=$random;e1=$random;hold=(i%7==0);
            if(i%3==0)a=0;
            if(i%5==0)b=0;
            if(i%11==0)e0=0;
            if(i%13==0)e1=0;
            if(i%17==0)b=32'h0000xxxx;
            if(i%19==0)a=32'h0000zzzz;
            if(i%23==0)e0=32'h0000000x;
            if(i%29==0)e1=32'h0000000z;
            @(posedge clk);#1;
            for(j=0;j<4;j=j+1)begin
                case(j)
                    0:begin select0=0;select1=1;end
                    1:begin select0=1;select1=0;end
                    2:begin select0=1'bx;select1=1'bz;end
                    3:begin select0=1'bz;select1=1'bx;end
                endcase
                #0.1;
                if(u_dut.u_issue.raw_source_zero_w[4] !== (u_dut.u_issue.pipe0_forward_e1_w==0) ||
                   u_dut.u_issue.raw_source_zero_w[5] !== (u_dut.u_issue.pipe1_forward_e1_w==0))begin
                    $display("ISSUE_MUL_ZERO_FAIL i=%0d j=%0d",i,j);$finish;
                end
                checks=checks+1;
            end
        end
        $display("ISSUE_MUL_ZERO_PASS checks=%0d",checks);$finish;
    end
endmodule
