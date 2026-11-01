// Derived from npu_service_axi128.v SHA256 28aa34fb7080dae4d0d33e8429f3bc32265ff8a78ff57050fb08670371381ed8.
// Pango asynchronous LUTRAM preserves the collected-write launch cycle.
/* TriHa NPU serialized service to AXI128.
 * CMD addresses are DDR-relative bytes. Only [02000000,08000000) is admitted;
 * translation adds 80000000 exactly once. A 256-bit word sends low 128 first.
 * Owned AXI offers never depend on healthy or arithmetic CE. Only coordinated
 * rst_ni may discard an in-flight channel. Errors quarantine new commands;
 * no timeout invents retirement. Block DMA retains verified-write ownership.
 */
`default_nettype none
module npu_service_axi128_compact (
    input wire clk_i, rst_ni, healthy_i,
    input wire p_cmd_valid, output wire p_cmd_ready, input wire p_cmd_write,
    input wire [31:0] p_cmd_offset, p_cmd_id, p_cmd_epoch,
    input wire [4:0] p_cmd_beats, input wire [2:0] p_cmd_client,
    input wire p_write_valid, output wire p_write_ready,
    input wire [255:0] p_write_data, input wire [31:0] p_write_strb, input wire p_write_last,
    output wire p_read_valid, input wire p_read_ready,
    output wire [255:0] p_read_data, output wire p_read_last,
    input wire p_abort_req,
    output wire p_done_valid, input wire p_done_ready, output wire [3:0] p_done_status,
    output wire [31:0] p_done_id, p_done_epoch, output wire [2:0] p_done_client,
    output wire idle_o, output reg fault_o, output reg [3:0] fault_code_o,
    output wire m_awvalid_o, input wire m_awready_i,
    output wire [31:0] m_awaddr_o, output wire [3:0] m_awid_o,
    output wire [7:0] m_awlen_o, output wire [2:0] m_awsize_o, output wire [1:0] m_awburst_o,
    output wire m_wvalid_o, input wire m_wready_i, output wire [127:0] m_wdata_o,
    output wire [15:0] m_wstrb_o, output wire m_wlast_o,
    input wire m_bvalid_i, output wire m_bready_o, input wire [3:0] m_bid_i, input wire [1:0] m_bresp_i,
    output wire m_arvalid_o, input wire m_arready_i,
    output wire [31:0] m_araddr_o, output wire [3:0] m_arid_o,
    output wire [7:0] m_arlen_o, output wire [2:0] m_arsize_o, output wire [1:0] m_arburst_o,
    input wire m_rvalid_i, output wire m_rready_o, input wire [127:0] m_rdata_i,
    input wire [3:0] m_rid_i, input wire [1:0] m_rresp_i, input wire m_rlast_i
);
    localparam [2:0] IDLE=0, COLLECT=1, WRITE=2, RADDR=3, READ=4, DONE=5;
    reg [2:0] state_q;
    reg [31:0] id_q, epoch_q, address_q;
    reg [2:0] client_q;
    reg [3:0] status_q;
    reg [4:0] total_q, remaining_q, chunk_q, collected_q, base_q, delivered_q;
    reg [5:0] write_index_q, read_index_q;
    reg aw_done_q, w_done_q, read_half_q, read_retired_q, read_valid_q, read_last_q;
    reg [127:0] read_low_q;
    reg [255:0] read_data_q;
    // Fully collected writes permit AW/W to retire in either order.
    wire [287:0] write_buffer_input = {p_write_strb,p_write_data};
    wire [287:0] write_buffer_output;
    wire [255:0] write_buffer_data = write_buffer_output[255:0];
    wire [31:0] write_buffer_mask = write_buffer_output[287:256];

    function [4:0] chunk_words;
        input [31:0] address;
        input [4:0] left;
        reg [8:0] to_page;
        reg [4:0] bounded;
        begin
            to_page=(13'd4096-{1'b0,address[11:0]})>>5;
            bounded=left>8?5'd8:left;
            chunk_words=to_page<{4'd0,bounded}?to_page[4:0]:bounded;
        end
    endfunction
    wire [32:0] command_end={1'b0,p_cmd_offset}+({28'd0,p_cmd_beats}<<5);
    wire legal_command=p_cmd_beats>=1 && p_cmd_beats<=16 && p_cmd_offset[4:0]==0 &&
        p_cmd_offset>=32'h02000000 && command_end<=33'h008000000;
    wire [5:0] axi_beats={chunk_q,1'b0};
    wire command_fire=p_cmd_valid&&p_cmd_ready;
    wire local_write_fire=p_write_valid&&p_write_ready;
    wire local_read_fire=p_read_valid&&p_read_ready;
    wire aw_fire=m_awvalid_o&&m_awready_i;
    wire w_fire=m_wvalid_o&&m_wready_i;
    wire b_fire=m_bvalid_i&&m_bready_o;
    wire ar_fire=m_arvalid_o&&m_arready_i;
    wire r_fire=m_rvalid_i&&m_rready_o;
    wire [31:0] next_address=address_q+({27'd0,chunk_q}<<5);
    wire [4:0] next_remaining=remaining_q-chunk_q;
    wire [4:0] write_word=base_q+{1'b0,write_index_q[4:1]};
    // 144 two-bit distributed RAMs, 16 used rows, no reset on memory contents.
    // A command fully overwrites its owned rows before any AXI offer.
    genvar ram_bit;
    generate for(ram_bit=0;ram_bit<144;ram_bit=ram_bit+1)begin: g_write_buffer
        GTP_RAM32X2DP u_ram (
            .DO(write_buffer_output[ram_bit*2+:2]), .DI(write_buffer_input[ram_bit*2+:2]),
            .RADDR({1'b0,write_word[3:0]}), .WADDR({1'b0,collected_q[3:0]}),
            .WCLK(clk_i), .WE(rst_ni&&local_write_fire)
        );
    end endgenerate
    reg [3:0] error_now;
    always @* begin
        error_now=0;
        if(command_fire&&!legal_command)error_now=1;
        else if(local_write_fire&&(p_write_last!==(collected_q+1==total_q)))error_now=4;
        else if(b_fire)begin
            if(m_bid_i!==4'd0)error_now=3;
            else if(m_bresp_i!==2'd0)error_now=2;
        end else if(r_fire)begin
            if(m_rid_i!==4'd0)error_now=3;
            else if(m_rresp_i!==2'd0)error_now=2;
            else if(m_rlast_i!==(read_index_q+1==axi_beats))error_now=4;
        end
        if(error_now==0&&p_abort_req)error_now=7;
        if(error_now==0&&((m_bvalid_i&&state_q!=WRITE)||(m_rvalid_i&&state_q!=READ)))error_now=4;
    end
    assign p_cmd_ready=rst_ni&&healthy_i&&state_q==IDLE&&!fault_o&&!p_abort_req&&!m_bvalid_i&&!m_rvalid_i;
    assign p_write_ready=rst_ni&&state_q==COLLECT;
    assign p_read_valid=rst_ni&&read_valid_q;
    assign p_read_data=read_data_q;
    assign p_read_last=read_last_q;
    assign p_done_valid=rst_ni&&state_q==DONE;
    assign p_done_status=status_q;
    assign p_done_id=id_q; assign p_done_epoch=epoch_q; assign p_done_client=client_q;
    assign idle_o=state_q==IDLE;
    assign m_awvalid_o=rst_ni&&state_q==WRITE&&!aw_done_q;
    assign m_awaddr_o=address_q; assign m_awid_o=0;
    assign m_awlen_o={2'd0,axi_beats}-8'd1; assign m_awsize_o=4; assign m_awburst_o=1;
    assign m_wvalid_o=rst_ni&&state_q==WRITE&&!w_done_q;
    assign m_wdata_o=write_index_q[0]?write_buffer_data[255:128]:write_buffer_data[127:0];
    assign m_wstrb_o=write_index_q[0]?write_buffer_mask[31:16]:write_buffer_mask[15:0];
    assign m_wlast_o=write_index_q+1==axi_beats;
    assign m_bready_o=rst_ni&&state_q==WRITE&&aw_done_q&&w_done_q;
    assign m_arvalid_o=rst_ni&&state_q==RADDR;
    assign m_araddr_o=address_q; assign m_arid_o=0;
    assign m_arlen_o={2'd0,axi_beats}-8'd1; assign m_arsize_o=4; assign m_arburst_o=1;
    assign m_rready_o=rst_ni&&state_q==READ&&!read_valid_q&&!read_retired_q;

    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            state_q<=IDLE;id_q<=0;epoch_q<=0;client_q<=0;address_q<=0;status_q<=0;
            total_q<=0;remaining_q<=0;chunk_q<=0;collected_q<=0;base_q<=0;delivered_q<=0;
            write_index_q<=0;read_index_q<=0;aw_done_q<=0;w_done_q<=0;
            read_half_q<=0;read_retired_q<=0;read_valid_q<=0;read_last_q<=0;read_low_q<=0;read_data_q<=0;
            fault_o<=0;fault_code_o<=0;
        end else begin
            if(!fault_o&&error_now!=0)begin fault_o<=1;fault_code_o<=error_now;end
            // A DONE tuple is immutable after it has become visible.
            if(state_q!=DONE&&status_q==0&&error_now!=0)status_q<=error_now;
            case(state_q)
                IDLE:if(command_fire)begin
                    id_q<=p_cmd_id;epoch_q<=p_cmd_epoch;client_q<=p_cmd_client;
                    address_q<=32'h80000000+p_cmd_offset;total_q<=p_cmd_beats;remaining_q<=p_cmd_beats;
                    chunk_q<=chunk_words(p_cmd_offset,p_cmd_beats);collected_q<=0;base_q<=0;delivered_q<=0;
                    read_half_q<=0;read_retired_q<=0;read_valid_q<=0;read_index_q<=0;write_index_q<=0;
                    aw_done_q<=0;w_done_q<=0;status_q<=legal_command?4'd0:4'd1;
                    state_q<=!legal_command?DONE:p_cmd_write?COLLECT:RADDR;
                end
                COLLECT:if(local_write_fire)begin
                    collected_q<=collected_q+1;
                    if(collected_q+1==total_q)state_q<=(fault_o||error_now!=0)?DONE:WRITE;
                end
                WRITE:begin
                    if(aw_fire)aw_done_q<=1;
                    if(w_fire)begin
                        write_index_q<=write_index_q+1;
                        if(write_index_q+1==axi_beats)w_done_q<=1;
                    end
                    if(b_fire)begin
                        // No further subtransaction is offered after a fault.
                        // The currently advertised AW/W has fully retired first.
                        if(fault_o||error_now!=0||remaining_q==chunk_q)state_q<=DONE;
                        else begin
                            address_q<=next_address;remaining_q<=next_remaining;base_q<=base_q+chunk_q;
                            chunk_q<=chunk_words(next_address,next_remaining);write_index_q<=0;aw_done_q<=0;w_done_q<=0;
                        end
                    end
                end
                RADDR:if(ar_fire)state_q<=READ;
                READ:begin
                    if(r_fire)begin
                        read_index_q<=read_index_q+1;read_half_q<=!read_half_q;
                        if(!read_half_q)read_low_q<=m_rdata_i;
                        else begin
                            read_data_q<={m_rdata_i,read_low_q};read_valid_q<=1;
                            read_last_q<=delivered_q+1==total_q;
                        end
                        if(read_index_q+1==axi_beats)read_retired_q<=1;
                    end
                    if(local_read_fire)begin
                        read_valid_q<=0;delivered_q<=delivered_q+1;
                        if(read_retired_q)begin
                            if(fault_o||error_now!=0||remaining_q==chunk_q)state_q<=DONE;
                            else begin
                                address_q<=next_address;remaining_q<=next_remaining;chunk_q<=chunk_words(next_address,next_remaining);
                                read_index_q<=0;read_retired_q<=0;state_q<=RADDR;
                            end
                        end
                    end
                end
                DONE:if(p_done_ready)state_q<=IDLE;
                default:begin state_q<=IDLE;fault_o<=1;fault_code_o<=4;end
            endcase
        end
    end
endmodule
`default_nettype wire
