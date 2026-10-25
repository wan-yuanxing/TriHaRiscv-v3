// Variable shifts use the primary unit; immediate shifts still pair in B.
`timescale 1ns/1ps
module tb_secondary_shift;
    parameter CHECK_SCHED=1;
    reg clk=0,rst=1,iv=0,pending=0,dack=0,done=0;
    always #5 clk=~clk;
    reg [31:0] rom[0:63];
    reg [63:0] idata=0,packet=0;
    reg [10:0] tag=0;
    wire [31:0] ipc,daddr;
    wire ird,drd;
    wire [3:0] dwr;
    wire [10:0] reqtag;
    integer k,cycles=0,reg_deferred=0,imm_pairs=0;
    reg [5:0] seen=0;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),.SUPPORT_REGFILE_XILINX(0)) u_dut(
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(!pending),.mem_i_valid_i(iv),.mem_i_error_i(1'b0),.mem_i_inst_i(idata),
        .mem_i_rd_o(ird),.mem_i_pc_o(ipc),.mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),
        .mem_d_ack_i(dack),.mem_d_error_i(1'b0),.mem_d_resp_tag_i(tag),
        .mem_d_addr_o(daddr),.mem_d_rd_o(drd),.mem_d_wr_o(dwr),.mem_d_req_tag_o(reqtag));
    `define I u_dut.u_issue
    initial begin
        for(k=0;k<64;k=k+1)rom[k]=32'h13;
        rom[0]=32'hfef00393;rom[1]=32'h00300413; // x7=-17, x8=3
        rom[2]=32'h00100293;rom[3]=32'h00839333; // addi / sll x6,x7,x8
        rom[4]=32'h00100293;rom[5]=32'h0083d4b3; // addi / srl x9,x7,x8
        rom[6]=32'h00100293;rom[7]=32'h4083d533; // addi / sra x10,x7,x8
        rom[8]=32'h0200006f; // reset packet alignment: jump 20->40
        rom[16]=32'h00100293;rom[17]=32'h00339313;
        rom[18]=32'h00100293;rom[19]=32'h0033d493;
        rom[20]=32'h00100293;rom[21]=32'h4033d513;
        rom[22]=32'h800000b7;rom[23]=32'h1000a023;
        rom[24]=32'h0000006f;
        repeat(5)@(negedge clk);rst=0;
    end
    task observe;
        input [31:0] pc,value;
        integer index;
        reg [31:0] expected;
        begin
            index=-1;expected=0;
            case(pc)
                32'h8000000c:begin index=0;expected=32'hffffff78;end
                32'h80000014:begin index=1;expected=32'h1ffffffd;end
                32'h8000001c:begin index=2;expected=32'hfffffffd;end
                32'h80000044:begin index=3;expected=32'hffffff78;end
                32'h8000004c:begin index=4;expected=32'h1ffffffd;end
                32'h80000054:begin index=5;expected=32'hfffffffd;end
            endcase
            if(index>=0)begin
                if(value!==expected)$fatal(1,"SECONDARY_SHIFT_FAIL pc=%h value=%h expected=%h",pc,value,expected);
                seen[index]=1;
            end
        end
    endtask
    always @(posedge clk)if(!rst)begin
        cycles=cycles+1;if(cycles>1000)$fatal(1,"SECONDARY_SHIFT_FAIL timeout");
        iv<=0;dack<=0;
        if(ird && !pending)begin
            if(ipc[31:8]!==24'h800000)$fatal(1,"SECONDARY_SHIFT_FAIL fetch_addr");
            pending<=1;packet<={rom[ipc[7:2]+1],rom[ipc[7:2]]};
        end else if(pending)begin pending<=0;iv<=1;idata<=packet;end
        if(drd)$fatal(1,"SECONDARY_SHIFT_FAIL unexpected_load");
        if(|dwr)begin
            if(daddr!==32'h80000100)$fatal(1,"SECONDARY_SHIFT_FAIL store_addr");
            dack<=1;tag<=reqtag;done<=1;
        end
        if(`I.opcode_b_valid_r && (`I.opcode_b_pc_r==32'h8000000c || `I.opcode_b_pc_r==32'h80000014 || `I.opcode_b_pc_r==32'h8000001c))begin
            if(CHECK_SCHED && `I.opcode_b_issue_r)$fatal(1,"SECONDARY_SHIFT_FAIL variable_shift_issued_in_B");
            if(`I.opcode_a_accept_r && !`I.opcode_b_accept_r)reg_deferred=reg_deferred+1;
        end
        if(`I.dual_issue_w && (`I.opcode_b_pc_r==32'h80000044 || `I.opcode_b_pc_r==32'h8000004c || `I.opcode_b_pc_r==32'h80000054))imm_pairs=imm_pairs+1;
        if(`I.pipe0_valid_wb_w)observe(`I.pipe0_pc_wb_w,`I.pipe0_result_wb_w);
        if(`I.pipe1_valid_wb_w)observe(`I.pipe1_pc_wb_w,`I.pipe1_result_wb_w);
        if(done && !dack)begin
            if(seen!==6'b111111 || (CHECK_SCHED && reg_deferred==0) || imm_pairs!=3)
                $fatal(1,"SECONDARY_SHIFT_FAIL coverage seen=%b deferred=%0d immediate=%0d",seen,reg_deferred,imm_pairs);
            $display("SECONDARY_SHIFT_PASS cycles=%0d deferred=%0d immediate_pairs=%0d",cycles,reg_deferred,imm_pairs);$finish;
        end
    end
    `undef I
endmodule
