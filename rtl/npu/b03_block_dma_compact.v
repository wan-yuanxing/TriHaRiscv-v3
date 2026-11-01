// Derived from frozen 558280b30219acdcf9f962acd6e907e0f680ab52 rtl/platform/b03_block_dma.v.
// Original imported blob SHA256 c8e7936f60ed4bb9cc72e21eedacb24293ea60a5605816b9b3674c90e14ce21b.
// Pango LUTRAM and first-mismatch byte encoding; protocol/state timing unchanged.
// One serialized local block service around the ordinary session-bridge port.
// Write verification is one same-port observation, not a production RAW fence.
module b03_block_dma_compact #(
    // Zero is valid only behind an adapter whose responses are registered.
    // It removes the command-ready bypass from read/completion qualification.
    parameter integer ALLOW_COMMAND_CYCLE_RESPONSE=1,
    parameter [31:0] INITIAL_ID=1,
    parameter [31:0] TIMEOUT_CYCLES=100000000
)(
    input wire clk,rst_n,cancel_request,bridge_fault,
    input wire [31:0] epoch,
    input wire req_valid,output wire req_ready,input wire req_write,req_verify,
    input wire [31:0] req_offset,req_tag,input wire [4:0] req_beats,input wire [2:0] req_client,
    input wire w_valid,output wire w_ready,input wire [255:0] w_data,input wire [31:0] w_strb,input wire w_last,
    output wire r_valid,input wire r_ready,output wire [255:0] r_data,output wire r_last,
    output reg rsp_valid,input wire rsp_ready,output reg [3:0] rsp_status,output reg [31:0] rsp_tag,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output wire [31:0] cmd_offset,cmd_id,cmd_epoch,output wire [4:0] cmd_beats,output wire [2:0] cmd_client,
    output wire write_valid,input wire write_ready,output wire [255:0] write_data,
    output wire [31:0] write_strb,output wire write_last,
    input wire read_valid,output wire read_ready,input wire [255:0] read_data,input wire read_last,
    input wire mem_done_valid,output wire mem_done_ready,input wire [3:0] mem_done_status,
    input wire [31:0] mem_done_id,mem_done_epoch,input wire [2:0] mem_done_client,
    output reg quarantined,reset_required,output wire abort_req,busy,
    output reg fault_valid,input wire fault_ready,output reg [175:0] fault_payload,
    output wire [3:0] debug_state,output reg [31:0] commands,read_beats,write_beats,
    output reg [31:0] verify_offset,verify_expected,verify_actual
);
    localparam IDLE=0,CHECK=1,COLLECT=2,PLAN=3,OFFER=4,ACTIVE=5,HELD=6,ISOLATED=7;
    reg [3:0] state;
    reg saved_write,saved_verify,verifying,offer_valid,owner,id_exhausted,active,fault_pending;
    reg [31:0] base,tag,saved_epoch,next_id,offered_id,elapsed;
    reg [4:0] beats,collected,sent,received;
    reg [2:0] client;
    wire [287:0] buffer_input={w_strb,w_data};
    wire [287:0] buffer_output;
    wire [255:0] buffer_data=buffer_output[255:0];
    wire [31:0] buffer_mask=buffer_output[287:256];
    // Write dispatch and readback verification are disjoint ownership phases.
    wire [3:0] buffer_address=verifying?received[3:0]:sent[3:0];
    reg buffer_write_enable;
    reg verify_bad;
    wire effective_owner=owner||(ALLOW_COMMAND_CYCLE_RESPONSE&&(cmd_valid&&cmd_ready));
    wire req_fire=req_valid&&req_ready;
    wire local_w_fire=w_valid&&w_ready;
    wire command_fire=cmd_valid&&cmd_ready;
    wire wf=write_valid&&write_ready,rf=read_valid&&read_ready,df=mem_done_valid&&mem_done_ready;
    wire [5:0] r_after={1'b0,received}+{5'b0,rf};
    wire [5:0] w_after={1'b0,sent}+{5'b0,wf};
    wire current_write=saved_write&&!verifying;
    wire done_identity=mem_done_id==offered_id&&mem_done_epoch==saved_epoch&&mem_done_client==client;
    wire bad_r=read_valid&&!quarantined&&(!effective_owner||current_write||received>=beats||
        (rf&&read_last!=(r_after=={1'b0,beats})));
    wire bad_done=mem_done_valid&&!quarantined&&(!effective_owner||!done_identity||mem_done_status!=0||
        (df&&(current_write?w_after:r_after)!={1'b0,beats}));
    wire timed_out=active&&elapsed+1>=TIMEOUT_CYCLES;
    wire transport_fault=!quarantined&&(bad_r||bad_done||(active&&(cancel_request||bridge_fault||epoch!=saved_epoch||timed_out)));
    wire [3:0] reason=bad_r?4'd4:bad_done?(!done_identity?4'd3:mem_done_status!=0?4'd2:4'd4):4'd5;
    wire [32:0] region_end={1'b0,base}+({28'b0,beats}<<5);
    wire legal=base[4:0]==0&&beats>=1&&beats<=16&&region_end<=33'h040000000&&
        ({1'b0,base[11:0]}+({8'd0,beats}<<5))<=4096&&next_id!=0&&!id_exhausted&&
        (!saved_verify||!saved_write||next_id!=32'hffffffff);
    always @*begin
        buffer_write_enable=0;
        if(rst_n&&!quarantined&&!transport_fault&&local_w_fire)begin
            if(w_last!=(collected+1==beats))buffer_write_enable=0;
            else buffer_write_enable=1;
        end
    end
    genvar ram_bit;
    generate for(ram_bit=0;ram_bit<144;ram_bit=ram_bit+1)begin: g_write_buffer
        GTP_RAM32X2DP u_ram (
            .DO(buffer_output[ram_bit*2+:2]), .DI(buffer_input[ram_bit*2+:2]),
            .RADDR({1'b0,buffer_address}), .WADDR({1'b0,collected[3:0]}),
            .WCLK(clk), .WE(buffer_write_enable)
        );
    end endgenerate
    assign req_ready=rst_n&&state==IDLE&&!rsp_valid&&!quarantined&&!fault_valid&&!fault_pending&&
        !cancel_request&&!bridge_fault&&epoch!=0&&!read_valid&&!mem_done_valid;
    assign w_ready=rst_n&&state==COLLECT&&!quarantined&&collected<beats;
    assign cmd_valid=rst_n&&offer_valid;
    assign cmd_offset=base;assign cmd_id=offered_id;assign cmd_epoch=saved_epoch;
    assign cmd_beats=beats;assign cmd_client=client;assign cmd_write=current_write;
    assign write_valid=rst_n&&effective_owner&&current_write&&sent<beats&&(state==ACTIVE||quarantined);
    assign write_data=buffer_data;assign write_strb=buffer_mask;
    assign write_last=sent+1==beats;
    assign r_valid=rst_n&&effective_owner&&!current_write&&!verifying&&read_valid&&!quarantined;
    assign r_data=read_data;assign r_last=read_last;
    assign read_ready=rst_n&&(quarantined||(effective_owner&&!current_write&&(verifying||r_ready)));
    assign mem_done_ready=rst_n&&(effective_owner||quarantined);
    assign abort_req=quarantined&&(offer_valid||owner);
    assign busy=state!=IDLE||rsp_valid;
    assign debug_state=state;
    reg mismatch_now;reg [31:0] bad_byte_offset,bad_expected,bad_actual;
    reg [4:0] bad_byte_index;
    integer b;
    always @*begin
        mismatch_now=0;bad_byte_index=0;bad_byte_offset=0;bad_expected=0;bad_actual=0;
        if(verifying&&rf&&received<beats)begin
            for(b=0;b<32;b=b+1)if(!mismatch_now&&buffer_mask[b]&&
                buffer_data[8*b+:8]!==read_data[8*b+:8])begin
                mismatch_now=1;bad_byte_index=b[4:0];
            end
            if(mismatch_now)begin
                // Concatenate the beat and byte offsets before one 32-bit add.
                bad_byte_offset=base+{22'd0,received,bad_byte_index};
                bad_expected={24'd0,buffer_data[{bad_byte_index,3'b0}+:8]};
                bad_actual={24'd0,read_data[{bad_byte_index,3'b0}+:8]};
            end
        end
    end
    task respond;
        input [3:0] status;
        begin rsp_valid<=1;rsp_status<=status;rsp_tag<=tag;active<=0;state<=HELD;end
    endtask
    task isolate;
        input [3:0] status;
        input have_command;
        begin
            if(!quarantined)begin
                fault_payload<={8'hb4,{have_command,3'b0,current_write,client},
                    have_command?base:32'd0,have_command?offered_id:32'd0,saved_epoch,
                    have_command?{27'd0,beats}:32'd0,
                    have_command?(current_write?{26'd0,w_after}:{26'd0,r_after}):{28'd0,status}};
                fault_pending<=1;
            end
            quarantined<=1;reset_required<=1;state<=ISOLATED;
            if(active)begin rsp_valid<=1;rsp_status<=status;rsp_tag<=tag;active<=0;end
        end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;saved_write<=0;saved_verify<=0;verifying<=0;offer_valid<=0;owner<=0;
            id_exhausted<=INITIAL_ID==0;active<=0;fault_pending<=0;
            base<=0;tag<=0;saved_epoch<=0;next_id<=INITIAL_ID;offered_id<=0;elapsed<=0;
            beats<=0;collected<=0;sent<=0;received<=0;client<=0;verify_bad<=0;
            rsp_valid<=0;rsp_status<=0;rsp_tag<=0;quarantined<=0;reset_required<=0;
            fault_valid<=0;fault_payload<=0;commands<=0;read_beats<=0;write_beats<=0;
            verify_offset<=0;verify_expected<=0;verify_actual<=0;
        end else begin
            if(fault_valid&&fault_ready)fault_valid<=0;
            if(fault_pending)begin fault_pending<=0;fault_valid<=1;end
            if(rsp_valid&&rsp_ready)begin rsp_valid<=0;if(!quarantined)state<=IDLE;end
            if(active)elapsed<=elapsed+1;
            if(req_fire)begin
                saved_write<=req_write;saved_verify<=req_verify;verifying<=0;base<=req_offset;tag<=req_tag;
                saved_epoch<=epoch;beats<=req_beats;client<=req_client;
                collected<=0;sent<=0;received<=0;verify_bad<=0;active<=1;elapsed<=0;state<=CHECK;
                verify_offset<=0;verify_expected<=0;verify_actual<=0;
            end
            if(command_fire)begin
                offer_valid<=0;owner<=1;commands<=commands+1;received<=0;sent<=0;
                if(next_id==32'hffffffff)id_exhausted<=1;else next_id<=next_id+1;
                if(!quarantined)state<=ACTIVE;
            end
            if(wf)begin sent<=sent+1;write_beats<=write_beats+1;end
            if(rf)begin received<=received+1;read_beats<=read_beats+1;end
            if(mismatch_now&&!verify_bad)begin
                verify_bad<=1;verify_offset<=bad_byte_offset;verify_expected<=bad_expected;verify_actual<=bad_actual;
            end
            if(!quarantined&&!transport_fault)begin
                case(state)
                CHECK:if(!legal)respond(1);else if(saved_write)state<=COLLECT;else state<=PLAN;
                COLLECT:if(local_w_fire)begin
                    if(w_last!=(collected+1==beats))isolate(4,1'b0);
                    else begin
                        collected<=collected+1;
                        if(collected+1==beats)state<=PLAN;
                    end
                end
                PLAN:begin offered_id<=next_id;offer_valid<=1;state<=OFFER;end
                default:begin end
                endcase
                if(df&&effective_owner&&!bad_done&&!bad_r)begin
                    owner<=0;
                    if(current_write&&saved_verify)begin verifying<=1;received<=0;sent<=0;state<=PLAN;end
                    else if(verifying&&(verify_bad||mismatch_now))begin respond(6);isolate(6,1'b0);end
                    else respond(0);
                end
            end
            // Isolation cannot turn a wrong/short/error completion into a
            // retired command. Keep that transport debt until session reset.
            if(quarantined&&df&&effective_owner&&done_identity&&mem_done_status==0&&
                (current_write?w_after:r_after)=={1'b0,beats})owner<=0;
            if(transport_fault)isolate(reason,effective_owner);
        end
    end
endmodule
