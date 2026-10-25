// Flush invalidates all words; bulk data may advance, CSR/class history may not.
`timescale 1ns/1ps
module tb_fifo_flush_data;
    parameter BROKEN=0;
    reg clk=0,rst=1,flush=0,push=0,pop0=0,pop1=0;
    always #5 clk=~clk;
    reg [31:0] pc=32'h10000,pred_pc=32'h10008;
    reg [63:0] data=64'h22222222_11111111;
    reg [17:0] info0=18'h20001,info1=18'h3ffff;
    reg csr0=1,csr1=0;
    wire ready,valid0,valid1,outcsr0,outcsr1;
    wire [31:0] word0,word1,pc0,pc1;
    wire [17:0] outinfo0,outinfo1;
    triha_fetch_fifo #(.OPC_INFO_W(18),.DEPTH(3)) u_fifo(
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),.pc_in_i(pc),
        .pred_pc_in_i(pred_pc),.pred_in_i(2'b0),.data_in_i(data),
        .info0_in_i(info0),.info1_in_i(info1),.csr0_in_i(csr0),.csr1_in_i(csr1),
        .accept_o(ready),.valid0_o(valid0),.valid1_o(valid1),
        .pc0_out_o(pc0),.pc1_out_o(pc1),.data0_out_o(word0),.data1_out_o(word1),
        .info0_out_o(outinfo0),.info1_out_o(outinfo1),.csr0_out_o(outcsr0),.csr1_out_o(outcsr1),
        .pop0_i(pop0),.pop1_i(pop1));
    initial begin
        repeat(3)@(negedge clk);rst=0;push=1;
        @(posedge clk);#1;
        if(!valid0 || !valid1 || word0!==32'h11111111 || outinfo0!==18'h20001 || outcsr0!==1)
            $fatal(1,"FIFO_FLUSH_DATA_FAIL setup");
        @(negedge clk);push=0;flush=1;pop0=1;
        if(BROKEN)force u_fifo.csr_q[0]=1'b0;
        @(posedge clk);#1;
        if(valid0 || valid1)$fatal(1,"FIFO_FLUSH_DATA_FAIL flush_valid");
        if(outinfo0!==18'h20001 || outinfo1!==18'h3ffff || outcsr0!==1 || outcsr1!==0)
            $fatal(1,"FIFO_FLUSH_DATA_FAIL lost_inactive_CSR_class_history");
        if(word0!==32'h22222222 || pc0!==32'h10004)
            $fatal(1,"FIFO_FLUSH_DATA_FAIL bulk_data_still_waits_on_flush");
        @(negedge clk);flush=0;pop0=0;push=1;
        data=64'h44444444_33333333;pc=32'h20000;pred_pc=32'h20008;
        info0=18'h12345;info1=18'h02345;csr0=0;csr1=1;
        @(posedge clk);#1;
        if(!valid0 || !valid1 || word0!==32'h33333333 || word1!==32'h44444444 ||
           pc0!==32'h20000 || outinfo0!==18'h12345 || outcsr0!==0 || outcsr1!==1)
            $fatal(1,"FIFO_FLUSH_DATA_FAIL stale_data_became_valid");
        // Keep the original procedural-if treatment: X/Z flush does not take
        // the flush branch, so metadata must advance with these valid words.
        @(negedge clk);push=0;pop0=1;flush=1'bx;
        @(posedge clk);#1;
        if(!valid0 || valid1 || word0!==32'h44444444 || outinfo0!==18'h02345 || outcsr0!==1)
            $fatal(1,"FIFO_FLUSH_DATA_FAIL unknown_flush_metadata_advance");
        @(negedge clk);push=1;flush=1'bz;pc=32'h30000;
        data=64'h66666666_55555555;info0=18'h30001;csr0=1;
        @(posedge clk);#1;
        if(!valid0 || !valid1 || word0!==32'h55555555 || outinfo0!==18'h30001 || outcsr0!==1)
            $fatal(1,"FIFO_FLUSH_DATA_FAIL highz_flush_metadata_advance");
        $display("FIFO_FLUSH_DATA_PASS");$finish;
    end
endmodule
