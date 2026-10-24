/* Check the instantiated decoder capacity, not just a stand-alone FIFO
 * overridden by a test parameter. Both decode configurations are exercised.
 */
`timescale 1ns/1ps
module tb_decode_capacity #(parameter BROKEN=0,parameter EXTRA=0,parameter WORDS=6);
    reg clk=0,rst=1,valid=0,pop=0,flush=0;
    reg [31:0] pc=32'h80001000;
    wire accept,v0,v1;
    wire [31:0] p0,p1,op0,op1;
    integer n,checks=0;
    always #5 clk=~clk;
    triha_decode #(.EXTRA_DECODE_STAGE(EXTRA)) u_dut (
        .clk_i(clk),.rst_i(rst),.fetch_in_valid_i(valid),.fetch_in_instr_i(64'h0010011300000093),
        .fetch_in_pred_branch_i(2'b0),.fetch_in_fault_fetch_i(1'b0),.fetch_in_fault_page_i(1'b0),
        .fetch_in_pc_i(pc),.fetch_out0_accept_i(pop),.fetch_out1_accept_i(pop),
        .branch_request_i(flush),.branch_pc_i(32'b0),.branch_priv_i(2'b11),
        .fetch_in_accept_o(accept),.fetch_out0_valid_o(v0),.fetch_out1_valid_o(v1),
        .fetch_out0_instr_o(op0),.fetch_out1_instr_o(op1),.fetch_out0_pc_o(p0),.fetch_out1_pc_o(p1));
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(n=0;n<WORDS/2;n=n+1)begin
            if(accept!==1) $fatal(1,"DECODE_CAPACITY_FAIL early_full packet=%0d expected_words=%0d",n,WORDS);
            valid=1;pc=32'h80001000+n*8;
            @(negedge clk);#1;checks=checks+1;
        end
        valid=0;
        // EXTRA has a separate input buffer; allow its last packet to arrive.
        repeat(EXTRA+1)@(negedge clk);#1;
        if(accept!==0) $fatal(1,"DECODE_CAPACITY_FAIL not_full");
        if(BROKEN)force u_dut.fetch_out1_instr_o=0;
        for(n=0;n<WORDS/2;n=n+1)begin
            if({v0,v1}!==2'b11 || p0!==32'h80001000+n*8 || p1!==p0+4 ||
               op0!==32'h00000093 || op1!==32'h00100113)
                $fatal(1,"DECODE_CAPACITY_FAIL order_payload packet=%0d",n);
            pop=1;@(negedge clk);#1;checks=checks+1;
        end
        pop=0;if(v0!==0 || v1!==0) $fatal(1,"DECODE_CAPACITY_FAIL not_empty");
        $display("DECODE_CAPACITY_PASS checks=%0d words=%0d extra=%0d",checks,WORDS,EXTRA);$finish;
    end
endmodule
