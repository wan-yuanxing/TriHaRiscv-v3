`timescale 1ns/1ps
module tb_role_queue #(parameter EXTRA=0,MULDIV=1,BROKEN=0);
    // Reuse the complete existing FIFO/decode history oracle and stimuli.
    tb_decode_alu_control #(.EXTRA(EXTRA),.MULDIV(MULDIV)) u_env();
    wire [2:0] expected0,expected1;
    integer checks=0;
    role_parent u_expected0(.opcode_i(u_env.got[148:117]),.invalid_i(1'b0),.fault_i(2'b00),.raw_i(3'b000),.roles_o(expected0));
    role_parent u_expected1(.opcode_i(u_env.got[73:42]),.invalid_i(1'b0),.fault_i(2'b00),.raw_i(3'b000),.roles_o(expected1));
    generate if(BROKEN && !EXTRA)begin:g_negative
        initial force u_env.u_dut.genblk1.roles0_in_w=3'b000;
    end endgenerate
    always @(negedge u_env.clk)begin
        #2;checks=checks+1;
        if(u_env.u_dut.fetch_out0_roles_o!==expected0 || u_env.u_dut.fetch_out1_roles_o!==expected1)begin
            $display("ROLE_QUEUE_FAIL check=%0d actual=%b/%b expected=%b/%b",checks,
                u_env.u_dut.fetch_out0_roles_o,u_env.u_dut.fetch_out1_roles_o,expected0,expected1);
            $finish;
        end
        if(checks==12000)$display("ROLE_QUEUE_PASS checks=%0d EXTRA=%0d MULDIV=%0d",checks,EXTRA,MULDIV);
    end
endmodule
