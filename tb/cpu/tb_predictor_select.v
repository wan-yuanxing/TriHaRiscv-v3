/* Predictor rewrite miter, with independent highest-index lookup oracle. */
`timescale 1ns / 1ps
`ifndef CPU_PREDICTOR_MODULE
`define CPU_PREDICTOR_MODULE triha_npc
`endif
module predictor_select_case #(
    parameter ENTRIES=32, ENTRY_W=5, BHT_ENTRIES=512, BHT_W=9,
    parameter RAS_ENTRIES=8, RAS_W=3, GSHARE=0, BROKEN=0
)(output reg done=0);
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg invalidate=0,request=0,taken=0,not_taken=0,is_call=0,is_ret=0,is_jmp=0,accept=0;
    reg [31:0] source=0,target=0,pc=0,random_q=32'hc80173a5;
    reg [1:0] poison=0;
    wire [31:0] candidate_pc,original_pc;
    wire [1:0] candidate_taken,original_taken;
    integer cycles=0,i,j,chosen,exact_hits=0,upper_hits=0,misses=0,duplicate_hits=0,match_count;
    reg expected_valid,expected_upper;
    reg [31:0] expected_target;
    `CPU_PREDICTOR_MODULE #(.NUM_BTB_ENTRIES(ENTRIES),.NUM_BTB_ENTRIES_W(ENTRY_W),
        .NUM_BHT_ENTRIES(BHT_ENTRIES),.NUM_BHT_ENTRIES_W(BHT_W),
        .NUM_RAS_ENTRIES(RAS_ENTRIES),.NUM_RAS_ENTRIES_W(RAS_W),.GSHARE_ENABLE(GSHARE)) u_candidate
        (.clk_i(clk),.rst_i(rst),.invalidate_i(invalidate),.branch_request_i(request),
         .branch_is_taken_i(taken),.branch_is_not_taken_i(not_taken),.branch_source_i(source),
         .branch_is_call_i(is_call),.branch_is_ret_i(is_ret),.branch_is_jmp_i(is_jmp),.branch_pc_i(target),
         .pc_f_i(pc),.pc_accept_i(accept),.next_pc_f_o(candidate_pc),.next_taken_f_o(candidate_taken));
    biriscv_npc #(.NUM_BTB_ENTRIES(ENTRIES),.NUM_BTB_ENTRIES_W(ENTRY_W),
        .NUM_BHT_ENTRIES(BHT_ENTRIES),.NUM_BHT_ENTRIES_W(BHT_W),
        .NUM_RAS_ENTRIES(RAS_ENTRIES),.NUM_RAS_ENTRIES_W(RAS_W),.GSHARE_ENABLE(GSHARE)) u_original
        (.clk_i(clk),.rst_i(rst),.invalidate_i(invalidate),.branch_request_i(request),
         .branch_is_taken_i(taken),.branch_is_not_taken_i(not_taken),.branch_source_i(source),
         .branch_is_call_i(is_call),.branch_is_ret_i(is_ret),.branch_is_jmp_i(is_jmp),.branch_pc_i(target),
         .pc_f_i(pc),.pc_accept_i(accept),.next_pc_f_o(original_pc),.next_taken_f_o(original_taken));
    task random_next;
        begin random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};end
    endtask
    task compare;
        begin
            if({candidate_pc,candidate_taken}!=={original_pc,original_taken})
                $fatal(1,"PREDICTOR_SELECT_FAIL output entries=%0d cycle=%0d pc=%h original=%h candidate=%h",ENTRIES,cycles,pc,original_pc,candidate_pc);
            if({u_candidate.BRANCH_PREDICTION.ras_index_q,u_candidate.BRANCH_PREDICTION.ras_index_real_q,
                u_candidate.BRANCH_PREDICTION.global_history_q,u_candidate.BRANCH_PREDICTION.global_history_real_q,
                u_candidate.BRANCH_PREDICTION.u_lru.lfsr_q}!==
               {u_original.BRANCH_PREDICTION.ras_index_q,u_original.BRANCH_PREDICTION.ras_index_real_q,
                u_original.BRANCH_PREDICTION.global_history_q,u_original.BRANCH_PREDICTION.global_history_real_q,
                u_original.BRANCH_PREDICTION.u_lru.lfsr_q})
                $fatal(1,"PREDICTOR_SELECT_FAIL control_state entries=%0d cycle=%0d",ENTRIES,cycles);
            for(j=0;j<ENTRIES;j=j+1)
                if({u_candidate.BRANCH_PREDICTION.btb_pc_q[j],u_candidate.BRANCH_PREDICTION.btb_target_q[j],
                    u_candidate.BRANCH_PREDICTION.btb_is_call_q[j],u_candidate.BRANCH_PREDICTION.btb_is_ret_q[j],u_candidate.BRANCH_PREDICTION.btb_is_jmp_q[j]}!==
                   {u_original.BRANCH_PREDICTION.btb_pc_q[j],u_original.BRANCH_PREDICTION.btb_target_q[j],
                    u_original.BRANCH_PREDICTION.btb_is_call_q[j],u_original.BRANCH_PREDICTION.btb_is_ret_q[j],u_original.BRANCH_PREDICTION.btb_is_jmp_q[j]})
                    $fatal(1,"PREDICTOR_SELECT_FAIL BTB_state entry=%0d cycle=%0d",j,cycles);
            for(j=0;j<BHT_ENTRIES;j=j+1)
                if(u_candidate.BRANCH_PREDICTION.bht_sat_q[j]!==u_original.BRANCH_PREDICTION.bht_sat_q[j])
                    $fatal(1,"PREDICTOR_SELECT_FAIL BHT_state entry=%0d cycle=%0d",j,cycles);
            for(j=0;j<RAS_ENTRIES;j=j+1)
                if(u_candidate.BRANCH_PREDICTION.ras_stack_q[j]!==u_original.BRANCH_PREDICTION.ras_stack_q[j])
                    $fatal(1,"PREDICTOR_SELECT_FAIL RAS_state entry=%0d cycle=%0d",j,cycles);
            chosen=-1;expected_upper=0;match_count=0;
            // Descending search chooses the first match, independently of the
            // production suffix mask and AND/OR payload selection.
            for(j=ENTRIES-1;j>=0;j=j-1) begin
                if(u_original.BRANCH_PREDICTION.btb_pc_q[j]==pc)begin
                    if(chosen<0) chosen=j;
                    match_count=match_count+1;
                end
            end
            if(chosen>=0) begin expected_upper=pc[2];exact_hits=exact_hits+1;end
            if(chosen<0 && !pc[2]) begin
                for(j=ENTRIES-1;j>=0;j=j-1)
                    if(u_original.BRANCH_PREDICTION.btb_pc_q[j]==(pc|32'd4)) begin
                        if(chosen<0)chosen=j;
                        match_count=match_count+1;
                    end
                if(chosen>=0) begin expected_upper=1;upper_hits=upper_hits+1;end
            end
            if(match_count>1)duplicate_hits=duplicate_hits+1;
            expected_valid=chosen>=0;
            expected_target=({pc[31:3],3'b0}+32'd8);
            if(chosen>=0) expected_target=u_original.BRANCH_PREDICTION.btb_target_q[chosen];
            else misses=misses+1;
            if({u_candidate.BRANCH_PREDICTION.btb_valid_r,u_candidate.BRANCH_PREDICTION.btb_upper_r,
                u_candidate.BRANCH_PREDICTION.btb_next_pc_r}!=={expected_valid,expected_upper,expected_target})
                $fatal(1,"PREDICTOR_SELECT_FAIL independent_lookup cycle=%0d",cycles);
            if(chosen>=0 &&
                {u_candidate.BRANCH_PREDICTION.btb_entry_r,u_candidate.BRANCH_PREDICTION.btb_is_call_r,
                 u_candidate.BRANCH_PREDICTION.btb_is_ret_r,u_candidate.BRANCH_PREDICTION.btb_is_jmp_r}!==
                {chosen[ENTRY_W-1:0],u_original.BRANCH_PREDICTION.btb_is_call_q[chosen],
                 u_original.BRANCH_PREDICTION.btb_is_ret_q[chosen],u_original.BRANCH_PREDICTION.btb_is_jmp_q[chosen]})
                $fatal(1,"PREDICTOR_SELECT_FAIL highest_index_metadata cycle=%0d",cycles);
        end
    endtask
    task step;
        begin
            #1;compare;
            @(posedge clk);#1;
            if(BROKEN && cycles==50) begin poison=original_taken^2'b01;force u_candidate.next_taken_f_o=poison;end
            compare;cycles=cycles+1;@(negedge clk);
        end
    endtask
    initial begin
        @(negedge clk);step;rst=0;
        // Populate all entries with duplicate tags and different data. This
        // covers states not reached by well-behaved training, including reset's
        // multiple PC=0 matches; no unique-tag assumption is permitted.
        for(i=0;i<ENTRIES;i=i+1) begin
            u_candidate.BRANCH_PREDICTION.btb_pc_q[i]=32'h80000004;
            u_original.BRANCH_PREDICTION.btb_pc_q[i]=32'h80000004;
            u_candidate.BRANCH_PREDICTION.btb_target_q[i]=32'h90000000+(i*8);
            u_original.BRANCH_PREDICTION.btb_target_q[i]=32'h90000000+(i*8);
            u_candidate.BRANCH_PREDICTION.btb_is_call_q[i]=i[0];u_original.BRANCH_PREDICTION.btb_is_call_q[i]=i[0];
            u_candidate.BRANCH_PREDICTION.btb_is_ret_q[i]=~i[0];u_original.BRANCH_PREDICTION.btb_is_ret_q[i]=~i[0];
        end
        pc=32'h80000000;step;pc=32'h80000004;step;
        for(i=0;i<4000;i=i+1) begin
            random_next;pc=32'h80000000+{25'b0,random_q[4:0],2'b0};
            request=random_q[17];accept=random_q[9];invalidate=random_q[25];
            is_call=random_q[6];is_ret=random_q[13];is_jmp=random_q[20];
            taken=random_q[14];not_taken=random_q[27];
            random_next;source=32'h80000000+{25'b0,random_q[4:0],2'b0};
            random_next;target={random_q[31:2],2'b0};
            if((i%31)==0) pc=32'h80000000;
            if((i%37)==0)pc=32'h80000004;
            if((i%101)==99)pc=32'hxxxxxxxx;
            if((i%127)==125)source=32'hxxxxxxxx;
            rst=((i%809)==805);
            if(rst)#1;
            step;
        end
        if(exact_hits<10||upper_hits<2||misses<10||duplicate_hits<2)
            $fatal(1,"PREDICTOR_SELECT_FAIL coverage");
        $display("PREDICTOR_SELECT_CASE_PASS entries=%0d gshare=%0d cycles=%0d exact=%0d upper=%0d miss=%0d duplicates=%0d",ENTRIES,GSHARE,cycles,exact_hits,upper_hits,misses,duplicate_hits);
        done=1;
    end
endmodule
module tb_predictor_select #(parameter BROKEN=0);
    wire full_done,small_done;
    predictor_select_case #(.BROKEN(BROKEN)) u_full(.done(full_done));
    predictor_select_case #(.ENTRIES(4),.ENTRY_W(2),.BHT_ENTRIES(16),.BHT_W(4),.RAS_ENTRIES(4),.RAS_W(2),.GSHARE(1)) u_small(.done(small_done));
    initial begin
        wait(full_done&&small_done);
        $display("PREDICTOR_SELECT_PASS complete_outputs_BTB_BHT_RAS_LFSR_and_priority");
        $finish;
    end
endmodule
