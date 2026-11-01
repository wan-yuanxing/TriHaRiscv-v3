`timescale 1ns/1ps
// Exercise accepted opcode capture, then each legal quantizer source boundary.
// Payload values are independent stimuli; compare only valid token contents.
module tb_b03_layer_control;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,run_ce=0,start=0,cancel=0;
 reg [1023:0] words=0;
 b03_layer_exec_payload #(.ENABLE_RUNTIME_DIAGNOSTICS(0),.TRUSTED_MODEL(1),.M_LANES(2),.QUANTIZER_LANES(1)) dut(
 .clk(clk),.rst_n(rst_n),.run_ce(run_ce),.cancel_request(cancel),.start_valid(start),.start_ready(),.op_words(words),
 .preflight(1'b0),.workspace_base(32'd0),.src0_base(32'd0),.src1_base(32'd0),.dst_base(32'd0),.epoch(32'd1),.tag(32'h678abcde),
 .done_ready(1'b0),.done_valid(),.done_status(),.done_detail(),.done_tag(),.done_op_id(),.cycles(),
 .mem_req_valid(),.mem_req_ready(1'b0),.mem_req_write(),.mem_req_verify(),.mem_req_offset(),.mem_req_tag(),.mem_req_beats(),.mem_req_client(),
 .mem_w_valid(),.mem_w_ready(1'b0),.mem_w_data(),.mem_w_strb(),.mem_w_last(),.mem_r_valid(1'b0),.mem_r_ready(),.mem_r_data(256'd0),.mem_r_last(1'b0),
 .mem_rsp_valid(1'b0),.mem_rsp_ready(),.mem_rsp_status(4'd0),.mem_rsp_tag(32'd0),.busy(),.debug_stage(),.stat_mac_vectors(),.stat_quant_groups(),.stat_rows());
 reg [255:0] acc,bias,mult,va,vb,vbias,vma,vmb;
 reg [47:0] shift,vshift;reg [127:0] vtag;reg [7:0] vmask;
 reg vvalid,vadd,capacity,dwvalid;reg [1:0] vdtype;
 reg [31:0] seed=32'h8e729193,opcode;reg [511:0] dwdata;
 reg [127:0] dwtag,expected_tag;reg [255:0] expected_psum;
 reg [7:0] expected_mask;reg expected_valid,expected_ready;integer n,c,i,issued,co_base,co,y,x,half,cc,cases=0;
 function[31:0] rnd(input[31:0] v);rnd=(v<<1)^(v[31]?32'h04c11db7:0);endfunction
 initial begin
  force dut.selected_acc=acc;force dut.selected_bias=bias;force dut.selected_mult=mult;force dut.selected_shift=shift;
  force dut.v_q_psum=va;force dut.v_q_psum_b=vb;force dut.v_q_bias=vbias;force dut.v_q_ma=vma;force dut.v_q_mb=vmb;
  force dut.v_q_shift=vshift;force dut.v_q_tag=vtag;force dut.v_q_mask=vmask;force dut.v_q_valid=vvalid;force dut.v_q_add=vadd;force dut.v_q_dtype=vdtype;
  force dut.q_in_capacity=capacity;force dut.dw_out_valid=dwvalid;
  for(n=0;n<1024;n=n+1)for(c=1;c<=8;c=c+1)begin
   @(negedge clk);rst_n=0;start=0;run_ce=0;cancel=0;
   @(negedge clk);rst_n=1;words=0;opcode=c;words[0+:32]=opcode;words[928+:32]=n;
   words[224+:32]=(n%4)+1;words[288+:32]=64;
   start=1;@(posedge clk);#1;@(negedge clk);start=0;
   seed=rnd(seed);acc={8{seed}};bias={8{seed^32'h11111111}};mult={8{seed^32'h22222222}};
   shift={8{seed[5:0]}};dwdata={16{seed^32'h33333333}};dwdata[511:256]=~dwdata[255:0];
   va={8{seed^32'h44444444}};vb=~va;vbias={8{seed^32'h55555555}};vma=~vbias;vmb=acc;
   vshift=~shift;vtag={4{seed}};vmask=seed[7:0];vvalid=n[0];vadd=n[1];vdtype=n[3:2];capacity=n[2];dwvalid=n[3];
   issued=n%6;co_base=(n%4)*16;co=64-(n%8);y=n%320;x=n%300;half=n%2;dwtag={4{seed^32'h76543210}};
   dut.q_issued=issued;dut.co_base=co_base;dut.m_count=2;dut.y=y;dut.x=x;dut.dw_half=half;dut.dw_q_valid=n[0];dut.dw_q_psum=dwdata;dut.dw_q_tag=dwtag;
   dut.op[288+:32]=co;run_ce=n[4];cancel=n[5];
   if(c==1)dut.state=11;else if(c==2)dut.state=14;else if(c==4||c==5)dut.state=15;else dut.state=22;
   #2;
   expected_ready=c==2&&(!n[0]||(half&&capacity));
   if(dut.core_ce!==(run_ce&&(c!=2||!dwvalid||expected_ready)))$fatal(1,"core enable mismatch n=%0d code=%0d",n,c);
   if(dut.dw_out_ready!==expected_ready)$fatal(1,"DW backpressure mismatch");
   expected_valid=c==1?issued<4:c==2?n[0]:(c==4||c==5)?0:vvalid;
   if(dut.q_in_valid!==expected_valid)$fatal(1,"quantizer valid mismatch");
   if(expected_valid)begin
    if(c==1||c==2)begin
     cc=co_base+(c==2?half:issued%2)*8;
     for(i=0;i<8;i=i+1)expected_mask[i]=cc+i<co;
     expected_tag=c==1?{32'h678abcde,32'(n),16'(y),16'(cc),32'(x+issued/2)}:{dwtag[127:48],16'(cc),dwtag[31:0]};
     expected_psum=c==1?acc:half?dwdata[511:256]:dwdata[255:0];
     if({dut.q_in_mask,dut.q_in_tag,dut.q_psum,dut.q_psum_b,dut.q_bias,dut.q_ma,dut.q_mb,dut.q_shift,dut.q_in_add,dut.q_dtype}!==
        {expected_mask,expected_tag,expected_psum,256'd0,bias,mult,256'd0,shift,1'b0,2'(n%4)})$fatal(1,"spatial token mismatch n=%0d code=%0d",n,c);
    end else if({dut.q_in_mask,dut.q_in_tag,dut.q_psum,dut.q_psum_b,dut.q_bias,dut.q_ma,dut.q_mb,dut.q_shift,dut.q_in_add,dut.q_dtype}!==
        {vmask,vtag,va,vb,vbias,vma,vmb,vshift,vadd,vdtype})$fatal(1,"vector token mismatch n=%0d",n);
   end
   cases=cases+1;
  end
  // A high invalid opcode bit must not be truncated into a legal DW command.
  for(n=4;n<32;n=n+1)for(i=0;i<8;i=i+1)begin
   @(negedge clk);rst_n=0;start=0;run_ce=0;cancel=0;
   @(negedge clk);rst_n=1;words=0;words[0+:32]=32'd2|(32'd1<<n);start=1;
   @(posedge clk);#1;@(negedge clk);start=0;run_ce=1;dwvalid=1;capacity=0;
   #2;if(dut.core_ce!==1)$fatal(1,"invalid opcode truncated bit=%0d",n);
   @(posedge clk);#1;if(!dut.done_valid||dut.done_status!==21)$fatal(1,"invalid opcode admitted bit=%0d",n);
   cases=cases+1;
  end
  $display("LAYER_CONTROL_PASS cases=%0d",cases);$finish;
 end
 initial begin #2000000;$fatal(1,"layer control timeout");end
endmodule
