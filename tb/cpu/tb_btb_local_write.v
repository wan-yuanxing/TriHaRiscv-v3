`timescale 1ns/1ps
module tb_btb_local_write;
    reg clk=0,rst=1,flush=0,train=0,taken=0;
    reg [31:0] source=0,target=0,pc=0;
    reg [2:0] kind=0;
    wire [38:0] got,ref_out;
    wire [15:0] got_we,ref_we;
    integer i,j,checks=0;
    always #5 clk=~clk;
    triha_btb dut(.clk_i(clk),.rst_i(rst),.invalidate_i(flush),.train_i(train),.taken_i(taken),
        .source_i(source),.target_i(target),.kind_i(kind),.pc_i(pc),.valid_o(got[38]),.upper_o(got[37]),
        .target_o(got[36:5]),.kind_o(got[4:2]),.call_valid_o(got[1]),.ret_valid_o(got[0]));
    triha_btb_parent oracle(.clk_i(clk),.rst_i(rst),.invalidate_i(flush),.train_i(train),.taken_i(taken),
        .source_i(source),.target_i(target),.kind_i(kind),.pc_i(pc),.valid_o(ref_out[38]),.upper_o(ref_out[37]),
        .target_o(ref_out[36:5]),.kind_o(ref_out[4:2]),.call_valid_o(ref_out[1]),.ret_valid_o(ref_out[0]));
    genvar bank,block_index;
    generate for(bank=0;bank<2;bank=bank+1)begin:g_bank
        for(block_index=0;block_index<8;block_index=block_index+1)begin:g_block
            assign got_we[bank*8+block_index]=dut.g_bank[bank].u_bank.g_block[block_index].target_we;
            assign ref_we[bank*8+block_index]=oracle.g_bank[bank].u_bank.g_block[block_index].target_we;
        end
    end endgenerate
    task check;
        begin #1;
            if(got!==ref_out || got_we!==ref_we ||
                dut.g_bank[0].u_bank.valid_q!==oracle.g_bank[0].u_bank.valid_q ||
                dut.g_bank[1].u_bank.valid_q!==oracle.g_bank[1].u_bank.valid_q)
                $fatal(1,"BTB_LOCAL_FAIL checks=%0d source=%h got_we=%h ref_we=%h",checks,source,got_we,ref_we);
            checks=checks+1;
        end
    endtask
    task step;
        begin check;@(posedge clk);#1;check;@(negedge clk);end
    endtask
    function four;
        input integer value;
        begin case(value%4)0:four=0;1:four=1;2:four=1'bx;3:four=1'bz;endcase end
    endfunction
    initial begin
        #2;rst=0;#1;rst=1;#4;rst=0;
        @(negedge clk);source=32'h80001000;pc=source;target=32'h80004000;train=1;taken=1;
        if($test$plusargs("POISON_SHARED"))begin
            force dut.g_bank[0].u_bank.write_target=0;check;
            release dut.g_bank[0].u_bank.write_target;
        end
        if($test$plusargs("FAULT_WE"))force dut.g_bank[0].u_bank.g_block[0].target_we=0;
        // Populate every bank/row, then verify not-taken retention and aliases.
        for(i=0;i<512;i=i+1)begin
            source=32'h80000000+i*4;pc=source;target=32'h90000000+i*4;
            kind=i%8;train=1;taken=1;step;
            taken=0;target=32'hdead0000+i*4;step;
            source=source^32'h00100000;pc=source;step;
        end
        for(i=0;i<12000;i=i+1)begin
            source=32'h80000000|($random&32'h003ffffc);pc=source;target=$random;kind=$random;
            train=four(i);taken=four(i/4);flush=(i%127==0);rst=(i%509==0);
            case(i%13)
                0:source[8]=1'bx;1:source[9]=1'bz;2:source[10]=1'bx;
                3:source[4]=1'bx;4:source[31]=1'bz;5:rst=four(i/16);
                6:flush=four(i/16);7:target[8]=1'bx;8:kind[1]=1'bz;
            endcase
            step;
        end
        // Independent four-state block index and update controls, both banks
        // and unknown bank selects. Keep low row bits known in this cross product.
        for(i=0;i<16384;i=i+1)for(j=0;j<4;j=j+1)begin
            source=32'h80000000|((i%32)<<3);pc=source;target=$random;kind=$random;
            source[8]=four(i);source[9]=four(i/4);source[10]=four(i/16);
            train=four(i/64);taken=four(i/256);flush=four(i/1024);rst=four(i/4096);
            source[2]=four(j);step;
        end
        rst=0;flush=0;train=0;taken=0;
        for(i=0;i<512;i=i+1)begin pc=32'h80000000+i*4;step;end
        $display("BTB_LOCAL_PASS checks=%0d",checks);$finish;
    end
endmodule
