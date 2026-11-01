// Derived from frozen upstream TB SHA256 f9022e2bf1a74643d0e383e90d52a221c781383a4d9d53058bbc11fbb4efbbd2.
// All public outputs are compared cycle-for-cycle against the unchanged payload RTL.
`timescale 1ns/1ps
module tb_b03_input_compact #(parameter integer TRUSTED_MODEL=0);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,run_ce=0,cancel_request=0;
    reg cmd_valid=0;wire cmd_ready;reg[1:0]cmd_kind=0;reg[1023:0]op_words=0;
    reg[31:0]workspace_base=32'h100000,resolved_src_base=32'h10000,epoch=1,cmd_tag=0;
    reg[8:0]row_y=0,x_begin=0;reg[4:0]m_count=0;
    wire done_valid;reg done_ready=0;wire[31:0]done_status,done_detail,done_tag;
    wire param_valid,rows_valid,a_valid;reg[2:0]param_group=0;wire[255:0]bias_flat,mult_flat;wire[47:0]shift_flat;wire[63:0]shadow_valid;wire[95:0]aux_coeff;
    reg a_req_valid=0,b_req_valid=0,dw_req_valid=0;wire a_req_ready,b_req_ready,dw_req_ready;
    reg[9:0]a_req_row=0,b_req_row=0;reg[31:0]a_req_tag=0,b_req_tag=0,dw_req_tag=0;
    wire a_rsp_valid,b_rsp_valid,dw_rsp_valid,a_rsp_error,b_rsp_error,dw_rsp_error;
    wire[127:0]a_rsp_data,b_rsp_data,dw_rsp_data;wire[31:0]a_rsp_tag,b_rsp_tag,dw_rsp_tag;
    reg[3:0]dw_req_tap=0;reg[8:0]dw_req_ox=0;reg[6:0]dw_req_co_base=0;
    wire mem_req_valid;wire mem_req_ready;wire mem_req_write,mem_req_verify;
    wire[31:0]mem_req_offset,mem_req_tag;wire[4:0]mem_req_beats;wire[2:0]mem_req_client;
    wire mem_w_valid,mem_w_last;reg mem_w_ready=0;wire[255:0]mem_w_data;wire[31:0]mem_w_strb;
    reg mem_r_valid=0,mem_r_last=0;wire mem_r_ready;reg[255:0]mem_r_data=0;
    reg mem_rsp_valid=0;wire mem_rsp_ready;reg[3:0]mem_rsp_status=0;reg[31:0]mem_rsp_tag=0;
    wire busy,reset_required;wire[7:0]debug_state;wire[31:0]cycles,read_bytes;
    b03_model_input_payload #(.TRUSTED_MODEL(TRUSTED_MODEL)) dut(.*);
generate if(!TRUSTED_MODEL)begin:default_lockstep
wire cmd_ready_compact;
wire done_valid_compact;
wire [31:0] done_status_compact;
wire [31:0] done_detail_compact;
wire [31:0] done_tag_compact;
wire param_valid_compact;
wire rows_valid_compact;
wire a_valid_compact;
wire [255:0] bias_flat_compact;
wire [255:0] mult_flat_compact;
wire [47:0] shift_flat_compact;
wire [63:0] shadow_valid_compact;
wire [95:0] aux_coeff_compact;
wire a_req_ready_compact;
wire a_rsp_valid_compact;
wire [127:0] a_rsp_data_compact;
wire [31:0] a_rsp_tag_compact;
wire a_rsp_error_compact;
wire b_req_ready_compact;
wire b_rsp_valid_compact;
wire [127:0] b_rsp_data_compact;
wire [31:0] b_rsp_tag_compact;
wire b_rsp_error_compact;
wire dw_req_ready_compact;
wire dw_rsp_valid_compact;
wire [127:0] dw_rsp_data_compact;
wire [31:0] dw_rsp_tag_compact;
wire dw_rsp_error_compact;
wire mem_req_valid_compact;
wire mem_req_write_compact;
wire mem_req_verify_compact;
wire [31:0] mem_req_offset_compact;
wire [31:0] mem_req_tag_compact;
wire [4:0] mem_req_beats_compact;
wire [2:0] mem_req_client_compact;
wire mem_w_valid_compact;
wire [255:0] mem_w_data_compact;
wire [31:0] mem_w_strb_compact;
wire mem_w_last_compact;
wire mem_r_ready_compact;
wire mem_rsp_ready_compact;
wire busy_compact;
wire reset_required_compact;
wire [7:0] debug_state_compact;
wire [31:0] cycles_compact;
wire [31:0] read_bytes_compact;
b03_model_input_compact compact(.clk(clk),.rst_n(rst_n),.run_ce(run_ce),.cancel_request(cancel_request),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready_compact),.cmd_kind(cmd_kind),.op_words(op_words),.workspace_base(workspace_base),.resolved_src_base(resolved_src_base),.epoch(epoch),.cmd_tag(cmd_tag),.row_y(row_y),.x_begin(x_begin),.m_count(m_count),.done_valid(done_valid_compact),.done_ready(done_ready),.done_status(done_status_compact),.done_detail(done_detail_compact),.done_tag(done_tag_compact),.param_valid(param_valid_compact),.rows_valid(rows_valid_compact),.a_valid(a_valid_compact),.param_group(param_group),.bias_flat(bias_flat_compact),.mult_flat(mult_flat_compact),.shift_flat(shift_flat_compact),.shadow_valid(shadow_valid_compact),.aux_coeff(aux_coeff_compact),.a_req_valid(a_req_valid),.a_req_ready(a_req_ready_compact),.a_req_row(a_req_row),.a_req_tag(a_req_tag),.a_rsp_valid(a_rsp_valid_compact),.a_rsp_data(a_rsp_data_compact),.a_rsp_tag(a_rsp_tag_compact),.a_rsp_error(a_rsp_error_compact),.b_req_valid(b_req_valid),.b_req_ready(b_req_ready_compact),.b_req_row(b_req_row),.b_req_tag(b_req_tag),.b_rsp_valid(b_rsp_valid_compact),.b_rsp_data(b_rsp_data_compact),.b_rsp_tag(b_rsp_tag_compact),.b_rsp_error(b_rsp_error_compact),.dw_req_valid(dw_req_valid),.dw_req_ready(dw_req_ready_compact),.dw_req_tap(dw_req_tap),.dw_req_ox(dw_req_ox),.dw_req_co_base(dw_req_co_base),.dw_req_tag(dw_req_tag),.dw_rsp_valid(dw_rsp_valid_compact),.dw_rsp_data(dw_rsp_data_compact),.dw_rsp_tag(dw_rsp_tag_compact),.dw_rsp_error(dw_rsp_error_compact),.mem_req_valid(mem_req_valid_compact),.mem_req_ready(mem_req_ready),.mem_req_write(mem_req_write_compact),.mem_req_verify(mem_req_verify_compact),.mem_req_offset(mem_req_offset_compact),.mem_req_tag(mem_req_tag_compact),.mem_req_beats(mem_req_beats_compact),.mem_req_client(mem_req_client_compact),.mem_w_valid(mem_w_valid_compact),.mem_w_ready(mem_w_ready),.mem_w_data(mem_w_data_compact),.mem_w_strb(mem_w_strb_compact),.mem_w_last(mem_w_last_compact),.mem_r_valid(mem_r_valid),.mem_r_ready(mem_r_ready_compact),.mem_r_data(mem_r_data),.mem_r_last(mem_r_last),.mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready_compact),.mem_rsp_status(mem_rsp_status),.mem_rsp_tag(mem_rsp_tag),.busy(busy_compact),.reset_required(reset_required_compact),.debug_state(debug_state_compact),.cycles(cycles_compact),.read_bytes(read_bytes_compact));
integer equivalence_cycles=0;
always @(posedge clk)begin
 #1;
 if(rst_n)begin
  if(cmd_ready !== cmd_ready_compact)$fatal(1,"compact lockstep cmd_ready differs state=%0d",debug_state);
  if(done_valid !== done_valid_compact)$fatal(1,"compact lockstep done_valid differs state=%0d",debug_state);
  if(done_status !== done_status_compact)$fatal(1,"compact lockstep done_status differs state=%0d",debug_state);
  if(done_detail !== done_detail_compact)$fatal(1,"compact lockstep done_detail differs state=%0d",debug_state);
  if(done_tag !== done_tag_compact)$fatal(1,"compact lockstep done_tag differs state=%0d",debug_state);
  if(param_valid !== param_valid_compact)$fatal(1,"compact lockstep param_valid differs state=%0d",debug_state);
  if(rows_valid !== rows_valid_compact)$fatal(1,"compact lockstep rows_valid differs state=%0d",debug_state);
  if(a_valid !== a_valid_compact)$fatal(1,"compact lockstep a_valid differs state=%0d",debug_state);
  if(bias_flat !== bias_flat_compact)$fatal(1,"compact lockstep bias_flat differs state=%0d",debug_state);
  if(mult_flat !== mult_flat_compact)$fatal(1,"compact lockstep mult_flat differs state=%0d",debug_state);
  if(shift_flat !== shift_flat_compact)$fatal(1,"compact lockstep shift_flat differs state=%0d",debug_state);
  if(shadow_valid !== shadow_valid_compact)$fatal(1,"compact lockstep shadow_valid differs state=%0d",debug_state);
  if(aux_coeff !== aux_coeff_compact)$fatal(1,"compact lockstep aux_coeff differs state=%0d",debug_state);
  if(a_req_ready !== a_req_ready_compact)$fatal(1,"compact lockstep a_req_ready differs state=%0d",debug_state);
  if(a_rsp_valid !== a_rsp_valid_compact)$fatal(1,"compact lockstep a_rsp_valid differs state=%0d",debug_state);
  if(a_rsp_data !== a_rsp_data_compact)$fatal(1,"compact lockstep a_rsp_data differs state=%0d",debug_state);
  if(a_rsp_tag !== a_rsp_tag_compact)$fatal(1,"compact lockstep a_rsp_tag differs state=%0d",debug_state);
  if(a_rsp_error !== a_rsp_error_compact)$fatal(1,"compact lockstep a_rsp_error differs state=%0d",debug_state);
  if(b_req_ready !== b_req_ready_compact)$fatal(1,"compact lockstep b_req_ready differs state=%0d",debug_state);
  if(b_rsp_valid !== b_rsp_valid_compact)$fatal(1,"compact lockstep b_rsp_valid differs state=%0d",debug_state);
  if(b_rsp_data !== b_rsp_data_compact)$fatal(1,"compact lockstep b_rsp_data differs state=%0d",debug_state);
  if(b_rsp_tag !== b_rsp_tag_compact)$fatal(1,"compact lockstep b_rsp_tag differs state=%0d",debug_state);
  if(b_rsp_error !== b_rsp_error_compact)$fatal(1,"compact lockstep b_rsp_error differs state=%0d",debug_state);
  if(dw_req_ready !== dw_req_ready_compact)$fatal(1,"compact lockstep dw_req_ready differs state=%0d",debug_state);
  if(dw_rsp_valid !== dw_rsp_valid_compact)$fatal(1,"compact lockstep dw_rsp_valid differs state=%0d",debug_state);
  if(dw_rsp_data !== dw_rsp_data_compact)$fatal(1,"compact lockstep dw_rsp_data differs state=%0d",debug_state);
  if(dw_rsp_tag !== dw_rsp_tag_compact)$fatal(1,"compact lockstep dw_rsp_tag differs state=%0d",debug_state);
  if(dw_rsp_error !== dw_rsp_error_compact)$fatal(1,"compact lockstep dw_rsp_error differs state=%0d",debug_state);
  if(mem_req_valid !== mem_req_valid_compact)$fatal(1,"compact lockstep mem_req_valid differs state=%0d",debug_state);
  if(mem_req_write !== mem_req_write_compact)$fatal(1,"compact lockstep mem_req_write differs state=%0d",debug_state);
  if(mem_req_verify !== mem_req_verify_compact)$fatal(1,"compact lockstep mem_req_verify differs state=%0d",debug_state);
  if(mem_req_offset !== mem_req_offset_compact)$fatal(1,"compact lockstep mem_req_offset differs state=%0d",debug_state);
  if(mem_req_tag !== mem_req_tag_compact)$fatal(1,"compact lockstep mem_req_tag differs state=%0d",debug_state);
  if(mem_req_beats !== mem_req_beats_compact)$fatal(1,"compact lockstep mem_req_beats differs state=%0d",debug_state);
  if(mem_req_client !== mem_req_client_compact)$fatal(1,"compact lockstep mem_req_client differs state=%0d",debug_state);
  if(mem_w_valid !== mem_w_valid_compact)$fatal(1,"compact lockstep mem_w_valid differs state=%0d",debug_state);
  if(mem_w_data !== mem_w_data_compact)$fatal(1,"compact lockstep mem_w_data differs state=%0d",debug_state);
  if(mem_w_strb !== mem_w_strb_compact)$fatal(1,"compact lockstep mem_w_strb differs state=%0d",debug_state);
  if(mem_w_last !== mem_w_last_compact)$fatal(1,"compact lockstep mem_w_last differs state=%0d",debug_state);
  if(mem_r_ready !== mem_r_ready_compact)$fatal(1,"compact lockstep mem_r_ready differs state=%0d",debug_state);
  if(mem_rsp_ready !== mem_rsp_ready_compact)$fatal(1,"compact lockstep mem_rsp_ready differs state=%0d",debug_state);
  if(busy !== busy_compact)$fatal(1,"compact lockstep busy differs state=%0d",debug_state);
  if(reset_required !== reset_required_compact)$fatal(1,"compact lockstep reset_required differs state=%0d",debug_state);
  if(debug_state !== debug_state_compact)$fatal(1,"compact lockstep debug_state differs state=%0d",debug_state);
  if(cycles !== cycles_compact)$fatal(1,"compact lockstep cycles differs state=%0d",debug_state);
  if(read_bytes !== read_bytes_compact)$fatal(1,"compact lockstep read_bytes differs state=%0d",debug_state);
  equivalence_cycles=equivalence_cycles+1;
 end
end

end endgenerate
    always @(posedge clk)if(rst_n&&run_ce&&dut.gather_pipeline.active&&dut.gather_pipeline.vp[1]&&!dut.gather_pipeline.return_good)
        $display("RESIDENT_GATHER_FAIL k=%0d vp=%b bank=%0d rv=%h rvb=%h req=%h reqb=%h state=%0d kind=%0d dummy=%b",dut.gather_pipeline.kp[1],dut.gather_pipeline.vp,dut.gather_pipeline.bankp[1],dut.rv,dut.rv_b,dut.rr,dut.rr_b,dut.state,dut.kind,dut.gather_pipeline.dummyp);
    GTP_GRS GRS_INST(.GRS_N(1'b1));
    reg[7:0]p_mem[0:12287],i_mem[0:307199];
    reg[31:0]mem_base,mem_tag;reg[4:0]mem_count,mem_sent;reg mem_owner=0;
    reg[31:0]w_phys,b_phys,q_phys,aux_phys,walloc,balloc,qalloc,in_logical,param_bytes;
    reg[31:0]K,Cin,Co,H,W,Kh,Kw,Sh,Sw,OutH,OutW;reg[7:0]Pt,Pl;
    integer tick_count=0,case_index=0,total=0,expected_status=0,commands=0,rbeats=0;
    integer valid_cases=0,bad_cases=0,a_checks=0,b_checks=0,dw_checks=0,ce0_beats=0,cancel_cases=0,epoch_cases=0;
    integer a_streak=0,b_streak=0,dw_streak=0,max_dw_streak=0,max_ab_streak=0;
    integer inject=0,hold_checks=0,first_read_client=0,service_fault_cases=0;
    integer rolling_rows=0,rolling_Rbytes=0,cold_reload_rows=0;
    integer layer_restart_cases=0,gather_cancel_cases=0;
    integer identity_chunks=0,param_identity_cases=0,resident_identity_reloads=0,id_cancel_cases=0,id_ce0_accepts=0;
    integer fd,scanned,n,m,c,k,ci,ky,kx,y,x,co_base,tap,limit,code;
    string root_path,fixture_path,p_path,i_path;
    reg[127:0]expected;
    reg[1023:0]saved_op;
    reg[31:0]held_status,held_detail,held_tag,held_cycles,held_bytes;
    function automatic [7:0] mem_byte(input reg[31:0]address);
        integer rel;
        begin
            mem_byte=8'ha5;
            if(code==1||code==2)begin
                if(address>=w_phys&&address<w_phys+walloc)mem_byte=p_mem[address-w_phys];
                else if(address>=b_phys&&address<b_phys+balloc)mem_byte=p_mem[walloc+address-b_phys];
                else if(address>=q_phys&&address<q_phys+qalloc)mem_byte=p_mem[walloc+balloc+address-q_phys];
            end else if((code==3||code==8)&&address>=aux_phys&&address<aux_phys+(code==3?16:8))
                mem_byte=p_mem[address-aux_phys];
            if(address>=resolved_src_base&&address<resolved_src_base+in_logical)mem_byte=i_mem[address-resolved_src_base];
        end
    endfunction
    assign mem_req_ready=rst_n&&!mem_owner&&!mem_rsp_valid&&tick_count%7!=2&&inject!=1;
    always @(posedge clk)begin
        if(!rst_n)begin
            mem_owner<=0;mem_r_valid<=0;mem_rsp_valid<=0;mem_sent<=0;mem_count<=0;mem_base<=0;mem_tag<=0;
        end else begin
            if(mem_req_valid&&mem_req_ready)begin
                if(mem_req_write||mem_req_verify||mem_req_beats==0||mem_req_beats>16||mem_req_offset[4:0]||
                   ({1'b0,mem_req_offset[11:0]}+(mem_req_beats<<5)>4096))$fatal(1,"INPUT illegal local memory request");
                mem_owner<=1;mem_base<=mem_req_offset;mem_tag<=mem_req_tag;mem_count<=mem_req_beats;mem_sent<=0;
                commands=commands+1;first_read_client=mem_req_client;
                $display("INPUT_REQ case=%0d kind=%0d client=%0d address=%08h beats=%0d tag=%08h",case_index,cmd_kind,mem_req_client,mem_req_offset,mem_req_beats,mem_req_tag);
            end
            if(mem_owner&&!mem_r_valid&&!mem_rsp_valid&&mem_sent<mem_count&&tick_count%11!=4)begin
                mem_r_valid<=1;mem_r_last<=mem_sent+1==mem_count;
                for(integer b=0;b<32;b=b+1)mem_r_data[8*b+:8]<=mem_byte(mem_base+(mem_sent<<5)+b);
            end
            if(mem_r_valid&&mem_r_ready)begin
                mem_r_valid<=0;mem_sent<=mem_sent+1;rbeats=rbeats+1;if(!run_ce)ce0_beats=ce0_beats+1;
                $display("INPUT_R case=%0d address=%08h data=%064h last=%0d",case_index,mem_base+(mem_sent<<5),mem_r_data,mem_r_last);
            end
            if(mem_owner&&mem_sent==mem_count&&!mem_r_valid&&!mem_rsp_valid)begin
                mem_rsp_valid<=1;mem_rsp_tag<=inject==2 ? mem_tag^32'h1 : mem_tag;mem_rsp_status<=0;
            end
            if(mem_rsp_valid&&mem_rsp_ready)begin mem_rsp_valid<=0;mem_owner<=0;end
        end
    end
    task automatic tick(input bit ce);
        @(negedge clk);run_ce=ce;
        @(posedge clk);#1;tick_count=tick_count+1;
        if(mem_w_valid)$fatal(1,"INPUT unexpected external write");
    endtask
    task automatic step;
        tick(tick_count%13!=3&&tick_count%13!=4);
    endtask
    task automatic start(input reg[1:0]kind);
        cmd_kind=kind;cmd_tag=32'h61000000+case_index*16+kind;cmd_valid=1;limit=0;
        while(!cmd_ready)begin step();limit=limit+1;if(limit>50)$fatal(1,"INPUT command not ready");end
        tick(1);cmd_valid=0;
    endtask
    task automatic start_ce0(input reg[1:0]kind);
        cmd_kind=kind;cmd_tag=32'h61000000+case_index*16+kind;cmd_valid=1;limit=0;
        while(!cmd_ready)begin step();limit=limit+1;if(limit>50)$fatal(1,"CE0 command not ready");end
        tick(0);cmd_valid=0;
        if(debug_state!==20)$fatal(1,"CE0 command did not lock ordinary metadata");
    endtask
    task automatic completion(input integer status);
        limit=0;while(!done_valid)begin step();limit=limit+1;if(limit>50000)$fatal(1,"INPUT command timeout case=%0d kind=%0d stage=%0d",case_index,cmd_kind,debug_state);end
        if(done_status!==status||done_tag!==cmd_tag)$fatal(1,"INPUT status case=%0d kind=%0d expected=%0d actual=%0d detail=%h",case_index,cmd_kind,status,done_status,done_detail);
        held_status=done_status;held_detail=done_detail;held_tag=done_tag;held_cycles=cycles;held_bytes=read_bytes;
        repeat(3)begin tick(0);if(!done_valid||done_status!==held_status||done_detail!==held_detail||done_tag!==held_tag||cycles!==held_cycles||read_bytes!==held_bytes)$fatal(1,"INPUT held response changed");hold_checks=hold_checks+1;end
        $display("INPUT_DONE case=%0d kind=%0d status=%0d detail=%08h cycles=%0d bytes=%0d",case_index,cmd_kind,done_status,done_detail,cycles,read_bytes);
        done_ready=1;tick(0);done_ready=0;if(done_valid)$fatal(1,"INPUT completion CE0 ACK");
    endtask
    task automatic bread(input integer row,input reg[127:0]value);
        b_req_row=row;b_req_tag=32'h42000000+row;b_req_valid=1;
        while(!b_req_ready)tick(1);
        tick(1);b_req_valid=0;tick(1);
        if(!b_rsp_valid||b_rsp_error||b_rsp_tag!==b_req_tag||b_rsp_data!==value)$fatal(1,"INPUT B read mismatch case=%0d row=%0d expected=%032h actual=%032h",case_index,row,value,b_rsp_data);
        tick(0);if(!b_rsp_valid||b_rsp_data!==value)$fatal(1,"INPUT B read CE hold");tick(1);b_checks=b_checks+1;
    endtask
    task automatic aread(input integer row,input reg[127:0]value);
        a_req_row=row;a_req_tag=32'h41000000+row;a_req_valid=1;
        while(!a_req_ready)tick(1);
        tick(1);a_req_valid=0;tick(1);
        if(!a_rsp_valid||a_rsp_error||a_rsp_tag!==a_req_tag||a_rsp_data!==value)$fatal(1,"INPUT A read mismatch case=%0d row=%0d expected=%032h actual=%032h",case_index,row,value,a_rsp_data);
        tick(0);if(!a_rsp_valid||a_rsp_data!==value)$fatal(1,"INPUT A read CE hold");tick(1);a_checks=a_checks+1;
    endtask
    function automatic [7:0] value_at(input integer channel,input integer iy,input integer ix);
        if(channel>=Cin||iy<0||iy>=H||ix<0||ix>=W)value_at=0;
        else value_at=i_mem[(channel*H+iy)*W+ix];
    endfunction
    task automatic check_dw_stream;
        integer tt,xx,cb,cy,cx;reg[127:0]value;
        for(cb=0;cb<Cin;cb=cb+16)for(xx=0;xx<OutW;xx=xx+1)for(tt=0;tt<(code==5?1:Kh*Kw);tt=tt+1)begin
            if(code==5)begin cy=row_y>>1;cx=xx>>1;end
            else begin cy=row_y*Sh-Pt+tt/Kw;cx=xx*Sw-Pl+tt%Kw;end
            value=0;for(integer lane=0;lane<16;lane=lane+1)value[8*lane+:8]=value_at(cb+lane,cy,cx);
            dw_req_tap=tt;dw_req_ox=xx;dw_req_co_base=cb;dw_req_tag=32'h44000000+dw_checks;dw_req_valid=1;
            while(!dw_req_ready)tick(1);
            tick(1);dw_req_valid=0;tick(1);
            if(!dw_rsp_valid||dw_rsp_error||dw_rsp_tag!==dw_req_tag||dw_rsp_data!==value)$fatal(1,"INPUT DW read case=%0d tap=%0d ox=%0d co=%0d expected=%032h actual=%032h err=%0d",case_index,tt,xx,cb,value,dw_rsp_data,dw_rsp_error);
            tick(0);if(!dw_rsp_valid||dw_rsp_data!==value)$fatal(1,"INPUT DW CE hold");tick(1);dw_checks=dw_checks+1;
        end
    endtask
    function automatic [127:0] a_vector(input integer kval);
        integer cc,yy,xx;reg[127:0]value;
        begin
            cc=kval/(Kh*Kw);yy=(kval%(Kh*Kw))/Kw;xx=kval%Kw;value=0;
            for(integer lane=0;lane<m_count;lane=lane+1)value[8*lane+:8]=value_at(cc,row_y*Sh-Pt+yy,(x_begin+lane)*Sw-Pl+xx);
            a_vector=value;
        end
    endfunction
    function automatic integer expected_row_bytes(input integer sy,input integer reused);
        integer cc,yy,iy,addr,bytes;
        begin
            bytes=0;
            for(cc=0;cc<Cin;cc=cc+1)for(yy=reused;yy<3;yy=yy+1)begin
                iy=sy*Sh-Pt+yy;
                if(iy>=0&&iy<H)begin addr=resolved_src_base+(cc*H+iy)*W;bytes=bytes+((W+(addr%32)+31)/32)*32;end
            end
            expected_row_bytes=bytes;
        end
    endfunction
    task automatic check_current_row;
        if(code==1)begin
            start(2);completion(0);
            for(integer kval=0;kval<K;kval=kval+1)aread(kval,a_vector(kval));
        end else check_dw_stream();
    endtask
    task automatic check_rolling;
        integer initial_y,reuse_rows,want;
        reg [31:0] old_src;
        begin
            initial_y=row_y;reuse_rows=3-Sh;old_src=resolved_src_base;
            for(integer ri=1;ri<=3&&initial_y+ri<OutH;ri=ri+1)begin
                row_y=initial_y+ri;want=((Cin+15)/16*H*((W+3)/4)<=1024)?0:expected_row_bytes(row_y,reuse_rows);
                start(1);completion(0);
                if(read_bytes!==want)$fatal(1,"FAST rolling reads case=%0d y=%0d got=%0d expected=%0d",case_index,row_y,read_bytes,want);
                rolling_rows=rolling_rows+1;rolling_Rbytes=rolling_Rbytes+read_bytes;check_current_row();
            end
            // A backwards jump and a new explicit binding invalidate reuse.
            row_y=0;want=((Cin+15)/16*H*((W+3)/4)<=1024)?0:expected_row_bytes(row_y,0);start(1);completion(0);
            if(read_bytes!==want)$fatal(1,"FAST backwards row reused stale data");cold_reload_rows=cold_reload_rows+1;check_current_row();
            if(OutH>1)begin
                resolved_src_base=old_src+32'h1000;row_y=1;want=((Cin+15)/16*H*((W+3)/4)<=1024)?((in_logical+31)/32)*32:expected_row_bytes(row_y,0);start(1);completion(0);
                if(read_bytes!==want)$fatal(1,"FAST new input binding reused old row");cold_reload_rows=cold_reload_rows+1;check_current_row();
            end
            resolved_src_base=old_src;
        end
    endtask
    task automatic check_layer_restart;
        integer want;
        begin
            row_y=0;start(1);completion(0);check_current_row();
            for(integer ib=0;ib<in_logical;ib=ib+1)i_mem[ib]=i_mem[ib]^8'h5a;
            // Same op, source address, epoch and tag; PARAMS starts a new layer.
            start(0);completion(0);
            if(rows_valid||a_valid)$fatal(1,"RESIDENT PARAMS kept prior layer input cache");
            want=((Cin+15)/16*H*((W+3)/4)<=1024)?((in_logical+31)/32)*32:expected_row_bytes(row_y,0);
            start(1);completion(0);
            if(read_bytes!==want||read_bytes==0)$fatal(1,"RESIDENT new layer did not cold reload changed input");
            check_current_row();layer_restart_cases=layer_restart_cases+1;
            for(integer ib=0;ib<in_logical;ib=ib+1)i_mem[ib]=i_mem[ib]^8'h5a;
            start(0);completion(0);
        end
    endtask
    task automatic check_full_identity;
        reg [1023:0] original,changed;
        integer before_commands;
        begin
            original=op_words;start(1);completion(0);check_current_row();
            // Every chunk is significant, including unused/reserved metadata.
            // Restore the external bus while the accepted op is in ID_COMPARE.
            for(integer chunk=0;chunk<32;chunk=chunk+1)begin
                changed=original;changed[32*chunk]=~changed[32*chunk];op_words=changed;
                before_commands=commands;start(2);
                if(debug_state!==20)$fatal(1,"IDENTITY missing compare stage");
                op_words=original;repeat(2)tick(0);completion(13);
                if(commands!=before_commands||read_bytes!=0||a_valid)$fatal(1,"IDENTITY mismatched chunk accepted or sent DDR");
                identity_chunks=identity_chunks+1;
                if(chunk==10||chunk==11||chunk==16)check_dw_stream();
            end
            changed=original;changed[1000]=~changed[1000];op_words=changed;before_commands=commands;
            start_ce0(2);op_words=original;repeat(3)tick(0);completion(13);
            if(commands!=before_commands||read_bytes!=0)$fatal(1,"CE0 identity request sent DDR");
            id_ce0_accepts=id_ce0_accepts+1;
            start(2);completion(0);for(integer kval=0;kval<K;kval=kval+1)aread(kval,a_vector(kval));
            changed=original;changed[1000]=~changed[1000];op_words=changed;before_commands=commands;
            start(1);op_words=original;repeat(2)tick(0);completion(13);
            if(commands!=before_commands||read_bytes!=0||rows_valid)$fatal(1,"IDENTITY PARAMS/ROWS mismatch used data");
            param_identity_cases=param_identity_cases+1;
            start(1);completion(0);check_current_row();
            before_commands=commands;start(2);cancel_request=1;repeat(3)tick(0);cancel_request=0;completion(18);
            if(commands!=before_commands||param_valid||rows_valid||a_valid||shadow_valid)$fatal(1,"IDENTITY cancel leaked state/debt");
            id_cancel_cases=id_cancel_cases+1;
            start(0);completion(0);start(1);completion(0);check_current_row();
        end
    endtask
    task automatic check_resident_identity;
        reg [1023:0] original,changed;
        integer expected_bytes;
        begin
            original=op_words;expected_bytes=((in_logical+31)/32)*32;
            start(1);completion(0);check_current_row();
            changed=original;changed[1000]=~changed[1000];op_words=changed;start(1);
            op_words=original;repeat(2)tick(0);completion(0);
            if(read_bytes!==expected_bytes||read_bytes==0)$fatal(1,"IDENTITY resident hit on different full op");
            resident_identity_reloads=resident_identity_reloads+1;
            op_words=changed;check_current_row();start(1);completion(0);
            if(read_bytes!=0)$fatal(1,"IDENTITY same resident op missed");
            op_words=original;start(1);completion(0);
            if(read_bytes!==expected_bytes)$fatal(1,"IDENTITY restored different op reused resident cache");
            resident_identity_reloads=resident_identity_reloads+1;check_current_row();
        end
    endtask
    integer key_save_cancels=0,key_save_ce0=0,key_save_epoch=0;
    task automatic check_key_save_interrupt(input integer bankmask,input integer positions);
        integer point,target,guard;reg [4:0]held_index;reg [2:0]held_written;
        begin
            for(point=0;point<positions;point=point+1)begin
                target=positions==32?point:(point==0?0:point==1?15:31);
                start(0);if(bankmask!=1)begin completion(0);start(1);end
                guard=0;
                while(!(debug_state==24&&dut.key_save_mask==bankmask&&dut.key_index==target))begin
                    tick(1);guard=guard+1;if(guard>50000)$fatal(1,"KEY_SAVE target not reached mask=%0d point=%0d",bankmask,target);
                end
                held_index=dut.key_index;held_written=dut.key_written;
                repeat(3)begin
                    tick(0);if(debug_state!=24||dut.key_index!==held_index||dut.key_written!==held_written||!busy||done_valid)$fatal(1,"KEY_SAVE CE0 changed");
                    key_save_ce0=key_save_ce0+1;
                end
                cancel_request=1;repeat(2)tick(0);cancel_request=0;completion(18);
                if(param_valid||rows_valid||a_valid||shadow_valid||dut.key_written&bankmask)$fatal(1,"KEY_SAVE partial identity published");
                key_save_cancels=key_save_cancels+1;
            end
            start(0);completion(0);start(1);completion(0);check_current_row();
        end
    endtask
    task automatic check_key_save_epoch_change;
        integer guard;
        begin
            start(0);guard=0;
            while(!(debug_state==24&&dut.key_save_mask==1&&dut.key_index==31))begin
                tick(1);guard=guard+1;if(guard>50000)$fatal(1,"KEY_SAVE epoch target");
            end
            epoch=epoch+1;tick(1);completion(18);
            if(param_valid||rows_valid||a_valid||shadow_valid||dut.key_written[0])$fatal(1,"KEY_SAVE epoch published partial identity");
            key_save_epoch=key_save_epoch+1;start(0);completion(0);start(1);completion(0);check_current_row();
        end
    endtask
    task automatic check_ab_II1;
        reg[1:0]vp;reg[127:0]a0,a1,b0,b1,value;reg[31:0]t0,t1;
        vp=0;a0=0;a1=0;b0=0;b1=0;t0=0;t1=0;
        for(integer it=0;it<K+2;it=it+1)begin
            a_req_valid=it<K;b_req_valid=it<K;a_req_row=it;b_req_row=it;a_req_tag=32'h79000000+it;b_req_tag=a_req_tag;
            @(negedge clk);run_ce=1;#1;
            if(a_rsp_valid!==vp[1]||b_rsp_valid!==vp[1])$fatal(1,"INPUT AB II1 valid");
            if(vp[1]&&(a_rsp_error||b_rsp_error||a_rsp_data!==a1||b_rsp_data!==b1||a_rsp_tag!==t1||b_rsp_tag!==t1))$fatal(1,"INPUT AB II1 data/tag");
            if(it<K&&(!a_req_ready||!b_req_ready))$fatal(1,"INPUT AB II1 stalled");
            value=0;if(it<K)for(integer lane=0;lane<16;lane=lane+1)value[8*lane+:8]=p_mem[16*it+lane];
            @(posedge clk);#1;tick_count=tick_count+1;
            vp={vp[0],it<K};a1=a0;a0=it<K?a_vector(it):0;b1=b0;b0=value;t1=t0;t0=32'h79000000+it;
        end
        a_req_valid=0;b_req_valid=0;max_ab_streak=K;
    endtask
    task automatic check_dw_II1;
        reg[1:0]vp;reg[127:0]q0,q1,value;reg[31:0]t0,t1;integer tt,xx,cb,cy,cx;
        vp=0;q0=0;q1=0;t0=0;t1=0;
        for(integer it=0;it<66;it=it+1)begin
            tt=it%9;xx=(it/9)%OutW;cb=0;
            dw_req_valid=it<64;dw_req_tap=tt;dw_req_ox=xx;dw_req_co_base=cb;dw_req_tag=32'h7a000000+it;
            cy=row_y*Sh-Pt+tt/Kw;cx=xx*Sw-Pl+tt%Kw;value=0;
            for(integer lane=0;lane<16;lane=lane+1)value[8*lane+:8]=value_at(cb+lane,cy,cx);
            @(negedge clk);run_ce=1;#1;
            if(dw_rsp_valid!==vp[1])$fatal(1,"INPUT DW II1 valid");
            if(vp[1]&&(dw_rsp_error||dw_rsp_data!==q1||dw_rsp_tag!==t1))$fatal(1,"INPUT DW II1 data/tag");
            if(it<64&&!dw_req_ready)$fatal(1,"INPUT DW II1 stalled");
            @(posedge clk);#1;tick_count=tick_count+1;
            vp={vp[0],it<64};q1=q0;q0=value;t1=t0;t0=32'h7a000000+it;
        end
        dw_req_valid=0;max_dw_streak=64;
    endtask
    initial begin
        if(!$value$plusargs("ROOT=%s",root_path))$fatal(1,"INPUT fixture ROOT required");
        fixture_path={root_path,"/cases.hex"};fd=$fopen(fixture_path,"r");if(!fd)$fatal(1,"INPUT cannot open fixture file");
        scanned=$fscanf(fd,"%d\n",total);
        repeat(2)tick(0);rst_n=1;tick(1);
        for(n=0;n<total;n=n+1)begin
            scanned=$fscanf(fd,"%d %d %h %h %h %h %d %d %d %d %d\n",case_index,expected_status,op_words,workspace_base,resolved_src_base,epoch,row_y,x_begin,m_count,param_bytes,in_logical);
            if(scanned!=11)$fatal(1,"INPUT case header parse %0d",scanned);
            for(integer j=0;j<12288;j=j+1)p_mem[j]=0;
            p_path=$sformatf("%s/case_%0d_params.hex",root_path,case_index);i_path=$sformatf("%s/case_%0d_input.hex",root_path,case_index);
            $readmemh(p_path,p_mem,0,param_bytes-1);$readmemh(i_path,i_mem,0,in_logical-1);
            code=op_words[0+:32];Cin=op_words[256+:32];Co=op_words[288+:32];H=op_words[320+:32];W=op_words[352+:32];
            OutH=op_words[384+:32];OutW=op_words[416+:32];Kh=op_words[448+:32];Kw=op_words[480+:32];Sh=op_words[512+:32];Sw=op_words[544+:32];
            Pt=op_words[576+:8];Pl=op_words[584+:8];K=op_words[896+:32];
            walloc=(((Co+15)/16*16*K)+255)&32'hffffff00;balloc=((Co*4)+255)&32'hffffff00;qalloc=((Co*8)+255)&32'hffffff00;
            w_phys=workspace_base+op_words[608+:32];b_phys=workspace_base+op_words[640+:32];q_phys=workspace_base+op_words[672+:32];aux_phys=workspace_base+op_words[704+:32];
            saved_op=op_words;
            start(0);completion(TRUSTED_MODEL&&expected_status==20?0:expected_status);
            if(expected_status!=0)begin
                if(TRUSTED_MODEL&&expected_status==20)begin
                    if(!param_valid)$fatal(1,"TRUSTED content validation was not bypassed");
                    if((code==1||code==2)&&shadow_valid!==((65'h1<<Co)-1))$fatal(1,"TRUSTED content bypass shadow mask");
                end else if(param_valid||shadow_valid)$fatal(1,"INPUT invalid params remained valid");
                bad_cases=bad_cases+1;
            end else begin
                valid_cases=valid_cases+1;
                if(code==1||code==2)begin
                    if(!param_valid||shadow_valid!==((65'h1<<Co)-1))$fatal(1,"INPUT shadow validity");
                    for(c=0;c<Co;c=c+1)begin
                        param_group=c/8;#1;
                        if(bias_flat[32*(c%8)+:32]!=={p_mem[walloc+4*c+3],p_mem[walloc+4*c+2],p_mem[walloc+4*c+1],p_mem[walloc+4*c]})$fatal(1,"INPUT bias shadow");
                        if(mult_flat[32*(c%8)+:32]!=={p_mem[walloc+balloc+8*c+3],p_mem[walloc+balloc+8*c+2],p_mem[walloc+balloc+8*c+1],p_mem[walloc+balloc+8*c]})$fatal(1,"INPUT M shadow");
                        if(shift_flat[6*(c%8)+:6]!==p_mem[walloc+balloc+8*c+4][5:0])$fatal(1,"INPUT shift shadow");
                    end
                    for(k=0;k<(Co+15)/16*K;k=k+1)begin expected=0;for(c=0;c<16;c=c+1)expected[8*c+:8]=p_mem[16*k+c];bread(k,expected);end
                end
                if(code==1||code==2||code==4||code==5)begin
                    start(1);completion(0);if(!rows_valid)$fatal(1,"INPUT ROW invalid after success");
                    if(code==1)begin
                        start(2);completion(0);if(!a_valid)$fatal(1,"INPUT A invalid after success");
                        for(k=0;k<K;k=k+1)begin
                            ci=k/(Kh*Kw);ky=(k%(Kh*Kw))/Kw;kx=k%Kw;expected=0;
                            for(m=0;m<m_count;m=m+1)expected[8*m+:8]=value_at(ci,row_y*Sh-Pt+ky,(x_begin+m)*Sw-Pl+kx);
                            aread(k,expected);
                        end
                        if(Cin==64&&Co==64)check_ab_II1();
                    end else begin check_dw_stream();if(code==2&&W==13)check_dw_II1();end
                end else begin
                    if(code==3&&aux_coeff!=={p_mem[11],p_mem[10],p_mem[9],p_mem[8],p_mem[7],p_mem[6],p_mem[5],p_mem[4],p_mem[3],p_mem[2],p_mem[1],p_mem[0]})$fatal(1,"INPUT ADD coeff");
                    if(code==8&&aux_coeff[63:0]!=={p_mem[7],p_mem[6],p_mem[5],p_mem[4],p_mem[3],p_mem[2],p_mem[1],p_mem[0]})$fatal(1,"INPUT sigmoid coeff");
                end
                if((code==1||code==2)&&Kh==3&&row_y+1<OutH)check_rolling();
                if(case_index==0||case_index==2||case_index==4||case_index==6||case_index==7||case_index==9||case_index==10)check_layer_restart();
                if(case_index==2)begin check_full_identity();check_key_save_interrupt(1,32);check_key_save_interrupt(2,3);check_key_save_epoch_change();end
                if(case_index==6)begin check_resident_identity();check_key_save_interrupt(4,3);end
                if(case_index==2)begin
                    start(1);completion(0);start(2);
                    while(!dut.gather_pipeline.active)tick(1);
                    cancel_request=1;repeat(3)tick(0);cancel_request=0;completion(18);
                    if(rows_valid||a_valid||param_valid)$fatal(1,"RESIDENT cancelled gather left valid cache");
                    gather_cancel_cases=gather_cancel_cases+1;start(0);completion(0);
                    // Cancel an already offered local request: payload is kept
                    // until ordinary service acceptance, then all debt drains.
                    resolved_src_base=resolved_src_base+32'h1000;
                    inject=1;start(1);limit=0;
                    while(!mem_req_valid)begin step();limit=limit+1;if(limit>200)$fatal(1,"INPUT missing held offer");end
                    cancel_request=1;repeat(3)begin tick(0);if(!mem_req_valid)$fatal(1,"INPUT withdrew canceled offer");end
                    cancel_request=0;inject=0;completion(18);if(rows_valid||param_valid||a_valid)$fatal(1,"INPUT cancel validity");
                    resolved_src_base=resolved_src_base-32'h1000;
                    cancel_cases=cancel_cases+1;start(0);completion(0);
                end
                if(case_index==4)begin
                    inject=2;start(0);completion(18);inject=0;
                    if(!reset_required||cmd_ready||param_valid)$fatal(1,"INPUT bad service context not isolated");
                    service_fault_cases=service_fault_cases+1;rst_n=0;repeat(2)tick(0);rst_n=1;tick(1);
                    start(0);completion(0);
                end
            end
            epoch=epoch+1;tick(1);if(param_valid||rows_valid||a_valid||a_req_ready||b_req_ready||dw_req_ready)$fatal(1,"INPUT epoch did not invalidate cache");epoch_cases=epoch_cases+1;
            if(reset_required)begin rst_n=0;repeat(2)tick(0);rst_n=1;tick(1);end
        end
        $fclose(fd);
        $display("INPUT_PROFILE trusted=%0d",TRUSTED_MODEL);
        if(valid_cases<8||bad_cases<6||a_checks==0||b_checks==0||dw_checks==0||ce0_beats==0||max_ab_streak!=128||max_dw_streak!=64||cancel_cases!=1||service_fault_cases!=1)$fatal(1,"INPUT coverage");
        if(rolling_rows<9||cold_reload_rows<6||layer_restart_cases!=7||gather_cancel_cases!=1)$fatal(1,"RESIDENT additional coverage");
        if(identity_chunks!=32||param_identity_cases!=1||resident_identity_reloads!=2||id_cancel_cases!=1||id_ce0_accepts!=1)$fatal(1,"IDENTITY coverage");
        if(key_save_cancels!=38||key_save_ce0!=114||key_save_epoch!=1)$fatal(1,"KEY_SAVE coverage");
        $display("WORDKEY_SAVE cancels=%0d ce0=%0d epoch=%0d",key_save_cancels,key_save_ce0,key_save_epoch);
        $display("IDENTITY_PIPE chunks=%0d param_mismatch=%0d resident_reloads=%0d cancel_ID_COMPARE=%0d CE0_cmd_accept=%0d",identity_chunks,param_identity_cases,resident_identity_reloads,id_cancel_cases,id_ce0_accepts);
        $display("PASS B03_MODEL_INPUT_WORDKEYS cycles=%0d cases=%0d valid_cases=%0d bad_cases=%0d a_checks=%0d b_checks=%0d dw_checks=%0d commands=%0d Rbeats=%0d CE0_Rbeats=%0d holds=%0d epoch_cases=%0d max_AB_streak=%0d max_DW_streak=%0d cancel_cases=%0d service_fault_cases=%0d rolling_rows=%0d rolling_Rbytes=%0d cold_reload_rows=%0d layer_restart_cases=%0d gather_cancel_cases=%0d",tick_count,total,valid_cases,bad_cases,a_checks,b_checks,dw_checks,commands,rbeats,ce0_beats,hold_checks,epoch_cases,max_ab_streak,max_dw_streak,cancel_cases,service_fault_cases,rolling_rows,rolling_Rbytes,cold_reload_rows,layer_restart_cases,gather_cancel_cases);
        $finish;
    end
    initial begin #100000000;$fatal(1,"INPUT wall timeout");end
endmodule
