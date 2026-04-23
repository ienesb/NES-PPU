`timescale 1ns / 1ps

// PPU Top-Level Module - Phase 7
// Integrates: timing engine, register file, BG renderer, sprite eval/render,
//             palette, output mux. Exposes CPU bus at $2000-$2007.

module ppu_top (
    input  wire        clk,
    input  wire        rst,

    // CPU bus ($2000-$2007, low 3 bits)
    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_din,
    output wire [7:0]  cpu_dout,
    input  wire        cpu_re,
    input  wire        cpu_we,
    output wire        nmi_n,

    // VRAM bus (shared: BG, sprite, and CPU $2007 access)
    output wire [13:0] vram_addr,
    output wire [7:0]  vram_din,
    input  wire [7:0]  vram_dout,
    output wire        vram_we,

    // OAM bus (ppu_oam lives outside; CPU and sprite-eval access it)
    output wire [7:0]  oam_addr,       // to ppu_oam.eval_addr during render, .cpu_addr otherwise
    input  wire [7:0]  oam_dout_ext,
    output wire [7:0]  oam_din_ext,
    output wire        oam_we_ext,

    // Framebuffer write interface
    output reg  [15:0] fb_addr,
    output reg  [5:0]  fb_data,
    output reg         fb_we,

    // Status / debug
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

    // Register-driven config (declared here, sourced below)
    wire ctrl_bg_pat_base, ctrl_sprite_pat_base, ctrl_sprite_size;
    wire mask_show_bg, mask_show_sprite;
    wire rendering_en = mask_show_bg | mask_show_sprite;

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
    // Register file
    // =================================================================
    wire [14:0] v_reg, t_reg;
    wire [2:0]  fine_x;
    wire        inc_x_tick, inc_y_tick, h_copy_tick, v_copy_tick;

    wire [7:0]  reg_oam_addr;
    wire [7:0]  reg_oam_din;
    wire        reg_oam_we;

    wire [13:0] reg_bus_addr;
    wire [7:0]  reg_bus_din;
    wire        reg_bus_we;

    wire        pal_we_reg;
    wire [4:0]  pal_addr_reg;
    wire [5:0]  pal_din_reg;
    wire [5:0]  pal_dout_read;

    ppu_registers u_regs (
        .clk                (clk),
        .rst                (rst),
        .cpu_addr           (cpu_addr),
        .cpu_din            (cpu_din),
        .cpu_dout           (cpu_dout),
        .cpu_re             (cpu_re),
        .cpu_we             (cpu_we),
        .inc_x_tick         (inc_x_tick),
        .inc_y_tick         (inc_y_tick),
        .h_copy_tick        (h_copy_tick),
        .v_copy_tick        (v_copy_tick),
        .vblank_set         (vblank_set),
        .vblank_clr_pulse   (vblank_clr),
        .sprite0_hit_in     (sprite0_hit),
        .sprite_overflow_in (sprite_overflow),
        .ctrl_nmi_enable    (),
        .ctrl_sprite_size   (ctrl_sprite_size),
        .ctrl_sprite_pat_base(ctrl_sprite_pat_base),
        .ctrl_bg_pat_base   (ctrl_bg_pat_base),
        .ctrl_vram_inc32    (),
        .mask_show_bg       (mask_show_bg),
        .mask_show_sprite   (mask_show_sprite),
        .mask_show_bg_left  (),
        .mask_show_sprite_left(),
        .v_reg              (v_reg),
        .t_reg              (t_reg),
        .fine_x             (fine_x),
        .nmi_n              (nmi_n),
        .oam_addr           (reg_oam_addr),
        .oam_din            (reg_oam_din),
        .oam_we             (reg_oam_we),
        .oam_dout           (oam_dout_ext),
        .ppu_bus_addr       (reg_bus_addr),
        .ppu_bus_din        (reg_bus_din),
        .ppu_bus_dout       (vram_dout),
        .ppu_bus_we         (reg_bus_we),
        .pal_we             (pal_we_reg),
        .pal_addr           (pal_addr_reg),
        .pal_din            (pal_din_reg),
        .pal_dout           (pal_dout_read)
    );

    // Vblank flag exposed for legacy consumers (mirror of register bit)
    reg vblank_flag_r;
    assign vblank_flag = vblank_flag_r;
    always @(posedge clk) begin
        if (rst)                   vblank_flag_r <= 1'b0;
        else if (vblank_set)       vblank_flag_r <= 1'b1;
        else if (vblank_clr)       vblank_flag_r <= 1'b0;
    end

    // =================================================================
    // Background renderer
    // =================================================================
    wire [3:0]  bg_pixel;
    wire [13:0] bg_vram_addr;

    ppu_bg u_bg (
        .clk             (clk),
        .rst             (rst),
        .cycle           (cycle),
        .scanline        (scanline),
        .visible_line    (visible_line),
        .pre_render_line (pre_render_line),
        .render_line     (render_line),
        .rendering_en    (rendering_en),
        .bg_pattern_base (ctrl_bg_pat_base),
        .v               (v_reg),
        .fine_x          (fine_x),
        .vram_addr       (bg_vram_addr),
        .vram_data       (vram_dout),
        .bg_pixel        (bg_pixel),
        .inc_x_tick      (inc_x_tick),
        .inc_y_tick      (inc_y_tick),
        .h_copy_tick     (h_copy_tick),
        .v_copy_tick     (v_copy_tick)
    );

    // =================================================================
    // Sprite evaluation and rendering
    // =================================================================
    wire [3:0]  sprite_pixel_raw;
    wire        sprite_priority_raw;
    wire        sprite_active_raw;
    wire        sprite0_active_raw;
    wire [7:0]  sp_oam_addr;
    wire [13:0] sp_vram_addr;
    wire        sp_vram_fetch_active;

    ppu_sprite u_sprite (
        .clk                (clk),
        .rst                (rst),
        .cycle              (cycle),
        .scanline           (scanline),
        .rendering_en       (rendering_en),
        .sprite_size        (ctrl_sprite_size),
        .sprite_pattern_base(ctrl_sprite_pat_base),
        .oam_addr           (sp_oam_addr),
        .oam_data           (oam_dout_ext),
        .vram_addr          (sp_vram_addr),
        .vram_fetch_active  (sp_vram_fetch_active),
        .vram_data          (vram_dout),
        .sprite_pixel       (sprite_pixel_raw),
        .sprite_priority    (sprite_priority_raw),
        .sprite_active      (sprite_active_raw),
        .sprite0_active     (sprite0_active_raw),
        .sprite_overflow    (sprite_overflow)
    );

    // VRAM bus arbitration: during render line the PPU pipeline owns the
    // bus. In vblank/idle the CPU register file drives $2007 traffic.
    wire ppu_bus_active = render_line;
    assign vram_addr = ppu_bus_active ? (sp_vram_fetch_active ? sp_vram_addr
                                                              : bg_vram_addr)
                                      : reg_bus_addr;
    assign vram_din  = reg_bus_din;
    assign vram_we   = ~ppu_bus_active & reg_bus_we;

    // OAM bus: sprite eval drives during render, CPU register file otherwise
    assign oam_addr    = ppu_bus_active ? sp_oam_addr : reg_oam_addr;
    assign oam_din_ext = reg_oam_din;
    assign oam_we_ext  = ~ppu_bus_active & reg_oam_we;

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
        .show_bg        (mask_show_bg),
        .show_sprite    (mask_show_sprite),
        .final_pixel    (final_pixel),
        .final_is_sprite(final_is_sprite),
        .sprite0_hit    (sprite0_hit)
    );

    // =================================================================
    // Palette lookup (render read-port + CPU write-port share module)
    // =================================================================
    wire [4:0] palette_addr = (final_pixel[1:0] == 2'b00)
                              ? 5'd0
                              : {final_is_sprite, final_pixel};
    wire [5:0] palette_color;

    ppu_palette u_palette (
        .clk      (clk),
        .addr     (palette_addr),
        .dout     (palette_color),
        .cpu_we   (pal_we_reg),
        .cpu_addr (pal_addr_reg),
        .cpu_din  (pal_din_reg),
        .cpu_dout (pal_dout_read)
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
            fb_addr <= {scanline[7:0], cycle[7:0] - 8'd1};
            fb_data <= palette_color;
        end else begin
            fb_we <= 0;
        end
    end

    // =================================================================
    // Debug
    // =================================================================
    assign dbg_scanline = scanline;
    assign dbg_cycle    = cycle;
    assign dbg_v        = v_reg;

endmodule
