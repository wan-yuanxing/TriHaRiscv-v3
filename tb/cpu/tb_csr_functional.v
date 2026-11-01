/* Standalone CSR functional tests. Positive tests use public ports only. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"

module tb_csr_functional #(parameter integer CORRUPT_RESULT=0);
    reg clk=0, rst=1;
    reg valid=0, invalid=0;
    reg [31:0] opcode=0, operand=0;
    reg [4:0] rs1=0;
    reg wb_write=0;
    reg [11:0] wb_addr=0;
    reg [31:0] wb_data=0;
    reg [5:0] trap=0;
    reg [31:0] trap_pc=0, trap_value=0;
    wire [31:0] read_value, write_value, branch_pc;
    wire read_valid, branch_valid;
    wire [5:0] decoded_exception;
    integer checks=0, csr_operations=0;
    reg [31:0] sampled_write;

    always #5 clk=~clk;
    triha_csr #(.SUPPORT_MULDIV(1), .SUPPORT_SUPER(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(1'b0),
        .opcode_valid_i(valid), .opcode_opcode_i(opcode), .opcode_pc_i(32'h80000040),
        .opcode_invalid_i(invalid), .opcode_rd_idx_i(5'd5),
        .opcode_ra_idx_i(rs1), .opcode_rb_idx_i(5'd0),
        .opcode_ra_operand_i(operand), .opcode_rb_operand_i(32'd0),
        .csr_writeback_write_i(wb_write), .csr_writeback_waddr_i(wb_addr),
        .csr_writeback_wdata_i(wb_data), .csr_writeback_exception_i(trap),
        .csr_writeback_exception_pc_i(trap_pc), .csr_writeback_exception_addr_i(trap_value),
        .cpu_id_i(32'd0), .reset_vector_i(32'h80000000), .interrupt_inhibit_i(1'b0),
        .csr_result_e1_value_o(read_value), .csr_result_e1_write_o(read_valid),
        .csr_result_e1_wdata_o(write_value), .csr_result_e1_exception_o(decoded_exception),
        .branch_csr_request_o(branch_valid), .branch_csr_pc_o(branch_pc),
        .branch_csr_priv_o(), .take_interrupt_o(), .ifence_o(),
        .mmu_priv_d_o(), .mmu_sum_o(), .mmu_mxr_o(), .mmu_flush_o(), .mmu_satp_o()
    );

    initial if(CORRUPT_RESULT) force u_dut.rd_result_e1_q=32'hc0ffee01;

    task check;
        input condition;
        input [319:0] message;
        begin
            checks=checks+1;
            if(condition!==1'b1) $fatal(1,"CSR_UNIT_FAIL %0s",message);
        end
    endtask

    task csr_access;
        input [11:0] address;
        input [2:0] funct3;
        input [4:0] source_index;
        input [31:0] source_value, expected_old;
        input do_commit;
        reg [31:0] source_bits, expected_write;
        begin
            source_bits=funct3[2] ? {27'b0,source_index} : source_value;
            case(funct3[1:0])
                2'd1: expected_write=source_bits;
                2'd2: expected_write=expected_old | source_bits;
                2'd3: expected_write=expected_old & ~source_bits;
                default: expected_write=0;
            endcase
            @(negedge clk); #1;
            opcode={address,source_index,funct3,5'd5,7'h73};
            operand=source_value; rs1=source_index; valid=1;
            @(posedge clk); #1;
            check(read_valid && decoded_exception==0,"CSR decode/valid");
            if(read_value!==expected_old)
                $fatal(1,"CSR_UNIT_FAIL old addr=%h expected=%h actual=%h",address,expected_old,read_value);
            checks=checks+1;
            check(write_value===expected_write,"CSR RMW result");
            sampled_write=write_value;
            @(negedge clk); #1;
            valid=0; wb_write=do_commit; wb_addr=address; wb_data=sampled_write;
            @(posedge clk); #1;
            check(!read_valid,"CSR valid bubble");
            @(negedge clk); #1;
            wb_write=0;
            csr_operations=csr_operations+1;
        end
    endtask

    task trap_event;
        input [5:0] cause;
        input [31:0] pc, tval, destination;
        begin
            @(negedge clk); #1;
            trap=cause; trap_pc=pc; trap_value=tval;
            @(posedge clk); #1;
            check(branch_valid && branch_pc===destination,"trap/return destination");
            @(negedge clk); #1; trap=0;
            @(posedge clk); #1;
            check(!branch_valid,"one-cycle branch request");
        end
    endtask

    initial begin
        repeat(5) @(negedge clk);
        #1; rst=0;
        repeat(3) @(negedge clk);
        csr_access(`CSR_MSCRATCH,3'd2,0,0,0,0);
        csr_access(`CSR_MSCRATCH,3'd1,1,32'h12345678,0,1);
        csr_access(`CSR_MSCRATCH,3'd2,1,32'h00f0000f,32'h12345678,1);
        csr_access(`CSR_MSCRATCH,3'd3,1,32'h00f0000f,32'h12f4567f,1);
        csr_access(`CSR_MSCRATCH,3'd5,31,0,32'h12045670,1);
        csr_access(`CSR_MSCRATCH,3'd6,1,0,32'h1f,1);
        csr_access(`CSR_MSCRATCH,3'd7,3,0,32'h1f,1);
        csr_access(`CSR_MSCRATCH,3'd2,0,0,32'h1c,0);
        csr_access(`CSR_MEPC,3'd1,1,32'h80000103,0,1);
        csr_access(`CSR_MEPC,3'd2,0,0,32'h80000100,0);
        csr_access(`CSR_MEPC,3'd2,1,3,32'h80000100,1);
        csr_access(`CSR_MEPC,3'd2,0,0,32'h80000100,0);
        csr_access(`CSR_MTVEC,3'd1,1,32'h80000200,0,1);
        csr_access(`CSR_MSTATUS,3'd1,1,32'h8,0,1);
        trap_event(`EXCEPTION_ILLEGAL_INSTRUCTION,32'h80000044,32'hffffffff,32'h80000200);
        csr_access(`CSR_MEPC,3'd2,0,0,32'h80000044,0);
        csr_access(`CSR_MCAUSE,3'd2,0,0,2,0);
        csr_access(`CSR_MTVAL,3'd2,0,0,32'hffffffff,0);
        csr_access(`CSR_MSTATUS,3'd2,0,0,32'h1880,0);
        trap_event(`EXCEPTION_ERET_M,0,0,32'h80000044);
        csr_access(`CSR_MSTATUS,3'd2,0,0,32'h88,0);
        // Decode an ECALL as an instruction, then commit its exception event.
        @(negedge clk); #1; valid=1; opcode=32'h00000073;
        @(posedge clk); #1;
        check(decoded_exception===`EXCEPTION_ECALL_M,"ECALL machine cause");
        @(negedge clk); #1; valid=0;
        trap_event(`EXCEPTION_ECALL_M,32'h80000080,0,32'h80000200);
        csr_access(`CSR_MCAUSE,3'd2,0,0,11,0);
        csr_access(`CSR_MEPC,3'd2,0,0,32'h80000080,0);
        $display("CSR_UNIT_PASS operations=%0d checks=%0d forms=6 traps=2 returns=1",csr_operations,checks);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1,"CSR_UNIT_FAIL timeout");
    end
endmodule
