`timescale 1ns/1ps
module tb_npu_operator_mmio;
    reg clk_i = 0;
    always #5 clk_i = ~clk_i;
    reg rst_ni = 0;
    reg [31:0] s_axi_awaddr_i = 0;
    reg s_axi_awvalid_i = 0;
    wire s_axi_awready_o;
    reg [31:0] s_axi_wdata_i = 0;
    reg [3:0] s_axi_wstrb_i = 0;
    reg s_axi_wvalid_i = 0;
    wire s_axi_wready_o;
    wire [1:0] s_axi_bresp_o;
    wire s_axi_bvalid_o;
    reg s_axi_bready_i = 0;
    reg [31:0] s_axi_araddr_i = 0;
    reg s_axi_arvalid_i = 0;
    wire s_axi_arready_o;
    wire [31:0] s_axi_rdata_o;
    wire [1:0] s_axi_rresp_o;
    wire s_axi_rvalid_o;
    reg s_axi_rready_i = 0;
    reg engine_busy_i = 0;
    reg engine_done_i = 0;
    reg engine_error_i = 0;
    reg [7:0] engine_error_code_i = 0;
    reg [31:0] engine_total_cycles_i = 0;
    reg [31:0] engine_compute_cycles_i = 0;
    reg [31:0] engine_dma_wait_cycles_i = 0;
    reg platform_fault_i = 0;
    wire start_o, irq_o;
    wire [31:0] frame_id_o, generation_o, op_tag_o;
    wire [31:0] cfg_input_base_o, cfg_weight_base_o, cfg_bias_base_o;
    wire [31:0] cfg_requant_base_o, cfg_output_base_o;
    wire [15:0] cfg_input_width_o, cfg_input_height_o;
    wire [15:0] cfg_output_width_o, cfg_output_height_o;
    wire [15:0] cfg_input_channels_o, cfg_output_channels_o;
    wire [1:0] cfg_kernel_o, cfg_stride_o, cfg_padding_o;
    wire cfg_depthwise_o, cfg_input_signed_o;
    wire [1:0] cfg_output_format_o;
    npu_operator_mmio u_dut (.*);

    localparam [31:0] BASE = 32'h20000000;
    integer starts = 0;
    integer checks = 0;
    always @(posedge clk_i) begin
        if (rst_ni && start_o) starts <= starts + 1;
    end

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic check(input bit okay, input string label_text);
        begin
            checks = checks + 1;
            if (!okay) $fatal(1, "MMIO_FAIL %s at %0t", label_text, $time);
        end
    endtask

    task automatic send_aw(input [31:0] address);
        integer n;
        begin
            @(negedge clk_i);
            s_axi_awaddr_i = address;
            s_axi_awvalid_i = 1;
            n = 0;
            begin : wait_aw
                forever begin
                    @(posedge clk_i);
                    if (s_axi_awready_o) disable wait_aw;
                    n = n + 1;
                    if (n > 100) $fatal(1, "MMIO_FAIL AW timeout");
                end
            end
            @(negedge clk_i); s_axi_awvalid_i = 0;
        end
    endtask

    task automatic send_w(input [31:0] value, input [3:0] strobes);
        integer n;
        begin
            @(negedge clk_i);
            s_axi_wdata_i = value;
            s_axi_wstrb_i = strobes;
            s_axi_wvalid_i = 1;
            n = 0;
            begin : wait_w
                forever begin
                    @(posedge clk_i);
                    if (s_axi_wready_o) disable wait_w;
                    n = n + 1;
                    if (n > 100) $fatal(1, "MMIO_FAIL W timeout");
                end
            end
            @(negedge clk_i); s_axi_wvalid_i = 0;
        end
    endtask

    task automatic take_b(input [1:0] response, input integer stall);
        integer n;
        begin
            n = 0;
            while (s_axi_bvalid_o !== 1'b1) begin
                tick(); n = n + 1;
                if (n > 100) $fatal(1, "MMIO_FAIL B timeout");
            end
            check(s_axi_bresp_o === response, "write response");
            repeat (stall) begin
                tick();
                check(s_axi_bvalid_o === 1 && s_axi_bresp_o === response,
                      "B held under backpressure");
                check(!s_axi_awready_o && !s_axi_wready_o,
                      "one write response outstanding");
            end
            @(negedge clk_i); s_axi_bready_i = 1;
            tick();
            @(negedge clk_i); s_axi_bready_i = 0;
        end
    endtask

    task automatic write_reg(input [31:0] offset, input [31:0] value,
                             input [3:0] strobes, input [1:0] response,
                             input integer ordering);
        begin
            if (ordering == 0) begin
                fork send_aw(BASE + offset); send_w(value, strobes); join
            end else if (ordering == 1) begin
                send_aw(BASE + offset); repeat (3) tick(); send_w(value, strobes);
            end else begin
                send_w(value, strobes); repeat (4) tick(); send_aw(BASE + offset);
            end
            take_b(response, 3);
        end
    endtask

    task automatic read_addr(input [31:0] address, input [31:0] value,
                             input [1:0] response, input integer stall);
        integer n;
        begin
            @(negedge clk_i);
            s_axi_araddr_i = address;
            s_axi_arvalid_i = 1;
            n = 0;
            begin : wait_ar
                forever begin
                    @(posedge clk_i);
                    if (s_axi_arready_o) disable wait_ar;
                    n = n + 1;
                    if (n > 100) $fatal(1, "MMIO_FAIL AR timeout");
                end
            end
            @(negedge clk_i); s_axi_arvalid_i = 0;
            n = 0;
            while (s_axi_rvalid_o !== 1'b1) begin
                tick(); n = n + 1;
                if (n > 100) $fatal(1, "MMIO_FAIL R timeout");
            end
            check(s_axi_rdata_o === value && s_axi_rresp_o === response,
                  $sformatf("read %08x expected %08x/%0d got %08x/%0d",
                            address, value, response, s_axi_rdata_o, s_axi_rresp_o));
            repeat (stall) begin
                tick();
                check(s_axi_rvalid_o === 1 && s_axi_rdata_o === value &&
                      s_axi_rresp_o === response, "R held under backpressure");
                check(!s_axi_arready_o, "one read response outstanding");
            end
            @(negedge clk_i); s_axi_rready_i = 1;
            tick();
            @(negedge clk_i); s_axi_rready_i = 0;
        end
    endtask

    task automatic read_reg(input [31:0] offset, input [31:0] value);
        begin read_addr(BASE + offset, value, 0, 3); end
    endtask

    task automatic complete(input bit error_value, input [7:0] error_code);
        begin
            @(negedge clk_i);
            engine_busy_i = 0;
            engine_error_i = error_value;
            engine_error_code_i = error_code;
            engine_total_cycles_i = 1234;
            engine_compute_cycles_i = 567;
            engine_dma_wait_cycles_i = 667;
            engine_done_i = 1;
            tick();
            @(negedge clk_i); engine_done_i = 0;
        end
    endtask

    initial begin
        repeat (3) tick();
        @(negedge clk_i); rst_ni = 1;
        read_reg('h00, 32'h4e500001);
        read_reg('h04, 32'h00010003);
        read_reg('h0c, 1);
        read_reg('h10, 0);
        read_reg('h14, 0);
        check(!start_o && !irq_o, "reset outputs");
        read_addr(BASE + 1, 0, 3, 2);
        read_addr(BASE + 'h34, 0, 3, 2);
        read_addr(BASE + 'h1000, 0, 3, 2);
        read_addr(32'h30000000, 0, 3, 2);
        write_reg('h1000, 1, 15, 3, 0);
        write_reg(1, 1, 15, 3, 1);
        write_reg('h34, 1, 15, 3, 2);
        write_reg(0, 1, 15, 2, 0);
        write_reg('h0c, 1, 15, 2, 0);
        write_reg('h18, 1, 15, 2, 0);
        write_reg('h24, 1, 15, 2, 0);
        write_reg('h08, 1, 1, 2, 0);
        write_reg('h08, 0, 15, 2, 0);
        write_reg('h08, 3, 15, 2, 0);
        write_reg('h120, 'h80000000, 15, 2, 0);
        write_reg('h124, 'h2, 15, 2, 0);
        write_reg('h14, 4, 15, 2, 0);
        write_reg('h10, 4, 15, 2, 0);

        // Each half must be latched at its own handshake, even if the bus
        // presents unrelated values while waiting for the other half.
        send_aw(BASE + 'h100);
        s_axi_awaddr_i = BASE;
        send_w('h81234567, 15);
        take_b(0, 3);
        read_reg('h100, 'h81234567);
        send_w('h89abcdef, 15);
        s_axi_wdata_i = 0;
        s_axi_wstrb_i = 0;
        send_aw(BASE + 'h100);
        take_b(0, 3);
        read_reg('h100, 'h89abcdef);

        write_reg('h100, 'h82000000, 15, 0, 0);
        write_reg('h100, 'h12345678, 5, 0, 1);
        read_reg('h100, 'h82340078);
        write_reg('h100, 'hffffffff, 0, 0, 2);
        read_reg('h100, 'h82340078);
        write_reg('h104, 'h83000000, 15, 0, 2);
        write_reg('h108, 'h84000000, 15, 0, 1);
        write_reg('h10c, 'h85000000, 15, 0, 0);
        write_reg('h110, 'h86000000, 15, 0, 0);
        write_reg('h114, 'h0140013f, 15, 0, 0);
        write_reg('h118, 'h00400003, 15, 0, 0);
        write_reg('h11c, 'h00a0009f, 15, 0, 0);
        write_reg('h120, 'h01010203, 15, 0, 0);
        write_reg('h124, 'h00000301, 15, 0, 0);
        write_reg('h120, 'hff000000, 1, 0, 0);
        read_reg('h120, 'h01010200);
        write_reg('h120, 3, 1, 0, 0);
        write_reg('h124, 'hffff0200, 2, 0, 0);
        write_reg('h1c, 'h12345678, 15, 0, 0);
        write_reg('h20, 'haabbccdd, 15, 0, 0);
        write_reg('h30, 'h99887766, 15, 0, 0);
        check(cfg_input_base_o == 'h82340078 && cfg_weight_base_o == 'h83000000 &&
              cfg_bias_base_o == 'h84000000 && cfg_requant_base_o == 'h85000000 &&
              cfg_output_base_o == 'h86000000, "base configuration outputs");
        check(cfg_input_width_o == 319 && cfg_input_height_o == 320 &&
              cfg_output_width_o == 159 && cfg_output_height_o == 160 &&
              cfg_input_channels_o == 3 && cfg_output_channels_o == 64,
              "dimension configuration outputs");
        check(cfg_kernel_o == 3 && cfg_stride_o == 2 && cfg_padding_o == 1 &&
              cfg_depthwise_o && cfg_input_signed_o && cfg_output_format_o == 2,
              "format configuration outputs");
        write_reg('h14, 1, 1, 0, 0);

        // Accept START before the engine raises busy; freeze immediately.
        write_reg('h08, 1, 15, 0, 0);
        read_reg('h0c, 2);
        check(starts == 1, "exactly one start pulse");
        write_reg('h100, 0, 15, 2, 0);
        write_reg('h20, 0, 15, 2, 0);
        write_reg('h08, 1, 15, 2, 0);
        engine_busy_i = 1;
        write_reg('h30, 0, 15, 2, 0);
        check(frame_id_o == 'haabbccdd && generation_o == 'h99887766 &&
              op_tag_o == 'h12345678 && cfg_input_base_o == 'h82340078,
              "identity and configuration frozen while active");
        complete(0, 0);
        read_reg('h0c, 5);
        read_reg('h10, 1);
        read_reg('h24, 1234);
        read_reg('h28, 567);
        read_reg('h2c, 667);
        check(irq_o, "enabled done interrupt");
        write_reg('h08, 1, 15, 2, 0);
        write_reg('h1c, 0, 15, 2, 0);
        write_reg('h124, 0, 15, 2, 0);
        read_reg('h10, 1);
        write_reg('h14, 0, 1, 0, 0);
        check(!irq_o, "interrupt masked without clearing event");
        write_reg('h08, 1, 15, 2, 0);
        write_reg('h10, 1, 2, 0, 0);
        read_reg('h10, 1);
        write_reg('h10, 1, 1, 0, 0);
        read_reg('h10, 0);

        // Busy without active and platform fault both prevent submission.
        engine_busy_i = 1;
        write_reg('h08, 1, 15, 2, 0);
        write_reg('h100, 0, 15, 2, 0);
        engine_busy_i = 0;
        platform_fault_i = 1;
        read_reg('h0c, 17);
        write_reg('h08, 1, 15, 2, 0);
        check(starts == 1, "rejected starts never pulse");
        platform_fault_i = 0;
        write_reg('h20, 'h01020304, 15, 0, 0);
        write_reg('h30, 'h05060708, 15, 0, 0);
        write_reg('h1c, 'h090a0b0c, 15, 0, 0);
        write_reg('h14, 2, 1, 0, 0);
        write_reg('h08, 1, 15, 0, 0);
        complete(1, 4);
        read_reg('h0c, 9);
        read_reg('h10, 2);
        read_reg('h18, 4);
        read_reg('h20, 'h01020304);
        read_reg('h30, 'h05060708);
        read_reg('h1c, 'h090a0b0c);
        check(irq_o && starts == 2, "error interrupt with correct identity");
        engine_error_code_i = 8'hfe;
        engine_total_cycles_i = 32'hffffffff;
        read_reg('h18, 4);
        read_reg('h24, 1234);

        // Pair a W1C execute edge with a new completion event.
        fork send_aw(BASE + 'h10); send_w(2, 1); join
        // Both send tasks return on the negedge before write_execute.
        engine_done_i = 1;
        tick();
        @(negedge clk_i); engine_done_i = 0;
        take_b(0, 2);
        read_reg('h10, 2);
        write_reg('h10, 2, 1, 0, 0);
        read_reg('h10, 0);

        // Independent read and write channels can operate together.
        fork
            write_reg('h100, 'h82000010, 15, 0, 2);
            read_reg('h04, 'h00010003);
        join
        read_reg('h100, 'h82000010);

        // Once accepted, even live STATUS data is stable until RREADY.
        @(negedge clk_i);
        s_axi_araddr_i = BASE + 'h0c;
        s_axi_arvalid_i = 1;
        @(posedge clk_i);
        check(s_axi_arready_o, "status read accepted");
        @(negedge clk_i);
        s_axi_arvalid_i = 0;
        platform_fault_i = 1;
        repeat (3) begin
            tick();
            check(s_axi_rvalid_o && s_axi_rdata_o == 1 && s_axi_rresp_o == 0,
                  "live status snapshot held under backpressure");
        end
        @(negedge clk_i); s_axi_rready_i = 1;
        tick();
        @(negedge clk_i); s_axi_rready_i = 0;
        read_reg('h0c, 17);
        platform_fault_i = 0;

        // Coordinate reset while both response channels are backpressured.
        write_reg('h08, 1, 15, 0, 0);
        complete(1, 4);
        check(irq_o, "completion pending before coordinated reset");
        fork send_aw(BASE + 'h100); send_w('hffffffff, 15); join
        @(negedge clk_i);
        s_axi_araddr_i = BASE;
        s_axi_arvalid_i = 1;
        tick();
        @(negedge clk_i); s_axi_arvalid_i = 0;
        check(s_axi_bvalid_o && s_axi_rvalid_o, "both responses pending before reset");
        rst_ni = 0;
        tick();
        check(!s_axi_bvalid_o && !s_axi_rvalid_o && !irq_o,
              "reset discards both held responses");
        @(negedge clk_i); rst_ni = 1;
        read_reg('h100, 0);

        // Reset abandons buffered halves/responses, sticky events and active.
        send_aw(BASE + 'h100);
        @(negedge clk_i); rst_ni = 0;
        repeat (2) tick();
        check(!s_axi_bvalid_o && !s_axi_rvalid_o && !start_o && !irq_o,
              "reset clears responses");
        @(negedge clk_i); rst_ni = 1;
        read_reg('h0c, 1);
        read_reg('h10, 0);
        read_reg('h14, 0);
        read_reg('h18, 0);
        read_reg('h24, 0);
        read_reg('h28, 0);
        read_reg('h2c, 0);
        read_reg('h100, 0);
        read_reg('h20, 0);
        read_reg('h30, 0);
        read_reg('h1c, 0);
        write_reg('h100, 'h82000020, 15, 0, 0);
        write_reg('h08, 1, 15, 0, 0);
        @(negedge clk_i); rst_ni = 0;
        tick();
        @(negedge clk_i); rst_ni = 1;
        read_reg('h0c, 1);
        $display("MMIO_PASS checks=%0d starts=%0d", checks, starts);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "MMIO_FAIL global timeout");
    end
endmodule
