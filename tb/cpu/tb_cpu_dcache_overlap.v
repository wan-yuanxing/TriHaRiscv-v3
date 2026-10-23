`timescale 1ns/1ps
// Independent lower-memory oracle. Only the public request/response interface
// is used for throughput, response ownership and registered-latency checks.
module tb_cpu_dcache_overlap;
    parameter integer CORRUPT_DATA=0;
    reg clk=0, rst_n=0;
    always #5 clk=!clk;
    integer cycles=0, checks=0, reads=0, writes=0;
    reg [31:0] memory[0:65535];
    reg [31:0] addr=0, wdata=0, random_q=32'h93b781af;
    reg rd=0, cacheable=1, inval=0, clean=0, flush=0;
    reg [3:0] mask=0;
    reg [10:0] tag=0;
    wire accept, ack, error;
    wire [10:0] resp_tag;
    wire [31:0] rdata, lower_addr, lower_data;
    wire lower_rd;
    wire [3:0] lower_wr;
    wire [7:0] lower_len;
    reg lower_ack=0, lower_error=0, pending=0;
    reg [31:0] lower_rdata=0, saved_addr, saved_data;
    reg [3:0] saved_mask;
    integer beat=0, last=0, delay_count=0;
    wire lower_accept=!pending && !lower_ack && random_q[2];
    reg fail_read=0, fail_write=0;
    task check;
        input ok;
        input [511:0] message;
        begin
            checks=checks+1;
            if(ok!==1'b1) begin
                $display("CPU_DCACHE_OVERLAP_FAIL %0s cycle=%0d",message,cycles);
                $fatal(1);
            end
        end
    endtask
    triha_dcache u_dut (
        .clk_i(clk),.rst_ni(rst_n),.mem_addr_i(addr),.mem_data_wr_i(wdata),
        .mem_rd_i(rd),.mem_wr_i(mask),.mem_cacheable_i(cacheable),.mem_req_tag_i(tag),
        .mem_invalidate_i(inval),.mem_writeback_i(clean),.mem_flush_i(flush),
        .mem_data_rd_o(rdata),.mem_accept_o(accept),.mem_ack_o(ack),
        .mem_error_o(error),.mem_resp_tag_o(resp_tag),
        .outport_accept_i(lower_accept),.outport_ack_i(lower_ack),
        .outport_error_i(lower_error),.outport_read_data_i(lower_rdata),
        .outport_rd_o(lower_rd),.outport_wr_o(lower_wr),.outport_len_o(lower_len),
        .outport_addr_o(lower_addr),.outport_write_data_o(lower_data)
    );
    integer lane;
    always @(posedge clk) begin
        cycles<=cycles+1;
        random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
        if(cycles>100000) check(0,"watchdog");
        if(!rst_n) begin pending<=0; lower_ack<=0; lower_error<=0; end
        else begin
            lower_ack<=0; lower_error<=0;
            if(lower_accept && (lower_rd || |lower_wr)) begin
                pending<=1; saved_addr<=lower_addr; saved_data<=lower_data;
                saved_mask<=lower_wr; beat<=0; last<=lower_len; delay_count<=3;
                if(lower_rd) reads<=reads+1; else writes<=writes+1;
            end
            if(pending && !lower_ack) begin
                if(delay_count>0) delay_count<=delay_count-1;
                else if(random_q[4]) begin
                    lower_ack<=1; lower_error<=saved_mask==0 ? fail_read : fail_write;
                    lower_rdata<=memory[(saved_addr[17:2]+beat)&65535]^CORRUPT_DATA;
                    for(lane=0;lane<4;lane=lane+1)
                        if(saved_mask[lane] && !fail_write) memory[saved_addr[17:2]][lane*8+:8]<=saved_data[lane*8+:8];
                    if(beat==last) pending<=0; else beat<=beat+1;
                end
            end
        end
    end
    task send;
        input [31:0] a;
        input [3:0] m;
        input [31:0] value;
        input cached;
        input expect_error;
        input [31:0] expected;
        reg [10:0] saved_tag;
        integer guard;
        begin
            @(negedge clk); addr=a; mask=m; wdata=value; rd=m==0; cacheable=cached;
            tag=tag+1; saved_tag=tag; guard=0;
            begin: await_accept
                forever begin @(posedge clk); if(accept) disable await_accept; end
            end
            @(negedge clk); rd=0; mask=0;
            while(!ack) begin @(negedge clk); guard=guard+1; if(guard>20000) check(0,"response timeout"); end
            check(resp_tag===saved_tag && error===expect_error,"serialized response ownership/error");
            if(!expect_error && m==0) check(rdata===expected,"serialized architectural load");
            if(expect_error || !cached) check(!accept,"error and uncached response remain serialized");
            @(negedge clk);
        end
    endtask
    task overlap;
        input [31:0] first_address;
        input [31:0] first_expected;
        input [31:0] second_address;
        input [3:0] second_mask;
        input [31:0] second_value;
        input second_cached;
        input integer maintenance;
        input second_error;
        input [31:0] second_expected;
        reg [10:0] first_tag, second_tag;
        integer first_cycle, guard;
        begin
            @(negedge clk); addr=first_address; rd=1; cacheable=1; mask=0;
            tag=tag+1; first_tag=tag;
            begin: await_first
                forever begin @(posedge clk); if(accept) begin first_cycle=cycles; disable await_first; end end
            end
            @(negedge clk);
            check(!ack,"load retains registered response boundary");
            addr=second_address; mask=second_mask; wdata=second_value;
            rd=maintenance==0 && second_mask==0; cacheable=second_cached;
            clean=maintenance==1; inval=maintenance==2; flush=maintenance==3;
            tag=tag+1; second_tag=tag; guard=0;
            while(!ack) begin @(negedge clk); guard=guard+1; if(guard>1000) check(0,"first response timeout"); end
            check(!error && resp_tag===first_tag && rdata===first_expected,"old registered response survives next payload");
            check(accept,"successful load response accepts the held next request");
            @(posedge clk);
            check(cycles-first_cycle==2,"resident read initiation interval is two cycles");
            check(ack && resp_tag===first_tag && rdata===first_expected,"old response stable through overlap edge");
            @(negedge clk); rd=0; mask=0; clean=0; inval=0; flush=0;
            check(!ack,"next request does not reuse prior acknowledgement");
            if(second_error) begin
                // Present a younger store while the overlapped load fails.
                // It must not be consumed on that load's error response.
                addr=32'h80000e04; mask=4'hf; wdata=32'hdeadbeef; tag=tag+1;
            end
            while(!ack) begin @(negedge clk); guard=guard+1; if(guard>20000) check(0,"next response timeout"); end
            check(error===second_error && resp_tag===second_tag,"next response owns next tag and error");
            if(second_error) check(!accept,"error cannot accept a younger store");
            if(!second_error && maintenance==0 && second_mask==0) check(rdata===second_expected,"next lookup uses accepted set/tag/word");
            if(second_mask!=0) check(!accept,"store update is serialized for read-first RAM safety");
            @(negedge clk); mask=0;
        end
    endtask
    reg score_active=0;
    reg [10:0] expected_tags[0:15];
    reg [31:0] expected_values[0:15];
    integer head=0, tail=0, last_accept_cycle=0;
    always @(posedge clk) if(rst_n && score_active) begin
        if(ack) begin
            check(head<tail,"one response for each accepted chain request");
            check(!error && resp_tag===expected_tags[head] && rdata===expected_values[head],
                  "continuous overlap preserves ordered data/tag");
            head=head+1;
        end
        if(rd && accept) begin
            if(tail>0) check(cycles-last_accept_cycle==2,"continuous resident load interval");
            expected_tags[tail]=tag;
            expected_values[tail]=memory[addr[17:2]];
            last_accept_cycle=cycles;
            tail=tail+1;
        end
    end
    integer n, saved_reads;
    initial begin
        for(n=0;n<65536;n=n+1) memory[n]=32'h3157c8a9^(n*32'h7acd139);
        repeat(4) @(negedge clk); rst_n=1;
        send(32'h80000040,0,0,1,0,memory['h10]);
        send(32'h80000084,0,0,1,0,memory['h21]);
        send(32'h800020c8,0,0,1,0,memory['h832]);
        overlap(32'h80000040,memory['h10],32'h80000084,0,0,1,0,0,memory['h21]);
        overlap(32'h80000084,memory['h21],32'h800020c8,0,0,1,0,0,memory['h832]);
        overlap(32'h80000040,memory['h10],32'h80000044,0,0,1,0,0,memory['h11]);
        @(negedge clk); score_active=1;
        for(n=0;n<12;n=n+1) begin
            addr=n[0] ? 32'h80000084 : 32'h800020c8; rd=1; tag=tag+1;
            begin: chain_accept
                forever begin @(posedge clk); if(accept) disable chain_accept; end
            end
            @(negedge clk);
        end
        rd=0;
        while(head!=tail) @(negedge clk);
        check(tail==12 && head==12,"continuous response/request overlap coverage");
        score_active=0;
        // Different tag at the same set must not use the prior RAM address.
        overlap(32'h80000040,memory['h10],32'h80004040,0,0,1,0,0,memory['h1010]);
        fail_read=1;
        overlap(32'h80000040,memory['h10],32'h80008060,0,0,1,0,1,0);
        fail_read=0;
        send(32'h80000100,4'hf,32'h1937abcd,1,0,0);
        send(32'h80002100,4'hf,32'h7a3bc591,1,0,0);
        fail_write=1;
        overlap(32'h80000040,memory['h10],32'h80004100,0,0,1,0,1,0);
        fail_write=0; saved_reads=reads;
        send(32'h80000100,0,0,1,0,32'h1937abcd);
        send(32'h80002100,0,0,1,0,32'h7a3bc591);
        check(reads==saved_reads,"failed overlapped eviction retains both dirty victims without refill");
        overlap(32'h80000040,memory['h10],32'h80000084,4'b0101,32'h12345678,1,0,0,0);
        send(32'h80000084,0,0,1,0,(memory['h21]&32'hff00ff00)|32'h00340078);
        overlap(32'h80000040,memory['h10],32'h82000a00,0,0,1,0,0,memory['h280]);
        overlap(32'h80000040,memory['h10],32'h80000084,0,0,1,1,0,0);
        overlap(32'h80000040,memory['h10],32'h80000084,0,0,1,2,0,0);
        overlap(32'h80000040,memory['h10],32'h80000000,0,0,1,3,0,0);
        fail_read=1;
        send(32'h80006000,0,0,1,1,0);
        fail_read=0;
        send(32'h80006000,0,0,1,0,memory['h1800]);
        send(32'h82006000,0,0,1,0,memory['h1800]);
        $display("CPU_DCACHE_OVERLAP_PASS checks=%0d reads=%0d writes=%0d",checks,reads,writes);
        $finish;
    end
endmodule
