/* PC update priority and modulo-32-bit arithmetic, independent oracle. */
`timescale 1ns / 1ps
module tb_pc_update #(parameter BROKEN=0);
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg csr_req=0, ex0_req=0, ex1_req=0, single_step=0, dual_step=0;
    reg [31:0] csr_pc=0, ex0_pc=0, ex1_pc=0;
    reg [1:0] csr_priv=0;
    reg [31:0] expected_pc=0, random_q=32'h71a5c093, corrupt_pc=0;
    reg [1:0] expected_priv=2'b11;
    integer cycles=0, i;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),.mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(),.mem_i_pc_o(),.mem_i_flush_o(),.mem_i_invalidate_o(),
        .mem_d_addr_o(),.mem_d_data_wr_o(),.mem_d_rd_o(),.mem_d_wr_o(),.mem_d_req_tag_o(),
        .mem_d_cacheable_o(),.mem_d_invalidate_o(),.mem_d_writeback_o(),.mem_d_flush_o()
    );
    task random_next;
        begin
            random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
        end
    endtask
    task step;
        begin
            if (rst) begin expected_pc=0;expected_priv=2'b11;end
            else begin
                casez ({csr_req,ex1_req,ex0_req,dual_step,single_step})
                    5'b1????: expected_pc=csr_pc;
                    5'b01???: expected_pc=ex1_pc;
                    5'b001??: expected_pc=ex0_pc;
                    5'b0001?: expected_pc=expected_pc+32'd8;
                    5'b00001: expected_pc=expected_pc+32'd4;
                    default: expected_pc=expected_pc;
                endcase
                if(csr_req) expected_priv=csr_priv;
            end
            @(posedge clk); #1;
            if(BROKEN && cycles==50) begin
                corrupt_pc=expected_pc^32'h80000000;
                force u_dut.u_issue.pc_x_q=corrupt_pc;
            end
            if(u_dut.u_issue.pc_x_q!==expected_pc || u_dut.u_issue.priv_x_q!==expected_priv)
                $fatal(1,"PC_UPDATE_FAIL cycle=%0d got=%h expected=%h priv=%h expected_priv=%h",
                    cycles,u_dut.u_issue.pc_x_q,expected_pc,u_dut.u_issue.priv_x_q,expected_priv);
            cycles=cycles+1;
            @(negedge clk);
        end
    endtask
    initial begin
        force u_dut.u_issue.branch_csr_request_i=csr_req;
        force u_dut.u_issue.branch_d_exec0_request_i=ex0_req;
        force u_dut.u_issue.branch_d_exec1_request_i=ex1_req;
        force u_dut.u_issue.branch_csr_pc_i=csr_pc;
        force u_dut.u_issue.branch_d_exec0_pc_i=ex0_pc;
        force u_dut.u_issue.branch_d_exec1_pc_i=ex1_pc;
        force u_dut.u_issue.branch_csr_priv_i=csr_priv;
        force u_dut.u_issue.single_issue_w=single_step;
        force u_dut.u_issue.dual_issue_w=dual_step;
        @(negedge clk);step;rst=0;
        // Keep low bits and exercise carry through all high bits and wrap.
        csr_req=1;csr_pc=32'hfffffffd;step;csr_req=0;single_step=1;step;
        dual_step=1;step;single_step=0;dual_step=0;step;
        for(i=0;i<4096;i=i+1) begin
            random_next;
            {csr_req,ex1_req,ex0_req,dual_step,single_step}=random_q[4:0];
            csr_priv=random_q[6:5];
            random_next;csr_pc=random_q;
            random_next;ex0_pc=random_q;
            random_next;ex1_pc=random_q;
            if((i%97)==0) begin
                csr_req=1;csr_pc=32'hffffffff;
            end
            if((i%97)==1) begin
                csr_req=0;ex0_req=0;ex1_req=0;single_step=1;dual_step=0;
            end
            rst=((i%503)==499);
            step;
        end
        $display("PC_UPDATE_PASS cycles=%0d priority_reset_hold_wrap_both_widths",cycles);
        $finish;
    end
endmodule
