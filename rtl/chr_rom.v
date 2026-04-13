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

    integer i, j;
    initial begin
        // Clear all
        for (i = 0; i < 8192; i = i + 1)
            mem[i] = 8'h00;

        // Pattern table 0 ($0000-$0FFF): 256 tiles
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                mem[i * 16 + j]     = i; // low plane
                mem[i * 16 + j + 8] = 0; // high plane
            end
        end

        // Pattern table 1 ($1000-$1FFF): inverted patterns
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                mem[4096 + i * 16 + j]     = ~i[7:0]; // low plane inverted
                mem[4096 + i * 16 + j + 8] = 0;
            end
        end
    end

    always @(posedge clk)
        data <= mem[addr];

endmodule
