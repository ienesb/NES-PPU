`timescale 1ns / 1ps

// Basys 3 Top-Level Module - Phase 6
// PPU background + sprite rendering -> framebuffer -> VGA
// SW[0]: BG pattern table select (0=$0000, 1=$1000)
// SW[1]: hide background (active high = hide)
// SW[2]: hide sprites   (active high = hide)
// SW[3]: sprite pattern table select (0=$0000, 1=$1000)

module basys3_top (
    input  wire       clk_100,
    input  wire       btnC,
    input  wire [3:0] sw,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire       hsync,
    output wire       vsync,
    output wire [1:0] led
);

    // =========================================================
    // Clock generation
    // =========================================================
    wire clk_vga, clk_ppu, mmcm_locked;

    clk_gen u_clk_gen (
        .clk_100 (clk_100),
        .rst_in  (btnC),
        .clk_ppu (clk_ppu),
        .clk_vga (clk_vga),
        .locked  (mmcm_locked)
    );

    // =========================================================
    // Reset synchronizers
    // =========================================================
    reg [3:0] rst_vga_shift = 4'hF;
    wire rst_vga;
    always @(posedge clk_vga or negedge mmcm_locked) begin
        if (~mmcm_locked) rst_vga_shift <= 4'hF;
        else              rst_vga_shift <= {rst_vga_shift[2:0], 1'b0};
    end
    assign rst_vga = rst_vga_shift[3];

    reg [3:0] rst_ppu_shift = 4'hF;
    wire rst_ppu;
    always @(posedge clk_ppu or negedge mmcm_locked) begin
        if (~mmcm_locked) rst_ppu_shift <= 4'hF;
        else              rst_ppu_shift <= {rst_ppu_shift[2:0], 1'b0};
    end
    assign rst_ppu = rst_ppu_shift[3];

    // =========================================================
    // PPU configuration
    // =========================================================
    wire bg_pattern_base     = sw[0];
    wire show_bg             = ~sw[1];
    wire show_sprite         = ~sw[2];
    wire sprite_pattern_base = sw[3];
    wire sprite_size         = 1'b0;   // 8x8 mode on hardware until Phase 7 register interface
    wire [14:0] t_reg        = 15'd0;
    wire [2:0]  fine_x       = 3'd0;

    // =========================================================
    // Primary OAM
    // =========================================================
    wire [7:0] oam_addr;
    wire [7:0] oam_data;

    ppu_oam u_oam (
        .clk       (clk_ppu),
        .cpu_addr  (8'd0),
        .cpu_din   (8'd0),
        .cpu_we    (1'b0),
        .cpu_dout  (),
        .eval_addr (oam_addr),
        .eval_dout (oam_data)
    );

    // =========================================================
    // PPU core
    // =========================================================
    wire [13:0] ppu_vram_addr;
    wire [7:0]  ppu_vram_data;
    wire [15:0] ppu_fb_addr;
    wire [5:0]  ppu_fb_data;
    wire        ppu_fb_we;

    ppu_top u_ppu (
        .clk                (clk_ppu),
        .rst                (rst_ppu),
        .bg_pattern_base    (bg_pattern_base),
        .sprite_pattern_base(sprite_pattern_base),
        .sprite_size        (sprite_size),
        .show_bg            (show_bg),
        .show_sprite        (show_sprite),
        .t_reg              (t_reg),
        .fine_x             (fine_x),
        .vram_addr          (ppu_vram_addr),
        .vram_data          (ppu_vram_data),
        .oam_addr           (oam_addr),
        .oam_data           (oam_data),
        .fb_addr            (ppu_fb_addr),
        .fb_data            (ppu_fb_data),
        .fb_we              (ppu_fb_we),
        .vblank_flag        (),
        .sprite0_hit        (),
        .sprite_overflow    (),
        .dbg_scanline       (),
        .dbg_cycle          (),
        .dbg_v              ()
    );

    // =========================================================
    // VRAM address decoding
    // =========================================================
    wire chr_select = ~ppu_vram_addr[13];

    wire [7:0] chr_data;
    chr_rom u_chr_rom (
        .clk  (clk_ppu),
        .addr (ppu_vram_addr[12:0]),
        .data (chr_data)
    );

    wire [10:0] nt_phys_addr = {ppu_vram_addr[10], ppu_vram_addr[9:0]};
    wire [7:0]  nt_data;

    vram u_vram (
        .clk  (clk_ppu),
        .we   (1'b0),
        .addr (nt_phys_addr),
        .din  (8'd0),
        .dout (nt_data)
    );

    reg chr_sel_d;
    always @(posedge clk_ppu)
        chr_sel_d <= chr_select;

    assign ppu_vram_data = chr_sel_d ? chr_data : nt_data;

    // =========================================================
    // Framebuffer (dual-port BRAM)
    // =========================================================
    wire [5:0]  fb_color;
    wire [15:0] fb_rd_addr;

    framebuffer u_framebuffer (
        .clk_a  (clk_ppu),
        .we_a   (ppu_fb_we),
        .addr_a (ppu_fb_addr),
        .din_a  (ppu_fb_data),
        .clk_b  (clk_vga),
        .addr_b (fb_rd_addr),
        .dout_b (fb_color)
    );

    // =========================================================
    // VGA timing
    // =========================================================
    wire       video_active;
    wire [9:0] pixel_x, pixel_y;

    vga_timing u_vga_timing (
        .clk          (clk_vga),
        .rst          (rst_vga),
        .hsync        (hsync),
        .vsync        (vsync),
        .video_active (video_active),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y)
    );

    // =========================================================
    // VGA scaler
    // =========================================================
    wire in_nes_area;

    vga_scaler u_scaler (
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_active (video_active),
        .fb_addr      (fb_rd_addr),
        .in_nes_area  (in_nes_area)
    );

    // =========================================================
    // NES palette LUT
    // =========================================================
    wire [3:0] pal_r, pal_g, pal_b;

    nes_palette_lut u_pal_lut (
        .color_index (fb_color),
        .r           (pal_r),
        .g           (pal_g),
        .b           (pal_b)
    );

    // =========================================================
    // VGA output with pipeline delay
    // =========================================================
    reg in_nes_d1, in_nes_d2;
    always @(posedge clk_vga) begin
        in_nes_d1 <= in_nes_area;
        in_nes_d2 <= in_nes_d1;
    end

    reg [3:0] r_out, g_out, b_out;
    always @(posedge clk_vga) begin
        if (in_nes_d2) begin
            r_out <= pal_r;
            g_out <= pal_g;
            b_out <= pal_b;
        end else begin
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end
    end

    assign vga_r = r_out;
    assign vga_g = g_out;
    assign vga_b = b_out;

    // =========================================================
    // Heartbeat LED
    // =========================================================
    reg [4:0] frame_count = 0;
    reg       led_state   = 0;
    reg       vsync_prev  = 1;

    always @(posedge clk_vga) begin
        if (rst_vga) begin
            frame_count <= 0;
            led_state   <= 0;
            vsync_prev  <= 1;
        end else begin
            vsync_prev <= vsync;
            if (vsync_prev && ~vsync) begin
                if (frame_count == 29) begin
                    frame_count <= 0;
                    led_state   <= ~led_state;
                end else begin
                    frame_count <= frame_count + 1;
                end
            end
        end
    end

    assign led[0] = led_state;
    assign led[1] = mmcm_locked;

endmodule
