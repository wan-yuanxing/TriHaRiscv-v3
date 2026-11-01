// External Q8 token, two physical arithmetic lanes, four ordered fragments.
// Uses the unchanged Q4 core with the upper two lanes wholly unobserved.
module b03_quant8_tdm2(
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
 reg [1:0] pending;
 reg [5:0] saved_mask;reg [191:0] saved_psum,saved_psum_b,saved_bias,saved_ma,saved_mb;
 reg [35:0] saved_shift;reg [127:0] saved_tag;reg [1:0] saved_dtype;reg saved_add;
 reg [15:0] phase_pipe;
 reg [1:0] collected;
 reg [5:0] partial_mask;reg [95:0] partial_values;reg [17:0] partial_error;
 reg [127:0] partial_tag;reg [1:0] partial_dtype;reg partial_add,partial_bad;
 wire core_ready,core_valid,core_out_ready,core_advance,core_busy,core_add;
 wire [3:0] core_mask;wire [63:0] core_values;wire [11:0] core_error;
 wire [127:0] core_tag;wire [1:0] core_dtype;
 wire [1:0] returned_phase=phase_pipe[15:14];
 wire output_available=!out_valid||out_ready;
 wire accepted=core_advance&&pending==0&&in_valid&&output_available;
 wire tuple_bad=core_tag!=partial_tag||core_dtype!=partial_dtype||core_add!=partial_add;
 wire [7:0] complete_mask={core_mask[1:0],partial_mask};
 // Private capacity excludes reset only. Use it under the parent reset branch;
 // public handshake remains reset-qualified and cycle-identical.
 assign in_capacity=!clear&&run_ce&&(!core_valid||core_out_ready)&&pending==0&&output_available;
 assign in_ready=rst_n&&in_capacity;
 assign advance=rst_n&&!clear&&run_ce&&output_available;
 assign busy=core_busy||pending!=0||collected!=0||out_valid;
 assign core_out_ready=returned_phase==collected&&(returned_phase!=3||output_available);

 reg [1:0] selected_mask;reg [63:0] selected_psum,selected_psum_b,selected_bias,selected_ma,selected_mb;
 reg [11:0] selected_shift;
 always @*begin
  selected_mask=in_mask[1:0];selected_psum=in_psum[63:0];selected_psum_b=in_psum_b[63:0];
  selected_bias=in_bias[63:0];selected_ma=in_multiplier[63:0];selected_mb=in_multiplier_b[63:0];selected_shift=in_shift[11:0];
  case(pending)
   1:begin selected_mask=saved_mask[1:0];selected_psum=saved_psum[63:0];selected_psum_b=saved_psum_b[63:0];selected_bias=saved_bias[63:0];selected_ma=saved_ma[63:0];selected_mb=saved_mb[63:0];selected_shift=saved_shift[11:0];end
   2:begin selected_mask=saved_mask[3:2];selected_psum=saved_psum[127:64];selected_psum_b=saved_psum_b[127:64];selected_bias=saved_bias[127:64];selected_ma=saved_ma[127:64];selected_mb=saved_mb[127:64];selected_shift=saved_shift[23:12];end
   3:begin selected_mask=saved_mask[5:4];selected_psum=saved_psum[191:128];selected_psum_b=saved_psum_b[191:128];selected_bias=saved_bias[191:128];selected_ma=saved_ma[191:128];selected_mb=saved_mb[191:128];selected_shift=saved_shift[35:24];end
   default:begin end
  endcase
 end
 b03_quant4_core core(
  .clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(run_ce),
  .in_valid(pending!=0||(in_valid&&output_available)),.in_ready(core_ready),
  .in_mask({2'b00,selected_mask}),.in_psum({64'd0,selected_psum}),.in_psum_b({64'd0,selected_psum_b}),
  .in_add(pending!=0?saved_add:in_add),.in_dtype(pending!=0?saved_dtype:in_dtype),
  .in_bias({64'd0,selected_bias}),.in_multiplier({64'd0,selected_ma}),.in_multiplier_b({64'd0,selected_mb}),
  .in_shift({12'd0,selected_shift}),.in_tag(pending!=0?saved_tag:in_tag),
  .out_valid(core_valid),.out_ready(core_out_ready),.out_mask(core_mask),.out_values(core_values),
  .out_dtype(core_dtype),.out_add(core_add),.out_error(core_error),.out_tag(core_tag),.advance(core_advance),.busy(core_busy)
 );
 // Private payloads are guarded by pending/collected, which clear at CE0 too.
 always @(posedge clk)begin
  if(rst_n&&!clear&&accepted)begin
   saved_mask<=in_mask[7:2];saved_psum<=in_psum[255:64];saved_psum_b<=in_psum_b[255:64];
   saved_bias<=in_bias[255:64];saved_ma<=in_multiplier[255:64];saved_mb<=in_multiplier_b[255:64];
   saved_shift<=in_shift[47:12];saved_tag<=in_tag;saved_dtype<=in_dtype;saved_add<=in_add;
  end
  if(rst_n&&!clear&&core_advance&&core_valid)begin
   case(returned_phase)
    0:begin partial_mask[1:0]<=core_mask[1:0];partial_values[31:0]<=core_values[31:0];partial_error[5:0]<=core_error[5:0];partial_tag<=core_tag;partial_dtype<=core_dtype;partial_add<=core_add;end
    1:begin partial_mask[3:2]<=core_mask[1:0];partial_values[63:32]<=core_values[31:0];partial_error[11:6]<=core_error[5:0];end
    2:begin partial_mask[5:4]<=core_mask[1:0];partial_values[95:64]<=core_values[31:0];partial_error[17:12]<=core_error[5:0];end
    default:begin end
   endcase
  end
 end
 integer lane;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   pending<=0;phase_pipe<=0;collected<=0;partial_bad<=0;out_valid<=0;
   out_mask<=0;out_values<=0;out_dtype<=0;out_add<=0;out_error<=0;out_tag<=0;
  end else if(clear)begin
   pending<=0;phase_pipe<=0;collected<=0;partial_bad<=0;out_valid<=0;
   out_mask<=0;out_values<=0;out_dtype<=0;out_add<=0;out_error<=0;out_tag<=0;
  end else begin
   if(out_valid&&advance)out_valid<=0;
   if(core_advance)begin
    phase_pipe<={phase_pipe[13:0],pending};
    if(pending!=0)pending<=pending==3?2'd0:pending+2'd1;
    else if(in_valid&&output_available)pending<=1;
    if(core_valid)begin
     collected<=returned_phase==3?2'd0:returned_phase+2'd1;
     if(returned_phase==0)partial_bad<=0;
     else partial_bad<=partial_bad||tuple_bad;
     if(returned_phase==3)begin
      out_valid<=1;out_mask<=complete_mask;out_tag<=partial_tag;out_dtype<=partial_dtype;out_add<=partial_add;
      if(partial_bad||tuple_bad)begin
       out_values<=0;
       for(lane=0;lane<8;lane=lane+1)out_error[3*lane+:3]<=complete_mask[lane]?3'd4:3'd0;
      end else begin out_values<={core_values[31:0],partial_values};out_error<={core_error[5:0],partial_error};end
     end
    end
   end
  end
 end
endmodule
