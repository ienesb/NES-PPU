`timescale 1ns / 1ps

// 8KB CHR ROM (Pattern Tables)
// Two pattern tables: $0000-$0FFF and $1000-$1FFF
// Each tile is 16 bytes: 8 low plane + 8 high plane
// 256 tiles per pattern table, 512 total
//
// Test data: each tile N has all rows = N (low plane), high plane = 0
// This creates unique horizontal stripe patterns per tile index

module chr_rom (
    input  wire        clk,
    input  wire [12:0] addr,   // 0-8191
    output reg  [7:0]  data
);

    reg [7:0] mem [0:8191];

    initial $readmemh("chr.mem", mem);

    always @(posedge clk)
        data <= mem[addr];

endmodule
