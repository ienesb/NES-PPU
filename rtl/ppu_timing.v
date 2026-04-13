`timescale 1ns / 1ps

// NES PPU Timing Engine
//
// NTSC PPU frame structure: 341 cycles x 262 scanlines
//
// Scanline regions:
//   0-239:   Visible (rendering active)
//   240:     Post-render (idle)
//   241-260: Vertical blank
//   261:     Pre-render
//
// Per-scanline cycle regions (visible/pre-render lines):
//   0:       Idle
//   1-256:   Pixel output / tile fetches
//   257-320: Sprite tile fetches
//   321-336: Next-line tile prefetch
//   337-340: Dummy nametable fetches
//
// Special events:
//   Scanline 241, cycle 1: Set vblank flag
//   Scanline 261, cycle 1: Clear vblank, sprite 0 hit, sprite overflow
//   Odd-frame skip: scanline 261 ends at cycle 339 (not 340) on odd
//                   frames when rendering is enabled

module ppu_timing (
    input  wire        clk,           // PPU clock (~5.369 MHz)
    input  wire        rst,
    input  wire        rendering_en,  // from PPUMASK (show_bg | show_spr)

    output reg  [8:0]  cycle,         // 0-340
    output reg  [8:0]  scanline,      // 0-261

    // Timing region signals
    output wire        visible_line,  // scanlines 0-239
    output wire        pre_render_line, // scanline 261
    output wire        render_line,   // visible or pre-render (fetches active)
    output wire        vblank_line,   // scanlines 241-260

    // Per-cycle signals
    output wire        visible_pixel, // visible line, cycles 1-256
    output wire        sprite_fetch,  // render line, cycles 257-320
    output wire        tile_prefetch, // render line, cycles 321-336
    output wire        fetch_active,  // any fetch cycle on render lines

    // Events (active for 1 cycle)
    output reg         vblank_set,    // pulse at scanline 241, cycle 1
    output reg         vblank_clr,    // pulse at scanline 261, cycle 1
    output wire        frame_end,     // last cycle of frame

    output reg         odd_frame      // toggles each frame
);

    // =========================================================
    // Cycle and scanline limits
    // =========================================================
    localparam CYCLES_PER_LINE  = 341;  // 0-340
    localparam SCANLINES        = 262;  // 0-261

    localparam SL_VISIBLE_END   = 239;
    localparam SL_POSTRENDER    = 240;
    localparam SL_VBLANK_START  = 241;
    localparam SL_VBLANK_END    = 260;
    localparam SL_PRERENDER     = 261;

    // =========================================================
    // Odd-frame cycle skip
    // On odd frames with rendering enabled, the pre-render line
    // is one cycle shorter (ends at 339 instead of 340)
    // =========================================================
    wire last_cycle = (scanline == SL_PRERENDER && odd_frame && rendering_en)
                      ? (cycle == CYCLES_PER_LINE - 2)   // 339
                      : (cycle == CYCLES_PER_LINE - 1);  // 340

    // =========================================================
    // Cycle counter
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
        end else if (last_cycle) begin
            cycle <= 0;
        end else begin
            cycle <= cycle + 1;
        end
    end

    // =========================================================
    // Scanline counter
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            scanline <= SL_PRERENDER; // start at pre-render
        end else if (last_cycle) begin
            if (scanline == SL_PRERENDER)
                scanline <= 0;
            else
                scanline <= scanline + 1;
        end
    end

    // =========================================================
    // Odd frame toggle
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            odd_frame <= 0;
        end else if (scanline == SL_PRERENDER && last_cycle) begin
            odd_frame <= ~odd_frame;
        end
    end

    // =========================================================
    // Region signals
    // =========================================================
    assign visible_line    = (scanline <= SL_VISIBLE_END);
    assign pre_render_line = (scanline == SL_PRERENDER);
    assign render_line     = visible_line | pre_render_line;
    assign vblank_line     = (scanline >= SL_VBLANK_START) && (scanline <= SL_VBLANK_END);

    // =========================================================
    // Per-cycle signals (only active on render lines)
    // =========================================================
    assign visible_pixel = visible_line && (cycle >= 1) && (cycle <= 256);
    assign sprite_fetch  = render_line  && (cycle >= 257) && (cycle <= 320);
    assign tile_prefetch = render_line  && (cycle >= 321) && (cycle <= 336);
    assign fetch_active  = render_line  && (((cycle >= 1) && (cycle <= 256)) ||
                                            ((cycle >= 257) && (cycle <= 336)));

    // =========================================================
    // Event pulses
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            vblank_set <= 0;
            vblank_clr <= 0;
        end else begin
            vblank_set <= (scanline == SL_VBLANK_START) && (cycle == 0);
            vblank_clr <= (scanline == SL_PRERENDER)    && (cycle == 0);
        end
    end

    assign frame_end = (scanline == SL_PRERENDER) && last_cycle;

endmodule
