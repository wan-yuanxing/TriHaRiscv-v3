// P0-1/P0-2 oracle uses literal architectural addresses, public ports only.
`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_document_csr #(parameter SUPER=0, SIM_CONTROL=0);
    reg clk=0, rst=1, valid=0, intr=0;
    reg [31:0] opcode=0, operand=0;
    reg [4:0] rs1=0;
    reg wb=0;
    reg [11:0] wa=0;
    reg [31:0] wd=0;
    reg [5:0] trap=0;
    reg [31:0] tval=0;
    wire [31:0] rv, wv, target;
    wire wr, branch, irq;
    wire [5:0] ex;
    reg accept=0, ack=0, error=0;
    wire [2:0] maint;
    wire [31:0] addr, lv;
    wire rd, cacheable, done, stall;
    wire [3:0] strobe;
    wire [5:0] lex;
    integer checks=0, failures=0, f, a, combo, err;
    reg [31:0] mask, expected, sampled;
    always #5 clk=~clk;
    triha_csr #(.SUPPORT_MULDIV(1),.SUPPORT_SUPER(SUPER)) u_csr (
        .clk_i(clk),.rst_i(rst),.intr_i(intr),.opcode_valid_i(valid),
        .opcode_opcode_i(opcode),.opcode_pc_i(32'h80000040),.opcode_invalid_i(1'b0),
        .opcode_rd_idx_i(5'd5),.opcode_ra_idx_i(rs1),.opcode_rb_idx_i(5'd0),
        .opcode_ra_operand_i(operand),.opcode_rb_operand_i(32'd0),
        .csr_writeback_write_i(wb),.csr_writeback_waddr_i(wa),.csr_writeback_wdata_i(wd),
        .csr_writeback_exception_i(trap),.csr_writeback_exception_pc_i(32'h80000040),
        .csr_writeback_exception_addr_i(tval),.cpu_id_i(32'd0),.reset_vector_i(32'h80000000),
        .interrupt_inhibit_i(1'b0),.csr_result_e1_value_o(rv),.csr_result_e1_write_o(wr),
        .csr_result_e1_wdata_o(wv),.csr_result_e1_exception_o(ex),
        .branch_csr_request_o(branch),.branch_csr_pc_o(target),.branch_csr_priv_o(),
        .take_interrupt_o(irq),.ifence_o(),.mmu_priv_d_o(),.mmu_sum_o(),.mmu_mxr_o(),
        .mmu_flush_o(),.mmu_satp_o());
    triha_lsu u_lsu (
        .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(opcode),
        .opcode_pc_i(32'h80000040),.opcode_invalid_i(1'b0),.opcode_rd_idx_i(5'd5),
        .opcode_ra_idx_i(rs1),.opcode_rb_idx_i(5'd0),.opcode_ra_operand_i(operand),
        .opcode_rb_operand_i(32'd0),.mem_data_rd_i(32'd0),.mem_accept_i(accept),
        .mem_ack_i(ack),.mem_error_i(error),.mem_resp_tag_i(11'd0),
        .mem_load_fault_i(1'b0),.mem_store_fault_i(1'b0),.mem_addr_o(addr),
        .mem_data_wr_o(),.mem_rd_o(rd),.mem_wr_o(strobe),.mem_cacheable_o(cacheable),
        .mem_req_tag_o(),.mem_invalidate_o(maint[2]),.mem_writeback_o(maint[1]),
        .mem_flush_o(maint[0]),.writeback_valid_o(done),.writeback_value_o(lv),
        .writeback_bypass_o(),.writeback_exception_o(lex),.stall_o(stall));
    task check;
        input ok;
        input [511:0] label;
        begin
            checks=checks+1;
            if(ok!==1'b1) begin
                failures=failures+1;
                $display("DOC_CSR_FAIL %0s opcode=%h ex=%h wr=%b rv=%h maint=%b",label,opcode,ex,wr,rv,maint);
            end
        end
    endtask
    task reset;
        begin
            @(negedge clk); rst=1; valid=0; wb=0; trap=0; intr=0; ack=0; error=0; accept=0;
            repeat(3) @(negedge clk);
            rst=0;
            repeat(3) @(negedge clk);
        end
    endtask
    task access;
        input [11:0] address;
        input [2:0] fun;
        input [4:0] src;
        input [31:0] data;
        input illegal;
        input commit;
        begin
            @(negedge clk); valid=1; opcode={address,src,fun,5'd5,7'h73}; rs1=src; operand=data;
            @(posedge clk); #1;
            check(ex===(illegal ? `EXCEPTION_ILLEGAL_INSTRUCTION : 6'd0),"decode exception");
            check(wr===!illegal,"fault suppresses CSR write result");
            if(illegal) check(rv===opcode,"illegal mtval instruction payload");
            sampled=wv;
            @(negedge clk); valid=0; wb=commit && wr && !ex; wa=address; wd=sampled;
            @(posedge clk); #1;
            @(negedge clk); wb=0;
        end
    endtask
    task readcheck;
        input [11:0] address;
        input [31:0] value;
        begin
            access(address,3'd2,0,0,0,0);
            check(rv===value,"CSR read value");
        end
    endtask
    task maintenance;
        input [11:0] address;
        input [2:0] wanted;
        input bus_error;
        begin
            reset;
            @(negedge clk); valid=1; opcode={address,5'd1,3'd1,5'd0,7'h73}; rs1=1; operand=32'h80000124;
            @(posedge clk); #1;
            check(ex===0 && wr,"new maintenance CSR accepted");
            check(maint===wanted && !rd && strobe==0,"maintenance request kind");
            check(addr===32'h80000124 && cacheable,"maintenance operand address");
            @(negedge clk); valid=0;
            repeat(3) begin
                @(posedge clk); #1;
                check(maint===wanted && stall && !done,"hold until acceptance");
            end
            @(negedge clk); accept=1;
            @(posedge clk); #1;
            @(negedge clk); accept=0;
            repeat(3) begin
                @(posedge clk); #1;
                check(!done && stall && maint==0,"wait for response");
            end
            @(negedge clk); ack=1; error=bus_error; #1;
            check(done,"maintenance completion");
            check(lex===(bus_error ? `EXCEPTION_FAULT_STORE : 6'd0),"maintenance bus error cause");
            if(bus_error) check(lv===32'h80000124,"maintenance bus error address");
            @(posedge clk); #1;
            @(negedge clk); ack=0; error=0;
            @(posedge clk); #1; check(!stall && !done && maint==0,"maintenance drained");
            $display("DOC_MAINT addr=%h error=%0d",address,bus_error);
        end
    endtask
    initial begin
        reset;
        // Unknown and former PMP-overlap addresses must fault in every CSR form.
        for(a=0;a<4;a=a+1) begin
            for(f=1;f<=7;f=f+1) if(f!=4) begin
                reset;
                access(a==3 ? 12'h7c4 : 12'h3a0+a, f, 1, 32'hffffffff, 1, 0);
                check(maint==0,"old/unknown CSR has no maintenance side effect");
                reset;
                access(a==3 ? 12'h7c4 : 12'h3a0+a, f, 0, 0, 1, 0);
                check(maint==0,"zero-source unknown CSR has no maintenance side effect");
            end
        end
        access(12'hfff,3'd2,0,0,1,0); // Unknown read-only address is not a read-zero CSR.
        // Both zero-source reads and write attempts, including rs1!=x0 containing 0.
        for(f=1;f<=7;f=f+1) if(f!=4) begin
            access(12'hf14,f,0,0,(f==1 || f==5),0);
            access(12'hf14,f,1,0,1,0);
            access(12'hc00,f,0,0,(f==1 || f==5),0);
            access(12'hc00,f,1,0,1,0);
        end
        // Standard identification CSRs explicitly implement permitted fixed zero.
        for(a=0;a<3;a=a+1) begin
            readcheck(12'hf11+a,0);
            for(f=1;f<=7;f=f+1) if(f!=4) begin
                access(12'hf11+a,f,0,0,(f==1 || f==5),0);
                access(12'hf11+a,f,1,0,1,0);
            end
        end
        for(f=1;f<=7;f=f+1) if(f!=4) begin
            access(12'h301,f,1,32'hffffffff,0,1);
            readcheck(12'h301,32'h40001100);
        end
        access(12'h100,3'd2,0,0,!SUPER,0);
        access(12'h302,3'd2,0,0,!SUPER,0);
        access(12'h8b2,3'd1,1,32'h02000000,!SIM_CONTROL,1);
        access(12'h7b2,3'd1,1,32'h02000000,!SIM_CONTROL,1);
        for(a=0;a<3;a=a+1) begin
            for(err=0;err<2;err=err+1) maintenance(12'h7c1+a,3'b001<<a,err);
            for(f=2;f<=7;f=f+1) if(f!=4) begin
                access(12'h7c1+a,f,1,0,0,0);
                check(maint==0,"only CSRRW starts maintenance");
            end
        end
        // All eight MEI/MSI/MTI sets. Pending bits written through normal CSR ports.
        for(combo=0;combo<8;combo=combo+1) begin
            reset;
            access(12'h305,1,1,32'h80000200,0,1);
            access(12'h304,1,1,32'h888,0,1);
            mask=((combo&4)?32'h800:0)|((combo&2)?32'h8:0)|((combo&1)?32'h80:0);
            access(12'h344,1,1,mask,0,1);
            access(12'h300,1,1,32'h8,0,1);
            repeat(3) @(negedge clk);
            check(irq===(combo!=0),"interrupt enable/pending");
            if(combo!=0) begin
                trap=`EXCEPTION_INTERRUPT;
                @(posedge clk); #1; check(branch && target==32'h80000200,"interrupt vector");
                @(negedge clk); trap=0;
                expected=(combo&4)?32'h8000000b:((combo&2)?32'h80000003:32'h80000007);
                readcheck(12'h342,expected);
                readcheck(12'h341,32'h80000040);
            end
            $display("DOC_IRQ combination=%0d expected=%h",combo,combo==0 ? 0 : expected);
        end
        // Timer compare remains at 0x7c0; actual timer and external input still work.
        reset;
        access(12'h304,1,1,32'h888,0,1);
        access(12'h7c0,1,1,32'd100,0,1);
        readcheck(12'h7c0,32'd100);
        access(12'h300,1,1,8,0,1);
        repeat(110) @(negedge clk);
        check(irq,"internal timer still interrupts");
        reset;
        access(12'h304,1,1,32'h800,0,1);
        access(12'h300,1,1,8,0,1);
        intr=1; repeat(5) @(negedge clk); check(irq,"external IRQ input");
        $display("DOC_CSR_SUMMARY super=%0d sim=%0d checks=%0d failures=%0d",SUPER,SIM_CONTROL,checks,failures);
        if(failures) $fatal(1,"DOC_CSR_FAIL total=%0d",failures);
        $display("DOC_CSR_PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"DOC_CSR_FAIL timeout"); end
endmodule
