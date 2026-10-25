// Actual CPU/LSU/CSR integration: held branch, older memory completion,
// wrong-path store, A/B misaligned branch exceptions and suppressed links.
`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_e1_recovery_integration;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [31:0] rom[0:63];
    reg iv=0,ipending=0,dpending=0,dack=0;
    reg [63:0] idata=0,ipacket=0;
    reg [31:0] ddata=0,scratch=0;
    reg [10:0] dtag=0,saved_tag=0;
    integer delay_count=0,cycles=0,k,holds=0,overlaps=0,recoveries=0,traps=0;
    integer a_misalign=0,b_misalign=0;
    reg load_retired=0,done=0,was_exception=0;
    reg [31:0] trap_pc=0;
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
        .mem_d_data_wr_o(dwrite),.mem_d_rd_o(drd),.mem_d_wr_o(dwr),.mem_d_req_tag_o(reqtag));
    `define I u_dut.u_issue
    `define C u_dut.u_csr.u_csrfile
    function [31:0] addi;
        input [4:0] rd,rs;
        input [11:0] imm;
        addi={imm,rs,3'b000,rd,7'h13};
    endfunction
    function [31:0] store;
        input [11:0] imm;
        store={imm[11:5],5'd2,5'd1,3'b010,imm[4:0],7'h23};
    endfunction
    initial begin
        for(k=0;k<64;k=k+1)rom[k]=32'h13;
        rom['h00/4]=32'h800000b7; // lui x1,80000
        rom['h04/4]=addi(2,0,'h55);
        rom['h08/4]=addi(6,1,'h80);
        rom['h0c/4]=32'h30531073; // csrw mtvec,x6
        rom['h10/4]=store('h100);
        rom['h14/4]=32'h1000a183; // lw x3,100(x1), delayed eight cycles
        rom['h18/4]=32'h00000463; // beq x0,x0,+8, held behind the load
        rom['h1c/4]=store('h104); // forbidden wrong-path external side effect
        rom['h20/4]=addi(4,0,1);
        rom['h24/4]=32'h002002ef; // jal x5,+2; upper/B branch can fault
        rom['h28/4]=addi(10,1,'h36);
        rom['h2c/4]=32'h000505e7; // jalr x11,x10,0 -> misaligned 80000036
        rom['h30/4]=32'h00000163; // beq x0,x0,+2; primary/A branch fault
        rom['h34/4]=store('h108); // completion, after all traps return
        rom['h38/4]=32'h0000006f;
        rom['h80/4]=32'h34102473; // csrr x8,mepc
        rom['h84/4]=addi(8,8,4);
        rom['h88/4]=32'h34141073; // csrw mepc,x8
        rom['h8c/4]=32'h30200073; // mret
        repeat(5)@(negedge clk);rst=0;
    end
    always @(posedge clk)if(!rst)begin
        cycles=cycles+1;
        if(cycles>2500)$fatal(1,"E1_RECOVERY_FAIL timeout");
        iv<=0;dack<=0;
        if(ird && !ipending)begin
            if(ipc[31:8]!==24'h800000 || ipc[2:0]!=0)
                $fatal(1,"E1_RECOVERY_FAIL fetch_address %h",ipc);
            ipacket<={rom[ipc[7:2]+1],rom[ipc[7:2]]};ipending<=1;
        end else if(ipending)begin iv<=1;idata<=ipacket;ipending<=0;end
        if((drd || |dwr) && !dpending)begin
            if(daddr==32'h80000104 && |dwr)$fatal(1,"E1_RECOVERY_FAIL wrong_path_store");
            if(daddr!=32'h80000100 && daddr!=32'h80000108)
                $fatal(1,"E1_RECOVERY_FAIL data_address %h",daddr);
            if(|dwr && dwrite!==32'h55)$fatal(1,"E1_RECOVERY_FAIL store_value");
            if(daddr==32'h80000100 && |dwr)scratch<=dwrite;
            if(daddr==32'h80000108 && |dwr)done<=1;
            ddata<=scratch;saved_tag<=reqtag;dpending<=1;delay_count<=8;
        end else if(dpending)begin
            if(delay_count==0)begin dpending<=0;dack<=1;dtag<=saved_tag;end
            else delay_count<=delay_count-1;
        end
        if(`I.stall_w && (`I.recover0_w || `I.recover1_w))begin
            holds=holds+1;
            if(`I.recovery_w || `I.branch_info_is_taken_o || `I.branch_info_is_not_taken_o)
                $fatal(1,"E1_RECOVERY_FAIL repeated_recovery_or_training_while_held");
        end
        if(`I.recovery_w)begin
            recoveries=recoveries+1;
            if(`I.opcode_a_issue_r || `I.opcode_b_issue_r || `I.lsu_opcode_valid_o)
                $fatal(1,"E1_RECOVERY_FAIL younger_issue_during_recovery");
            if(`I.writeback_mem_valid_i)overlaps=overlaps+1;
        end
        if(`I.resolved_fault_w)begin
            if(`I.opcode_a_issue_r || `I.opcode_b_issue_r || `I.lsu_opcode_valid_o)
                $fatal(1,"E1_RECOVERY_FAIL younger_issue_during_misalignment");
            if(`I.fault0_w)a_misalign=a_misalign+1;
            if(`I.fault1_w)b_misalign=b_misalign+1;
        end
        if((`I.pipe0_valid_wb_w && `I.pipe0_rd_wb_w==3) || (`I.pipe1_valid_wb_w && `I.pipe1_rd_wb_w==3))begin
            if((`I.pipe0_rd_wb_w==3 ? `I.pipe0_result_wb_w : `I.pipe1_result_wb_w)!==32'h55)
                $fatal(1,"E1_RECOVERY_FAIL lost_older_load_value");
            load_retired=1;
        end
        if(`I.pipe0_rd_wb_w==5 || `I.pipe1_rd_wb_w==5 || `I.pipe0_rd_wb_w==11 || `I.pipe1_rd_wb_w==11)
            $fatal(1,"E1_RECOVERY_FAIL misaligned_link_write");
        if(u_dut.csr_writeback_exception_w==`EXCEPTION_MISALIGNED_FETCH && !was_exception)begin
            case(traps)
                0:trap_pc=32'h80000024;
                1:trap_pc=32'h8000002c;
                2:trap_pc=32'h80000030;
                default:$fatal(1,"E1_RECOVERY_FAIL extra_trap");
            endcase
            if(u_dut.csr_writeback_exception_pc_w!==trap_pc)
                $fatal(1,"E1_RECOVERY_FAIL trap_pc actual=%h expected=%h",u_dut.csr_writeback_exception_pc_w,trap_pc);
            traps=traps+1;
        end
        was_exception=u_dut.csr_writeback_exception_w==`EXCEPTION_MISALIGNED_FETCH;
        if(done && !dpending && !dack)begin
            if(traps!=3 || !load_retired || holds==0 || overlaps==0 || a_misalign==0 || b_misalign==0)
                $fatal(1,"E1_RECOVERY_FAIL coverage traps=%0d load=%b holds=%0d overlap=%0d misalign=%0d/%0d",traps,load_retired,holds,overlaps,a_misalign,b_misalign);
            // The unchanged vendor CSR reports source PC for fetch misalignment.
            // This checks compatibility only; target-valued mtval is not claimed.
            if(`C.csr_mcause_q!==0 || `C.csr_mtval_q!==32'h80000030)
                $fatal(1,"E1_RECOVERY_FAIL legacy_csr_payload");
            $display("E1_RECOVERY_PASS cycles=%0d holds=%0d complete_recovery_overlap=%0d traps=%0d misalign=%0d/%0d recoveries=%0d",cycles,holds,overlaps,traps,a_misalign,b_misalign,recoveries);$finish;
        end
    end
    `undef I
    `undef C
endmodule
