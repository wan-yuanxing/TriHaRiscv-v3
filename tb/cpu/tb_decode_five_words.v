// Check the instantiated odd-capacity queue, including its two-word reserve.
`timescale 1ns/1ps
module tb_decode_five_words #(parameter EXTRA=0,parameter BROKEN=0);
    reg clk=0,rst=1,valid=0,pop0=0,pop1=0;
    reg [31:0] pc=32'h80001004;
    wire accept,v0,v1;
    wire [31:0] pc0,pc1,word0,word1;
    always #5 clk=~clk;
    triha_decode #(.EXTRA_DECODE_STAGE(EXTRA)) u_dut(
        .clk_i(clk),.rst_i(rst),.fetch_in_valid_i(valid),
        .fetch_in_instr_i(64'h00100113_00000093),.fetch_in_pc_i(pc),
        .fetch_in_pred_pc_i(pc+8),.fetch_in_pred_branch_i(2'b0),
        .fetch_in_fault_fetch_i(1'b0),.fetch_in_fault_page_i(1'b0),
        .fetch_out0_accept_i(pop0),.fetch_out1_accept_i(pop1),
        .branch_request_i(1'b0),.branch_pc_i(32'b0),.branch_priv_i(2'b11),
        .fetch_in_accept_o(accept),.fetch_out0_valid_o(v0),.fetch_out1_valid_o(v1),
        .fetch_out0_pc_o(pc0),.fetch_out1_pc_o(pc1),
        .fetch_out0_instr_o(word0),.fetch_out1_instr_o(word1));
    task send_packet;
        input [31:0] address;
        begin
            @(negedge clk);pc=address;valid=1;
            #1;if(accept!==1)$fatal(1,"DECODE_FIVE_FAIL early_backpressure");
            @(negedge clk);valid=0;
            repeat(EXTRA+1)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;
        if(u_dut.genblk1.u_fifo.WORDS!=5)
            $fatal(1,"DECODE_FIVE_FAIL actual_capacity=%0d",u_dut.genblk1.u_fifo.WORDS);
        send_packet(32'h80001004); // upper word only
        send_packet(32'h80001008); // two words
        send_packet(32'h80001010); // two words, occupancy five
        #1;
        if(BROKEN)force u_dut.fetch_out0_instr_o=0;
        #1;if(u_dut.genblk1.u_fifo.count_q!==5 || accept!==0 ||
              {v0,v1}!==2'b11 || pc0!==32'h80001004 || pc1!==32'h80001008 ||
              word0!==32'h00100113 || word1!==32'h00000093)
            $fatal(1,"DECODE_FIVE_FAIL full_payload_or_count");
        @(negedge clk);pop0=1;
        @(negedge clk);pop0=0;#1;
        if(u_dut.genblk1.u_fifo.count_q!==4 || accept!==0 ||
           pc0!==32'h80001008 || pc1!==32'h8000100c)
            $fatal(1,"DECODE_FIVE_FAIL two_word_reserve");
        pop0=1;pop1=1;
        @(negedge clk);pop0=0;pop1=0;#1;
        if(u_dut.genblk1.u_fifo.count_q!==2 || accept!==1 ||
           {v0,v1}!==2'b11 || pc0!==32'h80001010 || pc1!==32'h80001014)
            $fatal(1,"DECODE_FIVE_FAIL pair_drain");
        pop0=1;pop1=1;
        @(negedge clk);pop0=0;pop1=0;#1;
        if(v0!==0 || v1!==0 || accept!==1)$fatal(1,"DECODE_FIVE_FAIL empty");
        $display("DECODE_FIVE_PASS extra=%0d",EXTRA);$finish;
    end
endmodule
