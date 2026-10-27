`timescale 1ns/1ps
module tb_lsu_zero_program;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [31:0] rom[0:255];
    reg iv=0,ipending=0,dpending=0,dack=0,done=0;
    reg [63:0] idata=0,ipacket=0;
    reg [31:0] ddata=32'h80000001;
    reg [10:0] dtag=0,saved_tag=0;
    integer delay_count=0,cycles=0,k,n=0,rounds,holds=0,mul_a=0,mul_b=0,loads=0,alus=0;
    wire [31:0] ipc,daddr,dwrite;
    wire ird,drd;
    wire [3:0] dwr;
    wire [10:0] reqtag;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),
        .SUPPORT_REGFILE_XILINX(0),.EXTRA_DECODE_STAGE(0)) u_dut(
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(!ipending),.mem_i_valid_i(iv),.mem_i_error_i(1'b0),.mem_i_inst_i(idata),
        .mem_i_rd_o(ird),.mem_i_pc_o(ipc),
        .mem_d_data_rd_i(ddata),.mem_d_accept_i(!dpending),.mem_d_ack_i(dack),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(dtag),.mem_d_addr_o(daddr),
        .mem_d_data_wr_o(dwrite),.mem_d_rd_o(drd),.mem_d_wr_o(dwr),.mem_d_req_tag_o(reqtag),
        .mem_i_invalidate_o(),.mem_i_flush_o(),.mem_d_flush_o(),
        .mem_d_writeback_o(),.mem_d_invalidate_o(),.mem_d_cacheable_o());

    function [31:0] addi;
        input [4:0] rd,rs;input [11:0] imm;
        addi={imm,rs,3'b000,rd,7'h13};
    endfunction
    function [31:0] mul;
        input [4:0] rd,ra,rb;input [2:0] kind;
        mul={7'b0000001,rb,ra,kind,rd,7'h33};
    endfunction
    task emit;
        input [31:0] op;begin rom[n]=op;n=n+1;end
    endtask
    task fail_branch;
        input neq;
        reg [12:0] offset;
        begin offset=13'd960-n*4;
            emit({offset[12],offset[10:5],5'b0,5'd5,2'b00,neq,offset[4:1],offset[11],7'h63});
        end
    endtask
    function [31:0] expected_load;
        input integer index;
        begin case(index%6)
            0:expected_load=0;1:expected_load=32'hffffff80;2:expected_load=128;
            3:expected_load=32'hffff8000;4:expected_load=1;5:expected_load=32'h80000001;
        endcase end
    endfunction
    task check_write;
        input valid;input [4:0] rd;input [31:0] value;
        begin
            if(valid && rd==5)begin
                if(value!==expected_load(loads))$fatal(1,"LSU_PROGRAM_FAIL load %0d value=%h",loads,value);
                loads=loads+1;
            end
            if(valid && rd==6)begin
                if(value!==(expected_load(alus)+32'd1))$fatal(1,"LSU_PROGRAM_FAIL ALU %0d value=%h",alus,value);
                alus=alus+1;
            end
        end
    endtask
    initial begin
        for(k=0;k<256;k=k+1)rom[k]=32'h13;
        emit(addi(1,0,256));emit(addi(2,0,0));emit(addi(3,0,7));
        for(rounds=0;rounds<8;rounds=rounds+1)begin
            emit(32'h00108283);fail_branch(1);emit(addi(6,5,1)); // LB zero
            emit(32'h00308283);fail_branch(0);emit(addi(6,5,1)); // LB -128
            emit(32'h0030c283);fail_branch(0);emit(addi(6,5,1)); // LBU 128
            emit(32'h00209283);fail_branch(0);emit(addi(6,5,1)); // LH -32768
            emit(32'h0000d283);fail_branch(0);emit(addi(6,5,1)); // LHU 1
            emit(32'h0000a283);fail_branch(0);emit(addi(6,5,1)); // LW
            if(rounds%2==0)emit(32'h13);
        end
        emit(32'h0030a023);emit(32'h0000006f);
        rom[240]=32'h0000a023;rom[241]=32'h0000006f;
        repeat(5)@(negedge clk);rst=0;
    end
    always @(posedge clk)if(!rst)begin
        cycles=cycles+1;iv<=0;dack<=0;
        check_write(u_dut.u_issue.pipe0_valid_wb_w,u_dut.u_issue.pipe0_rd_wb_w,u_dut.u_issue.pipe0_result_wb_w);
        check_write(u_dut.u_issue.pipe1_valid_wb_w,u_dut.u_issue.pipe1_rd_wb_w,u_dut.u_issue.pipe1_result_wb_w);
        if(done && loads==48 && alus==48)begin
            if(mul_a==0 || mul_b==0 || holds==0)$fatal(1,"LSU_PROGRAM_FAIL lane/hold coverage");
            $display("LSU_PROGRAM_PASS cycles=%0d lsu_a=%0d lsu_b=%0d holds=%0d loads=%0d alus=%0d",cycles,mul_a,mul_b,holds,loads,alus);$finish;
        end
        if(loads>48 || alus>48)$fatal(1,"LSU_PROGRAM_FAIL unexpected retirement count");
        if(cycles>10000)$fatal(1,"LSU_PROGRAM_FAIL timeout");
        if(u_dut.u_issue.opcode_a_issue_r && u_dut.u_issue.issue_a_lsu_w)mul_a=mul_a+1;
        if(u_dut.u_issue.opcode_b_issue_r && u_dut.u_issue.issue_b_lsu_w)mul_b=mul_b+1;
        if(u_dut.u_mul.hold_i)holds=holds+1;
        if(ird && !ipending)begin
            if(ipc[31:10]!==22'h200000)$fatal(1,"LSU_PROGRAM_FAIL fetch %h",ipc);
            ipacket<={rom[ipc[9:2]+1],rom[ipc[9:2]]};ipending<=1;
        end else if(ipending)begin iv<=1;idata<=ipacket;ipending<=0;end
        if((drd || |dwr) && !dpending)begin
            if(daddr<256 || daddr>259)$fatal(1,"LSU_PROGRAM_FAIL data address");
            if(|dwr)begin
                if(dwrite!==7)$fatal(1,"LSU_PROGRAM_FAIL wrong branch");
                done<=1;
            end
            dpending<=1;delay_count<=cycles%9;saved_tag<=reqtag;
        end else if(dpending)begin
            if(delay_count==0)begin dack<=1;dtag<=saved_tag;dpending<=0;end
            else delay_count<=delay_count-1;
        end
    end
endmodule
