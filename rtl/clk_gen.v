`timescale 1ns / 1ps

// Clock Generator using Artix-7 MMCM
//
// Input:  100 MHz board oscillator
// Output: clk_vga  = 25.0 MHz   (VGA pixel clock, 0.7% under 25.175 MHz)
//         clk_ppu  = 5.369 MHz  (NES PPU clock, 0.002% error)
//
// MMCM config: D=1, M=6.000, VCO = 600 MHz
//   CLKOUT0: 600 / 111.750 = 5.3691 MHz  (PPU)
//   CLKOUT1: 600 / 24      = 25.0 MHz    (VGA)

module clk_gen (
    input  wire clk_100,     // 100 MHz input
    input  wire rst_in,      // asynchronous reset input
    output wire clk_ppu,     // ~5.369 MHz PPU clock
    output wire clk_vga,     // 25.0 MHz VGA pixel clock
    output wire locked       // MMCM locked indicator
);

    wire clkfb;              // feedback clock
    wire clk_ppu_unbuf;      // unbuffered MMCM outputs
    wire clk_vga_unbuf;

    // MMCME2_BASE: Mixed-Mode Clock Manager
    MMCME2_BASE #(
        .BANDWIDTH         ("OPTIMIZED"),
        .CLKIN1_PERIOD     (10.0),        // 100 MHz -> 10 ns period
        .DIVCLK_DIVIDE     (1),           // D = 1
        .CLKFBOUT_MULT_F   (6.000),       // M = 6.0 -> VCO = 600 MHz
        .CLKFBOUT_PHASE    (0.0),

        // CLKOUT0: PPU clock ~5.369 MHz
        .CLKOUT0_DIVIDE_F  (111.750),     // 600 / 111.75 = 5.3691 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE     (0.0),

        // CLKOUT1: VGA clock 25.0 MHz
        .CLKOUT1_DIVIDE    (24),          // 600 / 24 = 25.0 MHz
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE     (0.0),

        .REF_JITTER1       (0.010),
        .STARTUP_WAIT      ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_100),
        .RST      (rst_in),
        .PWRDWN   (1'b0),

        // Feedback
        .CLKFBOUT (clkfb),
        .CLKFBIN  (clkfb),

        // Outputs
        .CLKOUT0  (clk_ppu_unbuf),
        .CLKOUT1  (clk_vga_unbuf),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT0B (),
        .CLKOUT1B (),
        .CLKOUT2B (),
        .CLKOUT3B (),

        .LOCKED   (locked)
    );

    // Global clock buffers for clean distribution
    BUFG u_bufg_ppu (.I(clk_ppu_unbuf), .O(clk_ppu));
    BUFG u_bufg_vga (.I(clk_vga_unbuf), .O(clk_vga));

endmodule
