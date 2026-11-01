`timescale 1ns/1ps
module tb_direct_load_forward #(parameter LOAD_BYPASS=1,MUL_BYPASS=1);
    reg [4:0] index_r=5;
    reg [29:0] tags=0;
    reg [191:0] values=0;
    reg [31:0] rf=32'h12345679,memory=32'h89abcdef;
    reg [1:0] valid=3;
    reg [9:0] ctrl0=2,ctrl1=2;
    reg [31:0] saved0=32'h55550001,saved1=32'hffff0003,mul=32'h31303031;
    wire [31:0] old0,old1,new0,new1,non0,non1,unused0,unused1;
    wire select0,select1;
    wire [31:0] actual0,actual1,expected0,expected1;
    reg poison=0;
    wire [191:0] original_values={values[191:128],old1,old0,values[63:0]};
    integer i,j,k,mask,idx,checks=0;
    parent_e2 #(.SUPPORT_LOAD_BYPASS(LOAD_BYPASS),.SUPPORT_MUL_BYPASS(MUL_BYPASS)) p0(.valid_e2_q(valid[0]),.ctrl_e2_q(ctrl0),.result_e2_q(saved0),.mem_bypass_e2_i(memory),.mul_result_e2_i(mul),.value_o(old0),.result_nonmem_e2_o(unused0),.bypass_mem_e2_o());
    parent_e2 #(.SUPPORT_LOAD_BYPASS(LOAD_BYPASS),.SUPPORT_MUL_BYPASS(MUL_BYPASS)) p1(.valid_e2_q(valid[1]),.ctrl_e2_q(ctrl1),.result_e2_q(saved1),.mem_bypass_e2_i(memory),.mul_result_e2_i(mul),.value_o(old1),.result_nonmem_e2_o(unused1),.bypass_mem_e2_o());
    candidate_e2 #(.SUPPORT_LOAD_BYPASS(LOAD_BYPASS),.SUPPORT_MUL_BYPASS(MUL_BYPASS)) n0(.valid_e2_q(valid[0]),.ctrl_e2_q(ctrl0),.result_e2_q(saved0),.mem_bypass_e2_i(memory),.mul_result_e2_i(mul),.value_o(new0),.result_nonmem_e2_o(non0),.bypass_mem_e2_o(select0));
    candidate_e2 #(.SUPPORT_LOAD_BYPASS(LOAD_BYPASS),.SUPPORT_MUL_BYPASS(MUL_BYPASS)) n1(.valid_e2_q(valid[1]),.ctrl_e2_q(ctrl1),.result_e2_q(saved1),.mem_bypass_e2_i(memory),.mul_result_e2_i(mul),.value_o(new1),.result_nonmem_e2_o(non1),.bypass_mem_e2_o(select1));
    // In the red parent test select ports are absent in real RTL. The poisoned
    // lane is qualified independently with the same known LOAD condition.
    wire load0=LOAD_BYPASS && valid[0] && (ctrl0[1]||ctrl0[2]);
    wire load1=LOAD_BYPASS && valid[1] && (ctrl1[1]||ctrl1[2]);
    wire [191:0] poisoned_values={values[191:128],(poison&&load1?32'hdeadbeef:new1),(poison&&load0?32'hdeadbeef:new0),values[63:0]};
    parent_operand oracle(.index_i(index_r),.rf_i(rf),.tags_i(tags),.values_i(original_values),.memory_i(memory),.mem_select_i(2'b0),.nonmem_i(64'b0),.value0_o(expected0),.value1_o(expected1));
    candidate_operand dut(.index_i(index_r),.rf_i(rf),.tags_i(tags),.values_i(poisoned_values),.memory_i(memory),.mem_select_i({select1,select0}),.nonmem_i({non1,non0}),.value0_o(actual0),.value1_o(actual1));
    task check;
        begin
            #1;
            if(old0!==new0 || old1!==new1 || actual0!==expected0 || actual1!==expected1)
                $fatal(1,"DIRECT_FORWARD_FAIL checks=%0d idx=%b tags=%h expected=%h actual=%h ctrl=%h/%h",checks,index_r,tags,expected0,actual0,ctrl0,ctrl1);
            checks=checks+1;
        end
    endtask
    initial begin
        if($test$plusargs("FAULT_OUTPUT"))force dut.value0_o[0]=0;
        tags[14:10]=5;check;
        if($test$plusargs("POISON_E2"))begin poison=1;check;poison=0;end
        for(i=0;i<256;i=i+1)begin
            valid={i[7],i[3]};ctrl0=0;ctrl1=0;
            {ctrl0[5],ctrl0[2],ctrl0[1]}=i[2:0];
            {ctrl1[5],ctrl1[2],ctrl1[1]}=i[6:4];check;
        end
        for(idx=0;idx<32;idx=idx+1)for(mask=0;mask<64;mask=mask+1)begin
            index_r=idx;valid=3;ctrl0=mask[0]?2:32;ctrl1=mask[1]?4:0;
            for(j=0;j<6;j=j+1)begin tags[j*5+:5]=mask[j]?idx:idx+1;values[j*32+:32]=$random;end
            check;
            memory=32'hzzzzzzzz;check;memory=32'hxxxxxxxx;check;memory=$random;
        end
        for(i=0;i<20000;i=i+1)begin
            index_r=$random;tags={$random,$random};values={$random,$random,$random,$random,$random,$random};
            rf=$random;memory=$random;mul=$random;saved0=$random;saved1=$random;
            valid=$random;ctrl0=$random;ctrl1=$random;check;
            if(i%7==0)begin ctrl0[1]=1'bx;ctrl1[5]=1'bz;check;end
            if(i%11==0)begin valid[0]=1'bx;valid[1]=1'bz;check;end
            if(i%13==0)begin tags[14]=1'bx;index_r[0]=1'bz;check;end
            if(i%17==0)begin rf[3]=1'bz;mul[15]=1'bx;memory[7]=1'bz;check;end
        end
        $display("DIRECT_FORWARD_PASS checks=%0d",checks);$finish;
    end
endmodule
