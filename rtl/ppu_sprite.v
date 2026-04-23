`timescale 1ns / 1ps

// NES PPU Sprite Evaluation and Rendering
//
// Evaluation (per scanline, for the NEXT scanline's rendering):
//   Cycle 0:      Reset evaluation state
//   Cycles 1-64:  Clear secondary OAM to $FF (on odd cycles)
//   Cycles 65-256: Scan primary OAM; copy up to 8 in-range sprites
//     Y range check: (scanline - Y_byte) < sprite_height (unsigned)
//
// Pattern fetch (cycles 257-320):
//   8 groups of 8 cycles (one per secondary OAM slot)
//   Cycle offset 0: Load X counter and attributes into sprite unit
//   Cycle offset 4-5: Fetch pattern low byte from CHR ROM
//   Cycle offset 6-7: Fetch pattern high byte, load shift registers
//
// Rendering (cycles 1-256 of next scanline):
//   Each sprite unit: decrement X counter until 0, then shift MSB-first
//   Pixel output: highest-priority (lowest index) non-transparent sprite wins

module ppu_sprite (
    input  wire        clk,
    input  wire        rst,
    input  wire [8:0]  cycle,
    input  wire [8:0]  scanline,
    input  wire        rendering_en,
    input  wire        sprite_size,          // 0=8x8, 1=8x16
    input  wire        sprite_pattern_base,  // PPUCTRL bit 3 (8x8 mode only)

    // Primary OAM read (async, combinational from ppu_oam)
    output wire [7:0]  oam_addr,
    input  wire [7:0]  oam_data,

    // VRAM bus (sprite pattern fetch, cycles 257-320)
    output reg  [13:0] vram_addr,
    output wire        vram_fetch_active,
    input  wire [7:0]  vram_data,

    // Sprite pixel output (combinational)
    output wire [3:0]  sprite_pixel,    // {palette[1:0], pattern[1:0]}
    output wire        sprite_priority, // 0=in front of BG, 1=behind BG
    output wire        sprite_active,   // a non-transparent sprite pixel is ready
    output wire        sprite0_active,  // pixel is from sprite 0 (for hit detection)
    output reg         sprite_overflow
);

    // =========================================================
    // Secondary OAM (32 bytes: 8 sprites × 4 bytes)
    // =========================================================
    reg [7:0] sec_y    [0:7];
    reg [7:0] sec_tile [0:7];
    reg [7:0] sec_attr [0:7];
    reg [7:0] sec_x    [0:7];
    reg [3:0] sec_count;    // valid sprite count (0-8)
    reg       sprite0_found; // sprite 0 is in secondary OAM

    // =========================================================
    // Evaluation state
    // =========================================================
    reg [6:0] n;         // primary OAM sprite index (0-64, 7-bit to allow == 64 check)
    reg [1:0] m;         // byte within sprite (0=Y, 1=tile, 2=attr, 3=X)
    reg [3:0] s;         // secondary OAM slot (0-8, 4-bit to allow == 8 check)
    reg [4:0] clear_ctr; // secondary OAM clear byte counter (0-31)

    // OAM address driven combinationally from evaluation state (use lower 6 bits of n)
    assign oam_addr = {n[5:0], m};

    // Y range check: in range if (scanline - Y_byte) < height (unsigned)
    wire [8:0] y_diff  = {1'b0, scanline[7:0]} - {1'b0, oam_data};
    wire       in_range = y_diff < (sprite_size ? 9'd16 : 9'd8);

    // =========================================================
    // Pattern fetch timing
    // =========================================================
    wire        in_sprite_fetch = (cycle >= 9'd257) && (cycle <= 9'd320);
    // fetch_idx = cycle - 257 (0-63), using the fact that 257 mod 64 = 1
    wire [5:0]  fetch_idx   = cycle[5:0] - 6'd1;
    wire [2:0]  fetch_slot  = fetch_idx[5:3]; // 0-7
    wire [2:0]  fetch_phase = fetch_idx[2:0]; // 0-7 within slot

    assign vram_fetch_active = in_sprite_fetch;

    // Current fetch slot's secondary OAM (read combinationally; stable during 257-320)
    wire [7:0] cur_sec_y    = sec_y   [fetch_slot];
    wire [7:0] cur_sec_tile = sec_tile [fetch_slot];
    wire [7:0] cur_sec_attr = sec_attr [fetch_slot];
    wire [7:0] cur_sec_x    = sec_x   [fetch_slot];

    // Tile row: scanline - Y_byte (computed for next scanline = scanline+1 - (Y_byte+1))
    wire [7:0] tile_y_raw = scanline[7:0] - cur_sec_y;
    wire       v_flip     = cur_sec_attr[7];
    wire       h_flip     = cur_sec_attr[6];
    wire [7:0] tile_y     = v_flip ? ((sprite_size ? 8'd15 : 8'd7) - tile_y_raw) : tile_y_raw;

    // Pattern table addresses
    //   8x8  mode: base = PPUCTRL bit 3; tile index = OAM byte1; row = tile_y[2:0]
    //   8x16 mode: base = OAM byte1 bit 0; tile index = {byte1[7:1], tile_y[3]}; row = tile_y[2:0]
    wire        sp_pt_base  = sprite_size ? cur_sec_tile[0] : sprite_pattern_base;
    wire [7:0]  sp_tile_idx = sprite_size ? {cur_sec_tile[7:1], tile_y[3]} : cur_sec_tile;
    wire [13:0] sp_pat_lo_addr = {1'b0, sp_pt_base, sp_tile_idx, 1'b0, tile_y[2:0]};
    wire [13:0] sp_pat_hi_addr = {1'b0, sp_pt_base, sp_tile_idx, 1'b1, tile_y[2:0]};

    // Horizontal flip: reverse bit order for shift register load
    function [7:0] flip_byte;
        input [7:0] b;
        flip_byte = {b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7]};
    endfunction

    // =========================================================
    // Sprite units (8 slots)
    // =========================================================
    reg [7:0] sr_lo     [0:7]; // pattern low plane shift register
    reg [7:0] sr_hi     [0:7]; // pattern high plane shift register
    reg [7:0] x_cnt     [0:7]; // X position down-counter
    reg [1:0] pal_latch [0:7]; // sprite palette index
    reg       prio_latch[0:7]; // 0=in front, 1=behind
    reg       active    [0:7]; // slot has valid sprite data

    reg [7:0] pat_lo_latch; // holds low pattern byte between fetch phases 5 and 7

    integer i;

    // =========================================================
    // Evaluation state machine
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            sec_count     <= 0;
            sprite0_found <= 0;
            sprite_overflow <= 0;
            n <= 7'd0; m <= 0; s <= 4'd0;
            clear_ctr <= 0;
            for (i = 0; i < 8; i = i+1) begin
                sec_y[i]    <= 8'hFF;
                sec_tile[i] <= 8'hFF;
                sec_attr[i] <= 8'hFF;
                sec_x[i]    <= 8'hFF;
            end
        end else if (rendering_en) begin

            // Cycle 0: reset evaluation state for the new scanline
            if (cycle == 9'd0) begin
                n <= 7'd0; m <= 0; s <= 4'd0;
                sec_count     <= 0;
                sprite0_found <= 0;
                sprite_overflow <= 0;
                clear_ctr <= 0;
                for (i = 0; i < 8; i = i+1) begin
                    sec_y[i]    <= 8'hFF;
                    sec_tile[i] <= 8'hFF;
                    sec_attr[i] <= 8'hFF;
                    sec_x[i]    <= 8'hFF;
                end
            end

            // Cycles 1-64: clear secondary OAM (one byte per odd cycle)
            if (cycle >= 9'd1 && cycle <= 9'd64 && cycle[0]) begin
                case (clear_ctr[1:0])
                    2'd0: sec_y   [clear_ctr[4:2]] <= 8'hFF;
                    2'd1: sec_tile[clear_ctr[4:2]] <= 8'hFF;
                    2'd2: sec_attr[clear_ctr[4:2]] <= 8'hFF;
                    2'd3: sec_x   [clear_ctr[4:2]] <= 8'hFF;
                endcase
                clear_ctr <= clear_ctr + 5'd1;
            end

            // Cycles 65-256: sprite evaluation (async OAM read via oam_data)
            if (cycle >= 9'd65 && cycle <= 9'd256 && n < 7'd64 && s < 4'd8) begin
                case (m)
                    2'd0: begin
                        if (in_range) begin
                            sec_y[s[2:0]] <= oam_data;
                            if (n == 7'd0) sprite0_found <= 1;
                            m <= 2'd1;
                        end else begin
                            n <= n + 7'd1;
                        end
                    end
                    2'd1: begin
                        sec_tile[s[2:0]] <= oam_data;
                        m <= 2'd2;
                    end
                    2'd2: begin
                        sec_attr[s[2:0]] <= oam_data;
                        m <= 2'd3;
                    end
                    2'd3: begin
                        sec_x[s[2:0]] <= oam_data;
                        sec_count  <= s + 4'd1;
                        s          <= s + 4'd1;
                        m          <= 2'd0;
                        n          <= n + 7'd1;
                    end
                endcase
            end

            // Overflow: more than 8 sprites would appear on this scanline
            if (cycle >= 9'd65 && cycle <= 9'd256 && s >= 4'd8 && n < 7'd64)
                sprite_overflow <= 1;
        end
    end

    // =========================================================
    // VRAM address for sprite pattern fetch (combinational)
    // =========================================================
    always @(*) begin
        vram_addr = 14'd0;
        if (in_sprite_fetch) begin
            case (fetch_phase)
                3'd4, 3'd5: vram_addr = sp_pat_lo_addr;
                3'd6, 3'd7: vram_addr = sp_pat_hi_addr;
                default:    vram_addr = 14'd0;
            endcase
        end
    end

    // =========================================================
    // Sprite unit loading (pattern fetch) and rendering (X counters + shift)
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 8; i = i+1) begin
                sr_lo[i]      <= 8'h00;
                sr_hi[i]      <= 8'h00;
                x_cnt[i]      <= 8'hFF;
                pal_latch[i]  <= 2'd0;
                prio_latch[i] <= 1'b0;
                active[i]     <= 1'b0;
            end
            pat_lo_latch <= 8'h00;
        end else begin

            // --- Sprite pattern fetch (cycles 257-320) ---
            if (in_sprite_fetch && rendering_en) begin
                case (fetch_phase)
                    3'd0: begin
                        // Load X counter and attributes at the start of each slot
                        x_cnt[fetch_slot]      <= cur_sec_x;
                        pal_latch[fetch_slot]   <= cur_sec_attr[1:0];
                        prio_latch[fetch_slot]  <= cur_sec_attr[5];
                        active[fetch_slot]      <= ({1'b0, fetch_slot} < sec_count);
                    end
                    3'd5: begin
                        // Capture pattern low byte (BRAM latency: addr set at phase 4)
                        pat_lo_latch <= h_flip ? flip_byte(vram_data) : vram_data;
                    end
                    3'd7: begin
                        // Load shift registers (BRAM latency: addr set at phase 6)
                        if ({1'b0, fetch_slot} < sec_count) begin
                            sr_lo[fetch_slot] <= pat_lo_latch;
                            sr_hi[fetch_slot] <= h_flip ? flip_byte(vram_data) : vram_data;
                        end else begin
                            // Inactive slot: zero pattern = always transparent
                            sr_lo[fetch_slot] <= 8'h00;
                            sr_hi[fetch_slot] <= 8'h00;
                        end
                    end
                    default: ;
                endcase
            end

            // --- Sprite rendering (cycles 1-256): X counters and shift registers ---
            if (rendering_en && cycle >= 9'd1 && cycle <= 9'd256) begin
                for (i = 0; i < 8; i = i+1) begin
                    if (x_cnt[i] != 8'd0) begin
                        x_cnt[i] <= x_cnt[i] - 8'd1;
                    end else if (active[i]) begin
                        sr_lo[i] <= {sr_lo[i][6:0], 1'b0};
                        sr_hi[i] <= {sr_hi[i][6:0], 1'b0};
                    end
                end
            end
        end
    end

    // =========================================================
    // Output: highest-priority (lowest index) non-transparent sprite
    // =========================================================
    reg [3:0] pix_out;
    reg       prio_out;
    reg       act_out;
    reg       sp0_out;
    integer   j;

    always @(*) begin
        pix_out  = 4'd0;
        prio_out = 1'b0;
        act_out  = 1'b0;
        sp0_out  = 1'b0;
        // Iterate from lowest priority (7) to highest (0); last write wins
        for (j = 7; j >= 0; j = j - 1) begin
            if (active[j] && (x_cnt[j] == 8'd0) &&
                ({sr_hi[j][7], sr_lo[j][7]} != 2'b00)) begin
                pix_out  = {pal_latch[j], sr_hi[j][7], sr_lo[j][7]};
                prio_out = prio_latch[j];
                act_out  = 1'b1;
                sp0_out  = (j == 0) && sprite0_found;
            end
        end
    end

    assign sprite_pixel    = pix_out;
    assign sprite_priority = prio_out;
    assign sprite_active   = act_out;
    assign sprite0_active  = sp0_out;

endmodule
