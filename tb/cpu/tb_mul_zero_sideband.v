`timescale 1ns/1ps
module tb_mul_zero_sideband;
    reg clk=0, rst=1, hold=0;
    reg [31:0] a=0, b=0;
    always #5 clk=~clk;
    wire [31:0] early;
    wire zero;
    triha_multiplier dut (
        .clk_i(clk), .rst_i(rst), .hold_i(hold),
        .opcode_valid_i(1'b1), .opcode_opcode_i(32'h02000033),
        .opcode_pc_i(32'b0), .opcode_invalid_i(1'b0),
        .opcode_rd_idx_i(5'd1), .opcode_ra_idx_i(5'd2), .opcode_rb_idx_i(5'd3),
        .opcode_ra_operand_i(a), .opcode_rb_operand_i(b),
        .writeback_value_o(), .early_low_value_o(early), .early_low_valid_o()
`ifdef HAS_ZERO_SIDEBAND
        ,.early_low_zero_o(zero)
`endif
    );
`ifndef HAS_ZERO_SIDEBAND
    assign zero=1'b0;
`endif
    reg [15:0] oracle_a=0, oracle_b=0;
    reg [31:0] product;
    reg observed;
    integer checks=0, i;
    always @(posedge clk or posedge rst) begin
        if(rst) begin oracle_a=0;oracle_b=0;end
        else if(hold);
        else begin oracle_a=a[15:0];oracle_b=b[15:0];end
        #1;
        product={16'b0,oracle_a}*{16'b0,oracle_b};
        observed=zero;
        if($test$plusargs("FAULT_ZERO"))observed=~zero;
        if(early!==product || observed!==(product==0))begin
            $display("MUL_ZERO_FAIL check=%0d a=%h b=%h product=%h early=%h zero=%b",checks,oracle_a,oracle_b,product,early,observed);
            $finish;
        end
        checks=checks+1;
    end
    task sample;
        input [31:0] av,bv;
        input hv;
        begin @(negedge clk);a=av;b=bv;hold=hv;@(posedge clk);#2;end
    endtask
    initial begin
        #2;rst=0;#1;rst=1;#4;rst=0;
        for(i=0;i<65536;i=i+1)begin
            sample(i,0,0);sample(0,i,0);sample(i,65535,0);
        end
        for(i=0;i<10000;i=i+1)sample($random,$random,(i%7==0));
        sample(0,32'h0000xxxx,0);sample(32'h0000zzzz,0,0);
        sample(32'hxxxx0001,32'hzzzz0002,0);
        sample(32'h00000001,32'h00000003,0);
        sample(0,0,1);sample(0,0,1'bx);sample(0,0,1'bz);
        @(negedge clk);hold=1;rst=1;#2;
        if(zero!==1'b1)$fatal(1,"async reset zero");
        #8;rst=0;sample(5,7,1);sample(5,7,0);
        $display("MUL_ZERO_PASS checks=%0d",checks);$finish;
    end
endmodule
