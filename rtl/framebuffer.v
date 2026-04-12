`timescale 1ns / 1ps

// Dual-port Block RAM Framebuffer
// 256 x 240 pixels, 6 bits per pixel (NES palette index)
// Port A (write): PPU clock domain
// Port B (read):  VGA clock domain

module framebuffer (
    // Port A - PPU write
    input  wire        clk_a,
    input  wire        we_a,
    input  wire [15:0] addr_a,    // 0 to 61439 (256*240 - 1)
    input  wire [5:0]  din_a,

    // Port B - VGA read
    input  wire        clk_b,
    input  wire [15:0] addr_b,
    output reg  [5:0]  dout_b
);

    // 61440 x 6-bit memory
    // Vivado infers true dual-port block RAM from this pattern
    reg [5:0] mem [0:61439];

    // Initialize to 0 (black)
    integer i;
    initial begin
        for (i = 0; i < 61440; i = i + 1)
            mem[i] = 6'd0;
    end

    // Port A: write-only
    always @(posedge clk_a) begin
        if (we_a)
            mem[addr_a] <= din_a;
    end

    // Port B: read-only
    always @(posedge clk_b) begin
        dout_b <= mem[addr_b];
    end

endmodule
