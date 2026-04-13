`timescale 1ns / 1ps

// Testbench for PPU background rendering pipeline
// Instantiates full PPU + memories, runs for 1 frame,
// checks key pixel values against expected results

module tb_ppu_bg;

    reg clk = 0;
    reg rst = 1;

    // ~5.369 MHz PPU clock
    always #93 clk = ~clk;

    // PPU configuration
    wire        bg_pattern_base = 0; // pattern table 0
    wire        show_bg         = 1;
    wire [14:0] t_reg           = 15'd0; // no scroll
    wire [2:0]  fine_x          = 3'd0;

    // PPU <-> VRAM bus
    wire [13:0] ppu_vram_addr;
    wire [7:0]  ppu_vram_data;

    // Framebuffer write
    wire [15:0] fb_addr;
    wire [5:0]  fb_data;
    wire        fb_we;

    // Status
    wire        vblank_flag;
    wire [8:0]  dbg_scanline, dbg_cycle;
    wire [14:0] dbg_v;

    // =========================================================
    // PPU core
    // =========================================================
    ppu_top u_ppu (
        .clk             (clk),
        .rst             (rst),
        .bg_pattern_base (bg_pattern_base),
        .show_bg         (show_bg),
        .t_reg           (t_reg),
        .fine_x          (fine_x),
        .vram_addr       (ppu_vram_addr),
        .vram_data       (ppu_vram_data),
        .fb_addr         (fb_addr),
        .fb_data         (fb_data),
        .fb_we           (fb_we),
        .vblank_flag     (vblank_flag),
        .dbg_scanline    (dbg_scanline),
        .dbg_cycle       (dbg_cycle),
        .dbg_v           (dbg_v)
    );

    // =========================================================
    // CHR ROM
    // =========================================================
    wire [7:0] chr_data;
    chr_rom u_chr (
        .clk  (clk),
        .addr (ppu_vram_addr[12:0]),
        .data (chr_data)
    );

    // =========================================================
    // Nametable VRAM (vertical mirroring)
    // =========================================================
    wire [10:0] nt_phys_addr = {ppu_vram_addr[10], ppu_vram_addr[9:0]};
    wire [7:0]  nt_data;

    vram u_vram (
        .clk  (clk),
        .we   (1'b0),
        .addr (nt_phys_addr),
        .din  (8'd0),
        .dout (nt_data)
    );

    // Data mux with 1-cycle delay for select
    wire chr_select = ~ppu_vram_addr[13];
    reg  chr_sel_d;
    always @(posedge clk) chr_sel_d <= chr_select;

    assign ppu_vram_data = chr_sel_d ? chr_data : nt_data;

    // =========================================================
    // Framebuffer capture (for verification)
    // =========================================================
    reg [5:0] fb_mem [0:61439];

    integer fb_writes;
    initial fb_writes = 0;

    always @(posedge clk) begin
        if (fb_we && fb_addr < 61440) begin
            fb_mem[fb_addr] <= fb_data;
            fb_writes = fb_writes + 1;
        end
    end

    // =========================================================
    // Test
    // =========================================================
    integer errors;
    integer i;
    reg [5:0] expected_color;

    // Helper: get expected NES color for a pixel
    // Tile at nametable position (tx, ty) = (ty * 32 + tx) & 0xFF
    // Each tile row = tile_index (low plane), high plane = 0
    // So pixel (px within tile, py within tile):
    //   pattern_bit = tile_index[7 - px]  (MSB first)
    //   If pattern_bit = 1: color = palette[palette_num * 4 + 1]
    //   If pattern_bit = 0: color = palette[0] = $0F (black)

    initial begin
        $dumpfile("tb_ppu_bg.vcd");
        $dumpvars(0, tb_ppu_bg);

        errors = 0;
        for (i = 0; i < 61440; i = i + 1)
            fb_mem[i] = 6'h3F; // sentinel

        // Release reset
        repeat (5) @(posedge clk);
        rst = 0;

        // Wait for vblank (end of first rendered frame)
        $display("Waiting for first frame...");
        wait (vblank_flag == 1);
        // Wait a few more cycles for last fb writes to complete
        repeat (100) @(posedge clk);

        $display("Frame complete. FB writes: %0d (expected 61440)", fb_writes);

        // ==========================================================
        // Test 1: Check total framebuffer writes
        // ==========================================================
        if (fb_writes < 61400) begin
            $display("ERROR: Too few framebuffer writes!");
            errors = errors + 1;
        end else begin
            $display("Test 1: FB write count OK");
        end

        // ==========================================================
        // Test 2: Check pixel at (0,0) - tile 0, all transparent
        // Tile 0 pattern: all rows = 0x00 (transparent)
        // Expected: universal background = palette[0] = $0F
        // ==========================================================
        $display("Test 2: Pixel (0,0)");
        if (fb_mem[0] !== 6'h0F) begin
            $display("  ERROR: pixel(0,0) = $%02x, expected $0F", fb_mem[0]);
            errors = errors + 1;
        end else begin
            $display("  OK: pixel(0,0) = $0F (black/background)");
        end

        // ==========================================================
        // Test 3: Check pixel at (0,8) - tile 1, row 0
        // Tile at NT pos (0,1) = tile index 32 (sequential: row*32+col)
        // Wait, NT is filled sequentially: mem[i] = i & 0xFF
        // Position (col=0, row=1) in nametable = index 32, tile = 32
        // Tile 32 pattern: all rows = 0x20 = 00100000
        // Pixel (0,8): tile col=0, tile row=1
        //   This is actually tile at (0,1) = nametable[32] = 32
        //   Pixel X=0 within tile: bit 7 of 0x20 = 0 -> transparent -> $0F
        // ==========================================================
        // Let me check a pixel where the pattern is non-zero
        // Tile at (0,0) = nametable[0] = tile 0, pattern = 0x00 -> all transparent
        // Tile at (1,0) = nametable[1] = tile 1, pattern = 0x01
        //   Pixel (8,0) = first pixel of tile 1, bit 7 of 0x01 = 0 -> transparent
        //   Pixel (15,0) = last pixel of tile 1, bit 0 of 0x01 = 1 -> color 1
        // ==========================================================
        $display("Test 3: Pixel (15,0) - tile 1, rightmost pixel");
        // Tile 1 pattern = 0x01 = 00000001, bit 0 = 1
        // This is in palette 0 region (top-left quadrant)
        // Color 1 of palette 0 = palette[1] = $20 (white)
        if (fb_mem[15] !== 6'h20) begin
            $display("  ERROR: pixel(15,0) = $%02x, expected $20", fb_mem[15]);
            errors = errors + 1;
        end else begin
            $display("  OK: pixel(15,0) = $20 (white)");
        end

        // ==========================================================
        // Test 4: Pixel (8,0) - tile 1, leftmost pixel (should be transparent)
        // Tile 1 pattern = 0x01, bit 7 = 0 -> transparent -> $0F
        // ==========================================================
        $display("Test 4: Pixel (8,0) - tile 1, leftmost pixel");
        if (fb_mem[8] !== 6'h0F) begin
            $display("  ERROR: pixel(8,0) = $%02x, expected $0F", fb_mem[8]);
            errors = errors + 1;
        end else begin
            $display("  OK: pixel(8,0) = $0F (transparent/black)");
        end

        // ==========================================================
        // Test 5: Check a pixel in palette 1 region (top-right)
        // Attribute table: x>=4 (tile columns 16-31) && y<4 -> palette 1
        // Tile at (16, 0) = nametable[16] = tile 16 = 0x10
        // Pattern 0x10 = 00010000, bit 7..0
        // Pixel at X=131 (tile 16, pixel 3 within tile): bit 4 of 0x10 = 1
        // Wait: pixel X = 16*8 + 3 = 131. Bit (7-3) = bit 4 of 0x10 = 1
        // Color 1 of palette 1 = palette[5] = $1A (green)
        // ==========================================================
        $display("Test 5: Pixel (131,0) - palette 1 region");
        if (fb_mem[131] !== 6'h1A) begin
            $display("  ERROR: pixel(131,0) = $%02x, expected $1A", fb_mem[131]);
            errors = errors + 1;
        end else begin
            $display("  OK: pixel(131,0) = $1A (green)");
        end

        // ==========================================================
        // Test 6: Check a pixel in palette 2 region (bottom-left)
        // Attribute: x<4 && y>=4 -> palette 2 (tile rows 16-29)
        // Scanline 128 = tile row 16, tile at (0,16) = nametable[512] = 0
        // Tile 0 = all transparent. Check tile at (1,16) = nametable[513] = 1
        // Pixel (15, 128): tile 1, bit 0 = 1, palette 2
        // Color 1 of palette 2 = palette[9] = $14 (purple)
        // FB addr = 128*256 + 15 = 32783
        // ==========================================================
        $display("Test 6: Pixel (15,128) - palette 2 region");
        if (fb_mem[32783] !== 6'h14) begin
            $display("  ERROR: pixel(15,128) = $%02x, expected $14", fb_mem[32783]);
            errors = errors + 1;
        end else begin
            $display("  OK: pixel(15,128) = $14 (purple)");
        end

        // ==========================================================
        // Test 7: Check all-transparent tile is fully background color
        // Tile 0 (position 0,0): all 8x8 pixels should be $0F
        // ==========================================================
        $display("Test 7: Tile 0 all transparent");
        begin : tile0_check
            integer px, py;
            reg fail;
            fail = 0;
            for (py = 0; py < 8; py = py + 1) begin
                for (px = 0; px < 8; px = px + 1) begin
                    if (fb_mem[py * 256 + px] !== 6'h0F) begin
                        if (!fail)
                            $display("  ERROR: pixel(%0d,%0d) = $%02x, expected $0F",
                                     px, py, fb_mem[py * 256 + px]);
                        fail = 1;
                    end
                end
            end
            if (fail) errors = errors + 1;
            else $display("  OK: all 64 pixels of tile 0 are $0F");
        end

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

    // Timeout (2 frames worth at ~186ns per cycle)
    initial begin
        #40_000_000_000; // 40 ms
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
