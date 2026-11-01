/* TriHa AXI128 serialized, fair owner arbitration.
 * Packed lane N occupies [N*WIDTH +: WIDTH]. Descriptors are captured before
 * downstream offers. W may precede downstream AW; source WVALID may precede
 * source AW, but WREADY waits until that source's AW establishes ownership.
 * Ownership ends only when the source accepts its B or advertised last R.
 * Errors stop new grants. Owned traffic drains its advertised count, and no
 * health signal or timeout retracts an outstanding VALID. Coordinated reset only.
 */
`default_nettype none
module soc_axi128_arbiter #(
    parameter integer MASTERS=2
)(
    input wire clk_i,rst_ni,healthy_i,
    input wire [MASTERS-1:0] s_awvalid_i,output reg [MASTERS-1:0] s_awready_o,
    input wire [MASTERS*32-1:0] s_awaddr_i,input wire [MASTERS*4-1:0] s_awid_i,
    input wire [MASTERS*8-1:0] s_awlen_i,input wire [MASTERS*3-1:0] s_awsize_i,input wire [MASTERS*2-1:0] s_awburst_i,
    input wire [MASTERS-1:0] s_wvalid_i,output reg [MASTERS-1:0] s_wready_o,
    input wire [MASTERS*128-1:0] s_wdata_i,input wire [MASTERS*16-1:0] s_wstrb_i,input wire [MASTERS-1:0] s_wlast_i,
    output reg [MASTERS-1:0] s_bvalid_o,input wire [MASTERS-1:0] s_bready_i,
    output reg [MASTERS*4-1:0] s_bid_o,output reg [MASTERS*2-1:0] s_bresp_o,
    input wire [MASTERS-1:0] s_arvalid_i,output reg [MASTERS-1:0] s_arready_o,
    input wire [MASTERS*32-1:0] s_araddr_i,input wire [MASTERS*4-1:0] s_arid_i,
    input wire [MASTERS*8-1:0] s_arlen_i,input wire [MASTERS*3-1:0] s_arsize_i,input wire [MASTERS*2-1:0] s_arburst_i,
    output reg [MASTERS-1:0] s_rvalid_o,input wire [MASTERS-1:0] s_rready_i,
    output reg [MASTERS*128-1:0] s_rdata_o,output reg [MASTERS*4-1:0] s_rid_o,
    output reg [MASTERS*2-1:0] s_rresp_o,output reg [MASTERS-1:0] s_rlast_o,
    output wire m_awvalid_o,input wire m_awready_i,output wire [31:0] m_awaddr_o,output wire [3:0] m_awid_o,
    output wire [7:0] m_awlen_o,output wire [2:0] m_awsize_o,output wire [1:0] m_awburst_o,
    output wire m_wvalid_o,input wire m_wready_i,output wire [127:0] m_wdata_o,
    output wire [15:0] m_wstrb_o,output wire m_wlast_o,
    input wire m_bvalid_i,output wire m_bready_o,input wire [3:0] m_bid_i,input wire [1:0] m_bresp_i,
    output wire m_arvalid_o,input wire m_arready_i,output wire [31:0] m_araddr_o,output wire [3:0] m_arid_o,
    output wire [7:0] m_arlen_o,output wire [2:0] m_arsize_o,output wire [1:0] m_arburst_o,
    input wire m_rvalid_i,output wire m_rready_o,input wire [127:0] m_rdata_i,
    input wire [3:0] m_rid_i,input wire [1:0] m_rresp_i,input wire m_rlast_i,
    output wire idle_o,output reg fault_o,output reg [7:0] fault_code_o
);
    localparam integer OWNER_BITS=MASTERS>1?$clog2(MASTERS):1;
    localparam [2:0] IDLE=0,WRITE=1,RADDR=2,READ=3,BADWRITE=4,BADREAD=5,RESP=6;
    reg [2:0] state_q;
    reg [OWNER_BITS-1:0] owner_q,round_robin_q;
    reg [MASTERS-1:0] prefer_read_q;
    reg [31:0] address_q;
    reg [3:0] id_q;
    reg [7:0] length_q;
    reg [2:0] size_q;
    reg [1:0] burst_q;
    reg [8:0] remaining_q;
    reg aw_done_q,transaction_error_q,read_valid_q,read_last_q;
    reg [127:0] read_data_q;
    reg [1:0] read_response_q,write_response_q;
    reg choice_valid,choice_write;
    integer choice,step,candidate;
    always @*begin
        choice_valid=0;choice_write=0;choice=0;candidate=0;
        for(step=0;step<MASTERS;step=step+1)begin
            candidate=round_robin_q+step;if(candidate>=MASTERS)candidate=candidate-MASTERS;
            if(!choice_valid&&(s_awvalid_i[candidate]===1'b1||s_arvalid_i[candidate]===1'b1))begin
                choice_valid=1;choice=candidate;
                choice_write=s_awvalid_i[candidate]&&(!s_arvalid_i[candidate]||!prefer_read_q[candidate]);
            end
        end
    end
    wire [31:0] choice_address=choice_write?s_awaddr_i[choice*32+:32]:s_araddr_i[choice*32+:32];
    wire [3:0] choice_id=choice_write?s_awid_i[choice*4+:4]:s_arid_i[choice*4+:4];
    wire [7:0] choice_length=choice_write?s_awlen_i[choice*8+:8]:s_arlen_i[choice*8+:8];
    wire [2:0] choice_size=choice_write?s_awsize_i[choice*3+:3]:s_arsize_i[choice*3+:3];
    wire [1:0] choice_burst=choice_write?s_awburst_i[choice*2+:2]:s_arburst_i[choice*2+:2];
    function legal;
        input [31:0] address;input [7:0] length;input [2:0] size;input [1:0] burst;
        reg [8:0] last_word;
        begin
            // DDR's [0x80000000,0x88000000) window is page aligned. With
            // aligned 16-byte INCR beats and no page crossing, the last beat
            // remains in that window iff the starting page is in it. Check
            // the inclusive final word, removing a 33-bit carry chain after
            // the arbitration mux without adding a transaction cycle.
            last_word={1'b0,address[11:4]}+{1'b0,length};
            legal=(^address!==1'bx)&&address[31:27]==5'b10000&&length[7:4]==0&&
                  address[3:0]==0&&size==4&&burst==1&&!last_word[8];
        end
    endfunction
    wire choice_legal=legal(choice_address,choice_length,choice_size,choice_burst)&&(^choice_id!==1'bx);
    wire capture=rst_ni&&state_q==IDLE&&!fault_o&&healthy_i&&choice_valid&&!m_bvalid_i&&!m_rvalid_i;
    wire local_w_fire=s_wvalid_i[owner_q]&&s_wready_o[owner_q];
    wire aw_fire=m_awvalid_o&&m_awready_i;
    wire w_fire=m_wvalid_o&&m_wready_i;
    wire b_fire=m_bvalid_i&&m_bready_o;
    wire r_fire=m_rvalid_i&&m_rready_o;
    wire local_r_fire=read_valid_q&&s_rready_i[owner_q];
    wire b_phase=state_q==WRITE&&(aw_done_q||aw_fire)&&(remaining_q==0||(w_fire&&remaining_q==1));
    wire r_phase=(state_q==READ&&remaining_q!=0)||(state_q==RADDR&&m_arvalid_o&&m_arready_i);
    reg [7:0] error_now;
    always @*begin
        error_now=0;
        if(capture&&choice_legal!==1'b1)error_now=1;
        else if(m_bvalid_i&&!b_phase)error_now=5;
        else if(m_rvalid_i&&!r_phase)error_now=5;
        else if(local_w_fire&&s_wlast_i[owner_q]!==(remaining_q==1))error_now=4;
        else if(b_fire)begin
            if(m_bid_i!==id_q)error_now=3;else if(m_bresp_i!==2'd0)error_now=2;
        end else if(r_fire)begin
            if(m_rid_i!==id_q)error_now=3;else if(m_rresp_i!==2'd0)error_now=2;
            else if(m_rlast_i!==(remaining_q==1))error_now=4;
        end
    end
    always @*begin
        s_awready_o=0;s_arready_o=0;s_wready_o=0;s_bvalid_o=0;s_bid_o=0;s_bresp_o=0;
        s_rvalid_o=0;s_rdata_o=0;s_rid_o=0;s_rresp_o=0;s_rlast_o=0;
        if(capture)begin
            if(choice_write)s_awready_o[choice]=1;else s_arready_o[choice]=1;
        end
        if(rst_ni)begin
            if(state_q==WRITE&&remaining_q!=0)s_wready_o[owner_q]=m_wready_i;
            if(state_q==BADWRITE)s_wready_o[owner_q]=1;
            if(state_q==RESP)begin
                s_bvalid_o[owner_q]=1;s_bid_o[owner_q*4+:4]=id_q;s_bresp_o[owner_q*2+:2]=write_response_q;
            end
            if((state_q==READ||state_q==BADREAD)&&read_valid_q)begin
                s_rvalid_o[owner_q]=1;s_rdata_o[owner_q*128+:128]=read_data_q;
                s_rid_o[owner_q*4+:4]=id_q;s_rresp_o[owner_q*2+:2]=read_response_q;s_rlast_o[owner_q]=read_last_q;
            end
        end
    end
    assign idle_o=state_q==IDLE;
    assign m_awvalid_o=rst_ni&&state_q==WRITE&&!aw_done_q;
    assign m_arvalid_o=rst_ni&&state_q==RADDR;
    assign m_awaddr_o=address_q;assign m_araddr_o=address_q;assign m_awid_o=id_q;assign m_arid_o=id_q;
    assign m_awlen_o=length_q;assign m_arlen_o=length_q;assign m_awsize_o=size_q;assign m_arsize_o=size_q;
    assign m_awburst_o=burst_q;assign m_arburst_o=burst_q;
    assign m_wvalid_o=rst_ni&&state_q==WRITE&&remaining_q!=0&&s_wvalid_i[owner_q];
    assign m_wdata_o=s_wdata_i[owner_q*128+:128];assign m_wstrb_o=s_wstrb_i[owner_q*16+:16];
    // Malformed source LAST cannot truncate the downstream advertised burst.
    assign m_wlast_o=remaining_q==1;
    assign m_bready_o=rst_ni&&state_q==WRITE&&aw_done_q&&remaining_q==0;
    assign m_rready_o=rst_ni&&state_q==READ&&!read_valid_q&&remaining_q!=0;
    initial if(MASTERS<1||MASTERS>8)$fatal(1,"AXI arbiter supports 1..8 masters");
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            state_q<=IDLE;owner_q<=0;round_robin_q<=0;prefer_read_q<=0;address_q<=0;id_q<=0;length_q<=0;size_q<=0;burst_q<=0;
            remaining_q<=0;aw_done_q<=0;transaction_error_q<=0;read_valid_q<=0;read_last_q<=0;read_data_q<=0;
            read_response_q<=0;write_response_q<=0;fault_o<=0;fault_code_o<=0;
        end else begin
            if(error_now!=0)begin
                if(!fault_o)begin fault_o<=1;fault_code_o<=error_now;end
                if(state_q!=IDLE)transaction_error_q<=1;
            end
            case(state_q)
                IDLE:if(capture)begin
                    owner_q<=choice[OWNER_BITS-1:0];address_q<=choice_address;id_q<=choice_id;length_q<=choice_length;
                    size_q<=choice_size;burst_q<=choice_burst;remaining_q<={1'b0,choice_length}+9'd1;
                    aw_done_q<=0;transaction_error_q<=choice_legal!==1'b1;read_valid_q<=0;
                    prefer_read_q[choice]<=choice_write;
                    if(choice_legal===1'b1)state_q<=choice_write?WRITE:RADDR;
                    else state_q<=choice_write?BADWRITE:BADREAD;
                end
                WRITE:begin
                    if(aw_fire)aw_done_q<=1;
                    if(w_fire)remaining_q<=remaining_q-1;
                    if(b_fire)begin write_response_q<=(transaction_error_q||error_now!=0)?2'b10:m_bresp_i;state_q<=RESP;end
                end
                BADWRITE:if(local_w_fire)begin
                    remaining_q<=remaining_q-1;
                    if(remaining_q==1)begin write_response_q<=2'b11;state_q<=RESP;end
                end
                RESP:if(s_bready_i[owner_q])begin
                    state_q<=IDLE;round_robin_q<=owner_q==MASTERS-1?0:owner_q+1'b1;
                end
                RADDR:if(m_arready_i)state_q<=READ;
                READ:begin
                    if(r_fire)begin
                        read_data_q<=m_rdata_i;read_last_q<=remaining_q==1;read_valid_q<=1;remaining_q<=remaining_q-1;
                        read_response_q<=(transaction_error_q||error_now!=0)?2'b10:m_rresp_i;
                    end
                    if(local_r_fire)begin
                        read_valid_q<=0;
                        if(read_last_q)begin state_q<=IDLE;round_robin_q<=owner_q==MASTERS-1?0:owner_q+1'b1;end
                    end
                end
                BADREAD:begin
                    if(!read_valid_q&&remaining_q!=0)begin
                        read_data_q<=0;read_last_q<=remaining_q==1;read_valid_q<=1;read_response_q<=2'b11;remaining_q<=remaining_q-1;
                    end
                    if(local_r_fire)begin
                        read_valid_q<=0;
                        if(read_last_q)begin state_q<=IDLE;round_robin_q<=owner_q==MASTERS-1?0:owner_q+1'b1;end
                    end
                end
                default:begin state_q<=IDLE;fault_o<=1;fault_code_o<=8'hff;end
            endcase
        end
    end
endmodule
`default_nettype wire
