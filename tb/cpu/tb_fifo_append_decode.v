// Queue storage destination must not wait on the late count subtraction.
// POISON_ARITH checks cone separation only; normal protocol is tested by the
// transaction-indexed prediction/alignment oracle and complete CPU traces.
`timescale 1ns/1ps
module tb_fifo_append_decode;
    parameter POISON_ARITH=1;
    parameter BROKEN=0;
    reg clk=0,rst=1,push=0,pop0=0,pop1=0;
    always #5 clk=~clk;
    reg [31:0] pc=32'h10000;
    reg [63:0] data=64'h22222222_11111111;
    wire accept,v0,v1;
    wire [31:0] word0,word1;
    triha_fetch_fifo #(.DEPTH(3),.OPC_INFO_W(19)) u_fifo(
        .clk_i(clk),.rst_i(rst),.flush_i(1'b0),.push_i(push),
        .pred_pc_in_i(pc+8),.pc_in_i(pc),.pred_in_i(2'b0),.data_in_i(data),
        .info0_in_i(19'h52345),.info1_in_i(19'h12345),.csr0_in_i(1'b1),.csr1_in_i(1'b0),
        .accept_o(accept),.valid0_o(v0),.valid1_o(v1),.data0_out_o(word0),.data1_out_o(word1),
        .pop0_i(pop0),.pop1_i(pop1));
    initial begin
        repeat(3)@(negedge clk);rst=0;push=1;
        @(posedge clk);#1;
        if(!v0 || !v1 || word0!==32'h11111111 || word1!==32'h22222222)
            $fatal(1,"FIFO_APPEND_FAIL setup");
        @(negedge clk);pc=32'h10008;data=64'h44444444_33333333;
        // Deliberately corrupt only the arithmetic used by next-count logic.
        // Old subtract-then-decode storage overwrites head instead of tail.
        if(POISON_ARITH)force u_fifo.remaining_r=0;
        if(BROKEN)force u_fifo.data_q[2]=32'b0;
        @(posedge clk);#1;
        if(word0!==32'h11111111 || word1!==32'h22222222 ||
           u_fifo.data_q[2]!==32'h33333333 || u_fifo.data_q[3]!==32'h44444444 ||
           u_fifo.pc_q[2]!==32'h10008 || u_fifo.pred_pc_q[2]!==32'h1000c ||
           u_fifo.info_q[2]!==19'h52345 || u_fifo.csr_q[2]!==1'b1)
            $fatal(1,"FIFO_APPEND_FAIL append_storage_depends_on_subtraction");
        if(POISON_ARITH)release u_fifo.remaining_r;
        $display("FIFO_APPEND_PASS arithmetic_isolation=%0d",POISON_ARITH);$finish;
    end
endmodule
