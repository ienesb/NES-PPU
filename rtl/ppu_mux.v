`timescale 1ns / 1ps

// PPU Output Multiplexer
// Composites background and sprite pixels according to NES priority rules:
//
//   Both transparent       -> universal background ($3F00)
//   BG transparent only    -> sprite (regardless of priority bit)
//   Sprite transparent     -> BG
//   Both opaque, sprite in front (priority=0) -> sprite
//   Both opaque, sprite behind (priority=1)   -> BG
//
// Sprite 0 hit fires when sprite 0 pixel and BG pixel are both non-transparent.
// (Priority bit does not affect hit detection.)

module ppu_mux (
    input  wire [3:0] bg_pixel,       // {attr[1:0], pattern[1:0]} from ppu_bg
    input  wire [3:0] sprite_pixel,   // {palette[1:0], pattern[1:0]} from ppu_sprite
    input  wire       sprite_active,  // sprite has a non-transparent pixel
    input  wire       sprite_priority,// 0=in front of BG, 1=behind BG
    input  wire       sprite0_active, // pixel is from sprite 0
    input  wire       show_bg,
    input  wire       show_sprite,

    output wire [3:0] final_pixel,    // selected pixel (use with palette lookup)
    output wire       final_is_sprite,// 1 if sprite pixel selected, 0 if BG
    output wire       sprite0_hit     // pulse: sprite 0 and BG overlap this cycle
);
    wire bg_opaque = show_bg     && (bg_pixel[1:0]   != 2'b00);
    wire sp_opaque = show_sprite && sprite_active;

    // Use sprite when: it is opaque AND (in front OR BG is transparent)
    wire use_sprite = sp_opaque && !(sprite_priority && bg_opaque);

    assign final_pixel     = use_sprite ? sprite_pixel :
                             bg_opaque  ? bg_pixel     : 4'd0;
    assign final_is_sprite = use_sprite;

    // Sprite 0 hit: both sprite 0 and BG have non-transparent pixels
    assign sprite0_hit = show_bg && show_sprite && bg_opaque && sprite0_active;

endmodule
