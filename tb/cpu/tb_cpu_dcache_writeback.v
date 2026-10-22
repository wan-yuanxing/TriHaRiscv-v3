`timescale 1ns / 1ps
// Architectural values are supplied by the test; backing memory changes only
// on accepted lower writes. No hierarchical cache state forms the data oracle.
module tb_cpu_dcache_writeback;
    parameter integer CORRUPT_DATA = 0;
    reg clk=0, rst_n=0;
    always #5 clk=!clk;
    reg [31:0] addr=0, wdata=0;
    reg rd=0, cacheable=1, inval=0, clean=0, flush=0;
    reg [3:0] mask=0;
    reg [10:0] tag=0;
    wire accept, ack, error;
    wire [31:0] rdata;
    wire [10:0] resp_tag;
    wire lower_rd;
    wire [3:0] lower_wr;
    wire [7:0] lower_len;
    wire [31:0] lower_addr, lower_data;
    reg lower_ack=0, lower_error=0;
    reg [31:0] lower_rdata=0;
    reg [31:0] memory[0:65535];
    reg [31:0] random_q=32'h157a93bc;
    reg pending=0, pending_write=0;
    reg [31:0] pending_addr, pending_data;
    reg [3:0] pending_mask;
    integer beat=0, last=0, delay_count=0;
    integer fail_write_word=-1, fail_read_word=-1;
    integer reads=0, writes=0, checks=0, cycles=0;
    wire lower_accept=!pending && !lower_ack && random_q[2];
    task check;
        input ok;
        input [511:0] why;
        begin
            checks=checks+1;
            if (ok !== 1'b1) begin
                $display("CPU_DCACHE_WB_FAIL %0s cycles=%0d addr=%h",why,cycles,addr);
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
    reg held=0;
    reg [76:0] held_request;
    always @(posedge clk) begin
        cycles<=cycles+1;
        random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
        if (cycles>100000) check(0,"watchdog");
        if (!rst_n) begin pending<=0; lower_ack<=0; held<=0; end
        else begin
            if (held) check({lower_rd,lower_wr,lower_len,lower_addr,lower_data} === held_request,
                            "lower request stable under backpressure");
            held<= (lower_rd || |lower_wr) && !lower_accept;
            held_request<={lower_rd,lower_wr,lower_len,lower_addr,lower_data};
            lower_ack<=0; lower_error<=0;
            if ((lower_rd || |lower_wr) && lower_accept) begin
                check(!(lower_rd && |lower_wr),"lower read/write exclusive");
                check(lower_len==0 || (lower_rd && lower_len==7 && lower_addr[4:0]==0),"lower geometry");
                pending<=1; pending_write<=|lower_wr; pending_addr<=lower_addr;
                pending_data<=lower_data; pending_mask<=lower_wr;
                beat<=0; last<=lower_len; delay_count<=5;
                if (lower_rd) reads<=reads+1; else writes<=writes+1;
            end
            if (pending && !lower_ack) begin
                if (delay_count>0) delay_count<=delay_count-1;
                else if (random_q[5]) begin
                    lower_ack<=1;
                    lower_error<=pending_write ? pending_addr[4:2]==fail_write_word : beat==fail_read_word;
                    lower_rdata<=memory[(pending_addr[17:2]+beat)&65535] ^ CORRUPT_DATA;
                    if (pending_write && pending_addr[4:2]!=fail_write_word)
                        for (lane=0;lane<4;lane=lane+1)
                            if (pending_mask[lane]) memory[pending_addr[17:2]][lane*8+:8]<=pending_data[lane*8+:8];
                    if (beat==last) pending<=0;
                    else beat<=beat+1;
                end
            end
        end
    end
    task access;
        input [31:0] a;
        input [3:0] m;
        input [31:0] v;
        input cached;
        input [1:0] maintenance; // 0=data, 1=clean line, 2=invalidate line, 3=flush all
        input expect_error;
        input [31:0] expected;
        integer guard;
        reg [10:0] saved_tag;
        begin
            @(negedge clk);
            addr=a; wdata=v; mask=m; rd=(maintenance==0 && m==0); cacheable=cached;
            clean=maintenance==1; inval=maintenance==2; flush=maintenance==3;
            tag=tag+1; saved_tag=tag; guard=0;
            begin: await_accept
                forever begin
                    @(posedge clk); guard=guard+1;
                    if (accept) disable await_accept;
                    if (guard>30000) check(0,"accept timeout");
                end
            end
            @(negedge clk); mask=0; rd=0; clean=0; inval=0; flush=0;
            while (!ack) begin
                @(negedge clk); guard=guard+1;
                if (guard>30000) check(0,"completion timeout");
            end
            check(error===expect_error,"precise error response");
            check(resp_tag===saved_tag,"response tag preserved");
            if (maintenance==0 && m==0 && !expect_error) check(rdata===expected,"architectural load value");
            @(negedge clk);
        end
    endtask
    integer n,k,old_reads,old_writes;
    reg [31:0] expected_word;
    initial begin
        for(n=0;n<65536;n=n+1) memory[n]=32'h817a693c^(n*32'h31479);
        repeat(4) @(negedge clk); rst_n=1;
        old_reads=reads; old_writes=writes;
        access(32'h8000010c,4'hf,32'h12345678,1,0,0,0);
        check(reads==old_reads+1 && writes==old_writes,"store miss allocates without external write");
        access(32'h8000010c,4'b0101,32'haabbccdd,1,0,0,0);
        access(32'h8000010c,0,0,1,0,0,32'h12bb56dd);
        check(writes==old_writes,"resident stores coalesce");
        check(memory['h43]!==32'h12bb56dd,"dirty data not yet visible to DDR");
        access(32'h8000010c,0,0,1,1,0,0);
        check(writes==old_writes+8 && memory['h43]===32'h12bb56dd,"line clean writes eight correct words");
        old_reads=reads; old_writes=writes;
        access(32'h8000010c,0,0,1,0,0,32'h12bb56dd);
        access(32'h8000010c,0,0,1,1,0,0);
        check(reads==old_reads && writes==old_writes,"clean retains valid line and is idempotent");
        // Each possible failed word must preserve all dirty cache words for retry.
        for(k=0;k<8;k=k+1) begin
            for(n=0;n<8;n=n+1) access(32'h80000100+n*4,4'hf,32'h88990000+k*256+n,1,0,0,0);
            old_writes=writes; fail_write_word=k;
            access(32'h80000100,0,0,1,1,1,0);
            check(writes==old_writes+k+1,"writeback stops at actual failing word");
            for(n=0;n<8;n=n+1) access(32'h80000100+n*4,0,0,1,0,0,32'h88990000+k*256+n);
            fail_write_word=-1; old_writes=writes;
            access(32'h80000100,0,0,1,1,0,0);
            check(writes==old_writes+8,"failed writeback retains dirty state for full retry");
            for(n=0;n<8;n=n+1) check(memory['h40+n]===32'h88990000+k*256+n,"retry restores entire backing line");
        end
        // Exercise eviction using two different tags at one set, then a third.
        for(n=0;n<8;n=n+1) access(32'h80000100+n*4,4'hf,32'h11220000+n,1,0,0,0);
        access(32'h80002100,4'hf,32'h33221100,1,0,0,0);
        old_writes=writes;
        access(32'h80004100,0,0,1,0,0,memory['h1040]);
        check(writes==old_writes+8,"dirty replacement writes victim before refill");
        for(n=0;n<8;n=n+1) check(memory['h40+n]===32'h11220000+n,"eviction victim address and all data");
        // A failed eviction must neither refill the new line nor corrupt the
        // dirty victim. An unrelated access may change replacement selection.
        fail_write_word=3; old_reads=reads;
        access(32'h80006100,0,0,1,0,1,0);
        check(reads==old_reads,"failed eviction never starts allocation");
        access(32'h80002100,0,0,1,0,0,32'h33221100);
        fail_write_word=-1;
        // Invalidate is discard; external owner data must survive a later flush.
        access(32'h80002100,0,0,1,2,0,0);
        memory['h840]=32'h76543210;
        access(32'h80002100,0,0,1,0,0,32'h76543210);
        // Full flush covers both ways, set zero and the highest set.
        access(32'h80000000,4'hf,32'h000000aa,1,0,0,0);
        access(32'h80003ffc,4'hf,32'hffff0055,1,0,0,0);
        access(32'h80000000,0,0,1,3,0,0);
        check(memory[0]===32'h000000aa && memory['hfff]===32'hffff0055,"flush includes all sets and ways");
        old_reads=reads;
        access(32'h80000000,0,0,1,0,0,32'h000000aa);
        check(reads==old_reads+1,"flush invalidates cleaned lines");
        access(32'h80000000,4'hf,32'h01020304,1,0,0,0);
        access(32'h80001fe0,4'hf,32'h88776655,1,0,0,0);
        fail_write_word=4;
        access(32'h80001800,0,0,1,3,1,0);
        access(32'h80000000,0,0,1,0,0,32'h01020304);
        access(32'h80001fe0,0,0,1,0,0,32'h88776655);
        fail_write_word=-1;
        access(32'h80001800,0,0,1,3,0,0);
        check(memory[0]===32'h01020304 && memory['h7f8]===32'h88776655,"failed flush is retryable and retains later dirty sets");
        // Both ways of one set must be cleaned, not only the first dirty way.
        access(32'h80000400,4'hf,32'h99112233,1,0,0,0);
        access(32'h80002400,4'hf,32'h445566aa,1,0,0,0);
        access(32'h80000000,0,0,1,3,0,0);
        check(memory['h100]===32'h99112233 && memory['h900]===32'h445566aa,"flush cleans both dirty ways of one set");
        old_reads=reads;
        access(32'h80000400,0,0,1,0,0,32'h99112233);
        access(32'h80002400,0,0,1,0,0,32'h445566aa);
        check(reads==old_reads+2,"flush invalidates both ways");
        old_writes=writes;
        access(32'h80000e00,4'hf,32'h35ca791b,0,0,0,0);
        old_reads=reads;
        access(32'h80000e00,0,0,0,0,0,32'h35ca791b);
        access(32'h80000e00,0,0,0,0,0,32'h35ca791b);
        check(reads==old_reads+2 && writes==old_writes+1,"private cacheable false also bypasses");
        // Shared and explicit uncached stores require the actual lower response.
        old_writes=writes;
        access(32'h82000800,4'hf,32'hdeadcafe,1,0,0,0);
        check(writes==old_writes+1 && memory['h200]===32'hdeadcafe,"shared store always bypasses");
        old_reads=reads;
        access(32'h82000800,0,0,1,0,0,32'hdeadcafe);
        access(32'h82000800,0,0,1,0,0,32'hdeadcafe);
        check(reads==old_reads+2,"shared reads never allocate");
        fail_write_word=0;
        access(32'h82000800,4'hf,32'hfacefeed,1,0,1,0);
        check(memory['h200]===32'hdeadcafe,"failed uncached store does not publish success");
        fail_write_word=-1;
        // All nonzero byte masks use an independent merge oracle, including
        // read-after-write and visibility after explicit clean.
        expected_word=memory['h2c0];
        for(k=1;k<16;k=k+1) begin
            access(32'h80000b00,k[3:0],32'h138acf50+k,1,0,0,0);
            for(n=0;n<4;n=n+1)
                if(k & (1<<n)) expected_word[n*8+:8]=(32'h138acf50+k)>>(n*8);
            access(32'h80000b00,0,0,1,0,0,expected_word);
        end
        access(32'h80000b00,0,0,1,1,0,0);
        check(memory['h2c0]===expected_word,"all byte masks survive clean");
        for(k=0;k<8;k=k+1) begin
            fail_read_word=k;
            access(32'h80001000+k*32,4'hf,32'h1234,1,0,1,0);
            fail_read_word=-1; old_reads=reads;
            access(32'h80001000+k*32,0,0,1,0,0,memory['h400+k*8]);
            check(reads==old_reads+1,"failed write allocation never becomes valid");
        end
        // Reset is explicitly coordinated and destructive to dirty cache data;
        // no prior ownership or acknowledgement may leak into the next epoch.
        expected_word=memory['h300];
        access(32'h80000c00,4'hf,32'h11223344,1,0,0,0);
        @(negedge clk); rst_n=0;
        repeat(4) @(negedge clk);
        check(!ack && !lower_rd && lower_wr==0,"reset clears owned requests and responses");
        rst_n=1;
        access(32'h80000c00,0,0,1,0,0,expected_word);
        $display("CPU_DCACHE_WB_PASS checks=%0d reads=%0d writes=%0d",checks,reads,writes);
        $finish;
    end
endmodule
