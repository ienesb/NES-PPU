`timescale 1ns / 1ps

// Basys 3 Top-Level Module - Phase 2
// MMCM clock generation: 100 MHz -> 25 MHz VGA + 5.369 MHz PPU
// VGA test pattern with PPU-clocked gradient to verify both clocks

module basys3_top (
    input  wire       clk_100,    // 100 MHz board oscillator
    input  wire       btnC,       // center button as reset
    output wire [3:0] vga_r,      // VGA red (4-bit)
    output wire [3:0] vga_g,      // VGA green (4-bit)
    output wire [3:0] vga_b,      // VGA blue (4-bit)
    output wire       hsync,      // VGA horizontal sync
    output wire       vsync,      // VGA vertical sync
    output wire [1:0] led         // LED 0: heartbeat, LED 1: MMCM locked
);

    // =========================================================
    // Clock generation (MMCM)
    // =========================================================
    wire clk_vga;                 // 25.0 MHz
    wire clk_ppu;                 // 5.369 MHz
    wire mmcm_locked;

    clk_gen u_clk_gen (
        .clk_100 (clk_100),
        .rst_in  (btnC),          // hold center button to reset MMCM
        .clk_ppu (clk_ppu),
        .clk_vga (clk_vga),
        .locked  (mmcm_locked)
    );

    // =========================================================
    // Reset synchronizer (wait for MMCM lock)
    // =========================================================
    reg [3:0] rst_vga_shift = 4'hF;
    wire rst_vga;

    always @(posedge clk_vga or negedge mmcm_locked) begin
        if (~mmcm_locked)
            rst_vga_shift <= 4'hF;
        else
            rst_vga_shift <= {rst_vga_shift[2:0], 1'b0};
    end

    assign rst_vga = rst_vga_shift[3];

    reg [3:0] rst_ppu_shift = 4'hF;
    wire rst_ppu;

    always @(posedge clk_ppu or negedge mmcm_locked) begin
        if (~mmcm_locked)
            rst_ppu_shift <= 4'hF;
        else
            rst_ppu_shift <= {rst_ppu_shift[2:0], 1'b0};
    end

    assign rst_ppu = rst_ppu_shift[3];

    // =========================================================
    // VGA timing generator (25 MHz domain)
    // =========================================================
    wire       video_active;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;

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
    // PPU-clocked frame counter (5.369 MHz domain)
    // Provides a slowly changing value to verify PPU clock works
    // =========================================================
    reg [21:0] ppu_counter = 0;

    always @(posedge clk_ppu) begin
        if (rst_ppu)
            ppu_counter <= 0;
        else
            ppu_counter <= ppu_counter + 1;
    end

    // =========================================================
    // Test pattern: color bars (left half) + PPU gradient (right half)
    //
    // Left 320px: 4 color bars (80px each) verifying VGA output
    // Right 320px: gradient colored by PPU counter, verifying PPU clock
    // =========================================================
    reg [3:0] r_out, g_out, b_out;

    wire [2:0] bar_index = (pixel_x < 80)  ? 3'd0 :
                           (pixel_x < 160) ? 3'd1 :
                           (pixel_x < 240) ? 3'd2 :
                           (pixel_x < 320) ? 3'd3 :
                           (pixel_x < 400) ? 3'd4 :
                           (pixel_x < 480) ? 3'd5 :
                           (pixel_x < 560) ? 3'd6 : 3'd7;

    always @(posedge clk_vga) begin
        if (~video_active) begin
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end else if (pixel_x >= 320) begin
            // Right half: gradient that shifts color over time via PPU counter
            r_out <= pixel_x[5:2] + ppu_counter[21:18];
            g_out <= pixel_y[5:2] + ppu_counter[21:18];
            b_out <= pixel_x[5:2] ^ pixel_y[5:2];
        end else begin
            // Left half: standard color bars
            case (bar_index)
                3'd0: begin r_out <= 4'hF; g_out <= 4'hF; b_out <= 4'hF; end // White
                3'd1: begin r_out <= 4'hF; g_out <= 4'hF; b_out <= 4'h0; end // Yellow
                3'd2: begin r_out <= 4'h0; g_out <= 4'hF; b_out <= 4'hF; end // Cyan
                3'd3: begin r_out <= 4'h0; g_out <= 4'hF; b_out <= 4'h0; end // Green
                default: begin r_out <= 4'h0; g_out <= 4'h0; b_out <= 4'h0; end
            endcase
        end
    end

    assign vga_r = r_out;
    assign vga_g = g_out;
    assign vga_b = b_out;

    // =========================================================
    // Heartbeat LED (VGA domain frame counter)
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

    assign led[0] = led_state;       // heartbeat ~1 Hz
    assign led[1] = mmcm_locked;     // MMCM lock status

endmodule
