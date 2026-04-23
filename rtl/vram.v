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

    initial $readmemh("nametable.mem", mem);

    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];
    end

endmodule
