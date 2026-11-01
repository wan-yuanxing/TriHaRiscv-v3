`timescale 1ns/1ps
// Derived from frozen B03 test; SHA256 56a9d3144443d32aaacef0744328e2bd9fcb292071b539f8533ec5d559d5f5f1.
// Extra cases check every strobe lane, first/middle/last mismatch and debt retirement.
`ifndef DMA_MODULE
`define DMA_MODULE b03_block_dma_compact
`endif
module tb_npu_service_compact;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,cancel_request=0,bridge_fault=0;reg [31:0] epoch=7;
reg req_valid=0,req_write=0,req_verify=0;wire req_ready;
reg [31:0] req_offset=0,req_tag=0;reg [4:0] req_beats=1;reg [2:0] req_client=3;
reg w_valid=0;wire w_ready;reg [255:0] w_data=0;reg [31:0] w_strb=0;reg w_last=0;
wire r_valid;reg r_ready=1;wire [255:0] r_data;wire r_last;
wire rsp_valid;reg rsp_ready=0;wire [3:0] rsp_status;wire [31:0] rsp_tag;
wire cmd_valid,cmd_write;reg cmd_ready=0;wire [31:0] cmd_offset,cmd_id,cmd_epoch;
wire [4:0] cmd_beats;wire [2:0] cmd_client;
wire write_valid,write_last;reg write_ready=0;wire [255:0] write_data;wire [31:0] write_strb;
reg read_valid=0,read_last=0;wire read_ready;reg [255:0] read_data=0;
reg mem_done_valid=0;wire mem_done_ready;reg [3:0] mem_done_status=0;
reg [31:0] mem_done_id=0,mem_done_epoch=0;reg [2:0] mem_done_client=0;
wire quarantined,reset_required,abort_req,busy,fault_valid;reg fault_ready=0;wire [175:0] fault_payload;
wire [3:0] debug_state;wire [31:0] commands,read_beats,write_beats,verify_offset,verify_expected,verify_actual;
`DMA_MODULE #(.TIMEOUT_CYCLES(300)) dut(.*);
reg [7:0] memory[0:65535];reg active=0,dir=0;reg [31:0] addr,id,ep;reg [2:0] cl;
integer count=0,nbeat=0,cyc=0,offered=0,served=0,total_r=0,checks=0,j,k;
reg proxy=1,corrupt=0;integer inject=0,corrupt_beat=0,corrupt_byte=0,corrupt_second=-1;reg [31:0] held_id;
reg read_consumed=0,done_consumed=0;
reg hold_cmd=0,hold_w=0,hold_r=0,hold_rsp=0;reg [106:0] cmd_snapshot;
reg [288:0] w_snapshot;reg [256:0] r_snapshot;reg [35:0] rsp_snapshot;
always @(posedge clk) if(rst_n) begin
    cyc=cyc+1;
    read_consumed=read_valid&&read_ready;done_consumed=mem_done_valid&&mem_done_ready;
    if(hold_cmd && (!cmd_valid||{cmd_write,cmd_offset,cmd_id,cmd_epoch,cmd_beats,cmd_client}!==cmd_snapshot))$fatal(1,"CMD not held");
    if(hold_w && (!write_valid||{write_data,write_strb,write_last}!==w_snapshot))$fatal(1,"W not held");
    if(hold_r && {r_data,r_last}!==r_snapshot)$fatal(1,"R not held");
    if(hold_rsp && {rsp_status,rsp_tag}!==rsp_snapshot)$fatal(1,"response not held");
    hold_cmd=cmd_valid&&!cmd_ready;cmd_snapshot={cmd_write,cmd_offset,cmd_id,cmd_epoch,cmd_beats,cmd_client};
    hold_w=write_valid&&!write_ready;w_snapshot={write_data,write_strb,write_last};
    hold_r=r_valid&&!r_ready;r_snapshot={r_data,r_last};
    hold_rsp=rsp_valid&&!rsp_ready;rsp_snapshot={rsp_status,rsp_tag};
    if(cmd_valid&&cmd_ready) begin
        if(active)$fatal(1,"overlapping ordinary owner");
        active=1;dir=cmd_write;addr=cmd_offset;id=cmd_id;ep=cmd_epoch;cl=cmd_client;
        count=cmd_beats;nbeat=0;offered=offered+1;
    end
    if(active&&dir&&write_valid&&write_ready)begin
        if(write_last!==(nbeat+1==count))$fatal(1,"W last");
        for(j=0;j<32;j=j+1)if(write_strb[j])memory[addr+nbeat*32+j]=write_data[j*8+:8];
        nbeat=nbeat+1;
    end
    if(read_valid&&read_ready)begin nbeat=nbeat+1;total_r=total_r+1;end
    if(mem_done_valid&&mem_done_ready)begin active=0;served=served+1;end
end else begin
    active=0;hold_cmd=0;hold_w=0;hold_r=0;hold_rsp=0;read_consumed=0;done_consumed=0;
end
always @(negedge clk)if(proxy)begin
    cmd_ready=rst_n&&cyc%5!=0;write_ready=rst_n&&cyc%3!=0;
    if(read_consumed)read_valid=0;
    if(done_consumed)mem_done_valid=0;
    if(!rst_n)begin read_valid=0;mem_done_valid=0;end
    else if(active)begin
        if(!dir&&nbeat<count&&!read_valid&&cyc%4!=0)begin
            read_valid=1;read_last=nbeat+1==count;
            for(k=0;k<32;k=k+1)read_data[k*8+:8]=memory[addr+nbeat*32+k];
            if(corrupt&&nbeat==corrupt_beat)begin
                read_data[corrupt_byte*8+:8]=read_data[corrupt_byte*8+:8]^8'h01;
                if(corrupt_second>=0)read_data[corrupt_second*8+:8]=read_data[corrupt_second*8+:8]^8'h01;
            end
            if(inject==4)read_last=!read_last;
        end
        if(nbeat==count&&!mem_done_valid&&cyc%3!=0)begin
            mem_done_valid=1;mem_done_id=id^(inject==1);mem_done_epoch=ep^(inject==2);
            mem_done_client=cl^(inject==3);mem_done_status=inject==5?4'd9:4'd0;
        end
    end
end
always @(negedge clk)if(rst_n)r_ready=cyc%7!=0;
task reset_session;begin
    @(negedge clk);rst_n=0;req_valid=0;w_valid=0;rsp_ready=0;cancel_request=0;bridge_fault=0;
    proxy=1;corrupt=0;inject=0;corrupt_beat=0;corrupt_byte=0;corrupt_second=-1;
    repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
end endtask
task request;input wr,vfy;input [31:0] a;input [4:0] n;begin
    @(negedge clk);req_write=wr;req_verify=vfy;req_offset=a;req_beats=n;req_tag=req_tag+1;req_valid=1;
    do @(posedge clk);while(!req_ready);
    @(negedge clk);req_valid=0;
end endtask
task put;input integer n;input [31:0] mask;integer b,t;begin
    for(b=0;b<n;b=b+1)begin
        @(negedge clk);w_valid=1;w_last=b+1==n;w_strb=mask;
        for(t=0;t<32;t=t+1)w_data[t*8+:8]=(req_tag+b*37+t*3)&255;
        do @(posedge clk);while(!w_ready);
        @(negedge clk);w_valid=0;
    end
end endtask
task response;input [3:0] status;integer timeout;begin
    timeout=0;
    while(!rsp_valid&&timeout<500)begin @(negedge clk);timeout=timeout+1;end
    if(!rsp_valid||rsp_status!==status||rsp_tag!==req_tag)$fatal(1,"response want %0d got %0d tag=%0d state=%0d",status,rsp_status,rsp_tag,debug_state);
    repeat(4)@(negedge clk);rsp_ready=1;@(negedge clk);rsp_ready=0;checks=checks+1;
end endtask
integer t,prior,wait_cycles;
initial begin
    for(t=0;t<65536;t=t+1)memory[t]=(t*17+23)&255;
    reset_session();
    for(t=1;t<=16;t=t+1)begin
        request(1,1,32*t,t);put(t,t%3==0?32'h00f0a55a:32'hffffffff);response(0);
        request(0,0,32*t,t);response(0);
    end
    request(1,1,0,1);put(1,0);response(0);
    request(0,0,1,1);response(1);
    request(0,0,0,0);response(1);
    request(0,0,4064,2);response(1);
    request(0,0,32'h3fffffe0,2);response(1);
    for(t=0;t<32;t=t+1)begin
        request(1,1,4096+t*32,1);put(1,32'h1<<t);response(0);
    end
    corrupt=1;request(1,1,6144,1);put(1,32'h2);response(0);corrupt=0;
    corrupt=1;request(1,1,2048,1);put(1,32'hffffffff);response(6);
    if(!quarantined||verify_offset!=2048||verify_expected==verify_actual)$fatal(1,"masked readback isolation");
    for(t=0;t<3;t=t+1)begin
        reset_session();corrupt=1;
        corrupt_beat=t==0?0:t==1?7:15;corrupt_byte=t==0?0:t==1?16:31;
        request(1,1,2048,16);put(16,32'hffffffff);response(6);
        if(!quarantined||verify_offset!==2048+corrupt_beat*32+corrupt_byte||
           verify_expected!==((req_tag+corrupt_beat*37+corrupt_byte*3)&255)||
           verify_actual!==(verify_expected^1))$fatal(1,"first/middle/final mismatch byte");
    end
    reset_session();corrupt=1;corrupt_beat=8;corrupt_byte=2;corrupt_second=27;
    request(1,1,2048,16);put(16,32'hffffffff);response(6);
    if(verify_offset!=2306||verify_expected!==((req_tag+8*37+6)&255)||verify_actual!==(verify_expected^1))
        $fatal(1,"multiple mismatches must report first byte");
    for(t=1;t<=5;t=t+1)begin reset_session();inject=t;request(0,0,1024,2);response(t<=3?3:t==5?2:4);if(!quarantined)$fatal(1,"fault not isolated");end
    reset_session();request(1,0,0,1);
    @(negedge clk);w_valid=1;w_last=0;response(4);w_valid=0;
    reset_session();proxy=0;cmd_ready=0;
    request(0,0,0,1);wait(cmd_valid);@(negedge clk);held_id=cmd_id;cancel_request=1;
    response(5);if(!cmd_valid||cmd_id!==held_id||!abort_req)$fatal(1,"offered command lost on cancel");
    prior=served;proxy=1;cancel_request=0;wait_cycles=0;
    while((abort_req||served!=prior+1)&&wait_cycles<100)begin @(negedge clk);wait_cycles=wait_cycles+1;end
    if(abort_req||served!=prior+1||commands!=1||read_beats!=1)$fatal(1,"cancelled read offer debt not repaid");
    reset_session();proxy=0;cmd_ready=1;write_ready=0;
    request(1,0,8192,16);put(16,32'h9137a50f);wait(write_valid);
    @(negedge clk);cancel_request=1;response(5);
    if(!write_valid||!abort_req)$fatal(1,"cancelled write VALID lost");
    prior=served;proxy=1;cancel_request=0;wait_cycles=0;
    while((abort_req||served!=prior+1)&&wait_cycles<150)begin @(negedge clk);wait_cycles=wait_cycles+1;end
    if(abort_req||served!=prior+1||commands!=1||write_beats!=16)$fatal(1,"cancelled write debt not repaid");
    reset_session();request(1,0,0,1);prior=commands;cancel_request=1;response(5);
    if(commands!=prior||cmd_valid)$fatal(1,"new command after collect cancel");
    reset_session();proxy=0;cmd_ready=0;request(0,0,0,1);response(5);
    if(!quarantined||!cmd_valid)$fatal(1,"timeout offer lost");
    reset_session();request(0,0,0,16);response(0);
    $display("PASS B03_BLOCK_DMA checks=%0d ordinary_commands=%0d served=%0d R=%0d cycles=%0d",checks,offered,served,total_r,cyc);$finish;
end
initial begin #2000000;$fatal(1,"watchdog");end
endmodule
