`timescale 1ns / 1ps

// Testbench for framebuffer + scaler + palette pipeline
// Verifies: dual-port write/read, scaler address mapping, palette output

module tb_framebuffer;

    // Clocks
    reg clk_ppu = 0;
    reg clk_vga = 0;

    // ~5.369 MHz PPU (93 ns half-period)
    always #93 clk_ppu = ~clk_ppu;
    // 25 MHz VGA (20 ns half-period)
    always #20 clk_vga = ~clk_vga;

    // Framebuffer signals
    reg        fb_we    = 0;
    reg [15:0] fb_waddr = 0;
    reg [5:0]  fb_wdata = 0;
    wire [5:0] fb_rdata;
    reg [15:0] fb_raddr = 0;

    framebuffer uut_fb (
        .clk_a  (clk_ppu),
        .we_a   (fb_we),
        .addr_a (fb_waddr),
        .din_a  (fb_wdata),
        .clk_b  (clk_vga),
        .addr_b (fb_raddr),
        .dout_b (fb_rdata)
    );

    // Scaler signals
    reg [9:0]  pixel_x = 0;
    reg [9:0]  pixel_y = 0;
    reg        video_active = 0;
    wire [15:0] scaler_addr;
    wire        in_nes_area;

    vga_scaler uut_scaler (
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_active (video_active),
        .fb_addr      (scaler_addr),
        .in_nes_area  (in_nes_area)
    );

    // Palette signals
    reg [5:0] pal_index = 0;
    wire [3:0] pal_r, pal_g, pal_b;

    nes_palette_lut uut_pal (
        .color_index (pal_index),
        .r           (pal_r),
        .g           (pal_g),
        .b           (pal_b)
    );

    integer errors = 0;
    integer i;

    initial begin
        $dumpfile("tb_framebuffer.vcd");
        $dumpvars(0, tb_framebuffer);

        // ==========================================================
        // Test 1: Write and read back from framebuffer
        // ==========================================================
        $display("Test 1: Framebuffer write/read");

        // Write known values at a few addresses
        // Set data before clock edge to avoid race conditions
        fb_we = 1;
        fb_waddr = 16'd0; fb_wdata = 6'h15;
        @(posedge clk_ppu); #1;

        fb_waddr = 16'd256; fb_wdata = 6'h2A;
        @(posedge clk_ppu); #1;

        fb_waddr = 16'd61439; fb_wdata = 6'h3F;
        @(posedge clk_ppu); #1;
        fb_we = 0;

        // Wait for writes to settle, then read back from VGA port
        #500;

        fb_raddr = 16'd0;
        @(posedge clk_vga); // addr sampled
        @(posedge clk_vga); #1; // data available
        if (fb_rdata !== 6'h15) begin
            $display("  ERROR: addr 0 expected 0x15, got 0x%02x", fb_rdata);
            errors = errors + 1;
        end

        fb_raddr = 16'd256;
        @(posedge clk_vga);
        @(posedge clk_vga); #1;
        if (fb_rdata !== 6'h2A) begin
            $display("  ERROR: addr 256 expected 0x2A, got 0x%02x", fb_rdata);
            errors = errors + 1;
        end

        fb_raddr = 16'd61439;
        @(posedge clk_vga);
        @(posedge clk_vga); #1;
        if (fb_rdata !== 6'h3F) begin
            $display("  ERROR: addr 61439 expected 0x3F, got 0x%02x", fb_rdata);
            errors = errors + 1;
        end

        $display("  Framebuffer read/write OK");

        // ==========================================================
        // Test 2: Scaler address mapping
        // ==========================================================
        $display("Test 2: Scaler address mapping");

        // VGA pixel (64, 0) -> NES pixel (0, 0) -> addr 0
        video_active = 1;
        pixel_x = 64; pixel_y = 0; #1;
        if (scaler_addr !== 16'd0 || !in_nes_area) begin
            $display("  ERROR: VGA(64,0) -> addr %0d, in_nes=%b (expected 0, 1)",
                     scaler_addr, in_nes_area);
            errors = errors + 1;
        end

        // VGA pixel (65, 0) -> NES pixel (0, 0) still (integer div by 2)
        pixel_x = 65; pixel_y = 0; #1;
        if (scaler_addr !== 16'd0) begin
            $display("  ERROR: VGA(65,0) -> addr %0d (expected 0)", scaler_addr);
            errors = errors + 1;
        end

        // VGA pixel (66, 0) -> NES pixel (1, 0) -> addr 1
        pixel_x = 66; pixel_y = 0; #1;
        if (scaler_addr !== 16'd1) begin
            $display("  ERROR: VGA(66,0) -> addr %0d (expected 1)", scaler_addr);
            errors = errors + 1;
        end

        // VGA pixel (575, 479) -> NES pixel (255, 239) -> addr 61439
        pixel_x = 575; pixel_y = 479; #1;
        if (scaler_addr !== 16'd61439) begin
            $display("  ERROR: VGA(575,479) -> addr %0d (expected 61439)", scaler_addr);
            errors = errors + 1;
        end

        // VGA pixel (63, 0) -> outside NES area (left border)
        pixel_x = 63; pixel_y = 0; #1;
        if (in_nes_area !== 0) begin
            $display("  ERROR: VGA(63,0) should be outside NES area");
            errors = errors + 1;
        end

        // VGA pixel (576, 0) -> outside NES area (right border)
        pixel_x = 576; pixel_y = 0; #1;
        if (in_nes_area !== 0) begin
            $display("  ERROR: VGA(576,0) should be outside NES area");
            errors = errors + 1;
        end

        $display("  Scaler mapping OK");

        // ==========================================================
        // Test 3: Palette LUT spot checks
        // ==========================================================
        $display("Test 3: Palette LUT");

        // $0D = black
        pal_index = 6'h0D; #1;
        if ({pal_r, pal_g, pal_b} !== 12'h000) begin
            $display("  ERROR: palette $0D expected 000, got %03x",
                     {pal_r, pal_g, pal_b});
            errors = errors + 1;
        end

        // $20 = white
        pal_index = 6'h20; #1;
        if ({pal_r, pal_g, pal_b} !== 12'hFFF) begin
            $display("  ERROR: palette $20 expected FFF, got %03x",
                     {pal_r, pal_g, pal_b});
            errors = errors + 1;
        end

        // $30 = white
        pal_index = 6'h30; #1;
        if ({pal_r, pal_g, pal_b} !== 12'hFFF) begin
            $display("  ERROR: palette $30 expected FFF, got %03x",
                     {pal_r, pal_g, pal_b});
            errors = errors + 1;
        end

        // Verify all 64 entries produce non-X output
        for (i = 0; i < 64; i = i + 1) begin
            pal_index = i; #1;
            if (pal_r === 4'bxxxx || pal_g === 4'bxxxx || pal_b === 4'bxxxx) begin
                $display("  ERROR: palette index %0d produces X", i);
                errors = errors + 1;
            end
        end

        $display("  Palette LUT OK");

        // ==========================================================
        // Summary
        // ==========================================================
        $display("");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

    // Timeout
    initial begin
        #10_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
