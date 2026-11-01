//-----------------------------------------------------------------
//                         biRISC-V CPU
//                            V0.8.1
//                     Ultra-Embedded.com
//                     Copyright 2019-2020
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------

// TriHa maintained LSU derivative; see ADAPTATIONS.json.
module triha_lsu
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter MEM_CACHE_ADDR_MIN = 0
    ,parameter MEM_CACHE_ADDR_MAX = 32'hffffffff
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           opcode_valid_i
    ,input  [ 31:0]  opcode_opcode_i
    ,input  [ 31:0]  opcode_pc_i
    ,input           opcode_invalid_i
    ,input  [  4:0]  opcode_rd_idx_i
    ,input  [  4:0]  opcode_ra_idx_i
    ,input  [  4:0]  opcode_rb_idx_i
    ,input  [ 31:0]  opcode_ra_operand_i
    ,input  [ 31:0]  opcode_rb_operand_i
    ,input  [ 31:0]  mem_data_rd_i
    ,input           mem_accept_i
    ,input           mem_ack_i
    ,input           mem_error_i
    ,input  [ 10:0]  mem_resp_tag_i
    ,input           mem_load_fault_i
    ,input           mem_store_fault_i

    // Outputs
    ,output [ 31:0]  mem_addr_o
    ,output [ 31:0]  mem_data_wr_o
    ,output          mem_rd_o
    ,output [  3:0]  mem_wr_o
    ,output          mem_cacheable_o
    ,output [ 10:0]  mem_req_tag_o
    ,output          mem_invalidate_o
    ,output          mem_writeback_o
    ,output          mem_flush_o
    ,output          writeback_valid_o
    ,output [ 31:0]  writeback_value_o
    ,output [31:0]   writeback_bypass_o
    ,output [  5:0]  writeback_exception_o
    ,output          stall_o
);



//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "biriscv_defs.v"

//-----------------------------------------------------------------
// Registers / Wires
//-----------------------------------------------------------------
reg [ 31:0]  mem_addr_q;
reg [ 31:0]  mem_data_wr_q;
reg          mem_rd_q;
reg [  3:0]  mem_wr_q;
reg          mem_cacheable_q;
reg          mem_invalidate_q;
reg          mem_writeback_q;
reg          mem_flush_q;
reg          mem_unaligned_e1_q;
reg          mem_unaligned_e2_q;

reg          mem_load_q;
reg          mem_xb_q;
reg          mem_xh_q;
reg          mem_ls_q;

//-----------------------------------------------------------------
// Outstanding Access Tracking
//-----------------------------------------------------------------
reg pending_lsu_e2_q;

wire issue_lsu_e1_w    = (mem_rd_o || (|mem_wr_o) || mem_writeback_o || mem_invalidate_o || mem_flush_o) && mem_accept_i;
wire complete_ok_e2_w  = mem_ack_i & ~mem_error_i;
wire complete_err_e2_w = mem_ack_i & mem_error_i;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pending_lsu_e2_q <= 1'b0;
else if (issue_lsu_e1_w)
    pending_lsu_e2_q <= 1'b1;
else if (complete_ok_e2_w || complete_err_e2_w)
    pending_lsu_e2_q <= 1'b0;

// Delay next instruction if outstanding response is late
wire delay_lsu_e2_w = pending_lsu_e2_q && !complete_ok_e2_w;

//-----------------------------------------------------------------
// Dummy Ack (unaligned access /E2)
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    mem_unaligned_e2_q <= 1'b0;
else
    mem_unaligned_e2_q <= mem_unaligned_e1_q & ~delay_lsu_e2_w;

//-----------------------------------------------------------------
// Opcode decode
//-----------------------------------------------------------------

wire load_inst_w = (((opcode_opcode_i & `INST_LB_MASK) == `INST_LB)  || 
                    ((opcode_opcode_i & `INST_LH_MASK) == `INST_LH)  || 
                    ((opcode_opcode_i & `INST_LW_MASK) == `INST_LW)  || 
                    ((opcode_opcode_i & `INST_LBU_MASK) == `INST_LBU) || 
                    ((opcode_opcode_i & `INST_LHU_MASK) == `INST_LHU) || 
                    ((opcode_opcode_i & `INST_LWU_MASK) == `INST_LWU));

wire load_signed_inst_w = (((opcode_opcode_i & `INST_LB_MASK) == `INST_LB)  || 
                           ((opcode_opcode_i & `INST_LH_MASK) == `INST_LH)  || 
                           ((opcode_opcode_i & `INST_LW_MASK) == `INST_LW));

wire store_inst_w = (((opcode_opcode_i & `INST_SB_MASK) == `INST_SB)  || 
                     ((opcode_opcode_i & `INST_SH_MASK) == `INST_SH)  || 
                     ((opcode_opcode_i & `INST_SW_MASK) == `INST_SW));

wire req_lb_w = ((opcode_opcode_i & `INST_LB_MASK) == `INST_LB) || ((opcode_opcode_i & `INST_LBU_MASK) == `INST_LBU);
wire req_lh_w = ((opcode_opcode_i & `INST_LH_MASK) == `INST_LH) || ((opcode_opcode_i & `INST_LHU_MASK) == `INST_LHU);
wire req_lw_w = ((opcode_opcode_i & `INST_LW_MASK) == `INST_LW) || ((opcode_opcode_i & `INST_LWU_MASK) == `INST_LWU);
wire req_sb_w = ((opcode_opcode_i & `INST_LB_MASK) == `INST_SB);
wire req_sh_w = ((opcode_opcode_i & `INST_LH_MASK) == `INST_SH);
wire req_sw_w = ((opcode_opcode_i & `INST_LW_MASK) == `INST_SW);

wire req_sw_lw_w = ((opcode_opcode_i & `INST_SW_MASK) == `INST_SW) || ((opcode_opcode_i & `INST_LW_MASK) == `INST_LW) || ((opcode_opcode_i & `INST_LWU_MASK) == `INST_LWU);
wire req_sh_lh_w = ((opcode_opcode_i & `INST_SH_MASK) == `INST_SH) || ((opcode_opcode_i & `INST_LH_MASK) == `INST_LH) || ((opcode_opcode_i & `INST_LHU_MASK) == `INST_LHU);

reg [31:0]  mem_addr_r;
reg         mem_unaligned_r;
reg [31:0]  mem_data_r;
reg         mem_rd_r;
reg [3:0]   mem_wr_r;

always @ *
begin
    mem_addr_r      = 32'b0;
    mem_data_r      = 32'b0;
    mem_unaligned_r = 1'b0;
    mem_wr_r        = 4'b0;
    mem_rd_r        = 1'b0;

    if ((opcode_opcode_i & `INST_CSRRW_MASK) == `INST_CSRRW)
        mem_addr_r = opcode_ra_operand_i;
    else if (load_inst_w)
        mem_addr_r = opcode_ra_operand_i + {{20{opcode_opcode_i[31]}}, opcode_opcode_i[31:20]};
    else
        mem_addr_r = opcode_ra_operand_i + {{20{opcode_opcode_i[31]}}, opcode_opcode_i[31:25], opcode_opcode_i[11:7]};

    if (opcode_valid_i && req_sw_lw_w)
        mem_unaligned_r = (mem_addr_r[1:0] != 2'b0);
    else if (opcode_valid_i && req_sh_lh_w)
        mem_unaligned_r = mem_addr_r[0];

    mem_rd_r = (opcode_valid_i && load_inst_w && !mem_unaligned_r);

    if ((opcode_opcode_i & `INST_SW_MASK) == `INST_SW)
    begin
        mem_data_r  = opcode_rb_operand_i;
        mem_wr_r    = 4'hF;
    end
    else if ((opcode_opcode_i & `INST_SH_MASK) == `INST_SH)
    begin
        case (mem_addr_r[1:0])
        2'h2 :
        begin
            mem_data_r  = {opcode_rb_operand_i[15:0],16'h0000};
            mem_wr_r    = 4'b1100;
        end
        default :
        begin
            mem_data_r  = {16'h0000,opcode_rb_operand_i[15:0]};
            mem_wr_r    = 4'b0011;
        end
        endcase
    end
    else if ((opcode_opcode_i & `INST_SB_MASK) == `INST_SB)
    begin
        case (mem_addr_r[1:0])
        2'h3 :
        begin
            mem_data_r  = {opcode_rb_operand_i[7:0],24'h000000};
            mem_wr_r    = 4'b1000;
        end
        2'h2 :
        begin
            mem_data_r  = {{8'h00,opcode_rb_operand_i[7:0]},16'h0000};
            mem_wr_r    = 4'b0100;
        end
        2'h1 :
        begin
            mem_data_r  = {{16'h0000,opcode_rb_operand_i[7:0]},8'h00};
            mem_wr_r    = 4'b0010;
        end
        2'h0 :
        begin
            mem_data_r  = {24'h000000,opcode_rb_operand_i[7:0]};
            mem_wr_r    = 4'b0001;
        end
        default :
        ;
        endcase
    end
    else
        mem_wr_r    = 4'b0;
    // Late validity qualifies strobes, not payload computation.
    if (!opcode_valid_i || mem_unaligned_r)
        mem_wr_r = 4'b0;

end

wire dcache_flush_w      = ((opcode_opcode_i & `INST_CSRRW_MASK) == `INST_CSRRW) && (opcode_opcode_i[31:20] == `CSR_DFLUSH);
wire dcache_writeback_w  = ((opcode_opcode_i & `INST_CSRRW_MASK) == `INST_CSRRW) && (opcode_opcode_i[31:20] == `CSR_DWRITEBACK);
wire dcache_invalidate_w = ((opcode_opcode_i & `INST_CSRRW_MASK) == `INST_CSRRW) && (opcode_opcode_i[31:20] == `CSR_DINVALIDATE);

//-----------------------------------------------------------------
// Sequential
//-----------------------------------------------------------------

// Wide request payload holds while waiting for a response or for acceptance.
// Late fault/issue-valid signals affect controls, not these data flops.
wire payload_wait_w = pending_lsu_e2_q && !mem_ack_i;
wire payload_request_w = mem_rd_q || (|mem_wr_q) || mem_writeback_q ||
                         mem_invalidate_q || mem_flush_q;
wire payload_hold_w = ((mem_rd_q || (|mem_wr_q) || mem_unaligned_e1_q) && payload_wait_w) ||
                      (payload_request_w && !mem_accept_i);
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    mem_addr_q      <= 32'b0;
    mem_data_wr_q   <= 32'b0;
    mem_cacheable_q <= 1'b0;
end
else if (!payload_hold_w)
begin
    mem_addr_q      <= mem_addr_r;
    mem_data_wr_q   <= mem_data_r;
/* verilator lint_off UNSIGNED */
/* verilator lint_off CMPCONST */
    mem_cacheable_q <= (mem_addr_r >= MEM_CACHE_ADDR_MIN && mem_addr_r <= MEM_CACHE_ADDR_MAX) ||
                      dcache_invalidate_w || dcache_writeback_w || dcache_flush_w;
/* verilator lint_on CMPCONST */
/* verilator lint_on UNSIGNED */
end

// Original request-control cancellation and response sequencing.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    mem_rd_q           <= 1'b0;
    mem_wr_q           <= 4'b0;
    mem_invalidate_q   <= 1'b0;
    mem_writeback_q    <= 1'b0;
    mem_flush_q        <= 1'b0;
    mem_unaligned_e1_q <= 1'b0;
    mem_load_q         <= 1'b0;
    mem_xb_q           <= 1'b0;
    mem_xh_q           <= 1'b0;
    mem_ls_q           <= 1'b0;
end
// Memory access fault - squash next operation (exception coming...)
else if (complete_err_e2_w || mem_unaligned_e2_q)
begin
    mem_rd_q           <= 1'b0;
    mem_wr_q           <= 4'b0;
    mem_invalidate_q   <= 1'b0;
    mem_writeback_q    <= 1'b0;
    mem_flush_q        <= 1'b0;
    mem_unaligned_e1_q <= 1'b0;
    mem_load_q         <= 1'b0;
    mem_xb_q           <= 1'b0;
    mem_xh_q           <= 1'b0;
    mem_ls_q           <= 1'b0;
end
else if ((mem_rd_q || (|mem_wr_q) || mem_unaligned_e1_q) && delay_lsu_e2_w)
    ;
else if (!((mem_writeback_o || mem_invalidate_o || mem_flush_o || mem_rd_o || mem_wr_o != 4'b0) && !mem_accept_i))
begin
    mem_rd_q           <= mem_rd_r;
    mem_wr_q           <= mem_wr_r;
    mem_invalidate_q   <= 1'b0;
    mem_writeback_q    <= 1'b0;
    mem_flush_q        <= 1'b0;
    mem_unaligned_e1_q <= mem_unaligned_r;
    mem_load_q         <= opcode_valid_i && load_inst_w;
    mem_xb_q           <= req_lb_w | req_sb_w;
    mem_xh_q           <= req_lh_w | req_sh_w;
    mem_ls_q           <= load_signed_inst_w;

    mem_invalidate_q <= opcode_valid_i & dcache_invalidate_w;
    mem_writeback_q  <= opcode_valid_i & dcache_writeback_w;
    mem_flush_q      <= opcode_valid_i & dcache_flush_w;
end

assign mem_addr_o       = {mem_addr_q[31:2], 2'b0};
assign mem_data_wr_o    = mem_data_wr_q;
assign mem_rd_o         = mem_rd_q & ~delay_lsu_e2_w;
assign mem_wr_o         = mem_wr_q & ~{4{delay_lsu_e2_w}};
assign mem_cacheable_o  = mem_cacheable_q;
assign mem_req_tag_o    = 11'b0;
assign mem_invalidate_o = mem_invalidate_q;
assign mem_writeback_o  = mem_writeback_q;
assign mem_flush_o      = mem_flush_q;

// Stall upstream if cache is busy
assign stall_o          = ((mem_writeback_o || mem_invalidate_o || mem_flush_o || mem_rd_o || mem_wr_o != 4'b0) && !mem_accept_i) || delay_lsu_e2_w || mem_unaligned_e1_q;

wire        resp_load_w;
wire [31:0] resp_addr_w;
wire        resp_byte_w;
wire        resp_half_w;
wire        resp_signed_w;

triha_lsu_fifo
#(
     .WIDTH(36)
    ,.DEPTH(2)
    ,.ADDR_W(1)
)
u_lsu_request
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(((mem_rd_o || (|mem_wr_o) || mem_writeback_o || mem_invalidate_o || mem_flush_o) && mem_accept_i) || (mem_unaligned_e1_q && ~delay_lsu_e2_w))
    ,.data_in_i({mem_addr_q, mem_ls_q, mem_xh_q, mem_xb_q, mem_load_q})
    ,.accept_o()

    ,.valid_o()
    ,.data_out_o({resp_addr_w, resp_signed_w, resp_half_w, resp_byte_w, resp_load_w})
    ,.pop_i(mem_ack_i || mem_unaligned_e2_q)
);

//-----------------------------------------------------------------
// Load response
//-----------------------------------------------------------------
reg [1:0]  addr_lsb_r;
reg        load_byte_r;
reg        load_half_r;
reg        load_signed_r;
reg [31:0] wb_result_r;

always @ *
begin
    wb_result_r   = 32'b0;

    // Tag associated with load
    addr_lsb_r    = resp_addr_w[1:0];
    load_byte_r   = resp_byte_w;
    load_half_r   = resp_half_w;
    load_signed_r = resp_signed_w;

    // Pure payload decode. The E2 forwarding path must not depend on the
    // response valid/error controls; issue/commit validity remains separate.
    begin
        if (load_byte_r)
        begin
            case (addr_lsb_r[1:0])
            2'h3: wb_result_r = {24'b0, mem_data_rd_i[31:24]};
            2'h2: wb_result_r = {24'b0, mem_data_rd_i[23:16]};
            2'h1: wb_result_r = {24'b0, mem_data_rd_i[15:8]};
            2'h0: wb_result_r = {24'b0, mem_data_rd_i[7:0]};
            endcase

            if (load_signed_r && wb_result_r[7])
                wb_result_r = {24'hFFFFFF, wb_result_r[7:0]};
        end
        else if (load_half_r)
        begin
            if (addr_lsb_r[1])
                wb_result_r = {16'b0, mem_data_rd_i[31:16]};
            else
                wb_result_r = {16'b0, mem_data_rd_i[15:0]};

            if (load_signed_r && wb_result_r[15])
                wb_result_r = {16'hFFFF, wb_result_r[15:0]};
        end
        else
            wb_result_r = mem_data_rd_i;
    end
end

assign writeback_valid_o    = mem_ack_i | mem_unaligned_e2_q;
// Preserve the original completion/badaddr payload for precise exceptions.
reg [31:0] wb_commit_r;
always @ *
begin
    wb_commit_r = 32'b0;
    if ((mem_ack_i && mem_error_i) || mem_unaligned_e2_q)
        wb_commit_r = resp_addr_w;
    else if (mem_ack_i && resp_load_w)
        wb_commit_r = wb_result_r;
end
assign writeback_value_o    = wb_commit_r;
assign writeback_bypass_o   = wb_result_r;

wire fault_load_align_w     = mem_unaligned_e2_q & resp_load_w;
wire fault_store_align_w    = mem_unaligned_e2_q & ~resp_load_w;
wire fault_load_bus_w       = mem_error_i &&  resp_load_w;
wire fault_store_bus_w      = mem_error_i && ~resp_load_w;
wire fault_load_page_w      = mem_error_i && mem_load_fault_i;
wire fault_store_page_w     = mem_error_i && mem_store_fault_i;


assign writeback_exception_o         = fault_load_align_w  ? `EXCEPTION_MISALIGNED_LOAD:
                                       fault_store_align_w ? `EXCEPTION_MISALIGNED_STORE:
                                       fault_load_page_w   ? `EXCEPTION_PAGE_FAULT_LOAD:
                                       fault_store_page_w  ? `EXCEPTION_PAGE_FAULT_STORE:
                                       fault_load_bus_w    ? `EXCEPTION_FAULT_LOAD:
                                       fault_store_bus_w   ? `EXCEPTION_FAULT_STORE:
                                       `EXCEPTION_W'b0;

endmodule 

module triha_lsu_fifo
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
    parameter WIDTH   = 8,
    parameter DEPTH   = 4,
    parameter ADDR_W  = 2
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input               clk_i
    ,input               rst_i
    ,input  [WIDTH-1:0]  data_in_i
    ,input               push_i
    ,input               pop_i

    // Outputs
    ,output [WIDTH-1:0]  data_out_o
    ,output              accept_o
    ,output              valid_o
);

generate
if (DEPTH == 2 && ADDR_W == 1) begin: g_head
    // Same circular storage in read-relative coordinates:
    // head = ram[rd_ptr], tail = ram[~rd_ptr]. On a pop the banks rotate.
    // Retaining the old head as tail also preserves data_out while empty.
    reg [WIDTH-1:0] head_q;
    reg [WIDTH-1:0] tail_q;
    reg [1:0] count_q;
    wire push_w = push_i && accept_o;
    wire pop_w = pop_i && valid_o;

    assign valid_o = count_q != 2'd0;
    assign accept_o = count_q != 2'd2;
    assign data_out_o = head_q;

    always @(posedge clk_i or posedge rst_i)
    if (rst_i) begin
        head_q <= {WIDTH{1'b0}};
        tail_q <= {WIDTH{1'b0}};
        count_q <= 2'd0;
    end else begin
        case ({pop_w,push_w})
            2'b01: begin
                if (count_q == 2'd0)
                    head_q <= data_in_i;
                else
                    tail_q <= data_in_i;
            end
            2'b10: begin
                head_q <= tail_q;
                tail_q <= head_q;
            end
            2'b11: begin
                // Only count=1 can accept both: replace the next head.
                head_q <= data_in_i;
                tail_q <= head_q;
            end
            default: ;
        endcase
        if (push_w && !pop_w)
            count_q <= count_q + 2'd1;
        else if (!push_w && pop_w)
            count_q <= count_q - 2'd1;
    end
end else begin: g_ring

//-----------------------------------------------------------------
// Local Params
//-----------------------------------------------------------------
localparam COUNT_W = ADDR_W + 1;

//-----------------------------------------------------------------
// Registers
//-----------------------------------------------------------------
reg [WIDTH-1:0]   ram_q[DEPTH-1:0];
reg [ADDR_W-1:0]  rd_ptr_q;
reg [ADDR_W-1:0]  wr_ptr_q;
reg [COUNT_W-1:0] count_q;

integer i;

//-----------------------------------------------------------------
// Sequential
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    count_q   <= {(COUNT_W) {1'b0}};
    rd_ptr_q  <= {(ADDR_W) {1'b0}};
    wr_ptr_q  <= {(ADDR_W) {1'b0}};

    for (i=0;i<DEPTH;i=i+1)
    begin
        ram_q[i] <= {(WIDTH) {1'b0}};
    end
end
else
begin
    // Push
    if (push_i & accept_o)
    begin
        ram_q[wr_ptr_q] <= data_in_i;
        wr_ptr_q        <= wr_ptr_q + 1;
    end

    // Pop
    if (pop_i & valid_o)
        rd_ptr_q      <= rd_ptr_q + 1;

    // Count up
    if ((push_i & accept_o) & ~(pop_i & valid_o))
        count_q <= count_q + 1;
    // Count down
    else if (~(push_i & accept_o) & (pop_i & valid_o))
        count_q <= count_q - 1;
end

//-------------------------------------------------------------------
// Combinatorial
//-------------------------------------------------------------------
/* verilator lint_off WIDTH */
assign valid_o       = (count_q != 0);
assign accept_o      = (count_q != DEPTH);
/* verilator lint_on WIDTH */

assign data_out_o    = ram_q[rd_ptr_q];

end
endgenerate

endmodule
