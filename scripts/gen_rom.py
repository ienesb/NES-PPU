#!/usr/bin/env python3
"""
Phase 8 ROM generator.

Emits three .mem files under data/:
    chr.mem        8192 bytes -- pattern tables $0000-$1FFF
    nametable.mem  2048 bytes -- two 1KB nametables ($2000 + $2400 mirror)
    palette.mem    32 bytes   -- $3F00-$3F1F

The CHR ROM contains:
    tile 0:        transparent (plane A=B=0)
    tiles 1-64:    ASCII font glyphs (plane A has shape, plane B = 0 -> color 1)
    tiles 128-131: "blocky" sprite shapes for OAM demo
The nametable renders a centered title "NES PPU OK" over a bordered playfield.

Output is Verilog $readmemh-friendly: one hex byte per line.
"""

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
DATA.mkdir(exist_ok=True)

# --- 8x8 font glyphs, one bitmap per ASCII code point (only a subset used) ---
# Each glyph is 8 rows, MSB = leftmost pixel. 0 = background, 1 = color 1.
FONT = {
    ' ': [0,0,0,0,0,0,0,0],
    '!': [0x18,0x18,0x18,0x18,0x00,0x18,0x18,0x00],
    '-': [0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00],
    '.': [0,0,0,0,0,0x18,0x18,0],
    '0': [0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00],
    '1': [0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00],
    '2': [0x3C,0x66,0x06,0x0C,0x30,0x60,0x7E,0x00],
    '3': [0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00],
    '4': [0x0C,0x1C,0x2C,0x4C,0x7E,0x0C,0x0C,0x00],
    '5': [0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00],
    '6': [0x3C,0x60,0x60,0x7C,0x66,0x66,0x3C,0x00],
    '7': [0x7E,0x06,0x0C,0x18,0x18,0x18,0x18,0x00],
    '8': [0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00],
    '9': [0x3C,0x66,0x66,0x3E,0x06,0x06,0x3C,0x00],
    'A': [0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00],
    'B': [0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00],
    'C': [0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00],
    'D': [0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00],
    'E': [0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00],
    'F': [0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00],
    'G': [0x3C,0x66,0x60,0x6E,0x66,0x66,0x3E,0x00],
    'H': [0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00],
    'I': [0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00],
    'K': [0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00],
    'L': [0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00],
    'M': [0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00],
    'N': [0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00],
    'O': [0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00],
    'P': [0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00],
    'R': [0x7C,0x66,0x66,0x7C,0x78,0x6C,0x66,0x00],
    'S': [0x3E,0x60,0x60,0x3C,0x06,0x06,0x7C,0x00],
    'T': [0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00],
    'U': [0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00],
    'V': [0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00],
    'Y': [0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00],
}

# Tile indices the nametable will reference.
# Reserve 1..26 for A-Z, 27..36 for digits 0-9, 37 for space, 38 for '-', etc.
CHAR_TO_TILE = {}
def _alloc_font():
    idx = 1
    for c in list("ABCDEFGHIJKLMNOPQRSTUVWXYZ") + list("0123456789") + [' ', '-', '.', '!']:
        if c in FONT:
            CHAR_TO_TILE[c] = idx
            idx += 1
_alloc_font()

# Border tiles
TILE_BORDER_H     = 80    # horizontal bar
TILE_BORDER_V     = 81    # vertical bar
TILE_CORNER_TL    = 82
TILE_CORNER_TR    = 83
TILE_CORNER_BL    = 84
TILE_CORNER_BR    = 85
TILE_SOLID        = 86    # fully filled (color 1)
TILE_CHECKER      = 87    # checkerboard

# Sprite tiles
SPRITE_BLOCK      = 128   # 8x8 solid square with outline
SPRITE_DOT        = 129   # small centered 4x4 square
SPRITE_ARROW      = 130   # upward-pointing triangle
SPRITE_HEART      = 131


def encode_tile(plane_a, plane_b=None):
    """Given two lists of 8 bytes (one bit per column), return 16-byte CHR entry."""
    if plane_b is None:
        plane_b = [0]*8
    return bytes(plane_a + plane_b)


def build_chr():
    chr_rom = bytearray(8192)

    def put_tile(idx, data16):
        chr_rom[idx*16:idx*16+16] = data16

    # tile 0 = transparent
    put_tile(0, encode_tile([0]*8))

    # font tiles
    for c, idx in CHAR_TO_TILE.items():
        put_tile(idx, encode_tile(FONT[c]))

    # border / background tiles
    put_tile(TILE_BORDER_H,  encode_tile([0,0,0,0xFF,0xFF,0,0,0]))
    put_tile(TILE_BORDER_V,  encode_tile([0x18]*8))
    put_tile(TILE_CORNER_TL, encode_tile([0,0,0,0x1F,0x1F,0x18,0x18,0x18]))
    put_tile(TILE_CORNER_TR, encode_tile([0,0,0,0xF8,0xF8,0x18,0x18,0x18]))
    put_tile(TILE_CORNER_BL, encode_tile([0x18,0x18,0x18,0x1F,0x1F,0,0,0]))
    put_tile(TILE_CORNER_BR, encode_tile([0x18,0x18,0x18,0xF8,0xF8,0,0,0]))
    put_tile(TILE_SOLID,     encode_tile([0xFF]*8))
    put_tile(TILE_CHECKER,   encode_tile([0xAA,0x55,0xAA,0x55,0xAA,0x55,0xAA,0x55]))

    # sprite tiles (color 1 opaque, rest transparent)
    put_tile(SPRITE_BLOCK,
             encode_tile([0xFF,0x81,0xBD,0xA5,0xA5,0xBD,0x81,0xFF]))
    put_tile(SPRITE_DOT,
             encode_tile([0,0,0x3C,0x3C,0x3C,0x3C,0,0]))
    put_tile(SPRITE_ARROW,
             encode_tile([0x18,0x3C,0x7E,0xFF,0x18,0x18,0x18,0x18]))
    put_tile(SPRITE_HEART,
             encode_tile([0x66,0xFF,0xFF,0xFF,0x7E,0x3C,0x18,0x00]))

    return bytes(chr_rom)


def build_nametable():
    # 32 cols x 30 rows of tile indices, then 64 bytes attribute, then NT 1 (blank)
    nt = bytearray(2048)

    # Fill background with tile 0 (transparent = universal bg color)
    for r in range(30):
        for c in range(32):
            nt[r*32+c] = 0

    # Draw border
    for c in range(1, 31):
        nt[0*32+c]  = TILE_BORDER_H
        nt[29*32+c] = TILE_BORDER_H
    for r in range(1, 29):
        nt[r*32+0]  = TILE_BORDER_V
        nt[r*32+31] = TILE_BORDER_V
    nt[0*32+0]     = TILE_CORNER_TL
    nt[0*32+31]    = TILE_CORNER_TR
    nt[29*32+0]    = TILE_CORNER_BL
    nt[29*32+31]   = TILE_CORNER_BR

    def place_text(row, col, text):
        for i, ch in enumerate(text):
            t = CHAR_TO_TILE.get(ch, CHAR_TO_TILE[' '])
            nt[row*32 + col + i] = t

    # Centered lines
    def centered(row, text):
        place_text(row, (32-len(text))//2, text)

    centered(5,  "NES PPU")
    centered(7,  "PHASE 8")
    centered(12, "TEST ROM")
    centered(14, "LOADED")
    centered(20, "HELLO NES")
    centered(24, "OK")

    # Attribute table: one byte per 4x4-tile region (32 bytes used of 64)
    # Byte layout: {BR BL TR TL} x 2 bits each -> picks BG palette 0..3
    # Lay out four bands top->bottom to show off all 4 BG palettes.
    for i in range(64):
        ax = i % 8   # attr col (0-7, covers 4 tiles each -> 32 tiles)
        ay = i // 8  # attr row
        # rows 0-1 (tiles 0-7)   -> pal 0
        # rows 2-3 (tiles 8-15)  -> pal 1
        # rows 4-5 (tiles 16-23) -> pal 2
        # rows 6-7 (tiles 24-29) -> pal 3
        if   ay < 2: pal = 0
        elif ay < 4: pal = 1
        elif ay < 6: pal = 2
        else:        pal = 3
        byte = (pal<<0) | (pal<<2) | (pal<<4) | (pal<<6)
        nt[960 + i] = byte

    return bytes(nt)


def build_palette():
    # 32-byte palette (6-bit NES color codes)
    pal = bytearray(32)
    pal[0]  = 0x0F  # universal bg (black)

    # BG palette 0: white title on dark bg -> use white, red, gray
    pal[1]  = 0x30  # white
    pal[2]  = 0x16  # red
    pal[3]  = 0x10  # gray
    pal[4]  = 0x0F

    # BG palette 1: cyan accent
    pal[5]  = 0x2C  # cyan
    pal[6]  = 0x21  # light blue
    pal[7]  = 0x11  # blue
    pal[8]  = 0x0F

    # BG palette 2: yellow/orange
    pal[9]  = 0x28  # yellow
    pal[10] = 0x27  # orange
    pal[11] = 0x17  # dark orange
    pal[12] = 0x0F

    # BG palette 3: green
    pal[13] = 0x2A  # bright green
    pal[14] = 0x1A  # green
    pal[15] = 0x09  # dark green

    # Sprite palettes: pal[16..19] sp0, pal[20..23] sp1, etc.
    pal[16] = 0x0F; pal[17] = 0x30; pal[18] = 0x27; pal[19] = 0x16  # white/orange/red
    pal[20] = 0x0F; pal[21] = 0x2C; pal[22] = 0x21; pal[23] = 0x12  # blues
    pal[24] = 0x0F; pal[25] = 0x2A; pal[26] = 0x1A; pal[27] = 0x09  # greens
    pal[28] = 0x0F; pal[29] = 0x28; pal[30] = 0x24; pal[31] = 0x14  # purples
    return bytes(pal)


def write_mem(path: Path, data: bytes):
    with path.open('w') as f:
        f.write(f"// Generated by {Path(__file__).name} -- {len(data)} bytes\n")
        for b in data:
            f.write(f"{b:02X}\n")
    print(f"  wrote {path.name:<20} ({len(data)} bytes)")


def main():
    print("Generating Phase 8 ROM data...")
    write_mem(DATA / "chr.mem",       build_chr())
    write_mem(DATA / "nametable.mem", build_nametable())
    write_mem(DATA / "palette.mem",   build_palette())
    print("Done.")


if __name__ == "__main__":
    main()
