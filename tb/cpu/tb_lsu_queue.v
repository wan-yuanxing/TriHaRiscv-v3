/* Request FIFO: compare all stale/valid data with the frozen original, and
   valid traffic with an independent ordered queue model. */
`timescale 1ns / 1ps
module lsu_queue_case #(parameter DEPTH=2, ADDR_W=1, BROKEN=0)(output reg done=0);
    reg clk=0, rst=1, push=0, pop=0;
    always #5 clk=~clk;
    reg [35:0] data_in=0, poison=0;
    wire [35:0] candidate, original;
    wire accept,valid,ref_accept,ref_valid;
    reg [35:0] queue[0:DEPTH-1];
    reg [31:0] random_q=32'h5e31c729;
    integer count=0, cycles=0, i,j, pushes=0,pops=0,full_pair=0,empty_pair=0;
    reg do_push,do_pop;
    triha_lsu_fifo #(.WIDTH(36),.DEPTH(DEPTH),.ADDR_W(ADDR_W)) u_candidate
        (.clk_i(clk),.rst_i(rst),.data_in_i(data_in),.push_i(push),.pop_i(pop),
         .data_out_o(candidate),.accept_o(accept),.valid_o(valid));
    biriscv_lsu_fifo #(.WIDTH(36),.DEPTH(DEPTH),.ADDR_W(ADDR_W)) u_original
        (.clk_i(clk),.rst_i(rst),.data_in_i(data_in),.push_i(push),.pop_i(pop),
         .data_out_o(original),.accept_o(ref_accept),.valid_o(ref_valid));
    task compare;
        begin
            if({accept,valid,candidate}!=={ref_accept,ref_valid,original})
                $fatal(1,"LSU_QUEUE_FAIL depth=%0d cycle=%0d including_stale candidate=%h original=%h",DEPTH,cycles,candidate,original);
            if(valid!==(count!=0) || accept!==(count<DEPTH))
                $fatal(1,"LSU_QUEUE_FAIL independent_flags depth=%0d cycle=%0d",DEPTH,cycles);
            if(valid && candidate!==queue[0])
                $fatal(1,"LSU_QUEUE_FAIL independent_data depth=%0d cycle=%0d",DEPTH,cycles);
        end
    endtask
    task step;
        begin
            compare;
            do_push=push&&(count<DEPTH);do_pop=pop&&(count!=0);
            if(push&&pop&&count==DEPTH) full_pair=full_pair+1;
            if(push&&pop&&count==0) empty_pair=empty_pair+1;
            if(rst) count=0;
            else begin
                if(do_pop) begin
                    for(j=0;j<DEPTH-1;j=j+1) queue[j]=queue[j+1];
                    count=count-1;pops=pops+1;
                end
                if(do_push) begin queue[count]=data_in;count=count+1;pushes=pushes+1;end
            end
            @(posedge clk);#1;
            if(BROKEN && cycles==50) begin poison=original^36'h1;force u_candidate.data_out_o=poison;end
            compare;cycles=cycles+1;
            @(negedge clk);
        end
    endtask
    initial begin
        @(negedge clk);#1;step;rst=0;
        for(i=0;i<10000;i=i+1) begin
            random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
            {push,pop}={random_q[0],random_q[16]};
            data_in={random_q[3:0],random_q};
            if(!push&&(i%17)==0)data_in=36'hxxxxxxxxx;
            rst=((i%509)==505);
            // Asynchronous reset changes the original before the next edge.
            if(rst)begin #1;count=0;end
            step;
        end
        $display("LSU_QUEUE_CASE_PASS depth=%0d cycles=%0d pushes=%0d pops=%0d full_pair=%0d empty_pair=%0d",DEPTH,cycles,pushes,pops,full_pair,empty_pair);
        if(pushes<1000||pops<1000||full_pair<100||empty_pair<100)
            $fatal(1,"LSU_QUEUE_FAIL insufficient_boundary_coverage");
        done=1;
    end
endmodule

module tb_lsu_queue #(parameter BROKEN=0);
    wire two_done,four_done;
    lsu_queue_case #(.BROKEN(BROKEN)) u_two(.done(two_done));
    lsu_queue_case #(.DEPTH(4),.ADDR_W(2)) u_four(.done(four_done));
    initial begin
        wait(two_done&&four_done);
        $display("LSU_QUEUE_PASS two_and_four_entries_all_stale_and_valid_data");
        $finish;
    end
endmodule
