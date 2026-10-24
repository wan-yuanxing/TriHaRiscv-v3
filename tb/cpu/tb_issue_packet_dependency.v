/* Independent selected-destination bitmap oracle for same-packet RAW/WAW.
 * Inputs are raw FIFO words; selected A indices/opcode are never forced.
 */
`timescale 1ns/1ps
module tb_issue_packet_dependency #(parameter BROKEN=0);
    reg clk=0,rst=1,clock_run=1;
    always #5 if(clock_run)clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),.mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    `define I u_dut.u_issue
    reg [4:0] rd0=0,rd1=0,bra=0,brb=0;
    reg [2:0] roles=0;
    reg alloc=0;
    reg [31:0] selected_pc=32'h80000000,rng=32'h7162b3a4;
    wire [31:0] word0={7'b0,5'b0,5'b0,3'b0,rd0,7'h33};
    wire [31:0] word1={7'b0,brb,bra,3'b0,rd1,7'h33};
    reg [31:0] selected,bitmap;
    reg expected;
    integer dest,consumer,role,lane,n,checks=0;
    task check;
        begin
            #1;
            selected=word1;
            if(selected_pc[2]==1'b0)selected=word0;
            bitmap=0;
            if(alloc && |selected[11:7])bitmap[selected[11:7]]=1'b1;
            expected=(roles[0] && bitmap[bra]) ||
                (roles[1] && bitmap[brb]) || (roles[2] && bitmap[rd1]);
            // Original code skips an unknown producer index entirely. Its
            // OR expression is only evaluated inside the known-index case.
            case(selected[11:7])
                5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15,
                5'd16,5'd17,5'd18,5'd19,5'd20,5'd21,5'd22,5'd23,5'd24,5'd25,5'd26,5'd27,5'd28,5'd29,5'd30,5'd31:begin
                    if((^bra===1'bx) || (^brb===1'bx) || (^rd1===1'bx))begin
                        expected=0;
                        if(alloc && |selected[11:7]) expected=
                            (roles[0] && ~|(bra^selected[11:7])) ||
                            (roles[1] && ~|(brb^selected[11:7])) ||
                            (roles[2] && ~|(rd1^selected[11:7]));
                    end
                end
                default:expected=0;
            endcase
            #1;checks=checks+1;
            if(`I.opcode_a_r!==selected || `I.same_packet_busy_r!==expected)
                $fatal(1,"PACKET_DEPENDENCY_FAIL check=%0d select=%b rd=%b/%b B=%b/%b/%b roles=%b alloc=%b actual=%b expected=%b",
                    checks,selected_pc[2],rd0,rd1,bra,brb,rd1,roles,alloc,`I.same_packet_busy_r,expected);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;clock_run=0;
        force `I.pc_x_q=selected_pc;
        force `I.fetch0_pc_i=32'h80000000;force `I.fetch1_pc_i=32'h80000004;
        force `I.fetch0_valid_i=1;force `I.fetch1_valid_i=1;
        force `I.fetch0_instr_i=word0;force `I.fetch1_instr_i=word1;
        force `I.issue_a_sb_alloc_w=alloc;force `I.b_roles_w=roles;
        if(BROKEN)force `I.same_packet_busy_r=0;
        for(lane=0;lane<2;lane=lane+1)for(dest=0;dest<32;dest=dest+1)
        for(consumer=0;consumer<32;consumer=consumer+1)for(role=0;role<8;role=role+1)begin
            rd0=dest;rd1=consumer;bra=consumer;brb=consumer;
            roles=role;alloc=1;selected_pc=32'h80000000+4*lane;check;
            alloc=0;check;
        end
        for(n=0;n<16000;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;
            {rd0,rd1,bra,brb}=rng[19:0];roles=rng[22:20];alloc=rng[23];
            selected_pc=32'h80000000;selected_pc[2]=rng[24];
            if(n%7==0)rd0[1]=1'bx;
            if(n%11==0)rd1[3]=1'bz;
            if(n%13==0)bra[0]=1'bx;
            if(n%17==0)brb[4]=1'bz;
            if(n%19==0)alloc=1'bx;
            if(n%23==0)alloc=1'bz;
            if(n%29==0)selected_pc[2]=1'bx;
            if(n%31==0)selected_pc[2]=1'bz;
            if(n%37==0)roles[1]=1'bx;
            check;
        end
        $display("PACKET_DEPENDENCY_PASS checks=%0d raw_words_and_four_state",checks);$finish;
    end
    `undef I
endmodule
