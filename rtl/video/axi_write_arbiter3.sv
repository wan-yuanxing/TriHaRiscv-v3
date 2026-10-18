`timescale 1ns/1ps

// Single-outstanding, round-robin AXI write arbiter. Master 0 occupies each
// packed input's least significant slice. Master BID/BRESP connect directly to
// the shared response bus; only BVALID is owner/phase qualified here.
//
// There is deliberately no abort: a published master AW must remain stable
// until accepted and every selected transaction must drain through B. Sticky
// faults report to the controller without suppressing selection or VALID.
// Coordinated reset of masters, arbiter and slave is the only cancellation.
module axi_write_arbiter3 (
    input  wire         clk,
    input  wire         reset_n,
    input  wire [11:0]  s_awid,
    input  wire [95:0]  s_awaddr,
    input  wire [23:0]  s_awlen,
    input  wire [8:0]   s_awsize,
    input  wire [5:0]   s_awburst,
    input  wire [2:0]   s_awvalid,
    output reg  [2:0]   s_awready,
    input  wire [383:0] s_wdata,
    input  wire [47:0]  s_wstrb,
    input  wire [2:0]   s_wlast,
    input  wire [2:0]   s_wvalid,
    output reg  [2:0]   s_wready,
    output reg  [2:0]   s_bvalid,
    input  wire [2:0]   s_bready,
    output reg  [3:0]   awid,
    output reg  [31:0]  awaddr,
    output reg  [7:0]   awlen,
    output reg  [2:0]   awsize,
    output reg  [1:0]   awburst,
    output reg          awvalid,
    input  wire         awready,
    output reg  [127:0] wdata,
    output reg  [15:0]  wstrb,
    output reg          wlast,
    output reg          wvalid,
    input  wire         wready,
    input  wire [3:0]   bid,
    input  wire [1:0]   bresp,
    input  wire         bvalid,
    output wire         bready,
    output reg          fault,
    output reg  [7:0]   fault_code,
    output wire         owner_active,
    output wire [1:0]   owner,
    output wire         idle
);
    localparam [7:0] FAULT_UNOWNED_B = 8'd1;
    localparam [7:0] FAULT_BID       = 8'd2;
    localparam [7:0] FAULT_BRESP     = 8'd3;
    localparam [7:0] FAULT_EARLY_B   = 8'd4;

    reg active;
    reg [1:0] owner_r;
    reg [1:0] next_owner;
    reg [1:0] grant;
    reg [3:0] selected_awid;
    reg aw_done;
    reg last_done;
    wire b_phase = aw_done && last_done;

    assign owner_active = active;
    assign owner = owner_r;
    assign idle = !active && !(|s_awvalid) && !bvalid;
    // An unowned response is consumed without ever asserting a master's BVALID.
    // A premature B is reported but held off until both AW and WLAST have
    // handshaken. If it remains VALID, it may then drain in the legal B phase;
    // it cannot retire or replace the owner early.
    assign bready = reset_n && (!active || (b_phase && s_bready[owner_r]));

    always @* begin
        grant = 2'd0;
        case (next_owner)
            2'd0: begin
                if (s_awvalid[0]) grant = 2'd0;
                else if (s_awvalid[1]) grant = 2'd1;
                else if (s_awvalid[2]) grant = 2'd2;
            end
            2'd1: begin
                if (s_awvalid[1]) grant = 2'd1;
                else if (s_awvalid[2]) grant = 2'd2;
                else if (s_awvalid[0]) grant = 2'd0;
            end
            2'd2: begin
                if (s_awvalid[2]) grant = 2'd2;
                else if (s_awvalid[0]) grant = 2'd0;
                else if (s_awvalid[1]) grant = 2'd1;
            end
            default: grant = 2'd0;
        endcase
    end

    always @* begin
        awid = 4'b0;
        awaddr = 32'b0;
        awlen = 8'b0;
        awsize = 3'b0;
        awburst = 2'b0;
        awvalid = 1'b0;
        wdata = 128'b0;
        wstrb = 16'b0;
        wlast = 1'b0;
        wvalid = 1'b0;
        s_awready = 3'b000;
        s_wready = 3'b000;
        s_bvalid = 3'b000;
        if (reset_n && active) begin
            awid = s_awid[owner_r*4 +: 4];
            awaddr = s_awaddr[owner_r*32 +: 32];
            awlen = s_awlen[owner_r*8 +: 8];
            awsize = s_awsize[owner_r*3 +: 3];
            awburst = s_awburst[owner_r*2 +: 2];
            awvalid = s_awvalid[owner_r] && !aw_done;
            s_awready[owner_r] = awready && !aw_done;
            wdata = s_wdata[owner_r*128 +: 128];
            wstrb = s_wstrb[owner_r*16 +: 16];
            wlast = s_wlast[owner_r];
            wvalid = s_wvalid[owner_r] && !last_done;
            s_wready[owner_r] = wready && !last_done;
            s_bvalid[owner_r] = bvalid && b_phase;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active <= 1'b0;
            owner_r <= 2'd0;
            next_owner <= 2'd0;
            selected_awid <= 4'b0;
            aw_done <= 1'b0;
            last_done <= 1'b0;
            fault <= 1'b0;
            fault_code <= 8'b0;
        end else begin
            // Case inequality rejects any X/Z response bit. First cause wins;
            // precedence is unowned, early phase, wrong/unknown ID, then RESP.
            if (!fault && bvalid) begin
                if (!active) begin
                    fault <= 1'b1;
                    fault_code <= FAULT_UNOWNED_B;
                end else if (!b_phase) begin
                    fault <= 1'b1;
                    fault_code <= FAULT_EARLY_B;
                end else if (bid !== selected_awid) begin
                    fault <= 1'b1;
                    fault_code <= FAULT_BID;
                end else if (bresp !== 2'b00) begin
                    fault <= 1'b1;
                    fault_code <= FAULT_BRESP;
                end
            end

            if (!active) begin
                if (|s_awvalid) begin
                    active <= 1'b1;
                    owner_r <= grant;
                    selected_awid <= s_awid[grant*4 +: 4];
                    aw_done <= 1'b0;
                    last_done <= 1'b0;
                end
            end else begin
                if (awvalid && awready) aw_done <= 1'b1;
                if (wvalid && wready && wlast) last_done <= 1'b1;
                if (bvalid && bready && b_phase) begin
                    active <= 1'b0;
                    case (owner_r)
                        2'd0: next_owner <= 2'd1;
                        2'd1: next_owner <= 2'd2;
                        default: next_owner <= 2'd0;
                    endcase
                end
            end
        end
    end
endmodule
