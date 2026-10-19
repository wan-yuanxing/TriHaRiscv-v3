/* Free-slot data capture, full/flush protection and original metadata history. */
`timescale 1ns / 1ps
`ifndef FIFO_MODULE
`define FIFO_MODULE fetch_fifo
`endif
module tb_fifo_payload #(parameter BROKEN=0);
    reg clk=0, rst=1, flush=0, push=0, pop0=0, pop1=0;
    reg [31:0] pc=32'h80001000;
    reg [63:0] data=64'h3000107300700293;
    reg [9:0] info0=10'h123, info1=10'h2aa;
    reg [1:0] pred=0;
    reg [31:0] random_q=32'h51ca738d;
    wire v0,v1,accept,g_v0,g_v1,g_accept;
    wire [31:0] pc0,pc1,d0,d1,g_pc0,g_pc1,g_d0,g_d1;
    wire [9:0] out0,out1,g_out0,g_out1;
    wire in_hint0,in_hint1,hint0,hint1,g_hint0,g_hint1;
    integer n,checks=0;
    always #5 clk=~clk;
    biriscv_decoder u_in0 (.valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(data[31:0]),
        .invalid_o(),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(in_hint0),.rd_valid_o());
    biriscv_decoder u_in1 (.valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(data[63:32]),
        .invalid_o(),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(in_hint1),.rd_valid_o());
    biriscv_decoder u_old0 (.valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(g_d0),
        .invalid_o(),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(g_hint0),.rd_valid_o());
    biriscv_decoder u_old1 (.valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(g_d1),
        .invalid_o(),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(g_hint1),.rd_valid_o());
    fetch_fifo #(.OPC_INFO_W(10)) u_golden (
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),.pc_in_i(pc),.pred_in_i(pred),.data_in_i(data),
        .info0_in_i(info0),.info1_in_i(info1),.accept_o(g_accept),
        .valid0_o(g_v0),.pc0_out_o(g_pc0),.data0_out_o(g_d0),.info0_out_o(g_out0),.pop0_i(pop0),
        .valid1_o(g_v1),.pc1_out_o(g_pc1),.data1_out_o(g_d1),.info1_out_o(g_out1),.pop1_i(pop1)
    );
    `FIFO_MODULE #(.OPC_INFO_W(10)) u_dut (
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),.pc_in_i(pc),.pred_in_i(pred),.data_in_i(data),
        .info0_in_i(info0),.info1_in_i(info1),.accept_o(accept),
        .valid0_o(v0),.pc0_out_o(pc0),.data0_out_o(d0),.info0_out_o(out0),.pop0_i(pop0),
        .valid1_o(v1),.pc1_out_o(pc1),.data1_out_o(d1),.info1_out_o(out1),.pop1_i(pop1)
        `ifdef FIFO_HAS_HINT
        ,.csr0_in_i(in_hint0),.csr1_in_i(in_hint1),.csr0_out_o(hint0),.csr1_out_o(hint1)
        `endif
    );
    `ifndef FIFO_HAS_HINT
    assign hint0=g_hint0;
    assign hint1=g_hint1;
    `endif
    always @(negedge clk) if(!rst) begin
        if({v0,v1,accept,out0,out1,hint0,hint1}!=={g_v0,g_v1,g_accept,g_out0,g_out1,g_hint0,g_hint1})
            $fatal(1,"FIFO_PAYLOAD_FAIL control_or_sticky_csr_metadata");
        if(v0 && {pc0,d0}!=={g_pc0,g_d0}) $fatal(1,"FIFO_PAYLOAD_FAIL active_lane0");
        if(v1 && {pc1,d1}!=={g_pc1,g_d1}) $fatal(1,"FIFO_PAYLOAD_FAIL active_lane1");
        checks=checks+1;
    end
    initial begin
        repeat(4) @(negedge clk);
        #1; rst=0;
        @(negedge clk); #1;
        if(pc0!==32'h80001000 || {d1,d0}!==64'h3000107300700293 || {v0,v1}!==0)
            $fatal(1,"FIFO_PAYLOAD_FAIL free_slot_not_sampling");
        if(BROKEN) force u_dut.data0_out_o=32'b0;
        push=1;
        @(negedge clk); #1; push=0;
        pc=32'h80002000; data=64'h0070029330001073;
        repeat(3) @(negedge clk);
        #1; push=1;
        @(negedge clk); #1; push=0;
        pc=32'h80003000; data=64'hfeedface12345678;
        repeat(3) @(negedge clk);
        #1; if(accept!==0) $fatal(1,"FIFO_PAYLOAD_FAIL full_not_held");
        pop0=1;
        @(negedge clk); #1; pop1=1;
        @(negedge clk); #1; pop0=0;pop1=0;
        repeat(2) @(negedge clk);
        #1; pop0=1;pop1=1;
        @(negedge clk); #1; pop0=0;pop1=0;
        // Empty free payload may change; old CSR classification must not.
        data=64'h3000107330001073;
        repeat(3) @(negedge clk);
        #1; flush=1;push=1;
        @(negedge clk); #1; flush=0;push=0;
        data=64'hxxxxxxxxxxxxxxxx; pc=32'hxxxxxxxx;
        info0=10'hxxx; info1=10'hxxx;
        repeat(3) @(negedge clk);
        for(n=0;n<2000;n=n+1) begin
            @(negedge clk); #1;
            random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
            push=random_q[0];pop0=random_q[1];pop1=random_q[2];flush=(random_q[7:3]==0);
            pred=random_q[9:8];pc={4'h8,random_q[27:3],3'b0};
            data={random_q^32'h98765432,~random_q};info0=random_q[9:0];info1=random_q[19:10];
        end
        repeat(2) @(negedge clk);
        #1; $display("FIFO_PAYLOAD_PASS checks=%d full_flush_partial_pop_sticky_csr",checks);
        $finish;
    end
endmodule
