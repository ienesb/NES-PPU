`timescale 1ns / 1ps

// NES PPU Background Rendering Pipeline
//
// 8-cycle tile fetch sequence (per tile):
//   Phase 0: NT address on bus
//   Phase 1: Latch NT byte, AT address on bus
//   Phase 2: AT address held
//   Phase 3: Latch AT byte, extract palette bits
//   Phase 4: PT low address on bus
//   Phase 5: Latch PT low byte
//   Phase 6: PT high address on bus
//   Phase 7: Latch PT high byte, load shift regs, increment coarse X
//
// Shift registers output pixels selected by fine X scroll.
// V register manages scroll position with coarse/fine increments.

module ppu_bg (
    input  wire        clk,
    input  wire        rst,

    // Timing signals
    input  wire [8:0]  cycle,
    input  wire [8:0]  scanline,
    input  wire        visible_line,
    input  wire        pre_render_line,
    input  wire        render_line,

    // Configuration
    input  wire        rendering_en,
    input  wire        bg_pattern_base,  // 0=$0000, 1=$1000

    // Scroll registers (from external / CPU registers)
    input  wire [14:0] t_reg,
    input  wire [2:0]  fine_x,

    // VRAM interface
    output reg  [13:0] vram_addr,
    input  wire [7:0]  vram_data,

    // Pixel output
    output wire [3:0]  bg_pixel,   // {attr[1:0], pattern[1:0]}

    // V register output (for debug / future use)
    output wire [14:0] v_out
);

    // =================================================================
    // V register (current VRAM address / scroll position)
    //
    // Bit layout: yyy NN YYYYY XXXXX
    //   [14:12] = fine Y scroll (0-7)
    //   [11:10] = nametable select
    //   [9:5]   = coarse Y scroll (0-29)
    //   [4:0]   = coarse X scroll (0-31)
    // =================================================================
    reg [14:0] v;
    assign v_out = v;

    // =================================================================
    // Fetch timing
    // =================================================================
    wire fetching = rendering_en && render_line && (
        (cycle >= 1 && cycle <= 256) ||
        (cycle >= 321 && cycle <= 336)
    );

    // Phase within 8-cycle fetch group
    wire [2:0] fetch_phase = cycle[2:0] - 3'd1;

    // Load shift registers at end of each tile fetch (phase 7)
    wire load_sr = fetching && (fetch_phase == 3'd7);

    // =================================================================
    // Fetch latches
    // =================================================================
    reg [7:0] nt_latch;     // nametable byte (tile index)
    reg [1:0] at_latch;     // 2-bit palette from attribute byte
    reg [7:0] pt_lo_latch;  // pattern table low plane byte

    // Attribute quadrant selection from v register
    // v[1] = coarseX bit 1, v[6] = coarseY bit 1
    wire [1:0] at_quadrant = {v[6], v[1]};

    // =================================================================
    // VRAM address generation (combinational)
    // =================================================================
    // NT address: $2000 | (v & $0FFF)
    wire [13:0] nt_addr = {2'b10, v[11:0]};

    // AT address: $23C0 | (v & $0C00) | ((v>>4) & $38) | ((v>>2) & $07)
    wire [13:0] at_addr = {2'b10, v[11:10], 4'b1111, v[9:7], v[4:2]};

    // PT low address: pattern_base | (nt_byte << 4) | (0 << 3) | fine_y
    wire [13:0] pt_lo_addr = {1'b0, bg_pattern_base, nt_latch, 1'b0, v[14:12]};

    // PT high address: same but bit 3 = 1
    wire [13:0] pt_hi_addr = {1'b0, bg_pattern_base, nt_latch, 1'b1, v[14:12]};

    always @(*) begin
        if (fetching) begin
            case (fetch_phase)
                3'd0, 3'd1: vram_addr = nt_addr;
                3'd2, 3'd3: vram_addr = at_addr;
                3'd4, 3'd5: vram_addr = pt_lo_addr;
                3'd6, 3'd7: vram_addr = pt_hi_addr;
                default:    vram_addr = 14'd0;
            endcase
        end else begin
            vram_addr = 14'd0;
        end
    end

    // =================================================================
    // Data latching (on odd fetch phases, data available from BRAM)
    // =================================================================
    always @(posedge clk) begin
        if (rst) begin
            nt_latch    <= 8'd0;
            at_latch    <= 2'd0;
            pt_lo_latch <= 8'd0;
        end else if (fetching) begin
            case (fetch_phase)
                3'd1: nt_latch <= vram_data;
                3'd3: begin
                    // Extract 2-bit palette from attribute byte
                    case (at_quadrant)
                        2'b00: at_latch <= vram_data[1:0];
                        2'b01: at_latch <= vram_data[3:2];
                        2'b10: at_latch <= vram_data[5:4];
                        2'b11: at_latch <= vram_data[7:6];
                    endcase
                end
                3'd5: pt_lo_latch <= vram_data;
                default: ;
            endcase
        end
    end

    // =================================================================
    // Shift registers
    //
    // 16-bit shift registers: upper byte = current tile, lower = next
    // Shift left each cycle during fetching
    // At tile boundary (load_sr): load new data into lower byte
    //
    // Attribute shift registers: filled with replicated palette bits
    // Attribute latches feed in from the right during shifts
    // =================================================================
    reg [15:0] pat_sr_lo, pat_sr_hi;
    reg [15:0] attr_sr_lo, attr_sr_hi;
    reg        attr_feed_lo, attr_feed_hi;  // feed bits for shift-in

    always @(posedge clk) begin
        if (rst) begin
            pat_sr_lo   <= 16'd0;
            pat_sr_hi   <= 16'd0;
            attr_sr_lo  <= 16'd0;
            attr_sr_hi  <= 16'd0;
            attr_feed_lo <= 1'b0;
            attr_feed_hi <= 1'b0;
        end else if (fetching) begin
            if (load_sr) begin
                // Shift upper byte left, load new tile into lower byte
                pat_sr_lo  <= {pat_sr_lo[14:7],  pt_lo_latch};
                pat_sr_hi  <= {pat_sr_hi[14:7],  vram_data};  // PT high direct from bus
                attr_sr_lo <= {attr_sr_lo[14:7], {8{at_latch[0]}}};
                attr_sr_hi <= {attr_sr_hi[14:7], {8{at_latch[1]}}};
                attr_feed_lo <= at_latch[0];
                attr_feed_hi <= at_latch[1];
            end else begin
                // Normal shift left
                pat_sr_lo  <= {pat_sr_lo[14:0],  1'b0};
                pat_sr_hi  <= {pat_sr_hi[14:0],  1'b0};
                attr_sr_lo <= {attr_sr_lo[14:0], attr_feed_lo};
                attr_sr_hi <= {attr_sr_hi[14:0], attr_feed_hi};
            end
        end
    end

    // =================================================================
    // Pixel output (combinational mux selected by fine X scroll)
    // =================================================================
    wire [3:0] pixel_sel = 4'd15 - {1'b0, fine_x};

    wire pat_bit_lo  = pat_sr_lo[pixel_sel];
    wire pat_bit_hi  = pat_sr_hi[pixel_sel];
    wire attr_bit_lo = attr_sr_lo[pixel_sel];
    wire attr_bit_hi = attr_sr_hi[pixel_sel];

    assign bg_pixel = (rendering_en && visible_line && cycle >= 1 && cycle <= 256)
                      ? {attr_bit_hi, attr_bit_lo, pat_bit_hi, pat_bit_lo}
                      : 4'd0;

    // =================================================================
    // V register management
    // =================================================================

    always @(posedge clk) begin
        if (rst) begin
            v <= 15'd0;
        end else if (rendering_en && render_line) begin

            // --- Coarse X increment (at end of each tile fetch) ---
            if (load_sr) begin
                if (v[4:0] == 5'd31) begin
                    v[4:0] <= 5'd0;
                    v[10]  <= ~v[10]; // toggle horizontal nametable
                end else begin
                    v[4:0] <= v[4:0] + 5'd1;
                end
            end

            // --- Fine Y / Coarse Y increment (at cycle 256) ---
            if (cycle == 9'd256) begin
                if (v[14:12] != 3'd7) begin
                    v[14:12] <= v[14:12] + 3'd1;
                end else begin
                    v[14:12] <= 3'd0;
                    if (v[9:5] == 5'd29) begin
                        v[9:5] <= 5'd0;
                        v[11]  <= ~v[11]; // toggle vertical nametable
                    end else if (v[9:5] == 5'd31) begin
                        v[9:5] <= 5'd0;   // wrap without toggle (quirk)
                    end else begin
                        v[9:5] <= v[9:5] + 5'd1;
                    end
                end
            end

            // --- Horizontal copy from t (at cycle 257) ---
            // Overwrites coarse X and horizontal nametable bit
            if (cycle == 9'd257) begin
                v[4:0] <= t_reg[4:0];
                v[10]  <= t_reg[10];
            end

            // --- Vertical copy from t (pre-render line, cycles 280-304) ---
            if (pre_render_line && cycle >= 9'd280 && cycle <= 9'd304) begin
                v[14:12] <= t_reg[14:12];
                v[9:5]   <= t_reg[9:5];
                v[11]    <= t_reg[11];
            end
        end
    end

endmodule
