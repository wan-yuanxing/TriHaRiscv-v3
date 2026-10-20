`timescale 1ns/1ps
module tb_indexed_btb #(parameter BROKEN=0);
    reg clk=0, rst=1, flush=0, train=0, taken=0;
    reg [31:0] source=0, target=0, pc=0, random_q=32'h27182818;
    reg [2:0] kind=0;
    wire hit, upper;
    wire [31:0] predicted;
    wire [2:0] predicted_kind;
    reg valid[0:511];
    reg [31:0] tags[0:511], targets[0:511];
    reg [2:0] kinds[0:511];
    integer i, index, chosen, checks=0, collisions=0, retained=0;
    reg expected_hit, expected_upper;
    reg [31:0] expected_target;
    reg [2:0] expected_kind;
    always #5 clk=~clk;
    triha_btb u_dut(.clk_i(clk),.rst_i(rst),.invalidate_i(flush),
        .train_i(train),.taken_i(taken),.source_i(source),.target_i(target),.kind_i(kind),
        .pc_i(pc),.valid_o(hit),.upper_o(upper),.target_o(predicted),.kind_o(predicted_kind));
    task check;
        begin
            chosen=-1; expected_upper=pc[2];
            index=(pc>>2)&511;
            if(valid[index] && tags[index]==pc) chosen=index;
            else if(!pc[2] && valid[index+1] && tags[index+1]==(pc|32'd4)) begin
                chosen=index+1;expected_upper=1;
            end
            expected_hit=chosen>=0;
            expected_target=expected_hit ? targets[chosen] : 0;
            expected_kind=expected_hit ? kinds[chosen] : 0;
            if(hit!==expected_hit || expected_hit &&
                {upper,predicted,predicted_kind}!=={expected_upper,expected_target,expected_kind})
                $fatal(1,"INDEXED_BTB_FAIL pc=%h hit=%b/%b target=%h/%h",pc,hit,expected_hit,predicted,expected_target);
            checks=checks+1;
        end
    endtask
    task step;
        begin
            #1; check;
            @(posedge clk);
            if(rst||flush) begin for(index=0;index<512;index=index+1)valid[index]=0;end
            else if(train) begin
                index=(source>>2)&511;
                if(valid[index] && tags[index]!=source)collisions=collisions+1;
                if(!valid[index] || tags[index]!=source || taken)targets[index]=target;
                else retained=retained+1;
                valid[index]=1;tags[index]=source;kinds[index]=kind;
            end
            #1;
            if(BROKEN && checks>=99) force u_dut.target_o=32'hdeadbeef;
            check;@(negedge clk);
        end
    endtask
    task random_next;
        begin random_q=random_q^(random_q<<13);random_q=random_q^(random_q>>17);random_q=random_q^(random_q<<5);end
    endtask
    initial begin
        for(i=0;i<512;i=i+1) begin valid[i]=0;tags[i]=0;targets[i]=0;kinds[i]=0;end
        @(negedge clk);step;rst=0;
        // Fill/query every entry and both banks, including index511.
        train=1;taken=1;
        for(i=0;i<512;i=i+1) begin source=32'h80000000+i*4;target=32'h90000000+i*8;kind=i[2:0];pc=source;step;end
        train=0;
        for(i=0;i<512;i=i+1) begin pc=32'h80000000+i*4;step;end
        // Retain a known target on not-taken training; a colliding tag replaces it.
        train=1;taken=0;source=32'h80000000;pc=source;target=32'hdeadbeef;step;
        source=32'h80000800;target=32'h12345678;pc=source;step;
        train=0;pc=32'h80000000;step;
        flush=1;step;flush=0;
        // Only upper word hit, then lower word must take priority.
        train=1;taken=1;source=32'h81000004;target=32'h91000004;pc=32'h81000000;step;
        source=32'h81000000;target=32'h91000000;step;
        for(i=0;i<4000;i=i+1) begin
            random_next;source=32'h82000000+{20'b0,random_q[9:0],2'b0};
            random_next;target={random_q[31:2],2'b0};kind=random_q[2:0];
            train=random_q[5];taken=random_q[7];
            pc=32'h82000000+{21'b0,random_q[8:0],2'b0};
            if((i%7)==0)pc=source;
            flush=(i%809)==808;step;
        end
        rst=1;train=0;step;rst=0;step;
        if(collisions<10 || retained<1)$fatal(1,"INDEXED_BTB_FAIL coverage");
        $display("INDEXED_BTB_PASS checks=%0d collisions=%0d target_retained=%0d entries=512",checks,collisions,retained);
        $finish;
    end
endmodule
