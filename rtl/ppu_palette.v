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
    // Render read port (combinational)
    input  wire [4:0]  addr,
    output wire [5:0]  dout,
    // CPU port (sync write, async read)
    input  wire        cpu_we,
    input  wire [4:0]  cpu_addr,
    input  wire [5:0]  cpu_din,
    output wire [5:0]  cpu_dout
);

    reg [5:0] palette [0:31];

    // Mirroring: addresses $10/$14/$18/$1C mirror $00/$04/$08/$0C
    function [4:0] eff_fn (input [4:0] a);
        eff_fn = (a[4] && a[1:0] == 2'b00) ? {1'b0, a[3:0]} : a;
    endfunction
    wire [4:0] eff_addr     = eff_fn(addr);
    wire [4:0] eff_cpu_addr = eff_fn(cpu_addr);

    assign dout     = palette[eff_addr];
    assign cpu_dout = palette[eff_cpu_addr];

    always @(posedge clk) begin
        if (cpu_we)
            palette[eff_cpu_addr] <= cpu_din;
    end

    // Palette initialized from palette.mem (Phase 8 test ROM).
    // Direct $readmemh into the distributed-RAM array; Vivado preserves
    // the init values only when loaded straight into `palette`. The
    // 8-bit hex bytes are truncated to the array's 6 bits on load.
    initial $readmemh("palette.mem", palette);

endmodule
