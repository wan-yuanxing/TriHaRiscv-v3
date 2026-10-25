// Independent survivor-list oracle over every reachable occupancy and all
// binary/X/Z dequeue, enqueue and flush controls. Does not use DUT count math.
`timescale 1ns/1ps
module tb_fifo_destination_oracle;
    reg clk=0,rst=1,push=0,pop0=0,pop1=0,flush=0;
    always #5 clk=~clk;
    reg [31:0] pc=32'h20000;
    reg [1:0] pred=0;
    wire accept,v0,v1;
    reg [31:0] saved_data[0:5],saved_pc[0:5],saved_pred[0:5];
    reg [18:0] saved_info[0:5];
    reg saved_csr[0:5];
    reg [31:0] expected_data[0:5],expected_pc[0:5],expected_pred[0:5];
    reg [18:0] expected_info[0:5];
    reg expected_csr[0:5];
    integer count,control,variant,k,j,kept,checks=0,expected_count;
    reg keep_entry;
    triha_fetch_fifo #(.DEPTH(3),.OPC_INFO_W(19)) u_fifo(
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),
        .pred_pc_in_i(32'h30000),.pc_in_i(pc),.pred_in_i(pred),
        .data_in_i(64'hbbbbbbbb_aaaaaaaa),
        .info0_in_i(19'h55555),.info1_in_i(19'h2aaaa),.csr0_in_i(1'b1),.csr1_in_i(1'b0),
        .accept_o(accept),.valid0_o(v0),.valid1_o(v1),.pop0_i(pop0),.pop1_i(pop1));
    function four_state;
        input integer code;
        case(code)
            0:four_state=0;1:four_state=1;2:four_state=1'bx;3:four_state=1'bz;
        endcase
    endfunction
    initial begin
        repeat(3)@(negedge clk);rst=0;
        for(count=0;count<=6;count=count+1)
        for(control=0;control<256;control=control+1)
        for(variant=0;variant<4;variant=variant+1)begin
            @(negedge clk);
            u_fifo.count_q=count;
            pop0=four_state(control%4);pop1=four_state((control/4)%4);
            push=four_state((control/16)%4);flush=four_state(control/64);
            pc=32'h20000+(variant%2)*4;pred=(variant/2);
            for(k=0;k<6;k=k+1)begin
                saved_data[k]=32'habc00000+k;
                saved_pc[k]=32'h10000+4*k;
                // Exercise non-contiguous B, which must not be removed.
                if(k==1 && control%2)saved_pc[k]=saved_pc[k]+4;
                saved_pred[k]=32'h40000+16*k;
                saved_info[k]=19'h10000+k;saved_csr[k]=k%2;
                u_fifo.data_q[k]=saved_data[k];u_fifo.pc_q[k]=saved_pc[k];
                u_fifo.pred_pc_q[k]=saved_pred[k];u_fifo.info_q[k]=saved_info[k];
                u_fifo.csr_q[k]=saved_csr[k];
                expected_data[k]=saved_data[k];expected_pc[k]=saved_pc[k];
                expected_pred[k]=saved_pred[k];expected_info[k]=saved_info[k];
                expected_csr[k]=saved_csr[k];
            end
            kept=0;
            for(k=0;k<count;k=k+1)begin
                keep_entry=1;
                if(k==0)begin if(!(pop0 && count!=0))keep_entry=1;else keep_entry=0;end
                if(k==1)begin
                    if(!(pop1 && count>1 && saved_pc[1]==saved_pc[0]+4))keep_entry=1;
                    else keep_entry=0;
                end
                if(keep_entry)begin
                    expected_data[kept]=saved_data[k];expected_pc[kept]=saved_pc[k];
                    expected_pred[kept]=saved_pred[k];expected_info[kept]=saved_info[k];
                    expected_csr[kept]=saved_csr[k];kept=kept+1;
                end
            end
            expected_count=kept;
            if(push && count<=4)begin
                expected_data[kept]=pc[2] ? 32'hbbbbbbbb : 32'haaaaaaaa;
                expected_pc[kept]=pc;
                expected_pred[kept]=(!pc[2] && pred[0]) ? 32'h30000 : pc+4;
                expected_info[kept]=pc[2] ? 19'h2aaaa : 19'h55555;
                expected_csr[kept]=!pc[2];expected_count=kept+1;
                if(!pc[2] && !pred[0])begin
                    expected_data[kept+1]=32'hbbbbbbbb;expected_pc[kept+1]=pc+4;
                    expected_pred[kept+1]=pc+8;expected_info[kept+1]=19'h2aaaa;
                    expected_csr[kept+1]=0;expected_count=kept+2;
                end
            end
            if(flush)expected_count=0;
            @(posedge clk);#1;
            if(u_fifo.count_q!==expected_count[2:0])
                $fatal(1,"FIFO_DEST_FAIL count n=%0d ctrl=%0d v=%0d",count,control,variant);
            for(j=0;j<6;j=j+1)begin
                if({u_fifo.data_q[j],u_fifo.pc_q[j],u_fifo.pred_pc_q[j]}!==
                   {expected_data[j],expected_pc[j],expected_pred[j]})
                    $fatal(1,"FIFO_DEST_FAIL bulk n=%0d ctrl=%0d v=%0d entry=%0d",count,control,variant,j);
                if(flush)begin expected_info[j]=saved_info[j];expected_csr[j]=saved_csr[j];end
                if({u_fifo.info_q[j],u_fifo.csr_q[j]}!=={expected_info[j],expected_csr[j]})
                    $fatal(1,"FIFO_DEST_FAIL metadata n=%0d ctrl=%0d v=%0d entry=%0d",count,control,variant,j);
            end
            checks=checks+1;
        end
        $display("FIFO_DEST_PASS states=%0d",checks);$finish;
    end
endmodule
