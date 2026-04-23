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
        for (k = 0; k < 256; k = k+1)
            mem[k] = 8'hFF; // all sprites off screen

        // Sprite 0: tile 1, screen Y=8-15, X=8, palette 0, in front, no flip
        //   Y byte = screen_top - 1 = 7
        mem[0] = 8'd7;   mem[1] = 8'd1;  mem[2] = 8'h00; mem[3] = 8'd8;

        // Sprite 1: tile 2, screen Y=21-28, X=40, palette 1, H-flip, in front
        mem[4] = 8'd20;  mem[5] = 8'd2;  mem[6] = 8'h41; mem[7] = 8'd40;

        // Sprite 2: tile 3, screen Y=101-108, X=80, palette 2, behind BG
        mem[8]  = 8'd100; mem[9]  = 8'd3; mem[10] = 8'h22; mem[11] = 8'd80;

        // Sprite 3: tile 4, screen Y=51-58, X=120, palette 3, V-flip, in front
        mem[12] = 8'd50;  mem[13] = 8'd4; mem[14] = 8'h83; mem[15] = 8'd120;
    end

    // Async reads (synthesizes to LUTRAM on Xilinx)
    assign cpu_dout  = mem[cpu_addr];
    assign eval_dout = mem[eval_addr];

    // Sync write
    always @(posedge clk)
        if (cpu_we) mem[cpu_addr] <= cpu_din;

endmodule
