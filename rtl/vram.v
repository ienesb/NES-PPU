`timescale 1ns / 1ps

// 2KB VRAM for nametable storage
// Nametable layout (1KB each, 2 physical nametables):
//   Bytes 0-959:    Tile indices (32 x 30 = 960 tiles)
//   Bytes 960-1023: Attribute table (64 bytes, palette selection)
//
// Mirroring is handled externally (address mapping in basys3_top)
//
// Test data: sequential tile indices, quadrant-based palette attributes

module vram (
    input  wire        clk,
    input  wire        we,
    input  wire [10:0] addr,   // 0-2047 (2KB)
    input  wire [7:0]  din,
    output reg  [7:0]  dout
);

    reg [7:0] mem [0:2047];

    integer i, ax, ay;
    initial begin
        // Clear all
        for (i = 0; i < 2048; i = i + 1)
            mem[i] = 8'h00;

        // === Nametable 0 (bytes 0-1023) ===

        // Tile data (bytes 0-959): sequential tile indices
        for (i = 0; i < 960; i = i + 1)
            mem[i] = i & 8'hFF;

        // Attribute table (bytes 960-1023): quadrant palette selection
        // Each byte covers 4x4 tiles (32x32 pixels)
        // Layout per byte: {BR[1:0], BL[1:0], TR[1:0], TL[1:0]}
        // Screen divided into 4 color regions
        for (i = 0; i < 64; i = i + 1) begin
            ax = i % 8;  // 0-7 (attribute column)
            ay = i / 8;  // 0-7 (attribute row)
            if (ax < 4 && ay < 4)
                mem[960 + i] = 8'b00_00_00_00; // all quadrants palette 0
            else if (ax >= 4 && ay < 4)
                mem[960 + i] = 8'b01_01_01_01; // all quadrants palette 1
            else if (ax < 4 && ay >= 4)
                mem[960 + i] = 8'b10_10_10_10; // all quadrants palette 2
            else
                mem[960 + i] = 8'b11_11_11_11; // all quadrants palette 3
        end

        // === Nametable 1 (bytes 1024-2047) ===
        // Leave as zeros (blank) for now
    end

    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];
    end

endmodule
