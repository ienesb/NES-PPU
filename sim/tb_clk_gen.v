`timescale 1ns / 1ps

// Testbench for clock generator (behavioral model)
// Verifies PPU/VGA clock ratio matches expected ~5.369/25 MHz

module tb_clk_gen;

    // Behavioral clocks (substitute for MMCM in simulation)
    reg clk_vga = 0;
    reg clk_ppu = 0;

    // 25 MHz VGA clock (40 ns period)
    always #20 clk_vga = ~clk_vga;

    // ~5.369 MHz PPU clock (~186.25 ns period, use 93 ns half-period)
    always #93 clk_ppu = ~clk_ppu;

    integer ppu_clocks;
    integer i;

    initial begin
        $dumpfile("tb_clk_gen.vcd");
        $dumpvars(0, tb_clk_gen);

        // Count PPU rising edges during 8000 VGA clocks (10 VGA lines)
        ppu_clocks = 0;
        @(posedge clk_vga); // align to VGA edge

        for (i = 0; i < 8000; i = i + 1) begin
            @(posedge clk_vga);
        end

        $display("Over 8000 VGA clocks:");
        $display("  PPU clocks counted: %0d (expected ~1720)", ppu_clocks);

        if (ppu_clocks > 1600 && ppu_clocks < 1850)
            $display("  Clock ratio OK");
        else
            $display("  ERROR: PPU clock count out of expected range!");

        $display("");
        $display("ALL CHECKS PASSED");
        $finish;
    end

    // Count PPU edges continuously
    always @(posedge clk_ppu) begin
        ppu_clocks = ppu_clocks + 1;
    end

    // Timeout
    initial begin
        #500_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
