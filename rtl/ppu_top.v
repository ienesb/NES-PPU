`timescale 1ns / 1ps

// PPU Top-Level Module - Phase 6
// Integrates: timing engine, BG renderer, sprite eval/render, palette, output mux

module ppu_top (
    input  wire        clk,
    input  wire        rst,

    // Configuration (will come from CPU registers in Phase 7)
    input  wire        bg_pattern_base,     // PPUCTRL bit 4: 0=$0000, 1=$1000
    input  wire        sprite_pattern_base, // PPUCTRL bit 3 (8x8 mode)
    input  wire        sprite_size,         // PPUCTRL bit 5: 0=8x8, 1=8x16
    input  wire        show_bg,             // PPUMASK bit 3
    input  wire        show_sprite,         // PPUMASK bit 4
    input  wire [14:0] t_reg,               // scroll target register
    input  wire [2:0]  fine_x,              // fine X scroll

    // VRAM interface (shared bus, muxed between BG and sprite)
    output wire [13:0] vram_addr,
    input  wire [7:0]  vram_data,

    // Primary OAM read (from ppu_oam, async)
    output wire [7:0]  oam_addr,
    input  wire [7:0]  oam_data,

    // Framebuffer write interface
    output reg  [15:0] fb_addr,
    output reg  [5:0]  fb_data,
    output reg         fb_we,

    // Status
    output wire        vblank_flag,
    output wire        sprite0_hit,
    output wire        sprite_overflow,
    output wire [8:0]  dbg_scanline,
    output wire [8:0]  dbg_cycle,
    output wire [14:0] dbg_v
);

    // =================================================================
    // Timing engine
    // =================================================================
    wire [8:0] cycle, scanline;
    wire visible_line, pre_render_line, render_line, vblank_line;
    wire visible_pixel, sprite_fetch, tile_prefetch, fetch_active;
    wire vblank_set, vblank_clr, frame_end;
    wire odd_frame;

    wire rendering_en = show_bg || show_sprite;

    ppu_timing u_timing (
        .clk            (clk),
        .rst            (rst),
        .rendering_en   (rendering_en),
        .cycle          (cycle),
        .scanline       (scanline),
        .visible_line   (visible_line),
        .pre_render_line(pre_render_line),
        .render_line    (render_line),
        .vblank_line    (vblank_line),
        .visible_pixel  (visible_pixel),
        .sprite_fetch   (sprite_fetch),
        .tile_prefetch  (tile_prefetch),
        .fetch_active   (fetch_active),
        .vblank_set     (vblank_set),
        .vblank_clr     (vblank_clr),
        .frame_end      (frame_end),
        .odd_frame      (odd_frame)
    );

    // =================================================================
    // Vblank flag
    // =================================================================
    reg vblank_reg;
    assign vblank_flag = vblank_reg;

    always @(posedge clk) begin
        if (rst)
            vblank_reg <= 0;
        else if (vblank_set)
            vblank_reg <= 1;
        else if (vblank_clr)
            vblank_reg <= 0;
    end

    // =================================================================
    // Background renderer
    // =================================================================
    wire [3:0]  bg_pixel;
    wire [14:0] v_out;
    wire [13:0] bg_vram_addr;

    ppu_bg u_bg (
        .clk             (clk),
        .rst             (rst),
        .cycle           (cycle),
        .scanline        (scanline),
        .visible_line    (visible_line),
        .pre_render_line (pre_render_line),
        .render_line     (render_line),
        .rendering_en    (show_bg),
        .bg_pattern_base (bg_pattern_base),
        .t_reg           (t_reg),
        .fine_x          (fine_x),
        .vram_addr       (bg_vram_addr),
        .vram_data       (vram_data),
        .bg_pixel        (bg_pixel),
        .v_out           (v_out)
    );

    // =================================================================
    // Sprite evaluation and rendering
    // =================================================================
    wire [3:0]  sprite_pixel_raw;
    wire        sprite_priority_raw;
    wire        sprite_active_raw;
    wire        sprite0_active_raw;
    wire [13:0] sp_vram_addr;
    wire        sp_vram_fetch_active;

    ppu_sprite u_sprite (
        .clk                (clk),
        .rst                (rst),
        .cycle              (cycle),
        .scanline           (scanline),
        .rendering_en       (rendering_en),
        .sprite_size        (sprite_size),
        .sprite_pattern_base(sprite_pattern_base),
        .oam_addr           (oam_addr),
        .oam_data           (oam_data),
        .vram_addr          (sp_vram_addr),
        .vram_fetch_active  (sp_vram_fetch_active),
        .vram_data          (vram_data),
        .sprite_pixel       (sprite_pixel_raw),
        .sprite_priority    (sprite_priority_raw),
        .sprite_active      (sprite_active_raw),
        .sprite0_active     (sprite0_active_raw),
        .sprite_overflow    (sprite_overflow)
    );

    // VRAM bus: sprite owns during cycles 257-320, BG owns otherwise
    assign vram_addr = sp_vram_fetch_active ? sp_vram_addr : bg_vram_addr;

    // =================================================================
    // Output multiplexer: BG vs sprite priority
    // =================================================================
    wire [3:0] final_pixel;
    wire       final_is_sprite;

    ppu_mux u_mux (
        .bg_pixel       (bg_pixel),
        .sprite_pixel   (sprite_pixel_raw),
        .sprite_active  (sprite_active_raw),
        .sprite_priority(sprite_priority_raw),
        .sprite0_active (sprite0_active_raw),
        .show_bg        (show_bg),
        .show_sprite    (show_sprite),
        .final_pixel    (final_pixel),
        .final_is_sprite(final_is_sprite),
        .sprite0_hit    (sprite0_hit)
    );

    // =================================================================
    // Palette lookup
    // =================================================================
    // Address: {is_sprite, palette_num[1:0], pattern[1:0]}
    // Transparent pixels (pattern==00) -> universal BG ($3F00 = addr 0)
    wire [4:0] palette_addr = (final_pixel[1:0] == 2'b00)
                              ? 5'd0
                              : {final_is_sprite, final_pixel};

    wire [5:0] palette_color;

    ppu_palette u_palette (
        .clk  (clk),
        .we   (1'b0),
        .addr (palette_addr),
        .din  (6'd0),
        .dout (palette_color)
    );

    // =================================================================
    // Framebuffer write
    // =================================================================
    always @(posedge clk) begin
        if (rst) begin
            fb_we   <= 0;
            fb_addr <= 0;
            fb_data <= 0;
        end else if (visible_pixel) begin
            fb_we   <= 1;
            fb_addr <= {scanline[7:0], cycle[7:0] - 8'd1}; // y*256 + (cycle-1)
            fb_data <= palette_color;
        end else begin
            fb_we <= 0;
        end
    end

    // =================================================================
    // Debug outputs
    // =================================================================
    assign dbg_scanline = scanline;
    assign dbg_cycle    = cycle;
    assign dbg_v        = v_out;

endmodule
