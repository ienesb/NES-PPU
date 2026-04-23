`timescale 1ns / 1ps

// PPU Palette RAM (32 bytes)
// Stores 6-bit NES color indices
//
// Address map (from PPU perspective, offset from $3F00):
//   $00:     Universal background color
//   $01-$03: BG palette 0
//   $04:     Unused (mirrors $00 during rendering)
//   $05-$07: BG palette 1
//   $08:     Unused (mirrors $00)
//   $09-$0B: BG palette 2
//   $0C:     Unused (mirrors $00)
//   $0D-$0F: BG palette 3
//   $10-$1F: Sprite palettes (mirrors: $10->$00, $14->$04, $18->$08, $1C->$0C)
//
// Combinational read (no latency), synchronous write

module ppu_palette (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  addr,
    input  wire [5:0]  din,
    output wire [5:0]  dout
);

    reg [5:0] palette [0:31];

    // Mirroring: addresses $10/$14/$18/$1C mirror $00/$04/$08/$0C
    wire [4:0] eff_addr = (addr[4] && addr[1:0] == 2'b00)
                          ? {1'b0, addr[3:0]}
                          : addr;

    // Combinational read
    assign dout = palette[eff_addr];

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            palette[eff_addr] <= din;
    end

    // Test palette initialization
    initial begin
        // Universal background
        palette[0]  = 6'h0F; // black

        // BG Palette 0: white, red, blue
        palette[1]  = 6'h20; // white
        palette[2]  = 6'h16; // red
        palette[3]  = 6'h12; // blue
        palette[4]  = 6'h0F;

        // BG Palette 1: green, yellow, cyan
        palette[5]  = 6'h1A; // green
        palette[6]  = 6'h28; // yellow
        palette[7]  = 6'h2C; // cyan
        palette[8]  = 6'h0F;

        // BG Palette 2: purple, orange, pink
        palette[9]  = 6'h14; // purple
        palette[10] = 6'h27; // orange
        palette[11] = 6'h25; // pink
        palette[12] = 6'h0F;

        // BG Palette 3: light blue, light green, light red
        palette[13] = 6'h21; // light blue
        palette[14] = 6'h2A; // light green
        palette[15] = 6'h26; // light red

        // Sprite palette 0: red, orange, yellow
        palette[16] = 6'h0F; // bg (mirrors $3F00)
        palette[17] = 6'h16; // red
        palette[18] = 6'h27; // orange
        palette[19] = 6'h37; // light yellow

        // Sprite palette 1: cyan, dark green, purple
        palette[20] = 6'h0F; // bg (mirrors $3F04)
        palette[21] = 6'h2C; // cyan
        palette[22] = 6'h0C; // dark green
        palette[23] = 6'h14; // purple

        // Sprite palette 2: bright white, green, yellow
        palette[24] = 6'h0F; // bg (mirrors $3F08)
        palette[25] = 6'h30; // bright white
        palette[26] = 6'h1A; // green
        palette[27] = 6'h28; // yellow

        // Sprite palette 3: orange, dark blue, medium blue
        palette[28] = 6'h0F; // bg (mirrors $3F0C)
        palette[29] = 6'h27; // orange
        palette[30] = 6'h12; // dark blue
        palette[31] = 6'h21; // medium blue
    end

endmodule
