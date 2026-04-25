`timescale 1ns / 1ps

// 256-byte OAM RAM (64 sprites × 4 bytes: Y, tile, attr, X)
// Async reads (LUTRAM) so sprite evaluation can sample data combinationally.
// CPU write port unused until Phase 7.
//
// OAM byte conventions:
//   Byte 0 (Y):    top scanline of sprite minus 1. Sprite visible on scanlines Y+1..Y+8.
//   Byte 1 (tile): CHR tile index (0-255)
//   Byte 2 (attr): bit7=V-flip, bit6=H-flip, bit5=priority(0=front), bits1:0=palette
//   Byte 3 (X):    left pixel column (0-255)

module ppu_oam (
    input  wire       clk,
    // CPU interface (Phase 7)
    input  wire [7:0] cpu_addr,
    input  wire [7:0] cpu_din,
    input  wire       cpu_we,
    output wire [7:0] cpu_dout,
    // PPU evaluation read port (async)
    input  wire [7:0] eval_addr,
    output wire [7:0] eval_dout
);
    reg [7:0] mem [0:255];

    integer k;
    initial begin
        // All sprites off screen (Y=$FF). Real NES OAM is uninitialized at
        // power-up, but $FF for every byte keeps every sprite hidden until
        // the game writes valid OAM data via $2003/$2004 or $4014 DMA.
        for (k = 0; k < 256; k = k+1)
            mem[k] = 8'hFF;
    end

    // Async reads (synthesizes to LUTRAM on Xilinx)
    assign cpu_dout  = mem[cpu_addr];
    assign eval_dout = mem[eval_addr];

    // Sync write
    always @(posedge clk)
        if (cpu_we) mem[cpu_addr] <= cpu_din;

endmodule
