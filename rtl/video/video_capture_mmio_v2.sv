`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
`include "video_capture_v2.vh"
// Same-clock AXI4-Lite capture endpoint. A coordinated reset owns all DMA and
// ingress reset. Explicit REARM is control reuse after software event ACK,
// never a local reset, DDR visibility fence or global slot allocation.
// capture_* metadata/count inputs mirror video_three_branch_capture's held
// accepted/completion records. accepted samples only identity and bases;
// completion additionally samples all counts, CRCs and FIFO peak.
module video_capture_mmio_v2 #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,PAD_TOP=40,PAD_BOTTOM=40
)(
    input wire clk_i,rst_ni,
    input wire [31:0] s_axi_awaddr_i,input wire [2:0] s_axi_awprot_i,
    input wire s_axi_awvalid_i,output wire s_axi_awready_o,
    input wire [31:0] s_axi_wdata_i,input wire [3:0] s_axi_wstrb_i,
    input wire s_axi_wvalid_i,output wire s_axi_wready_o,
    output reg [1:0] s_axi_bresp_o,output reg s_axi_bvalid_o,input wire s_axi_bready_i,
    input wire [31:0] s_axi_araddr_i,input wire [2:0] s_axi_arprot_i,
    input wire s_axi_arvalid_i,output wire s_axi_arready_o,
    output reg [31:0] s_axi_rdata_o,output reg [1:0] s_axi_rresp_o,
    output reg s_axi_rvalid_o,input wire s_axi_rready_i,
    output reg capture_req_valid_o,input wire capture_req_ready_i,
    output reg [1:0] capture_req_slot_o,
    output reg [31:0] capture_req_frame_id_o,capture_req_version_o,capture_req_generation_o,
    input wire accepted_valid_i,output wire accepted_ready_o,
    input wire completion_valid_i,output wire completion_ready_o,
    input wire completion_success_i,input wire [7:0] completion_code_i,
    input wire [1:0] capture_slot_i,
    input wire [31:0] capture_frame_id_i,capture_version_i,
    input wire [31:0] capture_raw_base_i,capture_preview_base_i,capture_input_base_i,
    input wire [31:0] capture_raw_pixels_i,capture_preview_pixels_i,capture_input_pixels_i,
    input wire [31:0] capture_raw_bytes_i,capture_preview_bytes_i,capture_input_bytes_i,
    input wire [31:0] capture_raw_crc_i,capture_preview_crc_i,capture_fifo_peak_i,
    input wire capture_live_fault_i,input wire [7:0] capture_live_code_i,
    input wire capture_port_drained_i,output wire capture_abort_o,irq_o
);
    localparam [1:0] OKAY=0,SLVERR=2,DECERR=3;
    localparam [7:0] PROTOCOL_ERROR=8'he1;
    localparam integer RAW_STRIDE=(FRAME_WIDTH*3+15)/16*16;
    localparam integer PREVIEW_STRIDE=(FRAME_WIDTH/2*3+15)/16*16;
    localparam integer INPUT_WIDTH=FRAME_WIDTH*2/5;
    localparam integer INPUT_HEIGHT=FRAME_HEIGHT*2/5+PAD_TOP+PAD_BOTTOM;
    localparam integer INPUT_STRIDE=(INPUT_WIDTH+15)/16*16;
    reg aw_full,w_full;
    reg [31:0] awaddr,wdata;
    reg [3:0] wstrb;
    reg enabled,shot_used,dispatched,accepted_pending,completion_pending;
    reg accepted_seen,completion_seen,sticky_fault;
    reg [7:0] first_error;
    reg [2:0] irq_mask,irq_pending;
    reg [1:0] shadow_slot,accepted_slot,completed_slot;
    reg [31:0] shadow_frame,shadow_version,shadow_generation;
    reg [31:0] accepted_generation,completed_generation;
    reg completed_drained;
    reg [31:0] accepted_frame,accepted_version,accepted_raw,accepted_preview,accepted_input;
    reg [31:0] completed_frame,completed_version,completed_raw,completed_preview,completed_input;
    reg completed_success;
    reg [7:0] completed_code;
    reg [31:0] completed_raw_pixels,completed_preview_pixels,completed_input_pixels;
    reg [31:0] completed_raw_bytes,completed_preview_bytes,completed_input_bytes;
    reg [31:0] completed_raw_crc,completed_preview_crc,completed_fifo_peak;
    wire rearm_allowed=shot_used && dispatched && completion_seen && completed_success &&
        !accepted_pending && !completion_pending && !capture_req_valid_o && !sticky_fault &&
        capture_live_fault_i===1'b0 && capture_port_drained_i===1'b1 && capture_req_ready_i===1'b1 &&
        accepted_valid_i===1'b0 && completion_valid_i===1'b0;
    wire [31:0] status_word={22'd0,capture_req_ready_i,rearm_allowed,capture_port_drained_i,sticky_fault,completion_pending,
        accepted_pending,dispatched,capture_req_valid_o,shot_used,enabled};
    assign s_axi_awready_o=rst_ni&&!aw_full&&!s_axi_bvalid_o;
    assign s_axi_wready_o=rst_ni&&!w_full&&!s_axi_bvalid_o;
    assign s_axi_arready_o=rst_ni&&!s_axi_rvalid_o;
    assign accepted_ready_o=rst_ni&&!accepted_pending;
    assign completion_ready_o=rst_ni&&!completion_pending;
    assign capture_abort_o=sticky_fault;
    assign irq_o=|(irq_pending&irq_mask);
    function automatic [31:0] raw_address(input [1:0] which);
        case(which)
            0:raw_address=`VIDEO_FRAME_SLOT_A;
            1:raw_address=`VIDEO_FRAME_SLOT_B;
            2:raw_address=`VIDEO_FRAME_SLOT_C;
            default:raw_address=0;
        endcase
    endfunction
    function automatic [31:0] input_address(input [1:0] which);
        case(which)
            0:input_address=`VIDEO_INPUT_SLOT_A;
            1:input_address=`VIDEO_INPUT_SLOT_B;
            2:input_address=`VIDEO_INPUT_SLOT_C;
            default:input_address=0;
        endcase
    endfunction
    function automatic [31:0] byte_mask(input [3:0] strobes);
        byte_mask={{8{strobes[3]}},{8{strobes[2]}},{8{strobes[1]}},{8{strobes[0]}}};
    endfunction
    function automatic valid_address(input [31:0] address);
        valid_address=(^address)!==1'bx&&address>=`VCAP_MMIO_BASE&&
            (64'd0+address)<(64'd0+`VCAP_MMIO_BASE+`VCAP_MMIO_BYTES)&&address[1:0]===2'b00;
    endfunction
    wire [31:0] write_offset=awaddr-`VCAP_MMIO_BASE;
    wire [31:0] mask_word=byte_mask(wstrb);
    wire execute_write=aw_full&&w_full&&!s_axi_bvalid_o;
    reg [1:0] write_response;
    reg do_control,do_mask,do_ack,do_slot,do_frame,do_version,do_command,do_generation,do_rearm;
    reg [31:0] write_merged;
    reg [2:0] ack_bits;
    // First validate the address and all accepted transport payload, including
    // unknown bytes outside WSTRB. No partially executed invalid write exists.
    always @* begin
        write_response=OKAY;write_merged=0;
        do_control=0;do_mask=0;do_ack=0;do_slot=0;do_frame=0;do_version=0;do_command=0;do_generation=0;do_rearm=0;ack_bits=0;
        if(!valid_address(awaddr))write_response=DECERR;
        else if((^wdata)===1'bx||(^wstrb)===1'bx)write_response=SLVERR;
        else case(write_offset)
            `VCAP_REG_CONTROL:begin
                write_merged=({31'd0,enabled}&~mask_word)|(wdata&mask_word);
                if(wstrb!=0)begin
                    if(shot_used||write_merged[31:1]!=0)write_response=SLVERR;
                    else do_control=1;
                end
            end
            `VCAP_REG_IRQ_MASK:begin
                write_merged=({29'd0,irq_mask}&~mask_word)|(wdata&mask_word);
                if(wstrb!=0)begin if(write_merged[31:3]!=0)write_response=SLVERR;else do_mask=1;end
            end
            `VCAP_REG_IRQ_PENDING:begin
                write_merged=wdata&mask_word;
                if(write_merged[31:3]!=0)write_response=SLVERR;
                else begin do_ack=1;ack_bits=write_merged[2:0];end
            end
            `VCAP_REG_REQUEST_SLOT:begin
                write_merged=({30'd0,shadow_slot}&~mask_word)|(wdata&mask_word);
                if(wstrb!=0)begin if(shot_used||write_merged[31:2]!=0)write_response=SLVERR;else do_slot=1;end
            end
            `VCAP_REG_REQUEST_FRAME_ID:begin
                write_merged=(shadow_frame&~mask_word)|(wdata&mask_word);
                if(wstrb!=0)begin if(shot_used)write_response=SLVERR;else do_frame=1;end
            end
            `VCAP_REG_REQUEST_VERSION:begin
                write_merged=(shadow_version&~mask_word)|(wdata&mask_word);
                if(wstrb!=0)begin if(shot_used)write_response=SLVERR;else do_version=1;end
            end
            `VCAP_REG_REQUEST_GENERATION:begin
                write_merged=(shadow_generation&~mask_word)|(wdata&mask_word);
                if(wstrb!=0)begin if(shot_used)write_response=SLVERR;else do_generation=1;end
            end
            `VCAP_REG_REARM:begin
                if(wstrb!=0)begin
                    if(wstrb!=15||(wdata!=0&&wdata!=1))write_response=SLVERR;
                    else if(wdata==1)begin
                        if(rearm_allowed!==1'b1)write_response=SLVERR;
                        else do_rearm=1;
                    end
                end
            end
            `VCAP_REG_CAPTURE_REQUEST:begin
                if(wstrb!=0)begin
                    if(wstrb!=15||(wdata!=0&&wdata!=1))write_response=SLVERR;
                    else if(wdata==1)begin
                        if(!enabled||shot_used||sticky_fault||capture_live_fault_i!==1'b0||
                            shadow_slot==3||shadow_frame==0||shadow_version!=`VIDEO_INPUT_PREPROCESS_VERSION)write_response=SLVERR;
                        else do_command=1;
                    end
                end
            end
            `VCAP_REG_VERSION,`VCAP_REG_CAPABILITIES,`VCAP_REG_STATUS,`VCAP_REG_ERROR_CODE,
            `VCAP_REG_CAPTURE_STATUS,`VCAP_REG_ACCEPTED_FRAME_ID,`VCAP_REG_COMPLETED_FRAME_ID,
            `VCAP_REG_REQUEST_RAW_BASE,`VCAP_REG_REQUEST_PREVIEW_BASE,`VCAP_REG_REQUEST_INPUT_BASE,
            `VCAP_REG_RAW_STRIDE,`VCAP_REG_PREVIEW_STRIDE,`VCAP_REG_INPUT_STRIDE,
            `VCAP_REG_FRAME_WIDTH,`VCAP_REG_FRAME_HEIGHT,`VCAP_REG_INPUT_WIDTH,`VCAP_REG_INPUT_HEIGHT,
            `VCAP_REG_ACCEPTED_SLOT,`VCAP_REG_ACCEPTED_FRAME_ID_RECORD,`VCAP_REG_ACCEPTED_VERSION,
            `VCAP_REG_ACCEPTED_RAW_BASE,`VCAP_REG_ACCEPTED_PREVIEW_BASE,`VCAP_REG_ACCEPTED_INPUT_BASE,
            `VCAP_REG_COMPLETED_SLOT,`VCAP_REG_COMPLETED_FRAME_ID_RECORD,`VCAP_REG_COMPLETED_VERSION,
            `VCAP_REG_COMPLETED_RESULT,`VCAP_REG_COMPLETED_RAW_BASE,`VCAP_REG_COMPLETED_PREVIEW_BASE,
            `VCAP_REG_COMPLETED_INPUT_BASE,`VCAP_REG_COMPLETED_RAW_PIXELS,`VCAP_REG_COMPLETED_PREVIEW_PIXELS,
            `VCAP_REG_COMPLETED_INPUT_PIXELS,`VCAP_REG_COMPLETED_RAW_BYTES,`VCAP_REG_COMPLETED_PREVIEW_BYTES,
            `VCAP_REG_COMPLETED_INPUT_BYTES,`VCAP_REG_COMPLETED_RAW_CRC,`VCAP_REG_COMPLETED_PREVIEW_CRC,
            `VCAP_REG_COMPLETED_FIFO_PEAK,`VCAP_REG_ACCEPTED_GENERATION,
            `VCAP_REG_COMPLETED_GENERATION,`VCAP_REG_COMPLETED_DRAINED:write_response=SLVERR;
            default:write_response=DECERR;
        endcase
    end
    reg [31:0] read_word;
    reg [1:0] read_response;
    always @* begin
        read_word=0;read_response=OKAY;
        if(!valid_address(s_axi_araddr_i))read_response=DECERR;
        else case(s_axi_araddr_i-`VCAP_MMIO_BASE)
            `VCAP_REG_VERSION:read_word=`VCAP_ABI_VERSION;
            `VCAP_REG_CAPABILITIES:read_word=`VCAP_CAPABILITIES;
            `VCAP_REG_CONTROL:read_word={31'd0,enabled};
            `VCAP_REG_STATUS,`VCAP_REG_CAPTURE_STATUS:read_word=status_word;
            `VCAP_REG_IRQ_MASK:read_word={29'd0,irq_mask};
            `VCAP_REG_IRQ_PENDING:read_word={29'd0,irq_pending};
            `VCAP_REG_ERROR_CODE:read_word={24'd0,first_error};
            `VCAP_REG_CAPTURE_REQUEST,`VCAP_REG_REARM:read_response=SLVERR;
            `VCAP_REG_REQUEST_GENERATION:read_word=shadow_generation;
            `VCAP_REG_ACCEPTED_GENERATION:read_word=accepted_generation;
            `VCAP_REG_COMPLETED_GENERATION:read_word=completed_generation;
            `VCAP_REG_COMPLETED_DRAINED:read_word={31'd0,completed_drained};
            `VCAP_REG_ACCEPTED_FRAME_ID,`VCAP_REG_ACCEPTED_FRAME_ID_RECORD:read_word=accepted_frame;
            `VCAP_REG_COMPLETED_FRAME_ID,`VCAP_REG_COMPLETED_FRAME_ID_RECORD:read_word=completed_frame;
            `VCAP_REG_REQUEST_SLOT:read_word={30'd0,shadow_slot};
            `VCAP_REG_REQUEST_FRAME_ID:read_word=shadow_frame;
            `VCAP_REG_REQUEST_VERSION:read_word=shadow_version;
            `VCAP_REG_REQUEST_RAW_BASE:read_word=raw_address(shadow_slot);
            `VCAP_REG_REQUEST_PREVIEW_BASE:read_word=shadow_slot==3?32'd0:raw_address(shadow_slot)+`VIDEO_FRAME_PREVIEW_OFFSET;
            `VCAP_REG_REQUEST_INPUT_BASE:read_word=input_address(shadow_slot);
            `VCAP_REG_RAW_STRIDE:read_word=RAW_STRIDE;
            `VCAP_REG_PREVIEW_STRIDE:read_word=PREVIEW_STRIDE;
            `VCAP_REG_INPUT_STRIDE:read_word=INPUT_STRIDE;
            `VCAP_REG_FRAME_WIDTH:read_word=FRAME_WIDTH;
            `VCAP_REG_FRAME_HEIGHT:read_word=FRAME_HEIGHT;
            `VCAP_REG_INPUT_WIDTH:read_word=INPUT_WIDTH;
            `VCAP_REG_INPUT_HEIGHT:read_word=INPUT_HEIGHT;
            `VCAP_REG_ACCEPTED_SLOT:read_word={30'd0,accepted_slot};
            `VCAP_REG_ACCEPTED_VERSION:read_word=accepted_version;
            `VCAP_REG_ACCEPTED_RAW_BASE:read_word=accepted_raw;
            `VCAP_REG_ACCEPTED_PREVIEW_BASE:read_word=accepted_preview;
            `VCAP_REG_ACCEPTED_INPUT_BASE:read_word=accepted_input;
            `VCAP_REG_COMPLETED_SLOT:read_word={30'd0,completed_slot};
            `VCAP_REG_COMPLETED_VERSION:read_word=completed_version;
            `VCAP_REG_COMPLETED_RESULT:read_word={16'd0,completed_code,7'd0,completed_success};
            `VCAP_REG_COMPLETED_RAW_BASE:read_word=completed_raw;
            `VCAP_REG_COMPLETED_PREVIEW_BASE:read_word=completed_preview;
            `VCAP_REG_COMPLETED_INPUT_BASE:read_word=completed_input;
            `VCAP_REG_COMPLETED_RAW_PIXELS:read_word=completed_raw_pixels;
            `VCAP_REG_COMPLETED_PREVIEW_PIXELS:read_word=completed_preview_pixels;
            `VCAP_REG_COMPLETED_INPUT_PIXELS:read_word=completed_input_pixels;
            `VCAP_REG_COMPLETED_RAW_BYTES:read_word=completed_raw_bytes;
            `VCAP_REG_COMPLETED_PREVIEW_BYTES:read_word=completed_preview_bytes;
            `VCAP_REG_COMPLETED_INPUT_BYTES:read_word=completed_input_bytes;
            `VCAP_REG_COMPLETED_RAW_CRC:read_word=completed_raw_crc;
            `VCAP_REG_COMPLETED_PREVIEW_CRC:read_word=completed_preview_crc;
            `VCAP_REG_COMPLETED_FIFO_PEAK:read_word=completed_fifo_peak;
            default:read_response=DECERR;
        endcase
    end
    wire accepted_take=accepted_valid_i===1'b1&&accepted_ready_o;
    wire completion_take=completion_valid_i===1'b1&&completion_ready_o;
    wire identity_good=(^({capture_slot_i,capture_frame_id_i,capture_version_i,capture_raw_base_i,
        capture_preview_base_i,capture_input_base_i}))!==1'bx&&
        capture_slot_i===capture_req_slot_o&&capture_frame_id_i===capture_req_frame_id_o&&
        capture_version_i===capture_req_version_o&&capture_raw_base_i===raw_address(capture_req_slot_o)&&
        capture_preview_base_i===(raw_address(capture_req_slot_o)+`VIDEO_FRAME_PREVIEW_OFFSET)&&
        capture_input_base_i===input_address(capture_req_slot_o);
    wire accepted_good=shot_used&&dispatched&&!accepted_seen&&!completion_seen&&identity_good;
    wire completion_known=(^({completion_success_i,completion_code_i,capture_raw_pixels_i,capture_preview_pixels_i,
        capture_input_pixels_i,capture_raw_bytes_i,capture_preview_bytes_i,capture_input_bytes_i,
        capture_raw_crc_i,capture_preview_crc_i,capture_fifo_peak_i}))!==1'bx;
    wire success_counts_good=capture_raw_pixels_i===FRAME_WIDTH*FRAME_HEIGHT &&
        capture_preview_pixels_i===(FRAME_WIDTH*FRAME_HEIGHT/4) &&
        capture_input_pixels_i===(INPUT_WIDTH*(FRAME_HEIGHT*2/5)) &&
        capture_raw_bytes_i===(FRAME_WIDTH*FRAME_HEIGHT*3) &&
        capture_preview_bytes_i===(FRAME_WIDTH*FRAME_HEIGHT/4*3) &&
        capture_input_bytes_i===(INPUT_WIDTH*INPUT_HEIGHT*3) &&
        capture_fifo_peak_i>=1 && capture_fifo_peak_i<=2048;
    wire completion_good=shot_used&&dispatched&&!completion_seen&&identity_good&&completion_known&&capture_port_drained_i===1'b1&&
        (completion_success_i?(success_counts_good&&completion_code_i==0&&(accepted_seen||(accepted_take&&accepted_good))):completion_code_i!=0);
    wire protocol_fault=(accepted_take&&!accepted_good)||(completion_take&&!completion_good);
    wire failed_completion=completion_take&&completion_good&&!completion_success_i;
    wire live_fault=capture_live_fault_i!==1'b0;
    wire [7:0] live_code=((^capture_live_code_i)===1'bx||capture_live_code_i==0)?PROTOCOL_ERROR:capture_live_code_i;
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            aw_full<=0;w_full<=0;awaddr<=0;wdata<=0;wstrb<=0;
            s_axi_bvalid_o<=0;s_axi_bresp_o<=0;s_axi_rvalid_o<=0;s_axi_rresp_o<=0;s_axi_rdata_o<=0;
            enabled<=0;shot_used<=0;dispatched<=0;accepted_pending<=0;completion_pending<=0;
            accepted_seen<=0;completion_seen<=0;sticky_fault<=0;first_error<=0;irq_mask<=0;irq_pending<=0;
            shadow_generation<=0;accepted_generation<=0;completed_generation<=0;completed_drained<=0;
            capture_req_generation_o<=0;
            shadow_slot<=0;shadow_frame<=0;shadow_version<=`VIDEO_INPUT_PREPROCESS_VERSION;
            capture_req_valid_o<=0;capture_req_slot_o<=0;capture_req_frame_id_o<=0;capture_req_version_o<=0;
            accepted_slot<=0;accepted_frame<=0;accepted_version<=0;accepted_raw<=0;accepted_preview<=0;accepted_input<=0;
            completed_slot<=0;completed_frame<=0;completed_version<=0;completed_success<=0;completed_code<=0;
            completed_raw<=0;completed_preview<=0;completed_input<=0;completed_raw_pixels<=0;completed_preview_pixels<=0;
            completed_input_pixels<=0;completed_raw_bytes<=0;completed_preview_bytes<=0;completed_input_bytes<=0;
            completed_raw_crc<=0;completed_preview_crc<=0;completed_fifo_peak<=0;
        end else begin
            if(s_axi_awvalid_i&&s_axi_awready_o)begin aw_full<=1;awaddr<=s_axi_awaddr_i;end
            if(s_axi_wvalid_i&&s_axi_wready_o)begin w_full<=1;wdata<=s_axi_wdata_i;wstrb<=s_axi_wstrb_i;end
            if(s_axi_bvalid_o&&s_axi_bready_i)s_axi_bvalid_o<=0;
            if(s_axi_rvalid_o&&s_axi_rready_i)s_axi_rvalid_o<=0;
            if(s_axi_arvalid_i&&s_axi_arready_o)begin
                s_axi_rvalid_o<=1;s_axi_rdata_o<=read_word;s_axi_rresp_o<=read_response;
            end
            if(execute_write)begin
                aw_full<=0;w_full<=0;s_axi_bvalid_o<=1;s_axi_bresp_o<=write_response;
                if(write_response==OKAY)begin
                    if(do_control)enabled<=write_merged[0];
                    if(do_mask)irq_mask<=write_merged[2:0];
                    if(do_slot)shadow_slot<=write_merged[1:0];
                    if(do_frame)shadow_frame<=write_merged;
                    if(do_version)shadow_version<=write_merged;
                    if(do_generation)shadow_generation<=write_merged;
                    if(do_rearm)begin
                        shot_used<=0;dispatched<=0;accepted_seen<=0;completion_seen<=0;
                    end
                    if(do_ack)begin
                        irq_pending<=irq_pending&~ack_bits;
                        if(ack_bits[0])accepted_pending<=0;
                        if(ack_bits[1])completion_pending<=0;
                    end
                    if(do_command)begin
                        shot_used<=1;capture_req_valid_o<=1;capture_req_generation_o<=shadow_generation;capture_req_slot_o<=shadow_slot;
                        capture_req_frame_id_o<=shadow_frame;capture_req_version_o<=shadow_version;
                    end
                end
            end
            if(capture_req_valid_o&&capture_req_ready_i)begin capture_req_valid_o<=0;dispatched<=1;end
            if(accepted_take&&accepted_good)begin
                accepted_generation<=capture_req_generation_o;
                accepted_seen<=1;accepted_pending<=1;irq_pending[0]<=1;
                accepted_slot<=capture_slot_i;accepted_frame<=capture_frame_id_i;accepted_version<=capture_version_i;
                accepted_raw<=capture_raw_base_i;accepted_preview<=capture_preview_base_i;accepted_input<=capture_input_base_i;
            end
            if(completion_take&&completion_good)begin
                completed_generation<=capture_req_generation_o;completed_drained<=capture_port_drained_i;
                completion_seen<=1;completion_pending<=1;irq_pending[1]<=1;
                completed_slot<=capture_slot_i;completed_frame<=capture_frame_id_i;completed_version<=capture_version_i;
                completed_success<=completion_success_i;completed_code<=completion_code_i;
                completed_raw<=capture_raw_base_i;completed_preview<=capture_preview_base_i;completed_input<=capture_input_base_i;
                completed_raw_pixels<=capture_raw_pixels_i;completed_preview_pixels<=capture_preview_pixels_i;completed_input_pixels<=capture_input_pixels_i;
                completed_raw_bytes<=capture_raw_bytes_i;completed_preview_bytes<=capture_preview_bytes_i;completed_input_bytes<=capture_input_bytes_i;
                completed_raw_crc<=capture_raw_crc_i;completed_preview_crc<=capture_preview_crc_i;completed_fifo_peak<=capture_fifo_peak_i;
            end
            // First fault is immutable. New event bits follow ACK assignments so
            // they win a same-edge W1C, including the very first fault interrupt.
            if(!sticky_fault&&(protocol_fault||failed_completion||live_fault))begin
                sticky_fault<=1;irq_pending[2]<=1;
                first_error<=protocol_fault?PROTOCOL_ERROR:failed_completion?completion_code_i:live_code;
            end
        end
    end
endmodule
`default_nettype wire
