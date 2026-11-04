
module triha_decode
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MULDIV   = 1
    ,parameter EXTRA_DECODE_STAGE = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           fetch_in_valid_i
    ,input  [ 63:0]  fetch_in_instr_i
    ,input  [  1:0]  fetch_in_pred_branch_i
    ,input           fetch_in_fault_fetch_i
    ,input           fetch_in_fault_page_i
    ,input [31:0] fetch_in_pred_pc_i
    ,input  [ 31:0]  fetch_in_pc_i
    ,input           fetch_out0_accept_i
    ,input           fetch_out1_accept_i
    ,input           branch_request_i
    ,input  [ 31:0]  branch_pc_i
    ,input  [  1:0]  branch_priv_i

    // Outputs
    ,output          fetch_in_accept_o
    ,output          fetch_out0_valid_o
    ,output [ 31:0]  fetch_out0_instr_o
    ,output [8:0] fetch_out0_alu_decode_o
    ,output [2:0] fetch_out0_roles_o
    ,output [31:0] fetch_out0_pred_pc_o
    ,output [ 31:0]  fetch_out0_pc_o
    ,output          fetch_out0_fault_fetch_o
    ,output          fetch_out0_fault_page_o
    ,output fetch_out0_instr_simple_exec_o
    ,output          fetch_out0_instr_exec_o
    ,output          fetch_out0_instr_lsu_o
    ,output          fetch_out0_instr_branch_o
    ,output          fetch_out0_instr_mul_o
    ,output          fetch_out0_instr_div_o
    ,output          fetch_out0_instr_csr_o
    ,output          fetch_out0_instr_rd_valid_o
    ,output          fetch_out0_instr_invalid_o
    ,output          fetch_out1_valid_o
    ,output [ 31:0]  fetch_out1_instr_o
    ,output [8:0] fetch_out1_alu_decode_o
    ,output [2:0] fetch_out1_roles_o
    ,output [31:0] fetch_out1_pred_pc_o
    ,output [ 31:0]  fetch_out1_pc_o
    ,output          fetch_out1_fault_fetch_o
    ,output          fetch_out1_fault_page_o
    ,output fetch_out1_instr_simple_exec_o
    ,output          fetch_out1_instr_exec_o
    ,output          fetch_out1_instr_lsu_o
    ,output          fetch_out1_instr_branch_o
    ,output          fetch_out1_instr_mul_o
    ,output          fetch_out1_instr_div_o
    ,output          fetch_out1_instr_csr_o
    ,output          fetch_out1_instr_rd_valid_o
    ,output          fetch_out1_instr_invalid_o
);



wire        enable_muldiv_w     = SUPPORT_MULDIV;

//-----------------------------------------------------------------
// 2 cycle frontend latency
//-----------------------------------------------------------------
generate
if (EXTRA_DECODE_STAGE)
begin
    triha_register_roles_predecode u_roles_compat0(.opcode_i(fetch_out0_instr_o),.roles_o(fetch_out0_roles_o));
    triha_register_roles_predecode u_roles_compat1(.opcode_i(fetch_out1_instr_o),.roles_o(fetch_out1_roles_o));
    triha_alu_predecode u_alu_compat0 (.opcode_i(fetch_out0_instr_o),.control_o(fetch_out0_alu_decode_o));
    triha_alu_predecode u_alu_compat1 (.opcode_i(fetch_out1_instr_o),.control_o(fetch_out1_alu_decode_o));
    wire        fetch_in_fault_page_w;
    wire        fetch_in_fault_fetch_w;
    wire [1:0]  fetch_in_pred_branch_w;
    wire [63:0] fetch_in_instr_raw_w;
    wire [63:0] fetch_in_instr_w;
    wire [31:0] fetch_in_pc_w;
    wire [31:0] fetch_in_pred_pc_w;
    wire        fetch_in_valid_w;

    reg [132:0] fetch_buffer_q;

    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
        fetch_buffer_q <= 133'b0;
    else if (branch_request_i)
        fetch_buffer_q <= 133'b0;
    else if (!fetch_in_valid_w || fetch_in_accept_o)
        fetch_buffer_q <= {fetch_in_pred_pc_i, fetch_in_fault_page_i, fetch_in_fault_fetch_i, fetch_in_pred_branch_i, fetch_in_instr_i, fetch_in_pc_i, fetch_in_valid_i};

    assign {fetch_in_pred_pc_w, fetch_in_fault_page_w, 
            fetch_in_fault_fetch_w, 
            fetch_in_pred_branch_w, 
            fetch_in_instr_raw_w, 
            fetch_in_pc_w, 
            fetch_in_valid_w} = fetch_buffer_q;

    assign fetch_in_instr_w = (fetch_in_fault_page_w | fetch_in_fault_fetch_w) ? 64'b0 : fetch_in_instr_raw_w;

    wire [7:0] info0_in_w;
    wire [9:0] info0_out_w;
    wire [7:0] info1_in_w;
    wire [9:0] info1_out_w;
    wire simple0_in_w,simple1_in_w;
    triha_exec_classify u_simple0(.opcode_i(fetch_in_instr_w[31:0]),.exec_o(),.simple_exec_o(simple0_in_w));
    triha_exec_classify u_simple1(.opcode_i(fetch_in_instr_w[63:32]),.exec_o(),.simple_exec_o(simple1_in_w));


    biriscv_decoder
    u_dec0
    (
         .valid_i(fetch_in_valid_w)
        ,.fetch_fault_i(fetch_in_fault_fetch_w | fetch_in_fault_page_w)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_in_instr_w[31:0])

        ,.invalid_o(info0_in_w[7])
        ,.exec_o(info0_in_w[6])
        ,.lsu_o(info0_in_w[5])
        ,.branch_o(info0_in_w[4])
        ,.mul_o(info0_in_w[3])
        ,.div_o(info0_in_w[2])
        ,.csr_o(info0_in_w[1])
        ,.rd_valid_o(info0_in_w[0])
    );

    biriscv_decoder
    u_dec1
    (
         .valid_i(fetch_in_valid_w)
        ,.fetch_fault_i(fetch_in_fault_fetch_w | fetch_in_fault_page_w)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_in_instr_w[63:32])

        ,.invalid_o(info1_in_w[7])
        ,.exec_o(info1_in_w[6])
        ,.lsu_o(info1_in_w[5])
        ,.branch_o(info1_in_w[4])
        ,.mul_o(info1_in_w[3])
        ,.div_o(info1_in_w[2])
        ,.csr_o(info1_in_w[1])
        ,.rd_valid_o(info1_in_w[0])
    );

    triha_fetch_fifo
    #( .OPC_INFO_W(11), .DEPTH(3) )
    u_fifo
    (
         .clk_i(clk_i)
        ,.rst_i(rst_i)

        ,.flush_i(branch_request_i)

        // Input side
        ,.push_i(fetch_in_valid_w)
        ,.pc_in_i(fetch_in_pc_w)
        ,.pred_pc_in_i(fetch_in_pred_pc_w)
        ,.pred_in_i(fetch_in_pred_branch_w)
        ,.data_in_i(fetch_in_instr_w)
        ,.info0_in_i({simple0_in_w, info0_in_w, fetch_in_fault_page_w, fetch_in_fault_fetch_w})
        ,.info1_in_i({simple1_in_w, info1_in_w, fetch_in_fault_page_w, fetch_in_fault_fetch_w})
        ,.accept_o(fetch_in_accept_o)

        // Outputs
        ,.valid0_o(fetch_out0_valid_o)
        ,.pred_pc0_out_o(fetch_out0_pred_pc_o)
        ,.pc0_out_o(fetch_out0_pc_o)
        ,.data0_out_o(fetch_out0_instr_o)
        ,.info0_out_o({fetch_out0_instr_simple_exec_o, fetch_out0_instr_invalid_o, fetch_out0_instr_exec_o,
                       fetch_out0_instr_lsu_o,     fetch_out0_instr_branch_o,
                       fetch_out0_instr_mul_o,     fetch_out0_instr_div_o,
                       fetch_out0_instr_csr_o,     fetch_out0_instr_rd_valid_o,
                       fetch_out0_fault_page_o,    fetch_out0_fault_fetch_o})
        ,.pop0_i(fetch_out0_accept_i)

        ,.valid1_o(fetch_out1_valid_o)
        ,.pred_pc1_out_o(fetch_out1_pred_pc_o)
        ,.pc1_out_o(fetch_out1_pc_o)
        ,.data1_out_o(fetch_out1_instr_o)
        ,.info1_out_o({fetch_out1_instr_simple_exec_o, fetch_out1_instr_invalid_o, fetch_out1_instr_exec_o,
                       fetch_out1_instr_lsu_o,     fetch_out1_instr_branch_o,
                       fetch_out1_instr_mul_o,     fetch_out1_instr_div_o,
                       fetch_out1_instr_csr_o,     fetch_out1_instr_rd_valid_o,
                       fetch_out1_fault_page_o,    fetch_out1_fault_fetch_o})
        ,.pop1_i(fetch_out1_accept_i)
        ,.csr0_in_i(1'b0),.csr1_in_i(1'b0),.csr0_out_o(),.csr1_out_o()
    );
end
//-----------------------------------------------------------------
// 1 cycle frontend latency
//-----------------------------------------------------------------
else
begin
    wire [63:0] payload_in_w = (fetch_in_fault_page_i | fetch_in_fault_fetch_i) ? 64'b0 : fetch_in_instr_i;
    wire [2:0] roles0_in_w,roles1_in_w,roles0_encoded_w,roles1_encoded_w;
    triha_register_roles_predecode u_roles_in0(.opcode_i(payload_in_w[31:0]),.roles_o(roles0_in_w));
    triha_register_roles_predecode u_roles_in1(.opcode_i(payload_in_w[63:32]),.roles_o(roles1_in_w));
    // Roles follow opcode bulk history even on flush. Inverted encoding
    // makes reset-zero payload represent opcode0's conservative role111.
    assign fetch_out0_roles_o=~roles0_encoded_w;
    assign fetch_out1_roles_o=~roles1_encoded_w;
    wire csr0_in_w, csr1_in_w, csr0_history_w, csr1_history_w;
    wire exec0_in_w,exec1_in_w,exec0_history_w,exec1_history_w;
    wire simple0_in_w,simple1_in_w;
    wire [4:0] unit0_in_w,unit1_in_w;
    wire illegal0_in_w,illegal1_in_w,legal0_history_w,legal1_history_w;
    biriscv_decoder u_csr_hint0 (
        .valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(enable_muldiv_w),.opcode_i(payload_in_w[31:0]),
        .invalid_o(),.exec_o(),.lsu_o(unit0_in_w[4]),.branch_o(unit0_in_w[3]),
        .mul_o(unit0_in_w[2]),.div_o(unit0_in_w[1]),.csr_o(csr0_in_w),.rd_valid_o(unit0_in_w[0])
    );
    biriscv_decoder u_csr_hint1 (
        .valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(enable_muldiv_w),.opcode_i(payload_in_w[63:32]),
        .invalid_o(),.exec_o(),.lsu_o(unit1_in_w[4]),.branch_o(unit1_in_w[3]),
        .mul_o(unit1_in_w[2]),.div_o(unit1_in_w[1]),.csr_o(csr1_in_w),.rd_valid_o(unit1_in_w[0])
    );
    biriscv_decoder u_legal_hint0 (
        .valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(enable_muldiv_w),.opcode_i(payload_in_w[31:0]),
        .invalid_o(illegal0_in_w),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(),.rd_valid_o()
    );
    biriscv_decoder u_legal_hint1 (
        .valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(enable_muldiv_w),.opcode_i(payload_in_w[63:32]),
        .invalid_o(illegal1_in_w),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(),.rd_valid_o()
    );
    triha_exec_classify u_exec_class0 (.opcode_i(payload_in_w[31:0]),.exec_o(exec0_in_w),.simple_exec_o(simple0_in_w));
    triha_exec_classify u_exec_class1 (.opcode_i(payload_in_w[63:32]),.exec_o(exec1_in_w),.simple_exec_o(simple1_in_w));
    wire [8:0] alu0_decode_w,alu1_decode_w;
    triha_alu_predecode u_alu_in0 (.opcode_i(payload_in_w[31:0]),.control_o(alu0_decode_w));
    triha_alu_predecode u_alu_in1 (.opcode_i(payload_in_w[63:32]),.control_o(alu1_decode_w));
    triha_fetch_fifo
    #( .WIDTH(70), .OPC_INFO_W(19), .DEPTH(3) )
    u_fifo
    (
         .clk_i(clk_i)
        ,.rst_i(rst_i)

        ,.flush_i(branch_request_i)

        // Input side
        ,.push_i(fetch_in_valid_i)
        ,.pc_in_i(fetch_in_pc_i)
        ,.pred_pc_in_i(fetch_in_pred_pc_i)
        ,.pred_in_i(fetch_in_pred_branch_i)
        ,.data_in_i({~roles1_in_w,payload_in_w[63:32],~roles0_in_w,payload_in_w[31:0]})
        ,.info0_in_i({simple0_in_w, ~illegal0_in_w, unit0_in_w, alu0_decode_w, exec0_in_w, fetch_in_fault_page_i, fetch_in_fault_fetch_i})
        ,.info1_in_i({simple1_in_w, ~illegal1_in_w, unit1_in_w, alu1_decode_w, exec1_in_w, fetch_in_fault_page_i, fetch_in_fault_fetch_i})
        ,.accept_o(fetch_in_accept_o)

        // Outputs
        ,.valid0_o(fetch_out0_valid_o)
        ,.pred_pc0_out_o(fetch_out0_pred_pc_o)
        ,.pc0_out_o(fetch_out0_pc_o)
        ,.data0_out_o({roles0_encoded_w,fetch_out0_instr_o})
        ,.info0_out_o({fetch_out0_instr_simple_exec_o, legal0_history_w, fetch_out0_instr_lsu_o, fetch_out0_instr_branch_o, fetch_out0_instr_mul_o, fetch_out0_instr_div_o, fetch_out0_instr_rd_valid_o, fetch_out0_alu_decode_o, exec0_history_w, fetch_out0_fault_page_o, fetch_out0_fault_fetch_o})
        ,.pop0_i(fetch_out0_accept_i)

        ,.valid1_o(fetch_out1_valid_o)
        ,.pred_pc1_out_o(fetch_out1_pred_pc_o)
        ,.pc1_out_o(fetch_out1_pc_o)
        ,.data1_out_o({roles1_encoded_w,fetch_out1_instr_o})
        ,.info1_out_o({fetch_out1_instr_simple_exec_o, legal1_history_w, fetch_out1_instr_lsu_o, fetch_out1_instr_branch_o, fetch_out1_instr_mul_o, fetch_out1_instr_div_o, fetch_out1_instr_rd_valid_o, fetch_out1_alu_decode_o, exec1_history_w, fetch_out1_fault_page_o, fetch_out1_fault_fetch_o})
        ,.pop1_i(fetch_out1_accept_i)
        ,.csr0_in_i(csr0_in_w),.csr1_in_i(csr1_in_w)
        ,.csr0_out_o(csr0_history_w),.csr1_out_o(csr1_history_w)
    );

    // Exec classification depends only on the stored opcode. Carry it in
    // the same queue payload, including inactive history and reset opcode0.
    assign fetch_out0_instr_exec_o=exec0_history_w;
    assign fetch_out1_instr_exec_o=exec1_history_w;
    // Legality is opcode-only; qualify it with the original live valid.
    // This CSR expression preserves the old ternary for all four states.
    assign fetch_out0_instr_invalid_o=fetch_out0_valid_o && ~legal0_history_w;
    assign fetch_out0_instr_csr_o=csr0_history_w | fetch_out0_instr_invalid_o |
        fetch_out0_fault_fetch_o | fetch_out0_fault_page_o;
    assign fetch_out1_instr_invalid_o=fetch_out1_valid_o && ~legal1_history_w;
    assign fetch_out1_instr_csr_o=csr1_history_w | fetch_out1_instr_invalid_o |
        fetch_out1_fault_fetch_o | fetch_out1_fault_page_o;
end
endgenerate

endmodule

module triha_fetch_fifo
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
    parameter WIDTH   = 64,
    parameter DEPTH   = 2,
    parameter ADDR_W  = 1,
    parameter OPC_INFO_W = 10
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
     input                  clk_i
    ,input                  rst_i

    ,input                  flush_i

    // Input side
    ,input                  push_i
    ,input [31:0] pred_pc_in_i
    ,input  [31:0]          pc_in_i
    ,input  [1:0]           pred_in_i
    ,input  [WIDTH-1:0]     data_in_i
    ,input [OPC_INFO_W-1:0] info0_in_i
    ,input [OPC_INFO_W-1:0] info1_in_i
    ,output                 accept_o

    // Outputs
    ,output                 valid0_o
    ,output [31:0] pred_pc0_out_o
    ,output  [31:0]         pc0_out_o
    ,output [(WIDTH/2)-1:0] data0_out_o
    ,output[OPC_INFO_W-1:0] info0_out_o
    ,input                  pop0_i

    ,output                 valid1_o
    ,output [31:0] pred_pc1_out_o
    ,output  [31:0]         pc1_out_o
    ,output [(WIDTH/2)-1:0] data1_out_o
    ,output[OPC_INFO_W-1:0] info1_out_o
    ,input                  pop1_i
    ,input                  csr0_in_i
    ,input                  csr1_in_i
    ,output                 csr0_out_o
    ,output                 csr1_out_o
);

// Registered two-word head backed by an enqueue-only circular payload store.
// Read position advances by consumed words. B-only consumption preserves head0;
// its duplicate in the circular store is deliberately not read back.
localparam WORDS=2*DEPTH;
localparam PTR_W=ADDR_W+2;
localparam PAYLOAD_W=64+WIDTH/2+OPC_INFO_W+1;
reg [PAYLOAD_W-1:0] ring_q[0:WORDS-1];
reg [PAYLOAD_W-1:0] head0_q,head1_q;
reg [PTR_W-1:0] rd_q,wr_q;
reg [ADDR_W+1:0] count_q;
wire pop_a_w=pop0_i && valid0_o;
wire pop_b_w=pop1_i && valid1_o;
wire push_w=push_i && accept_o;
wire push_two_w=!pc_in_i[2] && !pred_in_i[0];
reg remove_a_r,remove_b_r;
reg [ADDR_W+1:0] remaining_r;
always @* begin
    remove_a_r=1'b1;if(!pop_a_w)remove_a_r=1'b0;
    remove_b_r=1'b1;if(!pop_b_w)remove_b_r=1'b0;
    remaining_r=count_q-remove_a_r-remove_b_r;
end
function [PTR_W-1:0] advance;
    input [PTR_W-1:0] pointer;
    input [2:0] amount;
    reg [PTR_W:0] total;
    begin
        total={1'b0,pointer}+amount;
        advance=total>=WORDS ? total-WORDS : total;
    end
endfunction
assign accept_o=count_q<=WORDS-2;
assign valid0_o=count_q!=0;
assign valid1_o=count_q>1 && pc1_out_o==pc0_out_o+32'd4;
wire [WIDTH/2-1:0] head_data0_w,head_data1_w;
assign {pred_pc0_out_o,pc0_out_o,head_data0_w,info0_out_o,csr0_out_o}=head0_q;
assign {pred_pc1_out_o,pc1_out_o,head_data1_w,info1_out_o,csr1_out_o}=head1_q;
wire [9:0] read_index0_w /* synthesis syn_maxfan=16 */;
wire [9:0] read_index1_w /* synthesis syn_maxfan=16 */;
assign read_index0_w=head_data0_w[24:15];
assign read_index1_w=head_data1_w[24:15];
assign data0_out_o={head_data0_w[WIDTH/2-1:25],read_index0_w,head_data0_w[14:0]};
assign data1_out_o={head_data1_w[WIDTH/2-1:25],read_index1_w,head_data1_w[14:0]};
wire [PAYLOAD_W-1:0] first_in_w=pc_in_i[2] ?
    {(pred_in_i[1]?pred_pc_in_i:{pc_in_i[31:3],3'b100}+32'd4),{pc_in_i[31:3],3'b100},data_in_i[WIDTH-1:WIDTH/2],info1_in_i,csr1_in_i} :
    {(pred_in_i[0]?pred_pc_in_i:{pc_in_i[31:3],3'b000}+32'd4),{pc_in_i[31:3],3'b000},data_in_i[WIDTH/2-1:0],info0_in_i,csr0_in_i};
wire [PAYLOAD_W-1:0] second_in_w=
    {(pred_in_i[1]?pred_pc_in_i:{pc_in_i[31:3],3'b100}+32'd4),{pc_in_i[31:3],3'b100},data_in_i[WIDTH-1:WIDTH/2],info1_in_i,csr1_in_i};
wire [PTR_W-1:0] wr_next_w=advance(wr_q,3'd1);
wire [PTR_W-1:0] rd_two_w=advance(rd_q,3'd2);
wire [PTR_W-1:0] rd_three_w=advance(rd_q,3'd3);
wire [PAYLOAD_W-1:0] third_w=ring_q[rd_two_w];
wire [PAYLOAD_W-1:0] fourth_w=ring_q[rd_three_w];
wire [PAYLOAD_W-1:0] shifted0_w=remove_a_r ? (remove_b_r?third_w:head1_q) : head0_q;
wire [PAYLOAD_W-1:0] shifted1_w=remove_a_r && remove_b_r ? fourth_w :
    ((remove_a_r || remove_b_r)?third_w:head1_q);
reg [PAYLOAD_W-1:0] next0_r,next1_r;
always @* begin
    next0_r=head0_q;next1_r=head1_q;
    if(push_w && remaining_r==0)next0_r=first_in_w;
    else if(remaining_r>0)next0_r=shifted0_w;
    if(push_w && remaining_r==1)next1_r=first_in_w;
    else if(push_w && push_two_w && remaining_r==0)next1_r=second_in_w;
    else if(remaining_r>1)next1_r=shifted1_w;
end
always @(posedge clk_i or posedge rst_i)
if(rst_i)begin
    head0_q<=0;head1_q<=0;
end else begin
    head0_q[PAYLOAD_W-1:OPC_INFO_W+1]<=next0_r[PAYLOAD_W-1:OPC_INFO_W+1];
    head1_q[PAYLOAD_W-1:OPC_INFO_W+1]<=next1_r[PAYLOAD_W-1:OPC_INFO_W+1];
    if(!flush_i)begin
        head0_q[OPC_INFO_W:0]<=next0_r[OPC_INFO_W:0];
        head1_q[OPC_INFO_W:0]<=next1_r[OPC_INFO_W:0];
    end
end
always @(posedge clk_i or posedge rst_i)
if(rst_i)begin count_q<=0;rd_q<=0;wr_q<=0;end
else if(flush_i)begin count_q<=0;rd_q<=0;wr_q<=0;end
else begin
    count_q<=remaining_r;
    rd_q<=advance(rd_q,{2'b00,remove_a_r}+{2'b00,remove_b_r});
    if(push_w)begin
        count_q<=remaining_r+(push_two_w?2:1);
        wr_q<=advance(wr_q,push_two_w?3'd2:3'd1);
    end
end
// No dequeue, count-after-dequeue, or flush in a backend payload write cone.
// Uninitialized backend slots cannot reach a valid head before being written.
// Passive backend aliases for component verification; no CPU consumer.
wire [WIDTH/2-1:0] data_q[0:WORDS-1];
wire [31:0] pc_q[0:WORDS-1],pred_pc_q[0:WORDS-1];
wire [OPC_INFO_W-1:0] info_q[0:WORDS-1];
wire csr_q[0:WORDS-1];
genvar slot;
generate for(slot=0;slot<WORDS;slot=slot+1)begin:g_ring
    assign {pred_pc_q[slot],pc_q[slot],data_q[slot],info_q[slot],csr_q[slot]}=ring_q[slot];
    always @(posedge clk_i)begin
        if(!rst_i && push_w && wr_q==slot)ring_q[slot]<=first_in_w;
        else if(!rst_i && push_w && push_two_w && wr_next_w==slot)ring_q[slot]<=second_in_w;
    end
end endgenerate
endmodule

// Exact execution class, grouped by the original opcode/function masks.
// Explicit funct3 coverage retains four-state behavior even for groups that
// cover all eight binary values. Immediate shifts intentionally ignore bit25.
module triha_exec_classify (
    input wire [31:0] opcode_i,
    output wire exec_o,
    output wire simple_exec_o
);
    wire [6:0] major_w=opcode_i[6:0];
    wire [2:0] funct3_w=opcode_i[14:12];
    wire [6:0] funct7_w=opcode_i[31:25];
    wire [5:0] funct6_w=opcode_i[31:26];
    wire any_funct3_w=(funct3_w==3'd0)||(funct3_w==3'd1)||
        (funct3_w==3'd2)||(funct3_w==3'd3)||(funct3_w==3'd4)||
        (funct3_w==3'd5)||(funct3_w==3'd6)||(funct3_w==3'd7);
    wire plain_imm_w=(funct3_w==3'd0)||(funct3_w==3'd2)||
        (funct3_w==3'd3)||(funct3_w==3'd4)||(funct3_w==3'd6)||(funct3_w==3'd7);
    wire shift_func_w=(funct3_w==3'd1)||(funct3_w==3'd5);
    wire sub_or_sra_w=(funct3_w==3'd0)||(funct3_w==3'd5);
    wire immediate_class_w /* synthesis syn_keep=1 */;
    wire register_class_w /* synthesis syn_keep=1 */;
    wire upper_class_w /* synthesis syn_keep=1 */;
    assign immediate_class_w=(major_w==7'h13) &&
        (plain_imm_w || ((funct6_w==6'h00)&&shift_func_w) ||
        ((funct6_w==6'h10)&&(funct3_w==3'd5)));
    assign register_class_w=(major_w==7'h33) &&
        (((funct7_w==7'h00)&&any_funct3_w) || ((funct7_w==7'h20)&&sub_or_sra_w));
    assign upper_class_w=(major_w==7'h37)||(major_w==7'h17);
    assign exec_o=immediate_class_w|register_class_w|upper_class_w;
    // Same capability test as the former late issue predicate, sampled with
    // the opcode/class payload rather than re-decoded after queue storage.
    wire register_shift_w=major_w==7'h33 &&
        ((funct7_w==7'h00 && funct3_w==3'b001) ||
         ((funct7_w==7'h00 || funct7_w==7'h20) && funct3_w==3'b101));
    assign simple_exec_o=exec_o && !register_shift_w;
endmodule

// Early control fields retain the original exact-match/unknown-skip decode.
// [8:5] ALU operation, [4:3] A source, [2:0] B source. Opcode0 resets0.
`include "biriscv_defs.v"
module triha_alu_predecode (
    input wire [31:0] opcode_i,
    output reg [8:0] control_o
);
    localparam [1:0] A_ZERO=0,A_REG=1,A_UPPER=2,A_PC=3;
    localparam [2:0] B_ZERO=0,B_REG=1,B_IMM=2,B_UPPER=3,B_SHIFT=4,B_FOUR=5;
    always @* begin
        control_o=9'b0;
        case(opcode_i[6:0])
            7'h33:case({opcode_i[31:25],opcode_i[14:12]})
                {7'h00,3'd0}:control_o={`ALU_ADD,A_REG,B_REG};
                {7'h00,3'd1}:control_o={`ALU_SHIFTL,A_REG,B_REG};
                {7'h00,3'd2}:control_o={`ALU_LESS_THAN_SIGNED,A_REG,B_REG};
                {7'h00,3'd3}:control_o={`ALU_LESS_THAN,A_REG,B_REG};
                {7'h00,3'd4}:control_o={`ALU_XOR,A_REG,B_REG};
                {7'h00,3'd5}:control_o={`ALU_SHIFTR,A_REG,B_REG};
                {7'h00,3'd6}:control_o={`ALU_OR,A_REG,B_REG};
                {7'h00,3'd7}:control_o={`ALU_AND,A_REG,B_REG};
                {7'h20,3'd0}:control_o={`ALU_SUB,A_REG,B_REG};
                {7'h20,3'd5}:control_o={`ALU_SHIFTR_ARITH,A_REG,B_REG};
                default:;
            endcase
            7'h13:case(opcode_i[14:12])
                3'd0:control_o={`ALU_ADD,A_REG,B_IMM};
                3'd2:control_o={`ALU_LESS_THAN_SIGNED,A_REG,B_IMM};
                3'd3:control_o={`ALU_LESS_THAN,A_REG,B_IMM};
                3'd4:control_o={`ALU_XOR,A_REG,B_IMM};
                3'd6:control_o={`ALU_OR,A_REG,B_IMM};
                3'd7:control_o={`ALU_AND,A_REG,B_IMM};
                3'd1:if(opcode_i[31:26]==6'h00)control_o={`ALU_SHIFTL,A_REG,B_SHIFT};
                3'd5:begin
                    if(opcode_i[31:26]==6'h00)control_o={`ALU_SHIFTR,A_REG,B_SHIFT};
                    else if(opcode_i[31:26]==6'h10)control_o={`ALU_SHIFTR_ARITH,A_REG,B_SHIFT};
                end
                default:;
            endcase
            7'h37:control_o={`ALU_NONE,A_UPPER,B_ZERO};
            7'h17:control_o={`ALU_ADD,A_PC,B_UPPER};
            7'h6f:control_o={`ALU_ADD,A_PC,B_FOUR};
            7'h67:if(opcode_i[14:12]==0)control_o={`ALU_ADD,A_PC,B_FOUR};
            default:;
        endcase
    end
endmodule


module triha_register_roles_predecode(input [31:0] opcode_i,output [2:0] roles_o);
function [2:0] register_roles;
    input [31:0] op;
    input invalid;
    input [1:0] fault;
    begin
        register_roles=3'b111;
        if(!invalid && fault==0) case(op[6:0])
            7'h37,7'h17,7'h6f: register_roles=3'b100;
            7'h67,7'h03,7'h13: register_roles=3'b101;
            7'h23,7'h63: register_roles=3'b011;
            7'h33: register_roles=3'b111;
            7'h73: register_roles=op[14:12]==0 ? 3'b000 : (op[14] ? 3'b100 : 3'b101);
            7'h0f: register_roles=3'b000;
            default: register_roles=3'b111;
        endcase
    end
endfunction
assign roles_o=register_roles(opcode_i,1'b0,2'b00);
endmodule
