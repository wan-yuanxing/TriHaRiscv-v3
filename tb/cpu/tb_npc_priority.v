/* Highest matching entry: exhaustive small table, all pairs and four-state masks. */
`timescale 1ns/1ps
module tb_npc_priority #(parameter BROKEN=0);
    reg [31:0] match=0, random_q=32'h31415926;
    wire [31:0] raw, actual;
    wire [7:0] actual8;
    wire hit,hit8;
    integer checks=0, i, n, a, b;
    reg [31:0] expected, known_expected;
    reg [7:0] expected8;
    assign actual = BROKEN ? {raw[31:1],~raw[0]} : raw;
    triha_npc_priority #(.INPUTS(32)) u_full(.match_i(match),.select_o(raw),.hit_o(hit));
    triha_npc_priority #(.INPUTS(8)) u_small(.match_i(match[7:0]),.select_o(actual8),.hit_o(hit8));
    task check;
        begin
            #1;
            // Preserved bitwise specification, including X/Z propagation.
            for(i=0;i<32;i=i+1)
                expected[i]=match[i] & ~(|(match>>(i+1)));
            for(i=0;i<8;i=i+1)
                expected8[i]=match[i] & ~(|(match[7:0]>>(i+1)));
            if(actual!==expected || actual8!==expected8 || hit!==( |match) || hit8!==( |match[7:0]))begin
                $display("NPC_PRIORITY_FAIL mask=%h actual=%h expected=%h small=%h expected8=%h",
                    match,actual,expected,actual8,expected8);$finish;
            end
            // Independent ordered oracle for known values.
            if(^match!==1'bx)begin
                known_expected=0;
                for(i=0;i<32;i=i+1)
                    if(match[i])known_expected=32'b1<<i;
                if(actual!==known_expected)begin
                    $display("NPC_PRIORITY_FAIL highest_entry");$finish;
                end
            end
            checks=checks+4;
        end
    endtask
    initial begin
        match=0;check;match=32'hffffffff;check;
        for(a=0;a<32;a=a+1)
            for(b=0;b<32;b=b+1)begin match=(32'b1<<a)|(32'b1<<b);check;end
        for(n=0;n<256;n=n+1)begin match=n;check;end
        for(n=0;n<4096;n=n+1)begin
            random_q=random_q*32'd1664525+32'd1013904223;
            match=random_q;check;
        end
        for(n=0;n<512;n=n+1)begin
            random_q=random_q*32'd1664525+32'd1013904223;
            match=random_q;match[n%32]=1'bx;match[(n+7)%32]=1'bz;check;
        end
        $display("NPC_PRIORITY_PASS checks=%0d all_pairs_exhaustive8_fourstate",checks);$finish;
    end
endmodule
