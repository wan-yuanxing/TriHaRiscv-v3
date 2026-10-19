`timescale 1ns/1ps
module tb_display_mode_cdc;
    parameter integer CONTEXT_WIDTH=128;
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0;
    real core_half=4.0,pixel_half=12.5;
    always #(core_half) core_clk=~core_clk;
    always #(pixel_half) pixel_clk=~pixel_clk;
    reg cmd_valid=0;
    wire cmd_ready;
    reg [1:0] cmd_mode=0,cmd_slot=0;
    reg [31:0] cmd_seq=0,cmd_frame_id=0,cmd_generation=0;
    reg [CONTEXT_WIDTH-1:0] cmd_data=0;
    wire commit_valid;
    reg commit_ready=0;
    wire [1:0] commit_mode,commit_slot;
    wire [31:0] commit_seq,commit_frame_id,commit_generation;
    wire [CONTEXT_WIDTH-1:0] commit_data;
    wire pixel_cmd_valid;
    reg pixel_cmd_ready=0,pixel_commit=0;
    wire [1:0] pixel_cmd_mode,pixel_cmd_slot;
    wire [31:0] pixel_cmd_seq,pixel_cmd_frame_id,pixel_cmd_generation;
    wire [CONTEXT_WIDTH-1:0] pixel_cmd_data;
    wire pixel_waiting_commit,pixel_protocol_error,protocol_error;
    display_mode_cdc #(.CONTEXT_WIDTH(CONTEXT_WIDTH)) dut(.*);
    wire [CONTEXT_WIDTH+99:0] pixel_payload={pixel_cmd_mode,pixel_cmd_slot,pixel_cmd_seq,
        pixel_cmd_frame_id,pixel_cmd_generation,pixel_cmd_data};
    wire [CONTEXT_WIDTH+99:0] feedback={commit_mode,commit_slot,commit_seq,
        commit_frame_id,commit_generation,commit_data};
    reg [CONTEXT_WIDTH+99:0] expected_payload;
    reg actual_committed=0;
    integer scenario=0,t,bit_index,checked=0;
    task automatic check(input bit ok,input string why);
        if(!ok)$fatal(1,"mode_cdc case%0d: %s",scenario,why);
    endtask
    // Pixel acceptance cannot substitute for the consumer's actual commit.
    always @(posedge core_clk) if(core_reset_n && commit_valid) begin
        check(actual_committed,"feedback before actual pixel commit");
        check(feedback===expected_payload,"feedback identity/context changed");
    end
    task automatic reset_both;
        begin
            core_reset_n=0;pixel_reset_n=0;cmd_valid=0;commit_ready=0;
            pixel_cmd_ready=0;pixel_commit=0;actual_committed=0;
            repeat(4)@(negedge core_clk);
            repeat(3)@(negedge pixel_clk);
            check(!commit_valid&&!pixel_cmd_valid&&!pixel_waiting_commit,"coordinated reset flush");
            core_reset_n=1;pixel_reset_n=1;
        end
    endtask
    task automatic send_command(input integer id);
        begin
            @(negedge core_clk);
            cmd_mode=id%3;cmd_slot=id%3;cmd_seq=32'hfffffff8+id;
            cmd_frame_id=32'h71000000+id;cmd_generation=id*19+1;
            for(bit_index=0;bit_index<CONTEXT_WIDTH;bit_index=bit_index+1)
                cmd_data[bit_index]=(bit_index*13+id*7)%17<8;
            expected_payload={cmd_mode,cmd_slot,cmd_seq,cmd_frame_id,cmd_generation,cmd_data};
            cmd_valid=1;actual_committed=0;
            do @(posedge core_clk);while(!cmd_ready);
            @(negedge core_clk);cmd_valid=0;
            // Invalid source payload has no ownership after the transfer.
            {cmd_mode,cmd_slot,cmd_seq,cmd_frame_id,cmd_generation,cmd_data}='x;
        end
    endtask
    task automatic await_offer;
        begin
            wait(pixel_cmd_valid);
            repeat(17)begin
                @(negedge pixel_clk);
                check(pixel_cmd_valid&&pixel_payload===expected_payload,"pixel offer lost/changed under backpressure");
                check(!cmd_ready&&!commit_valid,"core reused an incomplete transaction");
            end
        end
    endtask
    task automatic accept_pixel;
        begin
            @(negedge pixel_clk);pixel_cmd_ready=1;
            @(posedge pixel_clk);#1;
            check(!pixel_cmd_valid&&pixel_waiting_commit,"accept must enter wait-for-actual-commit");
            @(negedge pixel_clk);pixel_cmd_ready=0;
            repeat(19)begin
                @(negedge pixel_clk);
                check(pixel_waiting_commit&&pixel_payload===expected_payload,"accepted record lost before commit");
                check(!commit_valid&&!cmd_ready,"acceptance treated as commit");
            end
        end
    endtask
    task automatic finish_commit;
        begin
            @(negedge pixel_clk);actual_committed=1;pixel_commit=1;
            @(negedge pixel_clk);pixel_commit=0;
            wait(commit_valid);
            repeat(13)begin
                @(negedge core_clk);
                check(commit_valid&&feedback===expected_payload&&!cmd_ready,"feedback not held under backpressure");
            end
            commit_ready=1;
            @(negedge core_clk);commit_ready=0;
            repeat(4)@(negedge core_clk);
            check(cmd_ready&&!commit_valid,"feedback did not retire exactly once");
            checked=checked+1;
        end
    endtask
    initial begin
        if($value$plusargs("CASE=%d",scenario))begin end
        if($value$plusargs("CORE_HALF=%f",core_half))begin end
        if($value$plusargs("PIXEL_HALF=%f",pixel_half))begin end
        reset_both();
        case(scenario)
        0: for(t=0;t<24;t=t+1)begin send_command(t);await_offer();accept_pixel();finish_commit();end
        1: begin
            @(negedge pixel_clk);pixel_commit=1;
            @(negedge pixel_clk);pixel_commit=0;
            repeat(5)@(negedge core_clk);
            check(pixel_protocol_error&&protocol_error&&!commit_valid,"stray commit not isolated/reported");
            send_command(77);await_offer();accept_pixel();finish_commit();
            @(negedge pixel_clk);pixel_commit=1;
            @(negedge pixel_clk);pixel_commit=0;
            check(pixel_protocol_error&&!commit_valid,"duplicate commit created feedback");
        end
        2: begin send_command(1);await_offer();reset_both();
            repeat(8)@(negedge pixel_clk);check(!commit_valid&&!pixel_cmd_valid,"old offered command survived reset");
            send_command(81);await_offer();accept_pixel();finish_commit();end
        3: begin send_command(2);await_offer();accept_pixel();reset_both();
            repeat(8)@(negedge pixel_clk);check(!commit_valid&&!pixel_waiting_commit,"old accepted command survived reset");
            send_command(82);await_offer();accept_pixel();finish_commit();end
        4: begin
            send_command(3);await_offer();accept_pixel();
            @(negedge pixel_clk);actual_committed=1;pixel_commit=1;
            @(negedge pixel_clk);pixel_commit=0;wait(commit_valid);reset_both();
            repeat(8)@(negedge pixel_clk);check(!commit_valid&&!pixel_cmd_valid,"old feedback survived reset");
            send_command(83);await_offer();accept_pixel();finish_commit();end
        default:$fatal(1,"Unknown case");
        endcase
        $display("DISPLAY_MODE_CDC_PASS case=%0d transactions=%0d",scenario,checked);$finish;
    end
    initial begin #2000000;$fatal(1,"mode_cdc timeout");end
endmodule
