/* Independent word-stream oracle for paired packet FIFO compaction. */
`timescale 1ns/1ps
module tb_fifo_cross_pair #(parameter BROKEN=0,parameter DEPTH=2);
    reg clk=0,rst=1,flush=0,push=0,pop0=0,pop1=0;
    reg [31:0] pc=32'h80001000;
    reg [63:0] data=64'h2222222211111111;
    reg [1:0] pred=0;
    reg [9:0] info0=1,info1=2;
    reg hint0=0,hint1=1;
    wire v0,v1,accept,h0,h1;
    wire [31:0] p0,p1,d0,d1;
    wire [9:0] i0,i1;
    integer count=0,n,k,checks=0;
    reg [31:0] qp[0:7],qd[0:7];
    reg [9:0] qi[0:7];
    reg qh[0:7];
    reg [31:0] rng=32'h12345679;
    reg expected_second;
    always #5 clk=~clk;
    triha_fetch_fifo #(.OPC_INFO_W(10),.DEPTH(DEPTH)) u_dut (
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),.pc_in_i(pc),
        .pred_in_i(pred),.data_in_i(data),.info0_in_i(info0),.info1_in_i(info1),.accept_o(accept),
        .valid0_o(v0),.pc0_out_o(p0),.data0_out_o(d0),.info0_out_o(i0),.pop0_i(pop0),
        .valid1_o(v1),.pc1_out_o(p1),.data1_out_o(d1),.info1_out_o(i1),.pop1_i(pop1),
        .csr0_in_i(hint0),.csr1_in_i(hint1),.csr0_out_o(h0),.csr1_out_o(h1));
    task remove_word;
        input integer idx;
        integer j;
        begin
            for(j=idx;j<count-1;j=j+1) begin
                qp[j]=qp[j+1];qd[j]=qd[j+1];qi[j]=qi[j+1];qh[j]=qh[j+1];
            end
            count=count-1;
        end
    endtask
    always @(posedge clk) begin
        if(rst || flush) count=0;
        else begin
            if(pop1 && v1) remove_word(1);
            if(pop0 && v0) remove_word(0);
            if(push && accept) begin
                qp[count]={pc[31:3],3'b000};qd[count]=data[31:0];qi[count]=info0;qh[count]=hint0;count=count+1;
                if(!pred[0]) begin
                    qp[count]={pc[31:3],3'b100};qd[count]=data[63:32];qi[count]=info1;qh[count]=hint1;count=count+1;
                end
            end
        end
    end
    task check;
        begin
            #1;checks=checks+1;
            if(accept !== (count<=2*DEPTH-2)) $fatal(1,"FIFO_CROSS_FAIL accept count=%0d accept=%b",count,accept);
            expected_second=(count>1) && qp[1]==qp[0]+4;
            if(v0 !== (count!=0) || v1 !== expected_second)
                $fatal(1,"FIFO_CROSS_FAIL valid count=%0d actual=%b%b expected_second=%b",count,v0,v1,expected_second);
            if(v0 && {p0,d0,i0,h0} !== {qp[0],qd[0],qi[0],qh[0]})
                $fatal(1,"FIFO_CROSS_FAIL head got=%h expected=%h",p0,qp[0]);
            if(v1 && {p1,d1,i1,h1} !== {qp[1],qd[1],qi[1],qh[1]})
                $fatal(1,"FIFO_CROSS_FAIL second got=%h expected=%h",p1,qp[1]);
            if(count>2*DEPTH) $fatal(1,"FIFO_CROSS_FAIL overflow");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=0;push=1;
        @(negedge clk);check;pc=pc+8;data=64'h4444444433333333;info0=3;info1=4;hint0=1;hint1=0;
        @(negedge clk);check;push=0;pop0=1;
        @(negedge clk);check; // upper first packet + lower next packet
        if(BROKEN) force u_dut.info1_out_o=0;
        pop1=1;
        @(negedge clk);check;pop1=0;
        @(negedge clk);check;pop0=0;
        for(n=0;n<4000;n=n+1) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            push=rng[0];pop0=rng[1];pop1=rng[2];flush=rng[7:3]==0;
            pred=rng[9:8];pc=(rng[10] && count>0) ? ((qp[count-1]&32'hfffffff8)+8) : {4'h8,rng[27:3],3'b0};
            data={rng,~rng};info0=rng[9:0];info1=rng[19:10];hint0=rng[11];hint1=rng[12];
            @(negedge clk);check;
        end
        $display("FIFO_CROSS_PASS checks=%0d",checks);$finish;
    end
endmodule
