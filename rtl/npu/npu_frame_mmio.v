`timescale 1ns/1ps
`include "frame_config.vh"

// Production frame control. Completion consumption never grants DDR visibility:
// done_publish_i must come from the system's task retirement/publication proof.
// Only a coordinated system reset clears fault; ACK does not abort a transaction.
module npu_frame_mmio #(parameter integer ENABLE_HARDWARE_POST=1) (
    input wire clk_i, rst_ni,
    input wire [31:0] s_axi_awaddr_i,
    input wire s_axi_awvalid_i,
    output wire s_axi_awready_o,
    input wire [31:0] s_axi_wdata_i,
    input wire [3:0] s_axi_wstrb_i,
    input wire s_axi_wvalid_i,
    output wire s_axi_wready_o,
    output reg [1:0] s_axi_bresp_o,
    output reg s_axi_bvalid_o,
    input wire s_axi_bready_i,
    input wire [31:0] s_axi_araddr_i,
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output reg [31:0] s_axi_rdata_o,
    output reg [1:0] s_axi_rresp_o,
    output reg s_axi_rvalid_o,
    input wire s_axi_rready_i,
    input wire platform_healthy_i,
    input wire [31:0] session_epoch_i, addr_version_i,
    output wire start_valid_o,
    input wire start_ready_i,
    output reg [1023:0] task_words_o,
    input wire done_valid_i,
    output wire done_ready_o,
    input wire [31:0] done_status_i, done_detail_i, done_cmd_i, done_epoch_i,
    input wire [63:0] done_frame_i,
    input wire [11:0] done_faces_i,
    input wire [31:0] done_result_offset_i, done_result_bytes_i, done_crc_i,
    input wire [63:0] done_total_cycles_i, done_model_cycles_i, done_post_cycles_i,
    input wire done_live_i, done_publish_i,
    output wire irq_o, fault_o
);
    localparam [1:0] OKAY=0, SLVERR=2, DECERR=3;
    reg aw_full, w_full, active, held, fault, start_pending;
    reg [31:0] aw_addr, w_data;
    reg [3:0] w_strb;
    reg [31:0] shadow[0:31];
    reg [31:0] completion[0:19];
    reg [31:0] ack_cmd, ack_frame, ack_epoch;
    reg [1:0] irq_status, irq_enable;
    wire write_execute=aw_full&&w_full&&!s_axi_bvalid_o;
    wire locked=active||held;
    wire [31:0] wo=aw_addr-`NF_BASE;
    wire [31:0] ro=s_axi_araddr_i-`NF_BASE;
    wire [31:0] byte_mask={{8{w_strb[3]}},{8{w_strb[2]}},{8{w_strb[1]}},{8{w_strb[0]}}};
    wire write_task=wo>=`NF_TASK_BASE && wo<`NF_TASK_BASE+128;
    wire read_task=ro>=`NF_TASK_BASE && ro<`NF_TASK_BASE+128;
    wire read_done=ro>=`NF_COMPLETION_BASE && ro<`NF_COMPLETION_BASE+80;
    wire event_done=done_valid_i&&done_ready_o;
    wire same_identity=done_cmd_i==task_words_o[14*32+:32] &&
        done_frame_i==task_words_o[15*32+:64] && done_epoch_i==task_words_o[17*32+:32];
    wire good_result=ENABLE_HARDWARE_POST ?
        (done_faces_i<=`B03_CAPACITY && done_result_offset_i==task_words_o[10*32+:32] &&
         done_result_bytes_i==32'd128+({20'd0,done_faces_i}<<5) && done_result_bytes_i<=`B03_RESULT_BYTES) :
        (done_faces_i==0 && done_crc_i==0 && done_result_offset_i==task_words_o[28*32+:32] &&
         done_result_bytes_i==`B03_HEADS_BYTES);
    wire valid_done=same_identity&&done_live_i&&platform_healthy_i&&
        session_epoch_i==task_words_o[17*32+:32]&&addr_version_i==task_words_o[18*32+:32]&&
        !fault&&(done_status_i!=0||good_result);
    reg task_valid;
    reg [31:0] expected_output;
    reg slot_valid;
    reg [1:0] wr_resp,rd_resp,irq_next;
    reg [31:0] rd_data;
    integer k;

    function address_valid;
        input [31:0] addr;
        begin address_valid=addr>=`NF_BASE && addr-`NF_BASE<`NF_BYTES && addr[1:0]==0; end
    endfunction
    function [31:0] merge;
        input [31:0] old_value,new_value,mask;
        begin merge=(old_value&~mask)|(new_value&mask); end
    endfunction
    function live_identity;
        input [31:0] value;
        begin live_identity=value!=0&&value!=32'hffffffff; end
    endfunction
    assign s_axi_awready_o=rst_ni&&!aw_full&&!s_axi_bvalid_o;
    assign s_axi_wready_o=rst_ni&&!w_full&&!s_axi_bvalid_o;
    assign s_axi_arready_o=rst_ni&&!s_axi_rvalid_o;
    assign start_valid_o=rst_ni&&start_pending&&!fault&&platform_healthy_i&&
        session_epoch_i==task_words_o[17*32+:32]&&addr_version_i==task_words_o[18*32+:32];
    assign done_ready_o=rst_ni&&active&&!start_pending&&!held;
    assign irq_o=|(irq_status&irq_enable);
    assign fault_o=fault;

    // The three slots are bound as pairs; software cannot use another frame's
    // output or relocate the model into private CPU memory through this ABI.
    always @* begin
        slot_valid=1;expected_output=0;
        case(shadow[8])
            `B03_INPUT_BASES_0-(`SOC_DDR_BASE+`SOC_WINDOW_BASE): expected_output=`B03_OUTPUT_BASES_0;
            `B03_INPUT_BASES_1-(`SOC_DDR_BASE+`SOC_WINDOW_BASE): expected_output=`B03_OUTPUT_BASES_1;
            `B03_INPUT_BASES_2-(`SOC_DDR_BASE+`SOC_WINDOW_BASE): expected_output=`B03_OUTPUT_BASES_2;
            default:slot_valid=0;
        endcase
        task_valid=slot_valid&&shadow[0]==32'h33444d42&&shadow[1]==1&&shadow[2]==128&&shadow[3]==1&&
            shadow[4]==`B03_PROGRAM_BASE-(`SOC_DDR_BASE+`SOC_WINDOW_BASE)&&shadow[5]==`B03_PROGRAM_BYTES&&
            shadow[6]==`B03_WORKSPACE_BASE-(`SOC_DDR_BASE+`SOC_WINDOW_BASE)&&shadow[7]==`B03_WORKSPACE_BYTES&&
            shadow[9]==`B03_INPUT_BYTES&&shadow[10]==expected_output+`B03_RESULT_OFFSET-(`SOC_DDR_BASE+`SOC_WINDOW_BASE)&&
            shadow[11]==`B03_RESULT_BYTES&&shadow[12]==`B03_POST_TABLE_BASE-(`SOC_DDR_BASE+`SOC_WINDOW_BASE)&&
            shadow[13]==`B03_POST_TABLE_BYTES&&live_identity(shadow[14])&&live_identity(shadow[15])&&shadow[16]==0&&
            live_identity(shadow[17])&&shadow[17]==session_epoch_i&&live_identity(shadow[18])&&shadow[18]==addr_version_i&&
            shadow[19]==`B03_SOURCE_WIDTH&&shadow[20]==`B03_SOURCE_HEIGHT&&shadow[21]==`B03_RESIZED_WIDTH&&
            shadow[22]==`B03_RESIZED_HEIGHT&&shadow[23]==`B03_PAD_LEFT&&shadow[24]==`B03_PAD_TOP&&
            shadow[25]==`B03_CAPACITY&&shadow[28]==expected_output+`B03_HEADS_OFFSET-(`SOC_DDR_BASE+`SOC_WINDOW_BASE)&&
            shadow[29]==1&&shadow[30]==`B03_WATCHDOG_CYCLES&&shadow[31]==0;
    end
    always @* begin
        wr_resp=OKAY;
        if(!address_valid(aw_addr))wr_resp=DECERR;
        else if(write_task)begin if(locked)wr_resp=SLVERR;end
        else case(wo)
            `NF_REG_CONTROL:if(w_strb!=15||w_data!=`NF_START||locked||fault||!platform_healthy_i||!task_valid)wr_resp=SLVERR;
            `NF_REG_IRQ_ENABLE,`NF_REG_IRQ_STATUS:if(|(w_data&byte_mask&32'hfffffffc))wr_resp=SLVERR;
            `NF_REG_ACK_CMD,`NF_REG_ACK_FRAME,`NF_REG_ACK_EPOCH:begin end
            `NF_REG_ACK:if(w_strb!=15||w_data!=1||!held||ack_cmd!=completion[`NF_DONE_CMD_ID]||
                ack_frame!=completion[`NF_DONE_FRAME_ID_LO]||ack_epoch!=completion[`NF_DONE_EPOCH])wr_resp=SLVERR;
            `NF_REG_ID_VERSION,`NF_REG_CAPS,`NF_REG_STATUS,`NF_REG_FAULT,`NF_REG_SESSION_EPOCH:wr_resp=SLVERR;
            default:wr_resp=(wo>=`NF_COMPLETION_BASE&&wo<`NF_COMPLETION_BASE+80)?SLVERR:DECERR;
        endcase
    end
    always @* begin
        rd_data=0;rd_resp=OKAY;
        if(!address_valid(s_axi_araddr_i))rd_resp=DECERR;
        else if(read_task)rd_data=shadow[(ro-`NF_TASK_BASE)>>2];
        else if(read_done)rd_data=completion[(ro-`NF_COMPLETION_BASE)>>2];
        else case(ro)
            `NF_REG_ID_VERSION:rd_data=`NF_ID_VERSION;
            `NF_REG_CAPS:rd_data=`NF_CAPS;
            `NF_REG_CONTROL,`NF_REG_ACK:rd_data=0;
            `NF_REG_STATUS:rd_data={28'd0,fault,held,active,(!locked&&!fault&&platform_healthy_i)};
            `NF_REG_IRQ_STATUS:rd_data={30'd0,irq_status};
            `NF_REG_IRQ_ENABLE:rd_data={30'd0,irq_enable};
            `NF_REG_FAULT:rd_data={31'd0,fault};
            `NF_REG_SESSION_EPOCH:rd_data=session_epoch_i;
            `NF_REG_ACK_CMD:rd_data=ack_cmd;
            `NF_REG_ACK_FRAME:rd_data=ack_frame;
            `NF_REG_ACK_EPOCH:rd_data=ack_epoch;
            default:rd_resp=DECERR;
        endcase
    end
    always @* begin
        irq_next=irq_status;
        if(write_execute&&wr_resp==OKAY&&wo==`NF_REG_IRQ_STATUS)irq_next=irq_next&~(w_data[1:0]&byte_mask[1:0]);
        if(event_done)irq_next=irq_next|((valid_done&&done_status_i==0)?2'b01:2'b10);
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            aw_full<=0;w_full<=0;aw_addr<=0;w_data<=0;w_strb<=0;
            s_axi_bvalid_o<=0;s_axi_bresp_o<=0;s_axi_rvalid_o<=0;s_axi_rresp_o<=0;s_axi_rdata_o<=0;
            active<=0;held<=0;fault<=0;start_pending<=0;task_words_o<=0;
            ack_cmd<=0;ack_frame<=0;ack_epoch<=0;irq_status<=0;irq_enable<=0;
            for(k=0;k<32;k=k+1)shadow[k]<=0;
            for(k=0;k<20;k=k+1)completion[k]<=0;
        end else begin
            irq_status<=irq_next;
            if(s_axi_awvalid_i&&s_axi_awready_o)begin aw_full<=1;aw_addr<=s_axi_awaddr_i;end
            if(s_axi_wvalid_i&&s_axi_wready_o)begin w_full<=1;w_data<=s_axi_wdata_i;w_strb<=s_axi_wstrb_i;end
            if(s_axi_bvalid_o&&s_axi_bready_i)s_axi_bvalid_o<=0;
            if(s_axi_rvalid_o&&s_axi_rready_i)s_axi_rvalid_o<=0;
            if(s_axi_arvalid_i&&s_axi_arready_o)begin s_axi_rvalid_o<=1;s_axi_rdata_o<=rd_data;s_axi_rresp_o<=rd_resp;end
            if(start_valid_o&&start_ready_i)start_pending<=0;
            if(locked&&(!platform_healthy_i||session_epoch_i!=task_words_o[17*32+:32]||
                addr_version_i!=task_words_o[18*32+:32]))begin
                fault<=1;start_pending<=0;
                completion[`NF_DONE_LIVE]<=0;completion[`NF_DONE_PUBLISHED]<=0;
            end
            if(write_execute)begin
                aw_full<=0;w_full<=0;s_axi_bvalid_o<=1;s_axi_bresp_o<=wr_resp;
                if(wr_resp==OKAY)begin
                    if(write_task)shadow[(wo-`NF_TASK_BASE)>>2]<=merge(shadow[(wo-`NF_TASK_BASE)>>2],w_data,byte_mask);
                    else case(wo)
                        `NF_REG_CONTROL:begin
                            for(k=0;k<32;k=k+1)task_words_o[k*32+:32]<=shadow[k];
                            for(k=0;k<20;k=k+1)completion[k]<=0;
                            active<=1;start_pending<=1;
                        end
                        `NF_REG_IRQ_ENABLE:irq_enable<=merge({30'd0,irq_enable},w_data,byte_mask);
                        `NF_REG_ACK_CMD:ack_cmd<=merge(ack_cmd,w_data,byte_mask);
                        `NF_REG_ACK_FRAME:ack_frame<=merge(ack_frame,w_data,byte_mask);
                        `NF_REG_ACK_EPOCH:ack_epoch<=merge(ack_epoch,w_data,byte_mask);
                        `NF_REG_ACK:held<=0;
                    endcase
                end
            end
            if(event_done)begin
                active<=0;held<=1;
                if(!valid_done)fault<=1;
                completion[`NF_DONE_STATUS]<=valid_done?done_status_i:32'hffffff01;
                completion[`NF_DONE_DETAIL]<=valid_done?done_detail_i:done_cmd_i;
                completion[`NF_DONE_CMD_ID]<=task_words_o[14*32+:32];
                completion[`NF_DONE_FRAME_ID_LO]<=task_words_o[15*32+:32];
                completion[`NF_DONE_FRAME_ID_HI]<=task_words_o[16*32+:32];
                completion[`NF_DONE_EPOCH]<=task_words_o[17*32+:32];
                completion[`NF_DONE_FACES]<=valid_done&&done_status_i==0?{20'd0,done_faces_i}:0;
                completion[`NF_DONE_RESULT_OFFSET]<=valid_done&&done_status_i==0?done_result_offset_i:0;
                completion[`NF_DONE_RESULT_BYTES]<=valid_done&&done_status_i==0?done_result_bytes_i:0;
                completion[`NF_DONE_CRC]<=valid_done&&done_status_i==0?done_crc_i:0;
                completion[`NF_DONE_TOTAL_LO]<=done_total_cycles_i[31:0];completion[`NF_DONE_TOTAL_HI]<=done_total_cycles_i[63:32];
                completion[`NF_DONE_MODEL_LO]<=done_model_cycles_i[31:0];completion[`NF_DONE_MODEL_HI]<=done_model_cycles_i[63:32];
                completion[`NF_DONE_POST_LO]<=done_post_cycles_i[31:0];completion[`NF_DONE_POST_HI]<=done_post_cycles_i[63:32];
                completion[`NF_DONE_LIVE]<={31'd0,valid_done};
                completion[`NF_DONE_PUBLISHED]<={31'd0,(valid_done&&done_status_i==0&&done_publish_i&&!fault)};
            end
        end
    end
endmodule
