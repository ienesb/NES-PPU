`timescale 1ns / 1ps

// Testbench for Phase 6: Sprite Evaluation and Rendering
// Instantiates full PPU + OAM + memories, runs one frame,
// verifies sprite compositing against BG at specific pixels.
//
// Test sprite configuration (from ppu_oam init):
//   Sprite 0: tile 1, screen Y=8-15, X=8,  palette 0, in front, no flip
//   Sprite 1: tile 2, screen Y=21-28, X=40, palette 1, H-flip, in front
//   Sprite 2: tile 3, screen Y=101-108, X=80, palette 2, BEHIND BG
//   Sprite 3: tile 4, screen Y=51-58, X=120, palette 3, V-flip, in front
//
// Key pixel expectations:
//   (8,  8): sprite 0 transparent + BG transparent -> $0F (background black)
//   (15, 8): sprite 0 color 1 in front of BG color -> $16 (red, spr pal 0)
//   (86,101): BG opaque + sprite 2 behind BG -> $20 (white, BG pal 0)

module tb_ppu_sprites;

    reg clk = 0;
    reg rst = 1;

    // ~5.369 MHz PPU clock
    always #93 clk = ~clk;

    // CPU bus for register programming
    reg  [2:0] cpu_addr = 0;
    reg  [7:0] cpu_din  = 0;
    reg        cpu_we   = 0;

    // OAM interface (shared between CPU write and sprite eval)
    wire [7:0] oam_bus_addr;
    wire [7:0] oam_din_ppu;
    wire       oam_we_ppu;
    wire [7:0] oam_data;

    // VRAM bus
    wire [13:0] ppu_vram_addr;
    wire [7:0]  ppu_vram_data;
    wire [7:0]  ppu_vram_din;
    wire        ppu_vram_we;

    wire [15:0] fb_addr;
    wire [5:0]  fb_data;
    wire        fb_we;

    wire        vblank_flag;
    wire [8:0]  dbg_scanline, dbg_cycle;
    wire [14:0] dbg_v;

    ppu_oam u_oam (
        .clk       (clk),
        .cpu_addr  (oam_bus_addr),
        .cpu_din   (oam_din_ppu),
        .cpu_we    (oam_we_ppu),
        .cpu_dout  (),
        .eval_addr (oam_bus_addr),
        .eval_dout (oam_data)
    );

    ppu_top u_ppu (
        .clk          (clk),
        .rst          (rst),
        .cpu_addr     (cpu_addr),
        .cpu_din      (cpu_din),
        .cpu_dout     (),
        .cpu_re       (1'b0),
        .cpu_we       (cpu_we),
        .nmi_n        (),
        .vram_addr    (ppu_vram_addr),
        .vram_din     (ppu_vram_din),
        .vram_dout    (ppu_vram_data),
        .vram_we      (ppu_vram_we),
        .oam_addr     (oam_bus_addr),
        .oam_dout_ext (oam_data),
        .oam_din_ext  (oam_din_ppu),
        .oam_we_ext   (oam_we_ppu),
        .fb_addr      (fb_addr),
        .fb_data      (fb_data),
        .fb_we        (fb_we),
        .vblank_flag  (vblank_flag),
        .sprite0_hit  (),
        .sprite_overflow (),
        .dbg_scanline (dbg_scanline),
        .dbg_cycle    (dbg_cycle),
        .dbg_v        (dbg_v)
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
    wire chr_select = ~ppu_vram_addr[13];
    wire [10:0] nt_phys_addr = {ppu_vram_addr[10], ppu_vram_addr[9:0]};
    wire [7:0]  nt_data;

    vram u_vram (
        .clk  (clk),
        .we   (ppu_vram_we & ~chr_select),
        .addr (nt_phys_addr),
        .din  (ppu_vram_din),
        .dout (nt_data)
    );

    // Data mux with 1-cycle delay for BRAM read latency
    reg  chr_sel_d;
    always @(posedge clk) chr_sel_d <= chr_select;
    assign ppu_vram_data = chr_sel_d ? chr_data : nt_data;

    // =========================================================
    // Framebuffer capture
    // =========================================================
    reg [5:0] fb_mem [0:61439];
    integer   fb_writes;
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

    initial begin
        $dumpfile("tb_ppu_sprites.vcd");
        $dumpvars(0, tb_ppu_sprites);

        errors = 0;
        for (i = 0; i < 61440; i = i + 1)
            fb_mem[i] = 6'h3F; // sentinel

        // Release reset
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // Program PPUMASK ($2001) = 0x18 -> show_bg + show_sprite
        @(negedge clk); cpu_addr = 3'h1; cpu_din = 8'h18; cpu_we = 1;
        @(negedge clk); cpu_we = 0;

        // Wait for vblank (end of first rendered frame)
        $display("Waiting for first frame...");
        wait (vblank_flag == 1);
        repeat (100) @(posedge clk);

        $display("Frame complete. FB writes: %0d (expected 61440)", fb_writes);

        // ======================================================
        // Test 1: Framebuffer write count
        // ======================================================
        if (fb_writes < 61400) begin
            $display("ERROR T1: Too few framebuffer writes (%0d)", fb_writes);
            errors = errors + 1;
        end else begin
            $display("PASS  T1: FB write count OK (%0d)", fb_writes);
        end

        // ======================================================
        // Test 2: Pixel (0,0) - universal background
        //   No sprite covers (0,0). BG tile 0 is all transparent.
        //   Expected: palette[0] = $0F (black)
        // ======================================================
        if (fb_mem[0] !== 6'h0F) begin
            $display("ERROR T2: pixel(0,0) = $%02x, expected $0F", fb_mem[0]);
            errors = errors + 1;
        end else begin
            $display("PASS  T2: pixel(0,0) = $0F (background)");
        end

        // ======================================================
        // Test 3: Pixel (8,8) - sprite 0 leftmost pixel
        //   Sprite 0: tile 1, row 0 = 0x01. Col 0 within tile = bit7 = 0 -> transparent.
        //   BG tile at (col=1,row=1) = tile 33 = 0x21. Pixel 0 within tile = bit7 = 0 -> transparent.
        //   Both transparent -> universal background = $0F
        // ======================================================
        // fb_addr = 8*256 + 8 = 2056
        if (fb_mem[2056] !== 6'h0F) begin
            $display("ERROR T3: pixel(8,8) = $%02x, expected $0F (spr0 transparent)", fb_mem[2056]);
            errors = errors + 1;
        end else begin
            $display("PASS  T3: pixel(8,8) = $0F (sprite 0 transparent over transparent BG)");
        end

        // ======================================================
        // Test 4: Pixel (15,8) - sprite 0 rightmost pixel in front of BG
        //   Sprite 0: tile 1, row 0 = 0x01. Col 7 = bit0 = 1 -> color 1.
        //   Sprite in front (attr[5]=0). Expected: palette[17] = $16 (red)
        //   (BG at (15,8): tile 33, bit0=1, color 1 of BG pal 0 = $20; sprite wins)
        // ======================================================
        // fb_addr = 8*256 + 15 = 2063
        if (fb_mem[2063] !== 6'h16) begin
            $display("ERROR T4: pixel(15,8) = $%02x, expected $16 (sprite 0 in front)", fb_mem[2063]);
            errors = errors + 1;
        end else begin
            $display("PASS  T4: pixel(15,8) = $16 (sprite 0 color 1 in front of BG)");
        end

        // ======================================================
        // Test 5: Pixel (86,101) - sprite 2 behind BG
        //   Sprite 2: tile 3, row 0 = 0x03. Col 6 = bit1 = 1 -> non-transparent.
        //   Sprite behind BG (attr[5]=1). BG at (86,101): tile 138 = 0x8A, col 6.
        //   bit1 of 0x8A = 1 -> BG color 1 of palette 0 = $20 (white). BG wins.
        //   Expected: $20
        // ======================================================
        // fb_addr = 101*256 + 86 = 25856 + 86 = 25942
        if (fb_mem[25942] !== 6'h20) begin
            $display("ERROR T5: pixel(86,101) = $%02x, expected $20 (BG over behind-sprite)", fb_mem[25942]);
            errors = errors + 1;
        end else begin
            $display("PASS  T5: pixel(86,101) = $20 (BG wins over sprite 2 behind)");
        end

        // ======================================================
        // Test 6: Sprite 0 covers scanlines 8-15 at col 15
        //   Tile 1: all rows = 0x01, so all 8 rows have bit0=1 at col 7.
        //   All pixels (15, 8) through (15, 15) should be $16 (sprite 0 color 1).
        // ======================================================
        begin : spr0_rows
            integer row;
            reg     fail;
            fail = 0;
            for (row = 8; row < 16; row = row + 1) begin
                if (fb_mem[row * 256 + 15] !== 6'h16) begin
                    if (!fail)
                        $display("ERROR T6: pixel(15,%0d) = $%02x, expected $16",
                                 row, fb_mem[row * 256 + 15]);
                    fail = 1;
                end
            end
            if (fail) errors = errors + 1;
            else $display("PASS  T6: sprite 0 col 7 = $16 on all scanlines 8-15");
        end

        // ======================================================
        // Test 7: No sprite above scanline 8 at col 15
        //   Sprite 0 first renders on scanline 8. At (15,7) the BG pixel
        //   should be present: tile 33 = 0x21, row 7 (scanline 7 -> tile row = 7%8=7),
        //   col 7 = bit0 = 1 -> BG color 1 of palette 0 = $20.
        // ======================================================
        // fb_addr = 7*256 + 15 = 1807
        if (fb_mem[1807] !== 6'h20) begin
            $display("ERROR T7: pixel(15,7) = $%02x, expected $20 (no sprite above row 8)",
                     fb_mem[1807]);
            errors = errors + 1;
        end else begin
            $display("PASS  T7: pixel(15,7) = $20 (BG only, sprite 0 not yet visible)");
        end

        // ======================================================
        // Summary
        // ======================================================
        $display("");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

    // Timeout (2 frames at ~186ns/cycle)
    initial begin
        #40_000_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
