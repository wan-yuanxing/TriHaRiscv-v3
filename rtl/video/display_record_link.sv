`timescale 1ns/1ps
`default_nettype none
// Join actual scanner/output proofs. The owner holds cmd_data unchanged from
// command acceptance through feedback acceptance. Local retirement is not FREE.
module display_record_link(
 input wire clk,reset_n,cmd_valid,output wire cmd_ready,input wire cmd_mode_only,
 input wire [1:0] cmd_slot,cmd_mode,
 input wire [31:0] cmd_frame,cmd_generation,cmd_base,cmd_stride,cmd_seq,input wire [5119:0] cmd_data,
 output wire record_valid,input wire record_ready,output wire [31:0] record_base,record_stride,record_frame,record_generation,output wire [1:0] record_slot,
 output wire r_cmd_valid,input wire r_cmd_ready,output wire [1:0] r_cmd_mode,r_cmd_slot,
 output wire [31:0] r_cmd_frame,r_cmd_generation,r_cmd_seq,output wire [5119:0] r_cmd_data,
 input wire raw_commit_valid,output wire raw_commit_ready,input wire [31:0] raw_commit_frame,raw_commit_generation,input wire [1:0] raw_commit_slot,
 input wire raw_release_valid,output wire raw_release_ready,input wire [31:0] raw_release_frame,raw_release_generation,input wire [1:0] raw_release_slot,
 input wire p_commit_valid,output wire p_commit_ready,input wire [1:0] p_commit_mode,p_commit_slot,
 input wire [31:0] p_commit_frame,p_commit_generation,p_commit_seq,
 input wire p_retire_valid,output wire p_retire_ready,input wire p_retire_raw,p_retire_asset,input wire [1:0] p_retire_slot,
 input wire [31:0] p_retire_frame,p_retire_generation,p_retire_seq,p_retire_asset_id,p_retire_asset_generation,
 output wire feedback_valid,input wire feedback_ready,output wire [1:0] feedback_slot,feedback_mode,
 output wire [31:0] feedback_frame,feedback_generation,feedback_seq,
 output reg retire_valid,input wire retire_ready,output reg [1:0] retire_slot,output reg [31:0] retire_frame,retire_generation,
 output reg asset_retire_valid,input wire asset_retire_ready,output reg [1:0] asset_retire_slot,
 output reg [31:0] asset_retire_frame,asset_retire_generation,asset_retire_seq,asset_retire_id,asset_retire_generation_id,
 input wire raw_error,renderer_fault,output reg fault,output reg [7:0] fault_code
);
 localparam [2:0] IDLE=0,PIXEL_OFFER=1,RAW_OFFER=2,WAIT_PROOFS=3,FEEDBACK=4;
 reg [2:0] state;reg mode_only,raw_seen,pixel_seen,active_valid;
 reg [1:0] slot,mode,active_slot;reg [31:0] frame,generation,base,stride,seq;
 reg [31:0] active_frame,active_generation;
 reg [2:0] leased,raw_done,pixels_done;
 reg [31:0] frames[0:2],generations[0:2];
 reg pixel_active,pixel_has_asset,retire_expected,expected_raw,expected_asset;
 reg [1:0] pixel_slot,expected_slot;
 reg [31:0] pixel_frame,pixel_generation,pixel_seq,pixel_asset_id,pixel_asset_generation;
 reg [31:0] expected_frame,expected_generation,expected_seq,expected_asset_id,expected_asset_generation;
 reg pending_has_asset;reg [31:0] pending_asset_id,pending_asset_generation;
 wire old_raw_done=pixel_active&&{pixel_slot,pixel_frame,pixel_generation}!=={slot,frame,generation};
 wire old_asset_done=pixel_active&&pixel_has_asset&&(!pending_has_asset||
   {pixel_asset_id,pixel_asset_generation}!=={pending_asset_id,pending_asset_generation});
 assign record_valid=reset_n&&state==RAW_OFFER;
 assign record_base=base;assign record_stride=stride;assign record_frame=frame;assign record_generation=generation;assign record_slot=slot;
 assign r_cmd_valid=reset_n&&state==PIXEL_OFFER;
 assign r_cmd_mode=mode;assign r_cmd_slot=slot;assign r_cmd_frame=frame;assign r_cmd_generation=generation;assign r_cmd_seq=seq;assign r_cmd_data=cmd_data;
 assign feedback_valid=reset_n&&state==FEEDBACK;
 assign feedback_slot=slot;assign feedback_mode=mode;assign feedback_frame=frame;assign feedback_generation=generation;assign feedback_seq=seq;
 assign cmd_ready=reset_n&&state==IDLE&&!fault&&!retire_valid&&raw_error===1'b0&&renderer_fault===1'b0&&
   raw_commit_valid===1'b0&&p_commit_valid===1'b0;
 assign raw_commit_ready=reset_n&&!fault;
 assign p_commit_ready=reset_n&&!fault;
 assign raw_release_ready=reset_n&&!fault;
 assign p_retire_ready=reset_n&&!fault&&!asset_retire_valid;
 wire raw_match=state==WAIT_PROOFS&&!mode_only&&!raw_seen&&
   {raw_commit_slot,raw_commit_frame,raw_commit_generation}==={slot,frame,generation};
 wire [99:0] pixel_identity_in={p_commit_slot,p_commit_mode,p_commit_frame,p_commit_generation,p_commit_seq};
 wire [99:0] pixel_identity_expected={slot,mode,frame,generation,seq};
 wire [6:0] pixel_identity_equal /* synthesis syn_keep=1 */;
 genvar identity_lane;
 generate for(identity_lane=0;identity_lane<6;identity_lane=identity_lane+1)begin : g_pixel_identity
  assign pixel_identity_equal[identity_lane]=pixel_identity_in[identity_lane*16+:16]===pixel_identity_expected[identity_lane*16+:16];
 end endgenerate
 assign pixel_identity_equal[6]=pixel_identity_in[99:96]===pixel_identity_expected[99:96];
 wire pixel_match=state==WAIT_PROOFS&&!pixel_seen&&(&pixel_identity_equal);
 reg release_match,pixels_match;reg [7:0] fault_now;integer k;
 always @* begin
  release_match=0;pixels_match=0;
  if((^{raw_release_slot,raw_release_frame,raw_release_generation})!==1'bx&&raw_release_slot<3)
   release_match=leased[raw_release_slot]&&!raw_done[raw_release_slot]&&
    {raw_release_frame,raw_release_generation}==={frames[raw_release_slot],generations[raw_release_slot]};
  if((^{p_retire_slot,p_retire_frame,p_retire_generation,p_retire_raw,p_retire_asset,p_retire_seq,p_retire_asset_id,p_retire_asset_generation})!==1'bx&&p_retire_slot<3)
   pixels_match=retire_expected&&leased[p_retire_slot]&&(!p_retire_raw||!pixels_done[p_retire_slot])&&
    {p_retire_slot,p_retire_frame,p_retire_generation,p_retire_seq,p_retire_raw,p_retire_asset,p_retire_asset_id,p_retire_asset_generation}===
    {expected_slot,expected_frame,expected_generation,expected_seq,expected_raw,expected_asset,expected_asset_id,expected_asset_generation};
  fault_now=0;
  if(raw_error!==1'b0)fault_now=1;
  else if(renderer_fault!==1'b0)fault_now=2;
  else if(raw_commit_valid===1'b1&&!raw_match)fault_now=3;
  else if(p_commit_valid===1'b1&&(!pixel_match||retire_expected))fault_now=4;
  else if(raw_release_valid===1'b1&&!release_match)fault_now=5;
  else if(p_retire_valid===1'b1&&!pixels_match)fault_now=6;
  else if(cmd_valid&&cmd_ready)begin
   if((^{cmd_mode_only,cmd_slot,cmd_mode,cmd_frame,cmd_generation,cmd_base,cmd_stride,cmd_seq})===1'bx||
    cmd_slot>2||cmd_mode>2||cmd_frame==0||cmd_stride!=2400||cmd_base!=32'h82000000+{30'd0,cmd_slot}*32'h200000)fault_now=7;
   else if(cmd_mode_only)begin
    if(!active_valid||{cmd_slot,cmd_frame,cmd_generation}!=={active_slot,active_frame,active_generation})fault_now=8;
   end else if(leased[cmd_slot])fault_now=9;
  end
  if(fault_now==0&&((raw_commit_valid!==1'b0&&raw_commit_valid!==1'b1)||
   (raw_release_valid!==1'b0&&raw_release_valid!==1'b1)||(p_commit_valid!==1'b0&&p_commit_valid!==1'b1)||
   (p_retire_valid!==1'b0&&p_retire_valid!==1'b1)||(cmd_valid!==1'b0&&cmd_valid!==1'b1)))fault_now=10;
 end
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   state<=IDLE;mode_only<=0;raw_seen<=0;pixel_seen<=0;active_valid<=0;active_slot<=0;active_frame<=0;active_generation<=0;
   slot<=0;mode<=0;frame<=0;generation<=0;base<=0;stride<=0;seq<=0;leased<=0;raw_done<=0;pixels_done<=0;
   retire_valid<=0;retire_slot<=0;retire_frame<=0;retire_generation<=0;asset_retire_valid<=0;asset_retire_slot<=0;
   asset_retire_frame<=0;asset_retire_generation<=0;asset_retire_seq<=0;asset_retire_id<=0;asset_retire_generation_id<=0;
   fault<=0;fault_code<=0;for(k=0;k<3;k=k+1)begin frames[k]<=0;generations[k]<=0;end
   pixel_active<=0;pixel_has_asset<=0;retire_expected<=0;expected_raw<=0;expected_asset<=0;pixel_slot<=0;expected_slot<=0;
   pixel_frame<=0;pixel_generation<=0;pixel_seq<=0;pixel_asset_id<=0;pixel_asset_generation<=0;
   expected_frame<=0;expected_generation<=0;expected_seq<=0;expected_asset_id<=0;expected_asset_generation<=0;
   pending_has_asset<=0;pending_asset_id<=0;pending_asset_generation<=0;
  end else begin
   if(!fault&&fault_now!=0)begin fault<=1;fault_code<=fault_now;end
   if(asset_retire_valid&&asset_retire_ready)asset_retire_valid<=0;
   if(retire_valid&&retire_ready)begin retire_valid<=0;leased[retire_slot]<=0;end
   if(!retire_valid&&!fault&&fault_now==0)begin
    // One candidate at a time; published payload is immutable until accepted.
    if(leased[0]&&raw_done[0]&&pixels_done[0]&&active_valid&&active_slot!=0)begin retire_valid<=1;retire_slot<=0;retire_frame<=frames[0];retire_generation<=generations[0];end
    else if(leased[1]&&raw_done[1]&&pixels_done[1]&&active_valid&&active_slot!=1)begin retire_valid<=1;retire_slot<=1;retire_frame<=frames[1];retire_generation<=generations[1];end
    else if(leased[2]&&raw_done[2]&&pixels_done[2]&&active_valid&&active_slot!=2)begin retire_valid<=1;retire_slot<=2;retire_frame<=frames[2];retire_generation<=generations[2];end
   end
   if(!fault&&fault_now==0)begin
    if(raw_commit_valid&&raw_commit_ready)raw_seen<=1;
    if(p_commit_valid&&p_commit_ready)begin
     pixel_seen<=1;pixel_active<=1;pixel_has_asset<=pending_has_asset;pixel_slot<=slot;pixel_frame<=frame;pixel_generation<=generation;pixel_seq<=seq;
     pixel_asset_id<=pending_asset_id;pixel_asset_generation<=pending_asset_generation;
     if(old_raw_done||old_asset_done)begin retire_expected<=1;expected_raw<=old_raw_done;expected_asset<=old_asset_done;
      expected_slot<=pixel_slot;expected_frame<=pixel_frame;expected_generation<=pixel_generation;expected_seq<=pixel_seq;
      expected_asset_id<=pixel_asset_id;expected_asset_generation<=pixel_asset_generation;end
    end
    if(raw_release_valid&&raw_release_ready)raw_done[raw_release_slot]<=1;
    if(p_retire_valid&&p_retire_ready)begin
     retire_expected<=0;
     if(p_retire_raw)pixels_done[p_retire_slot]<=1;
     if(p_retire_asset)begin asset_retire_valid<=1;asset_retire_slot<=p_retire_slot;asset_retire_frame<=p_retire_frame;
      asset_retire_generation<=p_retire_generation;asset_retire_seq<=p_retire_seq;asset_retire_id<=p_retire_asset_id;asset_retire_generation_id<=p_retire_asset_generation;end
    end
   end
   case(state)
    IDLE:if(cmd_valid&&cmd_ready&&fault_now==0)begin
     slot<=cmd_slot;mode<=cmd_mode;frame<=cmd_frame;generation<=cmd_generation;base<=cmd_base;stride<=cmd_stride;seq<=cmd_seq;
     mode_only<=cmd_mode_only;raw_seen<=cmd_mode_only;pixel_seen<=0;state<=PIXEL_OFFER;
     pending_has_asset<=cmd_mode==2&&!cmd_data[9*32+1]&&cmd_data[9*32+3]&&cmd_data[9*32+4];
     pending_asset_id<=cmd_data[14*32+:32];pending_asset_generation<=cmd_data[15*32+:32];
     if(!cmd_mode_only)begin leased[cmd_slot]<=1;raw_done[cmd_slot]<=0;pixels_done[cmd_slot]<=0;frames[cmd_slot]<=cmd_frame;generations[cmd_slot]<=cmd_generation;end
    end
    PIXEL_OFFER:if(r_cmd_ready)begin if(mode_only||fault||fault_now!=0)state<=WAIT_PROOFS;else state<=RAW_OFFER;end
    RAW_OFFER:if(record_ready)state<=WAIT_PROOFS;
    WAIT_PROOFS:if(raw_seen&&pixel_seen&&!fault&&fault_now==0)state<=FEEDBACK;
    FEEDBACK:if(feedback_ready)begin active_valid<=1;active_slot<=slot;active_frame<=frame;active_generation<=generation;state<=IDLE;end
    default:begin end
   endcase
  end
 end
endmodule
`default_nettype wire
