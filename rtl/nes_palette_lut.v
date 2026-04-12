`timescale 1ns / 1ps

// NES Palette Lookup Table
// Converts 6-bit NES color index (0-63) to 12-bit RGB (4 bits per channel)
// Based on the Nestopia RGB palette, quantized to 4-bit per channel

module nes_palette_lut (
    input  wire [5:0] color_index,
    output reg  [3:0] r,
    output reg  [3:0] g,
    output reg  [3:0] b
);

    always @(*) begin
        case (color_index)
            // Row 0: $00-$0F
            6'h00: {r, g, b} = 12'h666; // light gray
            6'h01: {r, g, b} = 12'h029; // dark blue
            6'h02: {r, g, b} = 12'h12B; // blue-purple
            6'h03: {r, g, b} = 12'h329; // purple
            6'h04: {r, g, b} = 12'h416; // red-purple
            6'h05: {r, g, b} = 12'h510; // red
            6'h06: {r, g, b} = 12'h420; // dark red-orange
            6'h07: {r, g, b} = 12'h330; // brown
            6'h08: {r, g, b} = 12'h240; // olive
            6'h09: {r, g, b} = 12'h050; // dark green
            6'h0A: {r, g, b} = 12'h060; // green
            6'h0B: {r, g, b} = 12'h054; // dark cyan-green
            6'h0C: {r, g, b} = 12'h057; // dark cyan
            6'h0D: {r, g, b} = 12'h000; // black
            6'h0E: {r, g, b} = 12'h000; // black (mirror)
            6'h0F: {r, g, b} = 12'h000; // black (mirror)

            // Row 1: $10-$1F
            6'h10: {r, g, b} = 12'hAAA; // mid gray
            6'h11: {r, g, b} = 12'h15E; // medium blue
            6'h12: {r, g, b} = 12'h34F; // blue
            6'h13: {r, g, b} = 12'h63E; // purple-blue
            6'h14: {r, g, b} = 12'h82B; // magenta
            6'h15: {r, g, b} = 12'h923; // red
            6'h16: {r, g, b} = 12'h830; // orange-red
            6'h17: {r, g, b} = 12'h650; // orange
            6'h18: {r, g, b} = 12'h470; // yellow-green
            6'h19: {r, g, b} = 12'h180; // green
            6'h1A: {r, g, b} = 12'h090; // bright green
            6'h1B: {r, g, b} = 12'h088; // cyan-green
            6'h1C: {r, g, b} = 12'h08B; // cyan
            6'h1D: {r, g, b} = 12'h000; // black
            6'h1E: {r, g, b} = 12'h000; // black (mirror)
            6'h1F: {r, g, b} = 12'h000; // black (mirror)

            // Row 2: $20-$2F
            6'h20: {r, g, b} = 12'hFFF; // white
            6'h21: {r, g, b} = 12'h4AF; // light blue
            6'h22: {r, g, b} = 12'h68F; // sky blue
            6'h23: {r, g, b} = 12'hA7F; // lavender
            6'h24: {r, g, b} = 12'hC6F; // pink
            6'h25: {r, g, b} = 12'hD5A; // light red
            6'h26: {r, g, b} = 12'hD65; // salmon
            6'h27: {r, g, b} = 12'hC85; // light orange
            6'h28: {r, g, b} = 12'hAA5; // yellow
            6'h29: {r, g, b} = 12'h5C4; // light green
            6'h2A: {r, g, b} = 12'h3D6; // mint green
            6'h2B: {r, g, b} = 12'h3CB; // light cyan-green
            6'h2C: {r, g, b} = 12'h3CE; // light cyan
            6'h2D: {r, g, b} = 12'h444; // dark gray
            6'h2E: {r, g, b} = 12'h000; // black (mirror)
            6'h2F: {r, g, b} = 12'h000; // black (mirror)

            // Row 3: $30-$3F
            6'h30: {r, g, b} = 12'hFFF; // white
            6'h31: {r, g, b} = 12'hADF; // pale blue
            6'h32: {r, g, b} = 12'hBCF; // pale sky blue
            6'h33: {r, g, b} = 12'hDBF; // pale lavender
            6'h34: {r, g, b} = 12'hFBF; // pale pink
            6'h35: {r, g, b} = 12'hFAB; // pale salmon
            6'h36: {r, g, b} = 12'hFBA; // pale orange
            6'h37: {r, g, b} = 12'hFC9; // pale yellow-orange
            6'h38: {r, g, b} = 12'hED9; // pale yellow
            6'h39: {r, g, b} = 12'hBE9; // pale green
            6'h3A: {r, g, b} = 12'hAEA; // pale mint
            6'h3B: {r, g, b} = 12'hAED; // pale cyan-green
            6'h3C: {r, g, b} = 12'hAEF; // pale cyan
            6'h3D: {r, g, b} = 12'h888; // medium gray
            6'h3E: {r, g, b} = 12'h000; // black (mirror)
            6'h3F: {r, g, b} = 12'h000; // black (mirror)

            default: {r, g, b} = 12'h000;
        endcase
    end

endmodule
