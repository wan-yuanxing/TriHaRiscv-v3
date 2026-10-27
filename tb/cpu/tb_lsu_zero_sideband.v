`timescale 1ns/1ps
module tb_lsu_zero_sideband #(parameter LOAD_BYPASS=1, parameter MUL_BYPASS=1);
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



    reg [31:0] data=0,alu0=0,alu1=0,mul=0;
    reg [1:0] addr=0;
    reg byte_load=0,half_load=0,signed_load=0,valid=0,ack=0,err=0,unaligned=0,stall=0;
    reg [9:0] ctrl=0;
    integer i,k,checks=0;
    wire scalar;
`ifdef HAS_LSU_ZERO
    assign scalar=u_dut.u_lsu.writeback_bypass_zero_o;
`else
    assign scalar=1'b0;
`endif
    function fourstate;
        input integer value;
        begin case(value%4)0:fourstate=0;1:fourstate=1;2:fourstate=1'bx;3:fourstate=1'bz;endcase end
    endfunction
    function [31:0] payload;
        input integer value;
        begin case(value%4)0:payload=0;1:payload=32'h81000001;2:payload=32'bx;3:payload=32'bz;endcase end
    endfunction
    task check;
        begin
            #1;
            if(scalar!==(u_dut.u_lsu.writeback_bypass_o==0))
                $fatal(1,"LSU_ZERO_FAIL payload check=%0d data=%h addr=%b byte=%b half=%b signed=%b scalar=%b value=%h",checks,data,addr,byte_load,half_load,signed_load,scalar,u_dut.u_lsu.writeback_bypass_o);
`ifdef HAS_LSU_ZERO
            if(u_dut.u_issue.raw_source_zero_w[2]!==(u_dut.u_issue.pipe0_result_e2_w==0) ||
               u_dut.u_issue.raw_source_zero_w[3]!==(u_dut.u_issue.pipe1_result_e2_w==0))
                $fatal(1,"LSU_ZERO_FAIL E2 check=%0d ctrl=%b valid=%b",checks,ctrl,valid);
`endif
            checks=checks+1;
        end
    endtask
    initial begin
        force u_dut.u_lsu.mem_data_rd_i=data;
        force u_dut.u_lsu.resp_addr_w={30'b0,addr};
        force u_dut.u_lsu.resp_byte_w=byte_load;
        force u_dut.u_lsu.resp_half_w=half_load;
        force u_dut.u_lsu.resp_signed_w=signed_load;
        force u_dut.u_lsu.mem_ack_i=ack;
        force u_dut.u_lsu.mem_error_i=err;
        force u_dut.u_lsu.mem_unaligned_e2_q=unaligned;
        force u_dut.u_issue.u_pipe0_ctrl.ctrl_e2_q=ctrl;
        force u_dut.u_issue.u_pipe1_ctrl.ctrl_e2_q=ctrl;
        force u_dut.u_issue.u_pipe0_ctrl.valid_e2_q=valid;
        force u_dut.u_issue.u_pipe1_ctrl.valid_e2_q=valid;
        force u_dut.u_issue.u_pipe0_ctrl.result_e2_q=alu0;
        force u_dut.u_issue.u_pipe1_ctrl.result_e2_q=alu1;
        force u_dut.u_issue.u_pipe0_ctrl.mul_result_e2_i=mul;
        force u_dut.u_issue.u_pipe1_ctrl.mul_result_e2_i=mul;
        force u_dut.u_issue.u_pipe0_ctrl.issue_stall_i=stall;
        force u_dut.u_issue.u_pipe1_ctrl.issue_stall_i=stall;
`ifdef HAS_LSU_ZERO
        if($test$plusargs("FAULT_ZERO"))force u_dut.u_lsu.writeback_bypass_zero_o=1'b0;
        if($test$plusargs("FAULT_E2"))force u_dut.u_issue.u_pipe0_ctrl.result_zero_e2_o=1'b0;
`endif
        #2;rst=0;check;
        // Every 4-state metadata combination, with walking payload/sign bits.
        for(i=0;i<1024;i=i+1)begin
            addr={fourstate(i/4),fourstate(i)};
            byte_load=fourstate(i/16);half_load=fourstate(i/64);signed_load=fourstate(i/256);
            valid=fourstate(i/8);ctrl=i%64;
            ctrl[1]=fourstate(i/2);ctrl[2]=fourstate(i/4);ctrl[5]=fourstate(i/16);
            ack=fourstate(i);err=fourstate(i/4);unaligned=fourstate(i/16);stall=fourstate(i/64);
            for(k=0;k<36;k=k+1)begin
                data=(k<32) ? (32'b1<<k) : 0;
                alu0=(k%2) ? 0 : 7;alu1=(k%3) ? 9 : 0;mul=(k%5) ? 0 : 13;
                if(k==33)data[7]=1'bx;
                if(k==34)data[23]=1'bz;
                if(k==35)begin data=32'hffffffff;data[31]=1'bx;end
                check;
            end
        end
        // Independent E2 selector cross-product, including valid STORE and
        // LOAD/STORE/MUL conflicts. Data inputs vary independently as well.
        byte_load=0;half_load=0;signed_load=0;addr=0;
        for(i=0;i<256;i=i+1)begin
            ctrl=0;ctrl[1]=fourstate(i);ctrl[2]=fourstate(i/4);
            ctrl[5]=fourstate(i/16);valid=fourstate(i/64);
            for(k=0;k<256;k=k+1)begin
                alu0=payload(k);alu1=payload(k/4);mul=payload(k/16);data=payload(k/64);
                check;
            end
        end
        $display("LSU_ZERO_PASS checks=%0d load=%0d mul=%0d",checks,LOAD_BYPASS,MUL_BYPASS);$finish;
    end
endmodule
