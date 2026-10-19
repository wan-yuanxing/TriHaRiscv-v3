`timescale 1ns/1ps
// File-driven stimulus and synchronous texture provider. Expected pixels are
// computed separately in overlay_reference.py, never by this driver.
module tb_display_overlay;
    parameter integer LINE_WIDTH = 2;
    parameter integer POINT_RADIUS = 2;
    reg clk = 0;
    always #12.5 clk = ~clk;
    reg rst = 1;
    reg [92:0] event_word = 0;
    reg [3786:0] configs [0:255];
    reg [3786:0] config_word;
    wire event_reset;
    wire [7:0] config_id;
    wire [31:0] pixel_frame_id;
    wire [10:0] pixel_x, pixel_y;
    wire [23:0] pixel_rgb;
    wire pixel_de, pixel_hs, pixel_vs, pixel_sof;
    wire [1:0] behavior;
    assign {event_reset,config_id,pixel_frame_id,pixel_x,pixel_y,pixel_rgb,
            pixel_de,pixel_hs,pixel_vs,pixel_sof,behavior} = event_word;
    wire [1:0] mode;
    wire result_valid, result_has_face, primary_valid, points_enable, avatar_enable;
    wire [31:0] result_frame_id;
    wire [3:0] primary_index;
    wire [15:0] box_valid;
    wire [255:0] box_x0, box_y0, box_x1, box_y1;
    wire [79:0] point_valid;
    wire [1279:0] point_x, point_y;
    wire signed [15:0] avatar_x0, avatar_y0, avatar_x1, avatar_y1;
    assign {mode,result_valid,result_has_face,result_frame_id,primary_valid,
            primary_index,points_enable,box_valid,box_x0,box_y0,box_x1,box_y1,
            point_valid,point_x,point_y,avatar_enable,
            avatar_x0,avatar_y0,avatar_x1,avatar_y1} = config_word;
    wire avatar_req_valid;
    wire [17:0] avatar_req_addr;
    reg sample_valid = 0, sample_error = 0;
    reg [31:0] sample_rgba = 0;
    wire [23:0] out_rgb;
    wire [10:0] out_x, out_y;
    wire [31:0] out_frame_id;
    wire out_de, out_hs, out_vs, out_sof;
    wire out_box, out_point, out_avatar, out_fault, overlay_fault;

    display_overlay #(.LINE_WIDTH(LINE_WIDTH),.POINT_RADIUS(POINT_RADIUS)) dut (
        .clk(clk),.rst(rst),.pixel_frame_id(pixel_frame_id),.pixel_x(pixel_x),
        .pixel_y(pixel_y),.pixel_rgb(pixel_rgb),.pixel_de(pixel_de),
        .pixel_hs(pixel_hs),.pixel_vs(pixel_vs),.pixel_sof(pixel_sof),
        .mode(mode),.result_valid(result_valid),.result_has_face(result_has_face),
        .result_frame_id(result_frame_id),.primary_valid(primary_valid),
        .primary_index(primary_index),.points_enable(points_enable),
        .box_valid(box_valid),.box_x0(box_x0),.box_y0(box_y0),.box_x1(box_x1),.box_y1(box_y1),
        .point_valid(point_valid),.point_x(point_x),.point_y(point_y),
        .avatar_enable(avatar_enable),.avatar_x0(avatar_x0),.avatar_y0(avatar_y0),
        .avatar_x1(avatar_x1),.avatar_y1(avatar_y1),
        .avatar_req_valid(avatar_req_valid),.avatar_req_addr(avatar_req_addr),
        .sample_valid(sample_valid),.sample_error(sample_error),.sample_rgba(sample_rgba),
        .out_rgb(out_rgb),.out_x(out_x),.out_y(out_y),.out_frame_id(out_frame_id),
        .out_de(out_de),.out_hs(out_hs),.out_vs(out_vs),.out_sof(out_sof),
        .out_box(out_box),.out_point(out_point),.out_avatar(out_avatar),
        .out_fault(out_fault),.overlay_fault(overlay_fault));

    reg [1:0] behavior_pipe [0:8];
    integer ids [0:12];
    reg [12:0] valids = 0;
    integer current_id = -1, i, sx, sy, r, g, b, a;
    integer dump_fd, event_fd, config_fd, scan_status, config_count = 0, count = 0;
    reg driving = 0;
    string directory;

    always @(posedge clk) begin
        if (rst) begin
            valids <= 0;
            sample_valid <= 0;
            sample_error <= 0;
            sample_rgba <= 0;
            for (i=0;i<9;i=i+1) behavior_pipe[i] <= 0;
        end else begin
            // Requests before this edge are consumed into the corresponding
            // registered response. No stalls, sliding, response reuse or queue.
            if (valids[8]) $fdisplay(dump_fd,"Q %0d %h %h",ids[8],avatar_req_valid,avatar_req_addr);
            sx = avatar_req_addr[9:2];
            sy = avatar_req_addr[17:10];
            r = (37*sx+13*sy+17)&255;
            g = (sx ^ (sy*7))&255;
            b = (255-sx+11*sy)&255;
            a = (sx+3*sy)&255;
            // Invalid material slots may carry uninitialized cache RAM data.
            // They must never contaminate RAW, BOX or an avatar fallback pixel.
            sample_rgba <= (!avatar_req_valid || behavior_pipe[8] == 1 || behavior_pipe[8] == 2)
                           ? 32'hxxxxxxxx : {r[7:0],g[7:0],b[7:0],a[7:0]};
            // Behavior3 also inserts unsolicited responses in non-request slots.
            sample_valid <= (avatar_req_valid && behavior_pipe[8] != 1) || behavior_pipe[8] == 3;
            sample_error <= behavior_pipe[8] == 2;
            behavior_pipe[0] <= behavior;
            for (i=1;i<9;i=i+1) behavior_pipe[i] <= behavior_pipe[i-1];
            valids <= {valids[11:0],driving};
            ids[0] <= current_id;
            for (i=1;i<13;i=i+1) ids[i] <= ids[i-1];
        end
        #1;
        if (rst && {out_rgb,out_x,out_y,out_frame_id,out_de,out_hs,out_vs,out_sof,
                    out_box,out_point,out_avatar,out_fault,overlay_fault} !== 0)
            $fatal(1,"Reset did not clear pixel pipeline");
        if (!rst && !valids[12] && {out_de,out_sof,out_box,out_point,out_avatar,out_fault} !== 0)
            $fatal(1,"Old pixel/overlay escaped into a reset or drain bubble");
        if (!rst && valids[12]) begin
            if ((^{out_frame_id,out_x,out_y,out_de,out_hs,out_vs,out_sof,
                    out_rgb,out_box,out_point,out_avatar,out_fault,overlay_fault}) === 1'bx)
                $fatal(1,"Unknown output at event %0d",ids[12]);
            $fdisplay(dump_fd,"P %0d %h %h %h %h %h %h %h %h %h %h %h %h %h",
                ids[12],out_frame_id,out_x,out_y,out_de,out_hs,out_vs,out_sof,
                out_rgb,out_box,out_point,out_avatar,out_fault,overlay_fault);
        end
    end

    initial begin
        if (!$value$plusargs("DIRECTORY=%s",directory)) $fatal(1,"Missing DIRECTORY");
        config_fd = $fopen({directory,"/configs.hex"},"r");
        if (!config_fd) $fatal(1,"Cannot open configs");
        while (!$feof(config_fd)) begin
            if (config_count == 256) $fatal(1,"Too many configs");
            scan_status = $fscanf(config_fd,"%h\n",configs[config_count]);
            if (scan_status != 1) $fatal(1,"Malformed config file");
            config_count = config_count+1;
        end
        $fclose(config_fd);
        dump_fd = $fopen({directory,"/pixels.log"},"w");
        event_fd = $fopen({directory,"/events.hex"},"r");
        if (!dump_fd || !event_fd) $fatal(1,"Cannot open vector/dump");
        config_word = 0;
        repeat (3) @(negedge clk);
        while (!$feof(event_fd)) begin
            scan_status = $fscanf(event_fd,"%h\n",event_word);
            if (scan_status != 1) $fatal(1,"Malformed event file");
            #1;
            rst = event_reset;
            config_word = configs[config_id];
            current_id = count;
            driving = 1;
            count = count+1;
            @(negedge clk);
        end
        driving = 0;
        event_word = 0;
        config_word = 0;
        rst = 0;
        repeat (16) @(negedge clk);
        $fclose(event_fd);
        $fclose(dump_fd);
        $display("DISPLAY_OVERLAY_DRIVER_PASS events=%0d",count);
        $finish;
    end
    initial begin
        #30000000;
        $fatal(1,"Overlay driver timeout");
    end
endmodule
