`timescale 1ns / 1ps

// PPU Top-Level Module
// Connects timing engine, background renderer, and palette
// Outputs: VRAM bus (to external CHR ROM / nametable), framebuffer writes

module ppu_top (
    input  wire        clk,        // PPU clock (~5.369 MHz)
    input  wire        rst,

    // Configuration (will come from CPU registers in Phase 7)
    input  wire        bg_pattern_base, // PPUCTRL bit 4: 0=$0000, 1=$1000
    input  wire        show_bg,         // PPUMASK bit 3
    input  wire [14:0] t_reg,           // scroll target register
    input  wire [2:0]  fine_x,          // fine X scroll

    // VRAM interface (active accent to external CHR ROM / nametable)
    output wire [13:0] vram_addr,
    input  wire [7:0]  vram_data,

    // Framebuffer write interface
    output reg  [15:0] fb_addr,
    output reg  [5:0]  fb_data,
    output reg         fb_we,

    // Status
    output wire        vblank_flag,
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

    wire rendering_en = show_bg; // simplified: just BG for now

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
    wire [3:0] bg_pixel;
    wire [14:0] v_out;

    ppu_bg u_bg (
        .clk             (clk),
        .rst             (rst),
        .cycle           (cycle),
        .scanline        (scanline),
        .visible_line    (visible_line),
        .pre_render_line (pre_render_line),
        .render_line     (render_line),
        .rendering_en    (rendering_en),
        .bg_pattern_base (bg_pattern_base),
        .t_reg           (t_reg),
        .fine_x          (fine_x),
        .vram_addr       (vram_addr),
        .vram_data       (vram_data),
        .bg_pixel        (bg_pixel),
        .v_out           (v_out)
    );

    // =================================================================
    // Palette lookup
    // =================================================================
    // Transparency: if pattern bits are 00, use universal background ($3F00)
    wire [4:0] palette_addr = (bg_pixel[1:0] == 2'b00)
                              ? 5'd0
                              : {1'b0, bg_pixel};

    wire [5:0] palette_color;

    ppu_palette u_palette (
        .clk  (clk),
        .we   (1'b0),        // no writes in Phase 5
        .addr (palette_addr),
        .din  (6'd0),
        .dout (palette_color)
    );

    // =================================================================
    // Framebuffer write
    // =================================================================
    // Pipeline: bg_pixel is combinational from shift registers
    //           palette lookup is combinational
    //           Register the output for clean timing

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
