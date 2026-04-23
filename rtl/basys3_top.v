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
    // Fake CPU (Phase 8): hardcoded init sequence simulating $2000-$2007
    // writes, then per-vblank refresh of PPUCTRL/PPUMASK from switches.
    //
    // Init:
    //   - OAMADDR=0 then 8 sprites * 4 bytes via OAMDATA
    //   - PPUCTRL (NMI enable + pattern-table selects from switches)
    //   - PPUMASK (show bg + sprites incl. left columns)
    // After init, same vblank loop as Phase 7 so switches stay live.
    // Full 6502 is Phase 9.
    // =========================================================
    //                        V P H  S(3)   B(4)  I NN
    wire [7:0] ppuctrl_val = {1'b1, 2'b00, sw[3], sw[0], 3'b000}; // NMI enable
    //                                showS   showBG  leftS leftBG greyscale
    wire [7:0] ppumask_val = {3'b000, ~sw[2], ~sw[1], 2'b11, 1'b0};

    wire vblank_flag_ppu;

    reg       cpu_we_r;
    reg [2:0] cpu_addr_r;
    reg [7:0] cpu_din_r;
    reg [5:0] init_step;
    reg       init_done;
    reg [1:0] wr_phase;
    reg       vblank_d;
    wire      vblank_rise = vblank_flag_ppu & ~vblank_d;

    // OAM init lookup: 8 sprites = 32 bytes. ROM indexed by init_step-1.
    // Layout per sprite: {Y, tile, attr, X}
    // Tiles from gen_rom.py: 128=BLOCK, 129=DOT, 130=ARROW, 131=HEART
    reg [7:0] oam_init [0:31];
    initial begin
        // sprite 0: BLOCK, pal 0, (64, 80)
        oam_init[ 0] = 8'd80;  oam_init[ 1] = 8'd128; oam_init[ 2] = 8'h00; oam_init[ 3] = 8'd64;
        // sprite 1: DOT,   pal 1, (96, 80)
        oam_init[ 4] = 8'd80;  oam_init[ 5] = 8'd129; oam_init[ 6] = 8'h01; oam_init[ 7] = 8'd96;
        // sprite 2: ARROW, pal 2, (128, 80)
        oam_init[ 8] = 8'd80;  oam_init[ 9] = 8'd130; oam_init[10] = 8'h02; oam_init[11] = 8'd128;
        // sprite 3: HEART, pal 3, (160, 80)
        oam_init[12] = 8'd80;  oam_init[13] = 8'd131; oam_init[14] = 8'h03; oam_init[15] = 8'd160;
        // sprite 4: BLOCK flipped H, pal 3, (64, 160)
        oam_init[16] = 8'd160; oam_init[17] = 8'd128; oam_init[18] = 8'h43; oam_init[19] = 8'd64;
        // sprite 5: ARROW flipped V, pal 0, (96, 160)
        oam_init[20] = 8'd160; oam_init[21] = 8'd130; oam_init[22] = 8'h80; oam_init[23] = 8'd96;
        // sprite 6: HEART behind bg, pal 1, (128, 160)
        oam_init[24] = 8'd160; oam_init[25] = 8'd131; oam_init[26] = 8'h21; oam_init[27] = 8'd128;
        // sprite 7: DOT, pal 2, (160, 160)
        oam_init[28] = 8'd160; oam_init[29] = 8'd129; oam_init[30] = 8'h02; oam_init[31] = 8'd160;
    end

    localparam [5:0] INIT_OAMADDR  = 6'd0;                     // write OAMADDR=0
    localparam [5:0] INIT_OAM_LAST = 6'd32;                    // steps 1..32 fill OAM
    localparam [5:0] INIT_PPUCTRL  = 6'd33;
    localparam [5:0] INIT_PPUMASK  = 6'd34;
    localparam [5:0] INIT_DONE     = 6'd35;

    // OAM CPU writes are gated by ~render_line inside ppu_top, so the init
    // sequence must run during vblank (scanlines 241-260). Hold init_step=0
    // until the first vblank rising edge, then pulse through all 35 steps.
    reg init_started;

    always @(posedge clk_ppu) begin
        if (rst_ppu) begin
            cpu_we_r     <= 1'b0;
            cpu_addr_r   <= 3'h0;
            cpu_din_r    <= 8'h00;
            init_step    <= 6'd0;
            init_started <= 1'b0;
            init_done    <= 1'b0;
            wr_phase     <= 2'd0;
            vblank_d     <= 1'b0;
        end else begin
            vblank_d <= vblank_flag_ppu;
            cpu_we_r <= 1'b0;

            if (!init_done) begin
                if (!init_started) begin
                    if (vblank_rise) init_started <= 1'b1;
                end else begin
                    cpu_we_r <= 1'b1;
                    if (init_step == INIT_OAMADDR) begin
                        cpu_addr_r <= 3'h3; cpu_din_r <= 8'h00;
                    end else if (init_step <= INIT_OAM_LAST) begin
                        cpu_addr_r <= 3'h4;
                        cpu_din_r  <= oam_init[init_step - 6'd1];
                    end else if (init_step == INIT_PPUCTRL) begin
                        cpu_addr_r <= 3'h0; cpu_din_r <= ppuctrl_val;
                    end else if (init_step == INIT_PPUMASK) begin
                        cpu_addr_r <= 3'h1; cpu_din_r <= ppumask_val;
                    end

                    if (init_step == INIT_DONE - 6'd1)
                        init_done <= 1'b1;
                    init_step <= init_step + 6'd1;
                end
            end else if (vblank_rise) begin
                wr_phase <= 2'd1;
            end else if (wr_phase != 2'd0) begin
                cpu_we_r <= 1'b1;
                case (wr_phase)
                    2'd1: begin cpu_addr_r <= 3'h0; cpu_din_r <= ppuctrl_val; end
                    2'd2: begin cpu_addr_r <= 3'h1; cpu_din_r <= ppumask_val; end
                endcase
                wr_phase <= (wr_phase == 2'd2) ? 2'd0 : wr_phase + 2'd1;
            end
        end
    end

    // =========================================================
    // Primary OAM (shared between CPU writes and sprite eval)
    // =========================================================
    wire [7:0] oam_bus_addr;
    wire [7:0] oam_din_ppu;
    wire       oam_we_ppu;
    wire [7:0] oam_data;

    ppu_oam u_oam (
        .clk       (clk_ppu),
        .cpu_addr  (oam_bus_addr),
        .cpu_din   (oam_din_ppu),
        .cpu_we    (oam_we_ppu),
        .cpu_dout  (),
        .eval_addr (oam_bus_addr),
        .eval_dout (oam_data)
    );

    // =========================================================
    // PPU core
    // =========================================================
    wire [13:0] ppu_vram_addr;
    wire [7:0]  ppu_vram_data;
    wire        ppu_vram_we;
    wire [7:0]  ppu_vram_din;
    wire [15:0] ppu_fb_addr;
    wire [5:0]  ppu_fb_data;
    wire        ppu_fb_we;
    wire        ppu_nmi_n;

    ppu_top u_ppu (
        .clk          (clk_ppu),
        .rst          (rst_ppu),
        .cpu_addr     (cpu_addr_r),
        .cpu_din      (cpu_din_r),
        .cpu_dout     (),
        .cpu_re       (1'b0),
        .cpu_we       (cpu_we_r),
        .nmi_n        (ppu_nmi_n),
        .vram_addr    (ppu_vram_addr),
        .vram_din     (ppu_vram_din),
        .vram_dout    (ppu_vram_data),
        .vram_we      (ppu_vram_we),
        .oam_addr     (oam_bus_addr),
        .oam_dout_ext (oam_data),
        .oam_din_ext  (oam_din_ppu),
        .oam_we_ext   (oam_we_ppu),
        .fb_addr      (ppu_fb_addr),
        .fb_data      (ppu_fb_data),
        .fb_we        (ppu_fb_we),
        .vblank_flag  (vblank_flag_ppu),
        .sprite0_hit  (),
        .sprite_overflow (),
        .dbg_scanline (),
        .dbg_cycle    (),
        .dbg_v        ()
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
        .we   (ppu_vram_we & ~chr_select),
        .addr (nt_phys_addr),
        .din  (ppu_vram_din),
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
