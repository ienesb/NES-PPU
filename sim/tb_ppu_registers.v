`timescale 1ns / 1ps

// Testbench for Phase 7: PPU Register Interface
//
// Drives the CPU bus to exercise:
//   - PPUCTRL/PPUMASK writes (enable rendering)
//   - PPUSTATUS read clears vblank flag and w latch
//   - PPUSCROLL dual-write (w toggle) sets t/x correctly
//   - PPUADDR dual-write copies t -> v on second write
//   - PPUDATA write to palette ($3F00..) + read-back
//   - VRAM-inc-by-1 between $2007 accesses
//   - NMI fires when vblank && NMI-enable
//   - Framebuffer still renders one full frame after CPU init

module tb_ppu_registers;

    reg clk = 0;
    reg rst = 1;
    always #93 clk = ~clk;

    // CPU bus
    reg  [2:0] cpu_addr;
    reg  [7:0] cpu_din;
    wire [7:0] cpu_dout;
    reg        cpu_re;
    reg        cpu_we;
    wire       nmi_n;

    wire [13:0] vram_addr;
    wire [7:0]  vram_din;
    wire [7:0]  vram_dout;
    wire        vram_we;

    wire [7:0]  oam_bus_addr;
    wire [7:0]  oam_din_ppu;
    wire        oam_we_ppu;
    wire [7:0]  oam_data;

    wire [15:0] fb_addr;
    wire [5:0]  fb_data;
    wire        fb_we;

    wire vblank_flag;
    wire [8:0] dbg_scanline, dbg_cycle;
    wire [14:0] dbg_v;

    // OAM memory
    ppu_oam u_oam (
        .clk       (clk),
        .cpu_addr  (oam_bus_addr),
        .cpu_din   (oam_din_ppu),
        .cpu_we    (oam_we_ppu),
        .cpu_dout  (),
        .eval_addr (oam_bus_addr),
        .eval_dout (oam_data)
    );

    // PPU core
    ppu_top u_ppu (
        .clk          (clk),
        .rst          (rst),
        .cpu_addr     (cpu_addr),
        .cpu_din      (cpu_din),
        .cpu_dout     (cpu_dout),
        .cpu_re       (cpu_re),
        .cpu_we       (cpu_we),
        .nmi_n        (nmi_n),
        .vram_addr    (vram_addr),
        .vram_din     (vram_din),
        .vram_dout    (vram_dout),
        .vram_we      (vram_we),
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

    // CHR ROM
    wire [7:0] chr_data;
    chr_rom u_chr (
        .clk  (clk),
        .addr (vram_addr[12:0]),
        .data (chr_data)
    );

    // Nametable VRAM
    wire chr_select = ~vram_addr[13];
    wire [10:0] nt_phys_addr = {vram_addr[10], vram_addr[9:0]};
    wire [7:0]  nt_data;
    vram u_vram (
        .clk  (clk),
        .we   (vram_we & ~chr_select),
        .addr (nt_phys_addr),
        .din  (vram_din),
        .dout (nt_data)
    );

    reg chr_sel_d;
    always @(posedge clk) chr_sel_d <= chr_select;
    assign vram_dout = chr_sel_d ? chr_data : nt_data;

    // Frame capture
    reg [5:0] fb_mem [0:61439];
    integer   fb_writes;
    always @(posedge clk) begin
        if (fb_we && fb_addr < 61440) begin
            fb_mem[fb_addr] <= fb_data;
            fb_writes <= fb_writes + 1;
        end
    end

    // ==============================================
    // CPU task helpers
    // ==============================================
    task cpu_write(input [2:0] a, input [7:0] d);
        begin
            @(negedge clk);
            cpu_addr = a; cpu_din = d; cpu_we = 1;
            @(negedge clk);
            cpu_we = 0;
            @(negedge clk);
        end
    endtask

    task cpu_read(input [2:0] a, output [7:0] d);
        begin
            @(negedge clk);
            cpu_addr = a; cpu_re = 1;
            @(negedge clk);
            cpu_re = 0;
            @(negedge clk); // cpu_dout registered after re sampled
            d = cpu_dout;
        end
    endtask

    integer errors;
    reg [7:0] rd;

    initial begin
        $dumpfile("tb_ppu_registers.vcd");
        $dumpvars(0, tb_ppu_registers);

        errors = 0;
        fb_writes = 0;
        cpu_addr = 0; cpu_din = 0; cpu_we = 0; cpu_re = 0;

        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // ----- T1: PPUSCROLL dual-write sets t and x -----
        cpu_write(3'h5, 8'b11010_101); // first write: t[4:0]=11010=26, x=101=5
        cpu_write(3'h5, 8'b01010_110); // second:    t[9:5]=01010=10, t[14:12]=110=6
        // expected t = {110, 00, 01010, 11010} = 110_00_01010_11010 = 0xC15A
        if (u_ppu.u_regs.t !== 15'h615A) begin
            $display("ERROR T1a: t=%h expected 615A", u_ppu.u_regs.t);
            errors = errors + 1;
        end else $display("PASS  T1a: PPUSCROLL -> t = 615A");
        if (u_ppu.u_regs.x !== 3'd5) begin
            $display("ERROR T1b: x=%0d expected 5", u_ppu.u_regs.x);
            errors = errors + 1;
        end else $display("PASS  T1b: fine_x = 5");

        // ----- T2: PPUSTATUS read resets w latch -----
        cpu_write(3'h5, 8'h00); // toggles w=1
        cpu_read (3'h2, rd);    // should clear w
        if (u_ppu.u_regs.w !== 1'b0) begin
            $display("ERROR T2: w not cleared by $2002 read"); errors = errors + 1;
        end else $display("PASS  T2: PPUSTATUS read clears w");

        // ----- T3: PPUADDR dual-write copies t -> v -----
        cpu_write(3'h6, 8'h21); // hi: t[13:8]=21, bit14 cleared
        cpu_write(3'h6, 8'h08); // lo: t[7:0]=08, v<=t
        if (u_ppu.u_regs.v !== 15'h2108) begin
            $display("ERROR T3: v=%h expected 2108", u_ppu.u_regs.v);
            errors = errors + 1;
        end else $display("PASS  T3: PPUADDR -> v = 2108");

        // ----- T4: PPUDATA palette write + read-back -----
        // point v to $3F00
        cpu_write(3'h6, 8'h3F);
        cpu_write(3'h6, 8'h00);
        cpu_write(3'h7, 8'h25); // write color 0x25 to palette[0]
        cpu_write(3'h7, 8'h1A); // palette[1] = 0x1A (v auto-inc to 3F02)

        cpu_write(3'h6, 8'h3F);
        cpu_write(3'h6, 8'h00);
        cpu_read (3'h7, rd); // palette read: direct (no buffer)
        if (rd !== 8'h25) begin
            $display("ERROR T4a: palette[0] read = %h expected 25", rd);
            errors = errors + 1;
        end else $display("PASS  T4a: palette[0] = 0x25");
        cpu_read (3'h7, rd);
        if (rd !== 8'h1A) begin
            $display("ERROR T4b: palette[1] read = %h expected 1A", rd);
            errors = errors + 1;
        end else $display("PASS  T4b: palette[1] = 0x1A");

        // ----- T5: Enable rendering, wait vblank, confirm frame written -----
        // Reset w before PPUCTRL/PPUMASK writes (not strictly needed but tidy)
        cpu_read (3'h2, rd);
        cpu_write(3'h0, 8'h80); // PPUCTRL: NMI enable
        cpu_write(3'h1, 8'h18); // PPUMASK: show BG + sprites
        // Reset v/t/x to 0 so BG scroll starts at top-left
        cpu_write(3'h5, 8'h00);
        cpu_write(3'h5, 8'h00);
        cpu_write(3'h6, 8'h00);
        cpu_write(3'h6, 8'h00);

        $display("Waiting for vblank...");
        wait (vblank_flag == 1);
        repeat (100) @(posedge clk);
        $display("FB writes = %0d", fb_writes);
        if (fb_writes < 61000) begin
            $display("ERROR T5: too few FB writes (%0d)", fb_writes);
            errors = errors + 1;
        end else $display("PASS  T5: frame rendered (fb_writes=%0d)", fb_writes);

        // ----- T6: NMI asserted while vblank && NMI enabled -----
        if (nmi_n !== 1'b0) begin
            $display("ERROR T6: nmi_n=%b expected 0 during vblank", nmi_n);
            errors = errors + 1;
        end else $display("PASS  T6: NMI active low during vblank");

        // ----- T7: Reading PPUSTATUS clears vblank flag -----
        cpu_read(3'h2, rd);
        if (rd[7] !== 1'b1) begin
            $display("ERROR T7a: PPUSTATUS bit7=%b expected 1", rd[7]);
            errors = errors + 1;
        end else $display("PASS  T7a: PPUSTATUS bit7=1 during vblank");
        // After read, vblank should be cleared
        @(posedge clk); @(posedge clk);
        if (u_ppu.u_regs.vblank_reg !== 1'b0) begin
            $display("ERROR T7b: vblank flag not cleared by read");
            errors = errors + 1;
        end else $display("PASS  T7b: PPUSTATUS read clears vblank");

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d errors", errors);
        $finish;
    end

    initial begin
        #40_000_000_000;
        $display("ERROR: Timeout"); $finish;
    end

endmodule
