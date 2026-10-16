`timescale 1ns/1ps
// Portable DIGITAL substitute for the native DDR IP interface only. No vendor
// training/calibration/physical timing is represented by this simulation model.
module ddr3_test #(

   parameter MEM_ROW_WIDTH       = 15          ,

   parameter MEM_COLUMN_WIDTH    = 10          ,

   parameter MEM_BANK_WIDTH      = 3           ,

  parameter MEM_DQ_WIDTH         =  32         ,

  parameter MEM_DM_WIDTH         =  4         ,

  parameter MEM_DQS_WIDTH        =  4         ,

   parameter CTRL_ADDR_WIDTH     = MEM_ROW_WIDTH + MEM_COLUMN_WIDTH + MEM_BANK_WIDTH
  )(
   input                              ref_clk                       ,
   input                              resetn                        ,
   output                             core_clk                      ,
   output                             pll_lock                      ,
   output                             phy_pll_lock                  ,
   output                             gpll_lock                     ,
   output                             rst_gpll_lock                 ,
   output                             ddrphy_cpd_lock               ,
   output                             ddr_init_done                 ,

   input  [CTRL_ADDR_WIDTH-1:0]       axi_awaddr                    ,
   input                              axi_awuser_ap                 ,
   input  [3:0]                       axi_awuser_id                 ,
   input  [3:0]                       axi_awlen                     ,
   output                             axi_awready                   ,
   input                              axi_awvalid                   ,

   input  [8*MEM_DQ_WIDTH-1:0]        axi_wdata                     ,
   input  [MEM_DQ_WIDTH-1:0]          axi_wstrb                     ,
   output                             axi_wready                    ,
   output [3:0]                       axi_wusero_id                 ,
   output                             axi_wusero_last               ,

   input  [CTRL_ADDR_WIDTH-1:0]       axi_araddr                    ,
   input                              axi_aruser_ap                 ,
   input  [3:0]                       axi_aruser_id                 ,
   input  [3:0]                       axi_arlen                     ,
   output                             axi_arready                   ,
   input                              axi_arvalid                   ,

   output [8*MEM_DQ_WIDTH-1:0]        axi_rdata                     ,
   output [3:0]                       axi_rid                       ,
   output                             axi_rlast                     ,
   output                             axi_rvalid                    ,

   input                              apb_clk                       ,
   input                              apb_rst_n                     ,
   input                              apb_sel                       ,
   input                              apb_enable                    ,
   input  [7:0]                       apb_addr                      ,
   input                              apb_write                     ,
   output                             apb_ready                     ,
   input  [15:0]                      apb_wdata                     ,
   output [15:0]                      apb_rdata                     ,


   output                             mem_cs_n                      ,

   output                             mem_rst_n                     ,
   output                             mem_ck                        ,
   output                             mem_ck_n                      ,
   output                             mem_cke                       ,
   output                             mem_ras_n                     ,
   output                             mem_cas_n                     ,
   output                             mem_we_n                      ,
   output                             mem_odt                       ,
   output [MEM_ROW_WIDTH-1:0]         mem_a                         ,
   output [MEM_BANK_WIDTH-1:0]        mem_ba                        ,
   inout  [MEM_DQS_WIDTH-1:0]         mem_dqs                       ,
   inout  [MEM_DQS_WIDTH-1:0]         mem_dqs_n                     ,
   inout  [MEM_DQ_WIDTH-1:0]          mem_dq                        ,
   output [MEM_DM_WIDTH-1:0]          mem_dm                        ,

   //debug
   input                              dbg_gate_start                ,
   input                              dbg_cpd_start                 ,
   input                              dbg_ddrphy_rst_n              ,
   input                              dbg_gpll_scan_rst             ,

   input                              samp_position_dyn_adj         ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_samp_position_even       ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_samp_position_odd        ,

   input                              wrcal_position_dyn_adj        ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_wrcal_position           ,

   input                              force_read_clk_ctrl           ,
   input  [4*MEM_DQS_WIDTH-1:0]       init_slip_step                ,
   input  [3*MEM_DQS_WIDTH-1:0]       init_read_clk_ctrl            ,

   output [33:0]                      debug_calib_ctrl              ,
   output [17*MEM_DQS_WIDTH -1:0]     dbg_slice_status              ,
   output [22*MEM_DQS_WIDTH -1:0]     dbg_slice_state               ,
   output [69*MEM_DQS_WIDTH -1:0]     debug_data                    ,
   output [1:0]                       dbg_dll_upd_state             ,
   output [8:0]                       debug_gpll_dps_phase          ,

   output [2:0]                       dbg_rst_dps_state             ,
   output [5:0]                       dbg_tran_err_rst_cnt          ,
   output                             dbg_ddrphy_init_fail          ,

   input                              debug_cpd_offset_adj          ,
   input                              debug_cpd_offset_dir          ,
   input  [9:0]                       debug_cpd_offset              ,
   output [9:0]                       debug_dps_cnt_dir0            ,
   output [9:0]                       debug_dps_cnt_dir1            ,

   input                              ck_dly_en                     ,
   input  [7:0]                       init_ck_dly_step              ,
   output [7:0]                       ck_dly_set_bin                ,

   output                             align_error                   ,
   output [3:0]                       debug_rst_state               ,
   output [3:0]                       debug_cpd_state
);

    reg model_init_enable=1,model_core_enable=1,model_drop_init=0,model_init_fail=0;
    reg model_align_error=0,model_drop_lock=0;
    reg [7:0] init_count;
    assign core_clk=ref_clk && model_core_enable;
    wire locked=resetn && !model_drop_lock;
    assign pll_lock=locked;
    assign phy_pll_lock=locked;
    assign gpll_lock=locked;
    assign rst_gpll_lock=locked;
    assign ddrphy_cpd_lock=locked;
    assign ddr_init_done=resetn && model_init_enable && init_count>=20 && !model_drop_init;
    assign dbg_ddrphy_init_fail=model_init_fail;
    assign align_error=model_align_error;
    always @(posedge core_clk or negedge resetn)
        if(!resetn)init_count<=0;else if(init_count<20)init_count<=init_count+1'b1;
    assign apb_ready=0;assign apb_rdata=0;
    assign mem_cs_n=1;assign mem_rst_n=resetn;assign mem_ck=core_clk;assign mem_ck_n=~core_clk;
    assign mem_cke=0;assign mem_ras_n=1;assign mem_cas_n=1;assign mem_we_n=1;
    assign mem_odt=0;assign mem_a=0;assign mem_ba=0;assign mem_dm=0;
    assign mem_dqs={MEM_DQS_WIDTH{1'bz}};assign mem_dqs_n={MEM_DQS_WIDTH{1'bz}};
    assign mem_dq={MEM_DQ_WIDTH{1'bz}};
    assign debug_calib_ctrl=0;assign dbg_slice_status=0;assign dbg_slice_state=0;
    assign debug_data=0;assign dbg_dll_upd_state=0;assign debug_gpll_dps_phase=0;
    assign dbg_rst_dps_state=0;assign dbg_tran_err_rst_cnt=0;assign debug_dps_cnt_dir0=0;
    assign debug_dps_cnt_dir1=0;assign ck_dly_set_bin=0;assign debug_rst_state=0;assign debug_cpd_state=0;
    integer write_beats,read_beats,earliest_beats,masked_beats,aw_commands,ar_commands,write_gaps;
    ddr_native_model #(.MEMORY_SLOTS(128)) native(.clk(core_clk),.reset_n(resetn),
        .fault_mode(0),.address_mask(28'hfffffff),.delayed(1'b1),
        .axi_awaddr(axi_awaddr),.axi_awvalid(axi_awvalid),.axi_awlen(axi_awlen),.axi_awuser_id(axi_awuser_id),
        .axi_awready(axi_awready),.axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),
        .axi_wready(axi_wready),.axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr),.axi_arvalid(axi_arvalid),.axi_arlen(axi_arlen),.axi_aruser_id(axi_aruser_id),
        .axi_arready(axi_arready),.axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid),
        .write_beats(write_beats),.read_beats(read_beats),.earliest_beats(earliest_beats),.masked_beats(masked_beats),
        .aw_commands(aw_commands),.ar_commands(ar_commands),.write_gaps(write_gaps));
    always @(posedge core_clk)if(resetn)begin
        if({apb_clk,apb_rst_n,apb_sel,apb_enable,apb_addr,apb_write,apb_wdata} !==
            {1'b0,1'b1,1'b0,1'b0,8'd0,1'b0,16'd0})$fatal(1,"APB inactive tie-off mismatch");
        if({dbg_gate_start,dbg_cpd_start,dbg_ddrphy_rst_n,dbg_gpll_scan_rst,
            samp_position_dyn_adj,init_samp_position_even,init_samp_position_odd,
            wrcal_position_dyn_adj,init_wrcal_position,force_read_clk_ctrl,init_slip_step,init_read_clk_ctrl,
            debug_cpd_offset_adj,debug_cpd_offset_dir,debug_cpd_offset,ck_dly_en,init_ck_dly_step} !==
            {1'b0,1'b0,1'b1,1'b0,1'b0,32'd0,32'd0,1'b0,32'd0,1'b0,16'd0,12'd0,1'b0,1'b0,10'd0,1'b0,8'd0})
            $fatal(1,"Dynamic debug tie-off mismatch");
        if(!ddr_init_done && (axi_awvalid || axi_arvalid))$fatal(1,"Native command before init");
    end
endmodule
module GTP_INBUFDS(input wire I,IB,output wire O);
    assign O=I;
endmodule
module GTP_CLKBUFG(input wire CLKIN,output wire CLKOUT);
    assign CLKOUT=CLKIN;
endmodule
