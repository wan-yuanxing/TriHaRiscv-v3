/* Independent synchronous-write/asynchronous-read register-file oracle. */
`timescale 1ns / 1ps
`ifndef RF_MODULE
`define RF_MODULE biriscv_regfile
`endif
module tb_regfile #(parameter BROKEN=0);
    reg clk=0, rst=0;
    reg [4:0] rd=0, ra=0, rb=0;
    reg [31:0] data=0;
    wire [31:0] value_a, value_b;
    reg [31:0] model [0:31];
    reg [31:0] random_q=32'h7da15e37;
    integer checks=0, i, j;
    `RF_MODULE #(.SUPPORT_REGFILE_XILINX(0),.SUPPORT_DUAL_ISSUE(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.rd0_i(rd),.rd1_i(5'b0),
        .rd0_value_i(data),.rd1_value_i(32'b0),
        .ra0_i(ra),.rb0_i(rb),.ra1_i(5'b0),.rb1_i(5'b0),
        .ra0_value_o(value_a),.rb0_value_o(value_b),.ra1_value_o(),.rb1_value_o()
    );
    task check;
        begin
            if(value_a!==model[ra] || value_b!==model[rb])
                $fatal(1,"REGFILE_FAIL read ra=%d got=%h expected=%h rb=%d got=%h expected=%h",ra,value_a,model[ra],rb,value_b,model[rb]);
            checks=checks+2;
        end
    endtask
    task step;
        begin
            #5; clk=1;
            if(rst) begin
                for(j=0;j<32;j=j+1) model[j]=0;
            end
            else if(rd!=0) model[rd]=data;
            #1; check;
            #4; clk=0;
        end
    endtask
    task scan;
        begin
            for(i=0;i<32;i=i+1) begin
                ra=i; rb=31-i;
                #1; check;
            end
        end
    endtask
    initial begin
        rst=1; step; rst=0;
        if(BROKEN) force u_dut.ra0_value_o=32'hc0ffee00;
        scan;
        for(i=0;i<32;i=i+1) begin
            rd=i; data=32'h13579bdf^(32'h01010101*i);
            ra=i; rb=i;
            step;
        end
        scan;
        repeat(1000) begin
            random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
            rd=random_q[4:0]; data=random_q^32'h98765432;
            ra=rd; rb=random_q[9:5];
            step;
        end
        scan;
        // A synchronous reset must not clear visible data before its edge.
        rst=1; #1; check;
        step; rst=0; scan;
        // Old RAM data must remain masked; rewriting one word reveals only it.
        rd=5'd17; data=32'hcafef00d; ra=17; rb=16; step;
        scan;
        rd=0; data=32'hffffffff; ra=0; rb=17; step;
        scan;
        $display("REGFILE_PASS checks=%d zero_read_latency_writes_x0_sync_reset",checks);
        $finish;
    end
endmodule
