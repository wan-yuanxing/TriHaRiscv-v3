// External Q8 token, one physical arithmetic lane, eight ordered fragments.
//
// This is the resource-bounded companion to b03_quant8_tdm2.  It uses the
// unchanged Q4 core and only drives lane zero; the other seven output lanes
// are serialized through the same exact arithmetic pipeline.  The external
// token, ordering, tags, masks and error ABI remain unchanged.
module b03_quant8_tdm1(
 input wire clk,rst_n,clear,run_ce,
 input wire in_valid,output wire in_ready,in_capacity,input wire [7:0] in_mask,
 input wire [255:0] in_psum,in_psum_b,input wire in_add,input wire [1:0] in_dtype,
 input wire [255:0] in_bias,in_multiplier,in_multiplier_b,input wire [47:0] in_shift,
 input wire [127:0] in_tag,
 output reg out_valid,input wire out_ready,output reg [7:0] out_mask,
 output reg [127:0] out_values,output reg [1:0] out_dtype,output reg out_add,
 output reg [23:0] out_error,output reg [127:0] out_tag,
 output wire advance,busy
);
 reg [2:0] pending;
 reg [6:0] saved_mask;
 reg [223:0] saved_psum,saved_psum_b,saved_bias,saved_ma,saved_mb;
 reg [41:0] saved_shift;
 reg [127:0] saved_tag;reg [1:0] saved_dtype;reg saved_add;
 reg [23:0] phase_pipe;
 reg [2:0] collected;
 reg [6:0] partial_mask;reg [111:0] partial_values;reg [20:0] partial_error;
 reg [127:0] partial_tag;reg [1:0] partial_dtype;reg partial_add,partial_bad;
 wire core_ready,core_valid,core_out_ready,core_advance,core_busy,core_add;
 wire [3:0] core_mask;wire [63:0] core_values;wire [11:0] core_error;
 wire [127:0] core_tag;wire [1:0] core_dtype;
 wire [2:0] returned_phase=phase_pipe[23:21];
 wire output_available=!out_valid||out_ready;
 wire accepted=core_advance&&pending==0&&in_valid&&output_available;
 wire tuple_bad=core_tag!=partial_tag||core_dtype!=partial_dtype||core_add!=partial_add;
 wire [7:0] complete_mask={core_mask[0],partial_mask};
 // Private capacity excludes reset only. Use it under the parent reset branch;
 // public handshake remains reset-qualified and cycle-identical.
 assign in_capacity=!clear&&run_ce&&(!core_valid||core_out_ready)&&pending==0&&output_available;
 assign in_ready=rst_n&&in_capacity;
 assign advance=rst_n&&!clear&&run_ce&&output_available;
 assign busy=core_busy||pending!=0||collected!=0||out_valid;
 assign core_out_ready=returned_phase==collected&&(returned_phase!=3'd7||output_available);

 reg selected_mask;
 reg [31:0] selected_psum,selected_psum_b,selected_bias,selected_ma,selected_mb;
 reg [5:0] selected_shift;
 always @* begin
  selected_mask=in_mask[0];
  selected_psum=in_psum[31:0];selected_psum_b=in_psum_b[31:0];
  selected_bias=in_bias[31:0];selected_ma=in_multiplier[31:0];
  selected_mb=in_multiplier_b[31:0];selected_shift=in_shift[5:0];
  case(pending)
   1:begin selected_mask=saved_mask[0];selected_psum=saved_psum[31:0];selected_psum_b=saved_psum_b[31:0];selected_bias=saved_bias[31:0];selected_ma=saved_ma[31:0];selected_mb=saved_mb[31:0];selected_shift=saved_shift[5:0];end
   2:begin selected_mask=saved_mask[1];selected_psum=saved_psum[63:32];selected_psum_b=saved_psum_b[63:32];selected_bias=saved_bias[63:32];selected_ma=saved_ma[63:32];selected_mb=saved_mb[63:32];selected_shift=saved_shift[11:6];end
   3:begin selected_mask=saved_mask[2];selected_psum=saved_psum[95:64];selected_psum_b=saved_psum_b[95:64];selected_bias=saved_bias[95:64];selected_ma=saved_ma[95:64];selected_mb=saved_mb[95:64];selected_shift=saved_shift[17:12];end
   4:begin selected_mask=saved_mask[3];selected_psum=saved_psum[127:96];selected_psum_b=saved_psum_b[127:96];selected_bias=saved_bias[127:96];selected_ma=saved_ma[127:96];selected_mb=saved_mb[127:96];selected_shift=saved_shift[23:18];end
   5:begin selected_mask=saved_mask[4];selected_psum=saved_psum[159:128];selected_psum_b=saved_psum_b[159:128];selected_bias=saved_bias[159:128];selected_ma=saved_ma[159:128];selected_mb=saved_mb[159:128];selected_shift=saved_shift[29:24];end
   6:begin selected_mask=saved_mask[5];selected_psum=saved_psum[191:160];selected_psum_b=saved_psum_b[191:160];selected_bias=saved_bias[191:160];selected_ma=saved_ma[191:160];selected_mb=saved_mb[191:160];selected_shift=saved_shift[35:30];end
   7:begin selected_mask=saved_mask[6];selected_psum=saved_psum[223:192];selected_psum_b=saved_psum_b[223:192];selected_bias=saved_bias[223:192];selected_ma=saved_ma[223:192];selected_mb=saved_mb[223:192];selected_shift=saved_shift[41:36];end
   default:begin end
  endcase
 end

 b03_quant4_core core(
  .clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(run_ce),
  .in_valid(pending!=0||(in_valid&&output_available)),.in_ready(core_ready),
  .in_mask({3'b000,selected_mask}),.in_psum({96'd0,selected_psum}),.in_psum_b({96'd0,selected_psum_b}),
  .in_add(pending!=0?saved_add:in_add),.in_dtype(pending!=0?saved_dtype:in_dtype),
  .in_bias({96'd0,selected_bias}),.in_multiplier({96'd0,selected_ma}),.in_multiplier_b({96'd0,selected_mb}),
  .in_shift({18'd0,selected_shift}),.in_tag(pending!=0?saved_tag:in_tag),
  .out_valid(core_valid),.out_ready(core_out_ready),.out_mask(core_mask),.out_values(core_values),
  .out_dtype(core_dtype),.out_add(core_add),.out_error(core_error),.out_tag(core_tag),.advance(core_advance),.busy(core_busy)
 );

 always @(posedge clk) begin
  if(rst_n&&!clear&&accepted) begin
   saved_mask<=in_mask[7:1];saved_psum<=in_psum[255:32];saved_psum_b<=in_psum_b[255:32];
   saved_bias<=in_bias[255:32];saved_ma<=in_multiplier[255:32];saved_mb<=in_multiplier_b[255:32];
   saved_shift<=in_shift[47:6];saved_tag<=in_tag;saved_dtype<=in_dtype;saved_add<=in_add;
  end
  if(rst_n&&!clear&&core_advance&&core_valid) begin
   case(returned_phase)
    0:begin partial_mask[0]<=core_mask[0];partial_values[15:0]<=core_values[15:0];partial_error[2:0]<=core_error[2:0];partial_tag<=core_tag;partial_dtype<=core_dtype;partial_add<=core_add;end
    1:begin partial_mask[1]<=core_mask[0];partial_values[31:16]<=core_values[15:0];partial_error[5:3]<=core_error[2:0];end
    2:begin partial_mask[2]<=core_mask[0];partial_values[47:32]<=core_values[15:0];partial_error[8:6]<=core_error[2:0];end
    3:begin partial_mask[3]<=core_mask[0];partial_values[63:48]<=core_values[15:0];partial_error[11:9]<=core_error[2:0];end
    4:begin partial_mask[4]<=core_mask[0];partial_values[79:64]<=core_values[15:0];partial_error[14:12]<=core_error[2:0];end
    5:begin partial_mask[5]<=core_mask[0];partial_values[95:80]<=core_values[15:0];partial_error[17:15]<=core_error[2:0];end
    6:begin partial_mask[6]<=core_mask[0];partial_values[111:96]<=core_values[15:0];partial_error[20:18]<=core_error[2:0];end
    default:begin end
   endcase
  end
 end

 integer lane;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   pending<=0;phase_pipe<=0;collected<=0;partial_bad<=0;out_valid<=0;
   out_mask<=0;out_values<=0;out_dtype<=0;out_add<=0;out_error<=0;out_tag<=0;
  end else if(clear) begin
   pending<=0;phase_pipe<=0;collected<=0;partial_bad<=0;out_valid<=0;
   out_mask<=0;out_values<=0;out_dtype<=0;out_add<=0;out_error<=0;out_tag<=0;
  end else begin
   if(out_valid&&advance)out_valid<=0;
   if(core_advance) begin
    phase_pipe<={phase_pipe[20:0],pending};
    if(pending!=0)pending<=(pending==3'd7) ? 3'd0 : (pending+3'd1);
    else if(in_valid&&output_available)pending<=3'd1;
    if(core_valid) begin
     collected<=(returned_phase==3'd7) ? 3'd0 : (returned_phase+3'd1);
     if(returned_phase==0)partial_bad<=0;
     else partial_bad<=partial_bad||tuple_bad;
     if(returned_phase==3'd7) begin
      out_valid<=1;out_mask<=complete_mask;out_tag<=partial_tag;out_dtype<=partial_dtype;out_add<=partial_add;
      if(partial_bad||tuple_bad) begin
       out_values<=0;
       for(lane=0;lane<8;lane=lane+1)out_error[3*lane+:3]<=complete_mask[lane]?3'd4:3'd0;
      end else begin out_values<={core_values[15:0],partial_values};out_error<={core_error[2:0],partial_error};end
     end
    end
   end
  end
 end
endmodule
