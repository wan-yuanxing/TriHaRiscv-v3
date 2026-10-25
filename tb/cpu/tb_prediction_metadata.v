// Prediction belongs to the accepted request, including skid and queue holds.
`timescale 1ns/1ps
module tb_prediction_metadata;
    parameter HAS_METADATA=0;
    parameter BROKEN=0;
    parameter EXTRA_DECODE=0;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg redirect=0, consume0=0, consume1=0, allow=1;
    reg [31:0] redirect_pc=32'h80000000;
    reg [31:0] prediction_pc=0;
    reg [1:0] prediction_bits=0;
    reg response=0, pending=0;
    reg [63:0] response_data=0;
    reg response_error=0, response_page=0;
    integer wait_count=0, pending_id=0, next_id=0;
    integer cycle=0, checks=0, packets=0, skids=0, drops=0, redirects=0;
    integer predicted0=0,predicted1=0,b_only=0;
    reg [31:0] request_pc[0:4095], request_next[0:4095];
    reg [1:0] request_bits[0:4095];
    reg [31:0] queue_pc[0:31], queue_next[0:31];
    integer count=0, removed, i, ident, stimulus;
    reg [31:0] packet_pc,packet_next;
    reg [1:0] packet_bits;
    reg stage_valid=0;
    reg [31:0] stage_pc=0,stage_next=0;
    reg [1:0] stage_bits=0;
    reg packet_valid;
    reg [31:0] rng=32'h31415926;
    wire rd,valid0,valid1;
    wire [31:0] pc,pc0,pc1,next0,next1;
    triha_frontend #(.SUPPORT_MMU(0),.SUPPORT_BRANCH_PREDICTION(0),
        .EXTRA_DECODE_STAGE(EXTRA_DECODE)) u_dut (
        .clk_i(clk),.rst_i(rst),.icache_accept_i(allow && !pending),
        .icache_valid_i(response),.icache_error_i(response_error),
        .icache_inst_i(response_data),.icache_page_fault_i(response_page),
        .fetch0_accept_i(consume0),.fetch1_accept_i(consume1),.fetch_invalidate_i(1'b0),
        .branch_request_i(redirect),.branch_pc_i(redirect_pc),.branch_priv_i(2'b11),
        .branch_info_request_i(1'b0),.branch_info_is_taken_i(1'b0),
        .branch_info_is_not_taken_i(1'b0),.branch_info_source_i(32'b0),
        .branch_info_is_call_i(1'b0),.branch_info_is_ret_i(1'b0),
        .branch_info_is_jmp_i(1'b0),.branch_info_pc_i(32'b0),
        .icache_rd_o(rd),.icache_pc_o(pc),
        .fetch0_valid_o(valid0),.fetch0_pc_o(pc0),
        .fetch1_valid_o(valid1),.fetch1_pc_o(pc1)
    );
    // No timing change: drive the existing predictor/request interface only.
    initial begin
        force u_dut.next_pc_f_w=prediction_pc;
        force u_dut.next_taken_f_w=prediction_bits;
    end
    generate if(HAS_METADATA)begin:g_metadata
        assign next0=BROKEN ? prediction_pc : u_dut.fetch0_pred_pc_o;
        assign next1=BROKEN ? prediction_pc : u_dut.fetch1_pred_pc_o;
    end else begin:g_absent
        assign next0=32'b0;
        assign next1=32'b0;
    end endgenerate

    // A separate transaction-indexed memory model. Live predictions change
    // during requests, responses, and backpressure; request snapshots do not.
    always @(posedge clk) begin
        if(rst)begin response<=0;pending<=0;end
        else begin
            response<=0;
            if(rd && allow && !pending)begin
                if(next_id>=4096)$fatal(1,"PRED_METADATA_FAIL transaction_capacity");
                request_pc[next_id]=pc;
                request_next[next_id]=prediction_pc;
                request_bits[next_id]=prediction_bits;
                pending_id<=next_id;
                next_id=next_id+1;
                wait_count<=rng[5:4];pending<=1;
            end else if(pending)begin
                if(wait_count==0)begin
                    response<=1;pending<=0;
                    response_data<={20'h00013,pending_id[11:0],20'h00013,pending_id[11:0]};
                    response_error<=(pending_id%29==13);
                    response_page<=(pending_id%31==17);
                end else wait_count<=wait_count-1;
            end
        end
    end

    // Architectural queue oracle; no DUT compaction/control expressions used.
    always @(posedge clk)begin
        if(rst)begin count=0;stage_valid=0;end
        else begin
            cycle=cycle+1;
            if(valid0 !== (count!=0))$fatal(1,"PRED_METADATA_FAIL valid0 cycle=%0d count=%0d",cycle,count);
            if(valid1 !== (count>1 && queue_pc[1]==queue_pc[0]+4))
                $fatal(1,"PRED_METADATA_FAIL valid1 cycle=%0d count=%0d",cycle,count);
            if(valid0)begin
                checks=checks+1;
                if(pc0!==queue_pc[0] || next0!==queue_next[0])
                    $fatal(1,"PRED_METADATA_FAIL head cycle=%0d pc=%h/%h next=%h/%h",cycle,pc0,queue_pc[0],next0,queue_next[0]);
            end
            if(valid1)begin
                checks=checks+1;
                if(pc1!==queue_pc[1] || next1!==queue_next[1])
                    $fatal(1,"PRED_METADATA_FAIL secondary cycle=%0d",cycle);
            end
            if(redirect)begin count=0;stage_valid=0;redirects=redirects+1;end
            else begin
                packet_valid=EXTRA_DECODE ? stage_valid && u_dut.fetch_accept_w :
                    u_dut.fetch_valid_w && u_dut.fetch_accept_w;
                if(EXTRA_DECODE)begin packet_pc=stage_pc;packet_next=stage_next;packet_bits=stage_bits;end
                // Observe accepted fetch response and check it against memory's
                // original request, including the unchanged response skid.
                if(u_dut.fetch_valid_w && u_dut.fetch_accept_w)begin
                    ident=u_dut.fetch_instr_w[11:0];
                    if(u_dut.fetch_pc_w!==request_pc[ident] || u_dut.fetch_pred_branch_w!==request_bits[ident])
                        $fatal(1,"PRED_METADATA_FAIL response_alignment id=%0d",ident);
                    if(EXTRA_DECODE==0)begin
                        packet_pc=request_pc[ident];packet_next=request_next[ident];packet_bits=request_bits[ident];
                    end
                end
                removed=0;
                if(valid0 && consume0)begin removed=1;end
                if(valid1 && consume1)begin
                    if(!consume0)begin
                        b_only=b_only+1;
                        for(i=1;i<count-1;i=i+1)begin queue_pc[i]=queue_pc[i+1];queue_next[i]=queue_next[i+1];end
                        count=count-1;
                    end else removed=2;
                end
                if(removed!=0)begin
                    for(i=0;i<count-removed;i=i+1)begin queue_pc[i]=queue_pc[i+removed];queue_next[i]=queue_next[i+removed];end
                    count=count-removed;
                end
                if(packet_valid)begin
                    packets=packets+1;
                    queue_pc[count]=packet_pc;
                    queue_next[count]=packet_bits[0] ? packet_next : packet_pc+4;
                    if(packet_bits[0])predicted0=predicted0+1;
                    count=count+1;
                    if(!packet_bits[0])begin
                        queue_pc[count]=packet_pc+4;
                        queue_next[count]=packet_bits[1] ? packet_next : packet_pc+8;
                        if(packet_bits[1])predicted1=predicted1+1;
                        count=count+1;
                    end
                end
                if(EXTRA_DECODE && (!stage_valid || u_dut.fetch_accept_w))begin
                    ident=u_dut.fetch_instr_w[11:0];
                    stage_pc=request_pc[ident];stage_next=request_next[ident];stage_bits=request_bits[ident];
                    stage_valid=u_dut.fetch_valid_w;
                end
            end
            if(u_dut.fetch_valid_w && !u_dut.fetch_accept_w)skids=skids+1;
            if(response && !u_dut.fetch_valid_w)drops=drops+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(stimulus=0;stimulus<12000;stimulus=stimulus+1)begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            prediction_pc={24'h800000,rng[7:3],3'b0};
            prediction_bits=(rng[9:8]==3) ? 2'b0 : rng[9:8];
            consume0=(cycle%79<35) && rng[10];
            consume1=(cycle%79<35) && rng[11];
            allow=rng[12] || rng[13];
            redirect=(cycle==0 || cycle%137==41 || cycle%137==42);
            redirect_pc={16'h8000,cycle[12:0],3'b000};
        end
        if(checks<2000 || skids<50 || drops<10 || predicted0<50 || predicted1<50 || b_only<20)
            $fatal(1,"PRED_METADATA_FAIL coverage checks=%0d skid=%0d drop=%0d pred=%0d/%0d b=%0d",checks,skids,drops,predicted0,predicted1,b_only);
        $display("PRED_METADATA_PASS checks=%0d packets=%0d skid=%0d drop=%0d pred=%0d/%0d b_only=%0d redirects=%0d",checks,packets,skids,drops,predicted0,predicted1,b_only,redirects);
        $finish;
    end
endmodule
