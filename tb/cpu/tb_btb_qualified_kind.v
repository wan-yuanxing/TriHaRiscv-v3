// Check qualified class flags against the original BTB valid/kind contract,
// including X/Z selector, tag-hit and class inputs.
`timescale 1ns/1ps
module tb_btb_qualified_kind;
    parameter HAS_QUALIFIED=0;
    parameter BROKEN=0;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [31:0] pc=0;
    reg [1:0] hits=0;
    reg [2:0] kind0=0,kind1=0;
    wire valid,upper,qualified_call,qualified_ret;
    wire [2:0] kind;
    wire [31:0] target;
    integer p,h0,h1,k0,k1,low,checks=0;
    generate if(HAS_QUALIFIED)begin:g_new
        triha_btb u_dut(.clk_i(clk),.rst_i(rst),.invalidate_i(1'b0),
            .train_i(1'b0),.taken_i(1'b0),.source_i(32'b0),.target_i(32'b0),.kind_i(3'b0),
            .pc_i(pc),.valid_o(valid),.upper_o(upper),.target_o(target),.kind_o(kind),
            .call_valid_o(qualified_call),.ret_valid_o(qualified_ret));
        initial begin
            force u_dut.hit=hits;force u_dut.kind[0]=kind0;force u_dut.kind[1]=kind1;
            if(BROKEN)force u_dut.call_valid_o=1'b0;
        end
    end else begin:g_old
        triha_btb u_dut(.clk_i(clk),.rst_i(rst),.invalidate_i(1'b0),
            .train_i(1'b0),.taken_i(1'b0),.source_i(32'b0),.target_i(32'b0),.kind_i(3'b0),
            .pc_i(pc),.valid_o(valid),.upper_o(upper),.target_o(target),.kind_o(kind));
        assign qualified_call=0;assign qualified_ret=0;
        initial begin
            force u_dut.hit=hits;force u_dut.kind[0]=kind0;force u_dut.kind[1]=kind1;
        end
    end endgenerate
    function state4;
        input integer code;
        case(code)0:state4=0;1:state4=1;2:state4=1'bx;3:state4=1'bz;endcase
    endfunction
    initial begin
        repeat(3)@(negedge clk);rst=0;
        for(p=0;p<4;p=p+1)for(h0=0;h0<4;h0=h0+1)for(h1=0;h1<4;h1=h1+1)
        for(k0=0;k0<16;k0=k0+1)for(k1=0;k1<16;k1=k1+1)for(low=0;low<16;low=low+1)begin
            pc[2]=state4(p);pc[1:0]={state4(low/4),state4(low%4)};
            hits={state4(h1),state4(h0)};
            kind0={state4(k0/4),state4(k0%4),1'b0};
            kind1={state4(k1/4),state4(k1%4),1'b0};
            #1;checks=checks+1;
            if({qualified_call,qualified_ret}!=={valid&&kind[2],valid&&kind[1]})
                $fatal(1,"BTB_QUALIFIED_FAIL pc=%h hits=%b kind=%b/%b expected=%b%b actual=%b%b",pc,hits,kind0,kind1,valid&&kind[2],valid&&kind[1],qualified_call,qualified_ret);
        end
        $display("BTB_QUALIFIED_PASS checks=%0d",checks);$finish;
    end
endmodule
