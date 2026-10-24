/* Exhaust every two-state support vector against the unchanged decoder. */
`timescale 1ns/1ps
module tb_exec_classify #(parameter BROKEN=0);
    reg [31:0] op=0,rng=32'h7183a42d;
    wire expected;
    reg observed;
    reg [16:0] support;
    integer n,bitno,k,position,checks=0;
    triha_decode #(.SUPPORT_MULDIV(1),.EXTRA_DECODE_STAGE(0)) u_dut (
        .clk_i(1'b0),.rst_i(1'b1),.fetch_in_valid_i(1'b0),.fetch_in_instr_i({32'b0,op}),
        .fetch_in_pred_branch_i(2'b0),.fetch_in_fault_fetch_i(1'b0),.fetch_in_fault_page_i(1'b0),
        .fetch_in_pc_i(0),.fetch_out0_accept_i(1'b0),.fetch_out1_accept_i(1'b0),
        .branch_request_i(1'b0),.branch_pc_i(0),.branch_priv_i(2'b0));
    biriscv_decoder u_reference (.valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),
        .opcode_i(op),.invalid_o(),.exec_o(expected),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(),.rd_valid_o());
    task check;
        begin
            #1;observed=u_dut.genblk1.exec0_in_w;
            if(BROKEN && expected===1'b1)observed=0;
            checks=checks+1;
            if(observed!==expected)$fatal(1,"EXEC_CLASSIFY_FAIL check=%0d op=%h actual=%b expected=%b",checks,op,observed,expected);
        end
    endtask
    initial begin
        for(n=0;n<131072;n=n+1)begin
            support=n;
            op={support[16:10],10'b0,support[9:7],5'b0,support[6:0]};
            check;
        end
        for(n=0;n<4096;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;
            support=rng[16:0];
            for(bitno=0;bitno<17;bitno=bitno+1)begin
                position=bitno<7 ? bitno : bitno<10 ? bitno+5 : bitno+15;
                op={support[16:10],10'bx,support[9:7],5'bz,support[6:0]};
                op[position]=1'bx;check;
                op[position]=1'bz;check;
            end
        end
        for(n=0;n<20000;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;op=rng;
            for(k=0;k<4;k=k+1)begin
                rng=rng*32'd1664525+32'd1013904223;
                if(rng[5])op[rng[4:0]]=1'bx;
                else op[rng[4:0]]=1'bz;
            end
            check;
        end
        $display("EXEC_CLASSIFY_PASS checks=%0d exhaustive17bit_plus_ignored_XZ",checks);$finish;
    end
endmodule
