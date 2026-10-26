`timescale 1ns/1ps
module tb_fifo_head_ring;
    parameter CHECK_STORAGE = 1;
    parameter BROKEN = 0;
    reg clk=0, rst=1, flush=0, push=0, pop0=0, pop1=0;
    always #5 clk=~clk;
    reg [31:0] pc=0, predpc=0;
    reg [1:0] pred=0;
    reg [63:0] data=0;
    reg [19:0] meta0=0, meta1=0;
    wire accept,v0,v1;
    wire [115:0] out0,out1;
    triha_fetch_fifo #(.DEPTH(3),.OPC_INFO_W(19)) u_fifo(
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),
        .pc_in_i(pc),.pred_pc_in_i(predpc),.pred_in_i(pred),.data_in_i(data),
        .info0_in_i(meta0[19:1]),.info1_in_i(meta1[19:1]),
        .csr0_in_i(meta0[0]),.csr1_in_i(meta1[0]),
        .pop0_i(pop0),.pop1_i(pop1),.accept_o(accept),.valid0_o(v0),.valid1_o(v1),
        .pred_pc0_out_o(out0[115:84]),.pc0_out_o(out0[83:52]),
        .data0_out_o(out0[51:20]),.info0_out_o(out0[19:1]),.csr0_out_o(out0[0]),
        .pred_pc1_out_o(out1[115:84]),.pc1_out_o(out1[83:52]),
        .data1_out_o(out1[51:20]),.info1_out_o(out1[19:1]),.csr1_out_o(out1[0]));
    reg [115:0] model[0:5], survivors[0:5];
    reg [115:0] before_payload[0:5];
    reg [31:0] random_state=32'h3196ab47;
    integer count=0,steps=0,i,j,n,oldcount;
    integer coverage[0:6][0:3];
    integer cross_coverage[0:6][0:3][0:2][0:1];
    integer cc,pp,ee,ff,fill,ecount,write_ptr=0,read_ptr=0,write_wraps=0,read_wraps=0;
    integer kind;
    reg take0,take1,enqueue;
    reg [31:0] aligned0,aligned1;
    task randomize;
        begin
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
        end
    endtask
    task step;
        begin
            #1;
            take0=pop0 && count>0;
            take1=pop1 && count>1 && model[1][83:52]==model[0][83:52]+32'd4;
            enqueue=push && count<=4;
            kind={take1,take0}; coverage[count][kind]=coverage[count][kind]+1;
            ecount=enqueue ? ((!pc[2] && !pred[0])?2:1) : 0;
            if(!rst)cross_coverage[count][kind][ecount][flush]=cross_coverage[count][kind][ecount][flush]+1;
            oldcount=count;
            for(i=0;i<6;i=i+1)before_payload[i]={u_fifo.pred_pc_q[i],u_fifo.pc_q[i],u_fifo.data_q[i],u_fifo.info_q[i],u_fifo.csr_q[i]};
            n=0;
            for(i=0;i<count;i=i+1)begin
                if(!((i==0 && take0)||(i==1 && take1)))begin
                    survivors[n]=model[i];n=n+1;
                end
            end
            aligned0={pc[31:3],3'b000};aligned1=aligned0+4;
            if(enqueue)begin
                if(pc[2])begin
                    survivors[n]={(pred[1]?predpc:aligned1+32'd4),aligned1,data[63:32],meta1};n=n+1;
                end else begin
                    survivors[n]={(pred[0]?predpc:aligned0+32'd4),aligned0,data[31:0],meta0};n=n+1;
                    if(!pred[0])begin
                        survivors[n]={(pred[1]?predpc:aligned1+32'd4),aligned1,data[63:32],meta1};n=n+1;
                    end
                end
            end
            if(rst)begin
                count=0;for(i=0;i<6;i=i+1)model[i]=0;
            end else begin
                for(i=0;i<n;i=i+1)begin
                    model[i][115:20]=survivors[i][115:20];
                    if(!flush)model[i][19:0]=survivors[i][19:0];
                end
                count=flush?0:n;
            end
            if(rst || flush)begin write_ptr=0;read_ptr=0;end
            else begin
                write_ptr=write_ptr+ecount;read_ptr=read_ptr+take0+take1;
                if(write_ptr>=6)begin write_ptr=write_ptr-6;write_wraps=write_wraps+1;end
                if(read_ptr>=6)begin read_ptr=read_ptr-6;read_wraps=read_wraps+1;end
            end
            @(posedge clk);#1;steps=steps+1;
            if(out0!==model[0] || out1!==model[1] || accept!==(count<=4) ||
                v0!==(count!=0) || v1!==((count>1)&&(model[1][83:52]==model[0][83:52]+32'd4)))
                $fatal(1,"HEAD_RING_FAIL sequence step=%0d old=%0d count=%0d out0=%h expected=%h out1=%h expected=%h",steps,oldcount,count,out0,model[0],out1,model[1]);
            if(CHECK_STORAGE && !enqueue && !rst)
                for(i=0;i<6;i=i+1)if({u_fifo.pred_pc_q[i],u_fifo.pc_q[i],u_fifo.data_q[i],u_fifo.info_q[i],u_fifo.csr_q[i]}!==before_payload[i])
                    $fatal(1,"HEAD_RING_FAIL backend_rewritten_without_enqueue step=%0d slot=%0d",steps,i);
            @(negedge clk);
        end
    endtask
    initial begin
        for(i=0;i<6;i=i+1)model[i]=0;
        for(i=0;i<7;i=i+1)for(j=0;j<4;j=j+1)coverage[i][j]=0;
        for(cc=0;cc<7;cc=cc+1)for(pp=0;pp<4;pp=pp+1)
            for(ee=0;ee<3;ee=ee+1)for(ff=0;ff<2;ff=ff+1)cross_coverage[cc][pp][ee][ff]=0;
        @(negedge clk);step;rst=0;
        push=1;pc=32'h10000;data=64'h22222222_11111111;step;
        pc=pc+8;data=64'h44444444_33333333;step;
        pc=pc+8;data=64'h66666666_55555555;step;
        push=0;pop0=1;pop1=1;step;
        if(BROKEN)force u_fifo.data0_out_o=32'hdeadbeef;
        for(cc=0;cc<7;cc=cc+1)for(pp=0;pp<4;pp=pp+1)
            for(ee=0;ee<3;ee=ee+1)for(ff=0;ff<2;ff=ff+1)begin
                rst=1;push=0;pop0=0;pop1=0;flush=0;step;rst=0;
                for(fill=0;fill<cc;fill=fill+1)begin
                    // When five words are present, the conservative reserve
                    // blocks a sixth single write: fill the final pair at four.
                    if(cc==6 && fill==4)begin
                        pc=32'h10010;pred=0;push=1;step;fill=fill+1;
                    end else begin pc=32'h10000+fill*4;pred=1;push=1;step;end
                end
                pc=32'h20000;pred=ee==1?1:0;push=ee!=0;pop0=pp[0];pop1=pp[1];flush=ff!=0;step;
            end
        for(j=0;j<20000;j=j+1)begin
            randomize;push=random_state[0];pop0=random_state[1];pop1=random_state[2];
            flush=(random_state[9:3]==0);rst=(random_state[19:10]==0);
            // Mostly sequential PC so both output lanes and B-only are exercised.
            if(random_state[5:4]!=0 && count>0)pc=model[count-1][83:52]+4;
            else pc={random_state[31:3],3'b000};
            pred=random_state[21:20];predpc=random_state^32'h12340000;
            data={random_state,~random_state};meta0=random_state[19:0];meta1=~random_state[19:0];step;
        end
        for(i=2;i<=6;i=i+1)for(j=0;j<4;j=j+1)
            if(coverage[i][j]==0)$fatal(1,"HEAD_RING_FAIL uncovered count=%0d consumption=%0d",i,j);
        for(cc=0;cc<7;cc=cc+1)for(pp=0;pp<4;pp=pp+1)
            for(ee=0;ee<(cc<=4?3:1);ee=ee+1)for(ff=0;ff<2;ff=ff+1)
                if((cc>1 || (cc==1 && pp<2) || (cc==0 && pp==0)) && cross_coverage[cc][pp][ee][ff]==0)
                    $fatal(1,"HEAD_RING_FAIL missing_cross count=%0d consume=%0d input=%0d flush=%0d",cc,pp,ee,ff);
        if(write_wraps==0 || read_wraps==0)$fatal(1,"HEAD_RING_FAIL no_wrap");
        $display("HEAD_RING_PASS steps=%0d storage=%0d write_wraps=%0d read_wraps=%0d",steps,CHECK_STORAGE,write_wraps,read_wraps);$finish;
    end
endmodule
