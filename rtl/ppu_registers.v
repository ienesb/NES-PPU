`timescale 1ns / 1ps

// PPU Register Interface - Phase 7
//
// Implements the 8 memory-mapped registers at $2000-$2007 and the
// internal v/t/x/w scroll/address state machine.
//
//   $2000 PPUCTRL   (W): NMI, sprite size, bg/sprite pattern base, VRAM inc, base NT
//   $2001 PPUMASK   (W): show bg/sprite (+ left-8 columns), greyscale, emphasis
//   $2002 PPUSTATUS (R): vblank, sprite0 hit, overflow; reading clears vblank and w
//   $2003 OAMADDR   (W): OAM byte pointer
//   $2004 OAMDATA   (R/W): access OAM at oam_addr; write increments oam_addr
//   $2005 PPUSCROLL (W x2): first -> coarseX + fineX ; second -> coarseY + fineY
//   $2006 PPUADDR   (W x2): first -> t[13:8] (bit14 cleared) ; second -> t[7:0], v<=t
//   $2007 PPUDATA   (R/W): VRAM access through v; read-buffered except palette;
//                          v auto-increments by 1 or 32 per access
//
// The scroll register `v` is also used by the background fetch pipeline;
// ppu_bg drives v increments via {inc_x_tick, inc_y_tick, h_copy_tick, v_copy_tick}.
// During rendering, CPU $2007 accesses collide with the fetch pipeline; software
// is expected to write $2007 only during vblank or with rendering disabled.

module ppu_registers (
    input  wire        clk,
    input  wire        rst,

    // CPU bus (low 3 bits of $2000-$2007)
    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_din,
    output reg  [7:0]  cpu_dout,
    input  wire        cpu_re,
    input  wire        cpu_we,

    // Timing ticks from ppu_bg / ppu_timing (1-cycle pulses)
    input  wire        inc_x_tick,   // coarse X increment
    input  wire        inc_y_tick,   // fine/coarse Y increment (cycle 256)
    input  wire        h_copy_tick,  // copy horiz bits t->v (cycle 257)
    input  wire        v_copy_tick,  // copy vert bits  t->v (pre-render 280-304)

    // Status inputs from PPU core
    input  wire        vblank_set,       // pulse: enter vblank
    input  wire        vblank_clr_pulse, // pulse: exit vblank (pre-render cycle 1)
    input  wire        sprite0_hit_in,   // mux output (asserted during render)
    input  wire        sprite_overflow_in,

    // Register outputs used by the rest of the PPU
    output wire        ctrl_nmi_enable,
    output wire        ctrl_sprite_size,
    output wire        ctrl_sprite_pat_base,
    output wire        ctrl_bg_pat_base,
    output wire        ctrl_vram_inc32,   // 0: +1 (across),  1: +32 (down)
    output wire        mask_show_bg,
    output wire        mask_show_sprite,
    output wire        mask_show_bg_left,
    output wire        mask_show_sprite_left,

    output wire [14:0] v_reg,
    output wire [14:0] t_reg,
    output wire [2:0]  fine_x,

    // NMI output (active-low pulse; held low while vblank && NMI enabled)
    output wire        nmi_n,

    // OAM bus (to ppu_oam)
    output wire [7:0]  oam_addr,
    output wire [7:0]  oam_din,
    output wire        oam_we,
    input  wire [7:0]  oam_dout,

    // PPU data bus for $2007 access (to vram / chr_rom)
    output wire [13:0] ppu_bus_addr,
    output wire [7:0]  ppu_bus_din,
    input  wire [7:0]  ppu_bus_dout,
    output wire        ppu_bus_we,

    // Palette RAM write port (for $3F00-$3FFF)
    output wire        pal_we,
    output wire [4:0]  pal_addr,
    output wire [5:0]  pal_din,
    input  wire [5:0]  pal_dout
);


    // =========================================================
    // PPUCTRL ($2000)
    // =========================================================
    reg [7:0] ppuctrl;
    assign ctrl_nmi_enable      = ppuctrl[7];
    assign ctrl_sprite_size     = ppuctrl[5];
    assign ctrl_bg_pat_base     = ppuctrl[4];
    assign ctrl_sprite_pat_base = ppuctrl[3];
    assign ctrl_vram_inc32      = ppuctrl[2];

    // =========================================================
    // PPUMASK ($2001)
    // =========================================================
    reg [7:0] ppumask;
    assign mask_show_sprite_left = ppumask[2];
    assign mask_show_bg_left     = ppumask[1];
    assign mask_show_bg          = ppumask[3];
    assign mask_show_sprite      = ppumask[4];

    // =========================================================
    // PPUSTATUS ($2002)
    // =========================================================
    reg vblank_reg;
    reg sprite0_reg;
    reg overflow_reg;

    // Sticky sprite-0 hit: set during render, cleared at pre-render
    always @(posedge clk) begin
        if (rst) sprite0_reg <= 1'b0;
        else if (sprite0_hit_in) sprite0_reg <= 1'b1;
        else if (vblank_clr_pulse) sprite0_reg <= 1'b0;
    end
    always @(posedge clk) begin
        if (rst) overflow_reg <= 1'b0;
        else if (sprite_overflow_in) overflow_reg <= 1'b1;
        else if (vblank_clr_pulse) overflow_reg <= 1'b0;
    end

    // =========================================================
    // Internal v / t / x / w scroll state
    // =========================================================
    reg [14:0] v;
    reg [14:0] t;
    reg [2:0]  x;
    reg        w;

    assign v_reg  = v;
    assign t_reg  = t;
    assign fine_x = x;

    // Palette address is always driven from v[4:0] so CPU $2007 reads see
    // the entry selected by the current VRAM pointer.
    assign pal_addr = v[4:0];

    // OAMADDR register (registered)
    reg [7:0] oam_addr_r;
    assign oam_addr = oam_addr_r;

    // =========================================================
    // Combinational CPU access decoding
    // Strobes fire on the same posedge cpu_we is sampled, ensuring
    // downstream modules see the matching address pre-increment.
    // =========================================================
    wire v_is_palette_now = (v[13:8] == 6'h3F);
    wire cpu_w_2007 = cpu_we && (cpu_addr == 3'h7);
    wire cpu_w_2004 = cpu_we && (cpu_addr == 3'h4);

    assign pal_we       = cpu_w_2007 &&  v_is_palette_now;
    assign pal_din      = cpu_din[5:0];
    assign ppu_bus_we   = cpu_w_2007 && ~v_is_palette_now;
    assign ppu_bus_addr = v[13:0];
    assign ppu_bus_din  = cpu_din;
    assign oam_we       = cpu_w_2004;
    assign oam_din      = cpu_din;

    // =========================================================
    // $2007 read buffer
    // =========================================================
    reg [7:0] read_buffer;

    // Decoded v region for $2007 access
    wire       v_is_palette = (v[13:8] == 6'h3F);
    wire [4:0] v_pal_addr   = v[4:0];
    wire [13:0] v_bus_addr  = v[13:0];

    // =========================================================
    // NMI generation
    // nmi_n is low while vblank flag is 1 and NMI enable is 1
    // =========================================================
    assign nmi_n = ~(vblank_reg & ctrl_nmi_enable);

    // =========================================================
    // Main register write/read logic
    // =========================================================
    reg vblank_clear_by_read;

    always @(posedge clk) begin
        if (rst) begin
            ppuctrl      <= 8'd0;
            ppumask      <= 8'd0;
            vblank_reg   <= 1'b0;
            v            <= 15'd0;
            t            <= 15'd0;
            x            <= 3'd0;
            w            <= 1'b0;
            read_buffer  <= 8'd0;
            oam_addr_r   <= 8'd0;
            cpu_dout     <= 8'd0;
        end else begin
            // ---- vblank flag bookkeeping ----
            if (vblank_set)       vblank_reg <= 1'b1;
            if (vblank_clr_pulse) vblank_reg <= 1'b0;

            // ---- CPU writes ----
            if (cpu_we) begin
                case (cpu_addr)
                    3'h0: begin // PPUCTRL
                        ppuctrl <= cpu_din;
                        t[11:10] <= cpu_din[1:0];
                    end
                    3'h1: ppumask <= cpu_din;
                    3'h3: oam_addr_r <= cpu_din;
                    3'h4: oam_addr_r <= oam_addr_r + 8'd1; // post-increment after write
                    3'h5: begin // PPUSCROLL dual-write
                        if (~w) begin
                            t[4:0] <= cpu_din[7:3];
                            x      <= cpu_din[2:0];
                            w      <= 1'b1;
                        end else begin
                            t[14:12] <= cpu_din[2:0];
                            t[9:5]   <= cpu_din[7:3];
                            w        <= 1'b0;
                        end
                    end
                    3'h6: begin // PPUADDR dual-write
                        if (~w) begin
                            t[13:8] <= cpu_din[5:0];
                            t[14]   <= 1'b0;
                            w       <= 1'b1;
                        end else begin
                            t[7:0] <= cpu_din;
                            v      <= {t[14:8], cpu_din};
                            w      <= 1'b0;
                        end
                    end
                    3'h7: v <= v + (ctrl_vram_inc32 ? 15'd32 : 15'd1);
                    default: ;
                endcase
            end

            // ---- CPU reads (combinational-style: registered one cycle later) ----
            if (cpu_re) begin
                case (cpu_addr)
                    3'h2: begin
                        cpu_dout   <= {vblank_reg, sprite0_reg, overflow_reg, 5'b0};
                        vblank_reg <= 1'b0;
                        w          <= 1'b0;
                    end
                    3'h4: cpu_dout <= oam_dout;
                    3'h7: begin
                        if (v_is_palette) begin
                            cpu_dout    <= {2'b0, pal_dout};
                            read_buffer <= ppu_bus_dout; // buffer still loads NT shadow
                        end else begin
                            cpu_dout    <= read_buffer;
                            read_buffer <= ppu_bus_dout;
                        end
                        v <= v + (ctrl_vram_inc32 ? 15'd32 : 15'd1);
                    end
                    default: cpu_dout <= 8'h00;
                endcase
            end

            // ---- Scroll/v increments from render pipeline ----
            // These run in parallel with CPU writes; CPU $2007 accesses during
            // rendering are not expected, so we don't arbitrate.
            if (inc_x_tick) begin
                if (v[4:0] == 5'd31) begin
                    v[4:0] <= 5'd0;
                    v[10]  <= ~v[10];
                end else begin
                    v[4:0] <= v[4:0] + 5'd1;
                end
            end
            if (inc_y_tick) begin
                if (v[14:12] != 3'd7) begin
                    v[14:12] <= v[14:12] + 3'd1;
                end else begin
                    v[14:12] <= 3'd0;
                    if (v[9:5] == 5'd29) begin
                        v[9:5] <= 5'd0;
                        v[11]  <= ~v[11];
                    end else if (v[9:5] == 5'd31) begin
                        v[9:5] <= 5'd0;
                    end else begin
                        v[9:5] <= v[9:5] + 5'd1;
                    end
                end
            end
            if (h_copy_tick) begin
                v[4:0] <= t[4:0];
                v[10]  <= t[10];
            end
            if (v_copy_tick) begin
                v[14:12] <= t[14:12];
                v[9:5]   <= t[9:5];
                v[11]    <= t[11];
            end
        end
    end

endmodule
