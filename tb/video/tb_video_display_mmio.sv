`timescale 1ns/1ps
`default_nettype none
// Literal software addresses and independent event identities are the oracle.
module tb_video_display_mmio;
    reg clk_i=0,rst_ni=0;always #4 clk_i=~clk_i;
    reg [1:0] mode_request_i=0; // disabled optional input when testing compact ABI compatibility
    reg [31:0] s_axi_awaddr_i=0,s_axi_wdata_i=0,s_axi_araddr_i=0;
    reg [2:0] s_axi_awprot_i=0,s_axi_arprot_i=0;
    reg [3:0] s_axi_wstrb_i=0;
    reg s_axi_awvalid_i=0,s_axi_wvalid_i=0,s_axi_bready_i=0,s_axi_arvalid_i=0,s_axi_rready_i=0;
    wire s_axi_awready_o,s_axi_wready_o,s_axi_bvalid_o,s_axi_arready_o,s_axi_rvalid_o;
    wire [1:0] s_axi_bresp_o,s_axi_rresp_o;wire [31:0] s_axi_rdata_o;
    reg [2:0] modes_i=7;reg asset_ready_i=1;reg [31:0] asset_id_i=1,asset_generation_i=7;
    wire cmd_valid_o,cmd_mode_only_o;reg cmd_ready_i=0;
    wire [1:0] cmd_slot_o,cmd_mode_o;
    wire [31:0] cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o;
    wire [5119:0] cmd_data_o;
    reg feedback_valid_i=0;wire feedback_ready_o;
    reg [1:0] feedback_slot_i=0,feedback_mode_i=0;
    reg [31:0] feedback_frame_i=0,feedback_generation_i=0,feedback_seq_i=0;
    reg retire_valid_i=0;wire retire_ready_o;reg [1:0] retire_slot_i=0;
    reg [31:0] retire_frame_i=0,retire_generation_i=0;
    wire irq_o;
    reg [31:0] record[0:159];reg [5119:0] expected_record;
    reg [1:0] sent_slot,sent_mode;reg [31:0] sent_frame,sent_gen,sent_seq;
    reg [31:0] rd;integer checks=0,test_case=0,j,k,n;
    string trace_path;integer trace_file,trace_status;reg [31:0] trace_off,trace_value;
    reg held=0;reg [5284:0] held_cmd;
    video_display_mmio dut(.submit_enable_i(1'b1),.external_fault_i(1'b0),.fault_o(),.fault_code_o(),.*);
    task automatic check(input bit ok,input string msg);
        begin checks++;if(ok!==1'b1)$fatal(1,"DISPLAY_MMIO case%0d: %s",test_case,msg);end
    endtask
    task automatic cycle;begin @(posedge clk_i);#1;end endtask
    always @(posedge clk_i)begin
        if(!rst_ni)held<=0;
        else begin
            if(held)check(cmd_valid_o&&{cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o}===held_cmd,
                "full command changed under consumer backpressure");
            held<=cmd_valid_o&&!cmd_ready_i;
            held_cmd<={cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o};
        end
    end
    task automatic read_word(input [31:0] off,input [1:0] wanted);
        reg [31:0] value;
        begin
            @(negedge clk_i);s_axi_araddr_i=32'h20011000+off;s_axi_arvalid_i=1;
            do @(posedge clk_i);while(!s_axi_arready_o);
            @(negedge clk_i);s_axi_arvalid_i=0;
            while(!s_axi_rvalid_o)@(negedge clk_i);
            check(s_axi_rresp_o===wanted,"read response");value=s_axi_rdata_o;
            repeat(2)begin @(negedge clk_i);check(s_axi_rvalid_o&&s_axi_rdata_o===value&&s_axi_rresp_o===wanted&&!s_axi_arready_o,"held R");end
            rd=value;s_axi_rready_i=1;@(negedge clk_i);s_axi_rready_i=0;
        end
    endtask
    task automatic expect_read(input [31:0] off,value,input [1:0] wanted);
        begin read_word(off,wanted);check(rd===value,$sformatf("read offset=%h got=%h expected=%h",off,rd,value));end
    endtask
    task automatic write_word(input [31:0] off,value,input [3:0] strobe,input [1:0] wanted,input integer skew);
        begin
            fork
                begin
                    repeat(skew<0?-skew:0)@(negedge clk_i);
                    @(negedge clk_i);s_axi_awaddr_i=32'h20011000+off;s_axi_awvalid_i=1;
                    do @(posedge clk_i);while(!s_axi_awready_o);
                    @(negedge clk_i);s_axi_awvalid_i=0;
                end
                begin
                    repeat(skew>0?skew:0)@(negedge clk_i);
                    @(negedge clk_i);s_axi_wdata_i=value;s_axi_wstrb_i=strobe;s_axi_wvalid_i=1;
                    do @(posedge clk_i);while(!s_axi_wready_o);
                    @(negedge clk_i);s_axi_wvalid_i=0;
                end
            join
            while(!s_axi_bvalid_o)@(negedge clk_i);
            check(s_axi_bresp_o===wanted,$sformatf("write off=%h got=%h expected=%h",off,s_axi_bresp_o,wanted));
            repeat(2)begin @(negedge clk_i);check(s_axi_bvalid_o&&s_axi_bresp_o===wanted&&!s_axi_awready_o&&!s_axi_wready_o,"held B");end
            s_axi_bready_i=1;@(negedge clk_i);s_axi_bready_i=0;
        end
    endtask
    task automatic reset_all;
        begin
            @(negedge clk_i);rst_ni=0;s_axi_awvalid_i=0;s_axi_wvalid_i=0;s_axi_arvalid_i=0;
            s_axi_bready_i=0;s_axi_rready_i=0;feedback_valid_i=0;retire_valid_i=0;cmd_ready_i=0;
            modes_i=7;asset_ready_i=1;asset_id_i=1;asset_generation_i=7;
            repeat(3)cycle;
            check(!cmd_valid_o&&!irq_o&&!s_axi_rvalid_o&&!s_axi_bvalid_o,"reset protocol");
            @(negedge clk_i);rst_ni=1;cycle;
        end
    endtask
    task automatic make_record(input integer slot,frame,gen);
        begin
            for(integer x=0;x<160;x++)record[x]=0;
            record[0]=32'h10000;record[1]=640;record[2]=slot;record[3]=frame;record[4]=gen;
            record[5]=32'h82000000+slot*32'h200000;record[6]=2400;record[7]=800;record[8]=600;
            record[9]=3;record[10]=frame;record[11]=gen;
        end
    endtask
    task automatic face_record;
        begin
            record[9]=29;record[12]=1;record[13]=0;
            record[14]=1;record[15]=7;record[16]=32'h82600000;record[17]=262144;
            record[18]=256;record[19]=256;record[20]=1024;
            record[21]={16'd150,16'd200};record[22]={16'd450,16'd600};
            record[32]={16'd150,16'd200};record[33]={16'd450,16'd600};record[34]=31;
            for(integer x=0;x<5;x++)record[35+x]={(16'(200+x*20)),(16'(250+x*25))};
        end
    endtask
    task automatic load_record;
        begin
            for(integer x=0;x<160;x++)begin
                write_word('h100+x*4,record[x],15,0,(x%3)-1);expected_record[x*32+:32]=record[x];
            end
        end
    endtask
    task automatic submit(input integer mode,seq,input bit mode_only);
        begin write_word('h24,mode,15,0,1);write_word('h28,seq,15,0,-1);write_word('h20,mode_only?3:1,15,0,0);end
    endtask
    task automatic await_command(input integer mode,seq,input bit mode_only);
        integer waited;
        begin
            waited=0;while(!cmd_valid_o)begin cycle;waited++;check(waited<80,"validated command missing");end
            check(cmd_data_o===expected_record&&cmd_slot_o==record[2]&&cmd_frame_o==record[3]&&
                cmd_generation_o==record[4]&&cmd_base_o==record[5]&&cmd_stride_o==2400&&
                cmd_mode_o==mode&&cmd_seq_o==seq&&cmd_mode_only_o==mode_only,"full record/metadata decode");
            sent_slot=cmd_slot_o;sent_frame=cmd_frame_o;sent_gen=cmd_generation_o;sent_seq=cmd_seq_o;sent_mode=cmd_mode_o;
            repeat(3)cycle;
        end
    endtask
    task automatic accept_and_commit;
        begin
            @(negedge clk_i);cmd_ready_i=1;cycle;@(negedge clk_i);cmd_ready_i=0;
            expect_read('h14,0,0); // Local command ACK is not an actual commit.
            @(negedge clk_i);feedback_valid_i=1;feedback_slot_i=sent_slot;feedback_frame_i=sent_frame;
            feedback_generation_i=sent_gen;feedback_seq_i=sent_seq;feedback_mode_i=sent_mode;
            #1;check(feedback_ready_o,"feedback ready");cycle;@(negedge clk_i);feedback_valid_i=0;
            expect_read('h14,1,0);expect_read('h30,sent_frame,0);expect_read('h40,sent_seq,0);
            expect_read('h44,sent_frame,0);expect_read('h48,sent_gen,0);expect_read('h50,{30'd0,sent_mode},0);
        end
    endtask
    task automatic reject_record(input integer mode,input [7:0] reason);
        begin
            load_record;submit(mode,41,0);repeat(25)cycle;
            check(!cmd_valid_o,"rejected record must not reserve or publish");
            expect_read('h14,4,0);expect_read('h68,41,0);expect_read('h6c,{24'd0,reason},0);
            expect_read('h1c,7,0);write_word('h18,4,15,0,0);
        end
    endtask
    initial begin
        if(!$value$plusargs("CASE=%d",test_case))test_case=0;
        reset_all;
        expect_read(0,32'h10000,0);expect_read(4,15,0);expect_read('h2c,640,0);expect_read('h1c,7,0);
        case(test_case)
        0:begin
            make_record(0,1,10);face_record;load_record;
            write_word('h10,15,15,0,0);submit(0,1,0);await_command(0,1,0);
            expect_read('h1c,6,0);check(!irq_o,"no event until actual feedback");accept_and_commit;
            check(irq_o,"commit IRQ");write_word('h18,1,15,0,0);
            for(j=1;j<=3;j++)begin
                submit(j%3,j+1,1);await_command(j%3,j+1,1);accept_and_commit;
                expect_read('h58,1,0);expect_read('h1c,6,0);write_word('h18,1,15,0,0);
            end
            expect_read('h74,4,0);expect_read('h78,0,0);
            make_record(1,2,11);face_record;load_record;submit(1,5,0);await_command(1,5,0);accept_and_commit;
            expect_read('h1c,4,0);write_word('h18,1,15,0,0);
            @(negedge clk_i);retire_valid_i=1;retire_slot_i=0;retire_frame_i=1;retire_generation_i=10;
            cycle;@(negedge clk_i);retire_valid_i=0;
            expect_read('h14,2,0);expect_read('h5c,1,0);expect_read('h60,10,0);expect_read('h1c,4,0);
            write_word('h18,3,15,2,0);expect_read('h14,2,0); // Atomic ACK failure.
            write_word('h18,2,15,0,0);expect_read('h1c,5,0);
        end
        1:begin
            for(j=0;j<15;j++)begin
                make_record(0,1,10);
                case(j)
                    0:record[0]=2;1:record[1]=641;2:record[7]=400;
                    3:record[10]=99;4:record[11]=99;5:record[9]=0;
                    6:record[12]=1;7:record[23]=1;8:record[159]=1;
                    9:begin face_record;record[33]=record[32];end
                    10:begin face_record;record[34]=32;end
                    11:begin face_record;record[16]=32'h827c0010;end
                    12:begin face_record;record[17]=262160;end
                    13:begin face_record;record[14]=2;end
                    14:begin face_record;record[15]=8;end
                endcase
                reject_record(j>=13?2:0,j<3?8'h10:j<7?8'h11:j<11?8'h12:j<13?8'h13:8'h14);
                asset_ready_i=1;
            end
        end
        2:begin
            write_word(0,1,15,2,0);expect_read('h20,0,2);expect_read('h84,0,3);
            write_word('h84,0,0,3,0);write_word('h101,0,15,3,0);expect_read(32'hfffff000,0,3);
            write_word('h10,16,15,2,0);write_word('h18,0,1,2,0);write_word('h20,1,1,2,0);
            write_word('h100,32'h11223344,15,0,3);write_word('h100,32'haabbccdd,5,0,-3);
            expect_read('h100,32'h11bb33dd,0);write_word('h100,32'hffffffff,0,0,0);
            expect_read('h100,32'h11bb33dd,0);write_word('h100,32'hx,0,2,0);
            expect_read('h100,32'h11bb33dd,0);write_word('h24,3,15,0,0);
        end
        3:begin
            make_record(0,1,10);face_record;load_record;submit(0,1,0);
            write_word('h100,9,15,2,0); // During protected validation/offer.
            await_command(0,1,0);
            // After owner acceptance, the source shadow can be reused even
            // while the published command is still blocked downstream.
            write_word('h104,9,15,0,0);write_word('h28,99,15,0,0);
            check(cmd_data_o===expected_record&&cmd_seq_o==1,"shadow reuse must not tear held command");
            accept_and_commit;write_word('h18,1,15,0,0);
            write_word('h104,640,15,0,0);submit(1,2,1);await_command(1,2,1);accept_and_commit;
        end
        4:begin
            make_record(0,1,10);load_record;submit(2,1,0); // valid no-face AVATAR needs no asset
            asset_ready_i=0;await_command(2,1,0);
            @(negedge clk_i);cmd_ready_i=1;cycle;@(negedge clk_i);cmd_ready_i=0;
            feedback_valid_i=1;feedback_slot_i=0;feedback_frame_i=1;feedback_generation_i=10;
            feedback_mode_i=2;feedback_seq_i=99;cycle;@(negedge clk_i);feedback_valid_i=0;
            expect_read('hc,32'he2,0);expect_read('h14,8,0);expect_read('h30,0,0);
            write_word('h20,1,15,2,0);
            @(negedge clk_i);feedback_seq_i=1;feedback_valid_i=1;cycle;@(negedge clk_i);feedback_valid_i=0;
            expect_read('h14,9,0);expect_read('h30,1,0);write_word('h18,1,15,0,0);
            expect_read('h14,8,0);expect_read('hc,32'he2,0);
        end
        5:begin
            make_record(0,1,10);load_record;submit(0,1,0);await_command(0,1,0);accept_and_commit;
            write_word('h18,1,15,0,0);submit(1,2,1);await_command(1,2,1);accept_and_commit;
            write_word('h18,1,15,0,0);
            @(negedge clk_i);retire_valid_i=1;retire_slot_i=0;retire_frame_i=1;retire_generation_i=10;
            cycle;@(negedge clk_i);retire_valid_i=0;
            expect_read('hc,32'he3,0);expect_read('h1c,6,0);expect_read('h14,8,0);
        end
        6:begin
            for(j=0;j<16;j++)begin end
            make_record(2,9,30);face_record;record[12]=65535;record[13]=15;
            for(j=1;j<16;j++)for(k=0;k<8;k++)record[32+j*8+k]=record[32+k];
            // Signed cross-edge rectangles and all five points are retained.
            record[32]={16'hfff0,16'hffe0};record[33]={16'd610,16'd810};
            record[21]={16'h8000,16'h8000};record[22]={16'h7fff,16'h7fff};
            load_record;submit(2,32'hffffffff,0);await_command(2,32'hffffffff,0);accept_and_commit;
            write_word('h18,1,15,0,0);submit(0,0,1);await_command(0,0,1);accept_and_commit;
        end
        7:begin
            make_record(0,1,10);load_record;submit(0,1,0);reset_all;
            expect_read('h1c,7,0);expect_read('h14,0,0);
            make_record(1,2,20);load_record;submit(1,2,0);await_command(1,2,0);reset_all;
            expect_read('h1c,7,0);
            make_record(2,3,30);load_record;submit(0,3,0);await_command(0,3,0);accept_and_commit;
            reset_all;expect_read('h30,0,0);expect_read('h1c,7,0);
        end
        8:begin
            make_record(0,1,10);face_record;load_record;asset_ready_i=0;
            submit(2,1,0);repeat(40)cycle;
            expect_read('h14,0,0);expect_read('h1c,7,0);check(!cmd_valid_o,"material wait cannot publish");
            read_word('h8,0);check(rd[0],"material preparation stays pending");
            write_word('h100,2,15,2,0);write_word('h24,0,15,2,0);
            @(negedge clk_i);asset_ready_i=1;await_command(2,1,0);accept_and_commit;
        end
        9:begin
            check($value$plusargs("DRIVER_TRACE=%s",trace_path),"driver trace path required");
            make_record(2,42,5);for(j=0;j<160;j++)expected_record[j*32+:32]=record[j];
            trace_file=$fopen(trace_path,"r");check(trace_file!=0,"open actual C driver trace");n=0;
            while(!$feof(trace_file))begin
                trace_status=$fscanf(trace_file,"%h %h\n",trace_off,trace_value);
                if(trace_status==2)begin write_word(trace_off,trace_value,15,0,(n%3)-1);n++;end
                else check($feof(trace_file),"malformed driver trace");
            end
            $fclose(trace_file);check(n==163,"exact driver write count");
            await_command(1,123,0);accept_and_commit;expect_read('h1c,3,0);
        end
        10:begin
            // Compact endpoint: accept one read independently of the busy
            // record-copy RAM, then retain its address until that port is free.
            make_record(0,1,10);face_record;load_record;submit(1,1,0);
            check(dut.phase==1||dut.phase==2,"read queue test requires active record copy");
            @(negedge clk_i);s_axi_araddr_i=32'h2001111c;s_axi_arvalid_i=1;
            #1;check(s_axi_arready_o,"queued shadow read must be admitted while record copy owns RAM");
            cycle;
            @(negedge clk_i);s_axi_arvalid_i=0;s_axi_araddr_i=32'hdeadbeef;
            n=0;
            while(!s_axi_rvalid_o)begin
                check(!s_axi_arready_o,"only one queued read may be outstanding");
                cycle;n++;check(n<1000,"queued shadow read must complete after copy");
            end
            check(s_axi_rresp_o==0&&s_axi_rdata_o===record[7],"queued read retains accepted address");
            @(negedge clk_i);s_axi_arvalid_i=1;s_axi_araddr_i=32'h20011000;
            repeat(5)begin cycle;check(!s_axi_arready_o&&s_axi_rvalid_o&&s_axi_rdata_o===record[7],"queued response stable under backpressure");end
            @(negedge clk_i);s_axi_rready_i=1;cycle;
            @(negedge clk_i);s_axi_rready_i=0;s_axi_arvalid_i=0;
            expect_read(0,32'h10000,0);
            reset_all;expect_read(0,32'h10000,0);
            make_record(0,2,11);load_record;submit(1,2,0);
            @(negedge clk_i);s_axi_araddr_i=32'h2001111c;s_axi_arvalid_i=1;
            #1;check(s_axi_arready_o,"second pending read admission");cycle;
            reset_all;repeat(170)cycle;
            check(!s_axi_rvalid_o,"reset discards queued read without ghost response");
            expect_read(0,32'h10000,0);
        end
        default:$fatal(1,"unknown case");
        endcase
        $display("DISPLAY_MMIO_PASS case=%0d checks=%0d",test_case,checks);$finish;
    end
    initial begin #10000000;$fatal(1,"DISPLAY_MMIO timeout");end
endmodule
`default_nettype wire
