`timescale 1ns / 1ps

// VGA Scaler: maps 640x480 VGA coordinates to 256x240 NES framebuffer
// 2x integer scaling: 256*2=512 x 240*2=480
// Centered horizontally: 64px black border on each side
// No vertical border (480 = 240*2 exactly)

module vga_scaler (
    input  wire [9:0]  pixel_x,      // VGA pixel X (0-639)
    input  wire [9:0]  pixel_y,      // VGA pixel Y (0-479)
    input  wire        video_active,  // VGA active area
    output wire [15:0] fb_addr,       // framebuffer read address
    output wire        in_nes_area    // high when inside NES display region
);

    // NES display area: X=[64, 575], Y=[0, 479]
    localparam H_BORDER = 64;
    localparam NES_W    = 256;
    localparam NES_H    = 240;

    wire h_in_range = (pixel_x >= H_BORDER) && (pixel_x < H_BORDER + NES_W * 2);
    assign in_nes_area = video_active && h_in_range;

    // Divide by 2 for both axes (integer scaling)
    wire [7:0] nes_x = (pixel_x - H_BORDER) >> 1; // 0-255
    wire [7:0] nes_y = pixel_y >> 1;                // 0-239

    // Framebuffer address = nes_y * 256 + nes_x
    assign fb_addr = {nes_y, nes_x};

endmodule
