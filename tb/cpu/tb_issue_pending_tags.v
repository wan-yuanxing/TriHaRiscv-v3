/* Independent conditional-indexed bitmap oracle for actual issue permissions. */
`timescale 1ns/1ps
module tb_issue_pending_tags #(parameter BROKEN=0,LOAD_BYPASS=1,MUL_BYPASS=1);
    reg clk=0,rst=1,clock_run=1;
    always #5 if(clock_run)clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),
        .SUPPORT_LOAD_BYPASS(LOAD_BYPASS),.SUPPORT_MUL_BYPASS(MUL_BYPASS)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(0),
        .mem_d_data_rd_i(0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),.mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    `define I u_dut.u_issue
    reg [4:0] tags[0:3];
    reg l0=0,l1=0,m0=0,m1=0,l20=0,l21=0,m20=0,m21=0,e0=0,e1=0;
    reg [4:0] ara=0,arb=0,ard=0,bra=0,brb=0,brd=0;
    reg [2:0] ar=0,br=0;
    reg va=1,vb=1,alloc=0,am=0;
    wire [31:0] opa={7'b0,arb,ara,3'b0,ard,7'h33};
    wire [31:0] opb={7'b0,brb,bra,3'b0,brd,7'h33};
    reg [31:0] rng=32'h27a1359b,mask,mask_a,same_mask;
    reg ah,bh,sh,prior,ea,eb;
    integer n,j,source,producer,consumer,lane,role,checks=0;
    task check;
        begin
            mask=0;
            if(!LOAD_BYPASS)begin if(l20)mask[tags[2]]=1; if(l21)mask[tags[3]]=1;end
            if(!MUL_BYPASS)begin if(m20)mask[tags[2]]=1; if(m21)mask[tags[3]]=1;end
            if(l0 || (m0 && !e0))mask[tags[0]]=1;
            if(l1 || (m1 && !e1))mask[tags[1]]=1;
            prior=(l0 || l1) && am;
            mask_a=mask;if(prior)mask_a=32'hffffffff;
            ah=(ar[0] && |ara && mask_a[ara]) || (ar[1] && |arb && mask_a[arb]) || (ar[2] && |ard && mask_a[ard]);
            bh=(br[0] && |bra && mask[bra]) || (br[1] && |brb && mask[brb]) || (br[2] && |brd && mask[brd]);
            same_mask=0;if(alloc && |ard)same_mask[ard]=1;
            sh=(br[0] && |bra && same_mask[bra]) || (br[1] && |brb && same_mask[brb]) || (br[2] && |brd && same_mask[brd]);
            ea=0;eb=0;if(va && !prior && !ah)ea=1;if(vb && ea && !bh && !sh)eb=1;
            #1;checks=checks+1;
            if(`I.older_scoreboard_r!==mask || `I.opcode_a_accept_r!==ea || `I.opcode_b_accept_r!==eb)
                $fatal(1,"PENDING_TAG_FAIL check=%0d cfg=%0d/%0d tags=%b/%b/%b/%b mask=%h actual_mask=%h A=%b/%b B=%b/%b roles=%b/%b idx=%b/%b/%b %b/%b/%b",checks,LOAD_BYPASS,MUL_BYPASS,tags[0],tags[1],tags[2],tags[3],mask,`I.older_scoreboard_r,`I.opcode_a_accept_r,ea,`I.opcode_b_accept_r,eb,ar,br,ara,arb,ard,bra,brb,brd);
        end
    endtask
    task clear;
        begin
            l0=0;l1=0;m0=0;m1=0;l20=0;l21=0;m20=0;m21=0;e0=0;e1=0;
            ara=0;arb=0;ard=0;bra=0;brb=0;brd=0;ar=0;br=0;va=1;vb=1;alloc=0;am=0;
            for(j=0;j<4;j=j+1)tags[j]=0;
        end
    endtask
    initial begin
        clear;repeat(5)@(negedge clk);rst=0;clock_run=0;
        force `I.pc_x_q=32'h80000000;force `I.fetch0_pc_i=32'h80000000;force `I.fetch1_pc_i=32'h80000004;
        force `I.fetch0_valid_i=1;force `I.fetch1_valid_i=1;force `I.fetch0_instr_i=opa;force `I.fetch1_instr_i=opb;
        force `I.opcode_a_r=opa;force `I.opcode_b_r=opb;force `I.opcode_a_valid_r=va;force `I.opcode_b_valid_r=vb;
        force `I.opcode_a_fault_r=0;force `I.opcode_b_fault_r=0;force `I.issue_a_invalid_w=0;force `I.issue_b_invalid_w=0;
        force `I.issue_a_ra_idx_w=ara;force `I.issue_a_rb_idx_w=arb;force `I.issue_a_rd_idx_w=ard;
        force `I.issue_b_ra_idx_w=bra;force `I.issue_b_rb_idx_w=brb;force `I.issue_b_rd_idx_w=brd;
        force `I.a_roles_w=ar;force `I.b_roles_w=br;force `I.issue_a_sb_alloc_w=alloc;force `I.issue_b_sb_alloc_w=0;
        force `I.issue_a_exec_w=1;force `I.issue_b_exec_w=1;force `I.issue_a_mul_w=am;force `I.issue_b_mul_w=0;
        force `I.issue_a_lsu_w=0;force `I.issue_b_lsu_w=0;force `I.issue_a_div_w=0;force `I.issue_b_div_w=0;
        force `I.issue_a_csr_w=0;force `I.issue_b_csr_w=0;force `I.issue_a_branch_w=0;force `I.issue_b_branch_w=0;
        force `I.pipe0_load_e1_w=l0;force `I.pipe1_load_e1_w=l1;force `I.pipe0_mul_e1_w=m0;force `I.pipe1_mul_e1_w=m1;
        force `I.pipe0_load_e2_w=l20;force `I.pipe1_load_e2_w=l21;force `I.pipe0_mul_e2_w=m20;force `I.pipe1_mul_e2_w=m21;
        force `I.pipe0_store_e1_w=0;force `I.pipe1_store_e1_w=0;force `I.pipe0_early_mul_w=e0;force `I.pipe1_early_mul_w=e1;
        force `I.pipe0_rd_e1_w=tags[0];force `I.pipe1_rd_e1_w=tags[1];force `I.pipe0_rd_e2_w=tags[2];force `I.pipe1_rd_e2_w=tags[3];
        force `I.squash_w=0;force `I.branch_csr_request_i=0;force `I.take_interrupt_i=0;
        force `I.lsu_stall_i=0;force `I.stall_w=0;force `I.div_pending_q=0;force `I.csr_pending_q=0;
        if(BROKEN)force `I.opcode_a_accept_r=1;
        for(source=0;source<4;source=source+1)for(producer=0;producer<32;producer=producer+1)
        for(consumer=0;consumer<32;consumer=consumer+1)for(lane=0;lane<2;lane=lane+1)for(role=0;role<3;role=role+1)begin
            clear;tags[source]=producer;
            case(source)0:l0=1;1:m1=1;2:begin l20=1;m20=1;end 3:begin l21=1;m21=1;end endcase
            if(lane==0)begin ar=1<<role;case(role)0:ara=consumer;1:arb=consumer;2:ard=consumer;endcase end
            else begin br=1<<role;case(role)0:bra=consumer;1:brb=consumer;2:brd=consumer;endcase end
            check;
        end
        for(n=0;n<8192;n=n+1)begin
            clear;
            for(j=0;j<4;j=j+1)begin rng=rng*32'd1664525+32'd1013904223;tags[j]=rng[4:0];end
            {l0,l1,m0,m1,l20,l21,m20,m21,e0,e1}=rng[14:5];
            rng=rng*32'd1664525+32'd1013904223;{ara,arb,ard,bra,brb,brd}=rng[29:0];
            ar=rng[2:0];br=rng[5:3];va=rng[6];vb=rng[7];alloc=rng[8];am=rng[9];
            if(n%3==0)ara=tags[0];if(n%5==0)brb=tags[1];if(n%7==0)brd=ard;
            if(n%11==0)tags[n%4]=5'b00x11;
            if(n%13==0)tags[n%4]=5'bz0001;
            if(n%17==0)ara=5'b00x01;
            if(n%19==0)brb=5'b0z001;
            if(n%23==0)e0=1'bx;if(n%29==0)l1=1'bz;if(n%31==0)alloc=1'bx;
            if(n%37==0)va=1'bx;if(n%41==0)vb=1'bz;if(n%43==0)ar[1]=1'bx;
            check;
        end
        clear;ar=1;ara=5'b0000x;check;
        clear;l0=1;tags[0]=5'b00x11;ara=3;ar=1;check;
        clear;m0=1;e0=1'bx;tags[0]=3;ara=3;ar=1;check;
        clear;l0=1'bx;am=1;check;
        clear;l0=1;am=1'bx;check;
        $display("PENDING_TAG_PASS checks=%0d cfg=%0d/%0d original_indexed_bitmap_oracle",checks,LOAD_BYPASS,MUL_BYPASS);$finish;
    end
    `undef I
endmodule
