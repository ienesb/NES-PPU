`timescale 1ns / 1ps

// Testbench for PPU timing engine
// Verifies frame length, vblank timing, odd-frame skip, region signals

module tb_ppu_timing;

    reg  clk = 0;
    reg  rst = 1;
    reg  rendering_en = 1;

    wire [8:0] cycle;
    wire [8:0] scanline;
    wire visible_line, pre_render_line, render_line, vblank_line;
    wire visible_pixel, sprite_fetch, tile_prefetch, fetch_active;
    wire vblank_set, vblank_clr, frame_end;
    wire odd_frame;

    always #93 clk = ~clk;

    ppu_timing uut (
        .clk            (clk),
        .rst            (rst),
        .rendering_en   (rendering_en),
        .cycle          (cycle),
        .scanline       (scanline),
        .visible_line   (visible_line),
        .pre_render_line(pre_render_line),
        .render_line    (render_line),
        .vblank_line    (vblank_line),
        .visible_pixel  (visible_pixel),
        .sprite_fetch   (sprite_fetch),
        .tile_prefetch  (tile_prefetch),
        .fetch_active   (fetch_active),
        .vblank_set     (vblank_set),
        .vblank_clr     (vblank_clr),
        .frame_end      (frame_end),
        .odd_frame      (odd_frame)
    );

    integer errors = 0;
    integer clk_count;

    // Task: wait for next frame_end, return cycle count
    task wait_frame_end;
        output integer count;
        begin
            count = 0;
            begin : wfe
                forever begin
                    @(posedge clk); #1;
                    count = count + 1;
                    if (frame_end) disable wfe;
                end
            end
        end
    endtask

    integer visible_pixel_count;
    integer vblank_set_count;
    integer vblank_clr_count;
    integer sprite_fetch_count;
    integer tile_prefetch_count;
    integer even_count, odd_count;

    initial begin
        $dumpfile("tb_ppu_timing.vcd");
        $dumpvars(0, tb_ppu_timing);

        repeat (3) @(posedge clk);
        rst = 0;

        // ==========================================================
        // Sync: skip partial frame after reset
        // ==========================================================
        wait_frame_end(clk_count);
        $display("Skipped partial frame (%0d cycles), odd_frame=%0b", clk_count, odd_frame);

        // ==========================================================
        // Test 1 & 2: Measure two consecutive frames
        // One will be even (89342), one will be odd (89341)
        // ==========================================================
        wait_frame_end(even_count);
        $display("Test 1: Frame A = %0d cycles, odd_frame after = %0b", even_count, odd_frame);

        wait_frame_end(odd_count);
        $display("Test 2: Frame B = %0d cycles, odd_frame after = %0b", odd_count, odd_frame);

        // One should be 89342, the other 89341
        if ((even_count == 89342 && odd_count == 89341) ||
            (even_count == 89341 && odd_count == 89342)) begin
            $display("  Even/odd frame lengths correct");
        end else begin
            $display("  ERROR: Expected {89341, 89342}, got {%0d, %0d}", even_count, odd_count);
            errors = errors + 1;
        end

        // ==========================================================
        // Test 3: Rendering disabled - both frames should be 89342
        // ==========================================================
        $display("Test 3: Frames with rendering disabled");
        rendering_en = 0;

        wait_frame_end(clk_count);
        $display("  No-render frame 1: %0d (expected 89342)", clk_count);
        if (clk_count != 89342) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        wait_frame_end(clk_count);
        $display("  No-render frame 2: %0d (expected 89342)", clk_count);
        if (clk_count != 89342) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        rendering_en = 1;

        // ==========================================================
        // Test 4: Count events per frame
        // ==========================================================
        $display("Test 4: Event counts per frame");

        // Sync to frame boundary
        wait_frame_end(clk_count);

        visible_pixel_count = 0;
        vblank_set_count    = 0;
        vblank_clr_count    = 0;
        sprite_fetch_count  = 0;
        tile_prefetch_count = 0;

        begin : count_events
            forever begin
                @(posedge clk); #1;
                if (visible_pixel)  visible_pixel_count  = visible_pixel_count + 1;
                if (vblank_set)     vblank_set_count     = vblank_set_count + 1;
                if (vblank_clr)     vblank_clr_count     = vblank_clr_count + 1;
                if (sprite_fetch)   sprite_fetch_count   = sprite_fetch_count + 1;
                if (tile_prefetch)  tile_prefetch_count  = tile_prefetch_count + 1;
                if (frame_end)      disable count_events;
            end
        end

        $display("  Visible pixels: %0d (expected 61440)", visible_pixel_count);
        if (visible_pixel_count != 61440) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        $display("  Sprite fetch cycles: %0d (expected 15424)", sprite_fetch_count);
        if (sprite_fetch_count != 15424) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        $display("  Tile prefetch cycles: %0d (expected 3856)", tile_prefetch_count);
        if (tile_prefetch_count != 3856) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        $display("  Vblank set: %0d, clear: %0d (expected 1, 1)",
                 vblank_set_count, vblank_clr_count);
        if (vblank_set_count != 1 || vblank_clr_count != 1) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        // ==========================================================
        // Test 5: Vblank set at scanline 241, cycle 1
        // ==========================================================
        $display("Test 5: Vblank set timing");

        begin : wait_vblank
            forever begin
                @(posedge clk); #1;
                if (vblank_set) disable wait_vblank;
            end
        end

        $display("  Vblank set at scanline=%0d, cycle=%0d (expected 241, 1)",
                 scanline, cycle);
        if (scanline != 241 || cycle != 1) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        // ==========================================================
        // Test 6: Vblank clear at scanline 261, cycle 1
        // ==========================================================
        $display("Test 6: Vblank clear timing");

        begin : wait_vblank_clr
            forever begin
                @(posedge clk); #1;
                if (vblank_clr) disable wait_vblank_clr;
            end
        end

        $display("  Vblank clear at scanline=%0d, cycle=%0d (expected 261, 1)",
                 scanline, cycle);
        if (scanline != 261 || cycle != 1) begin
            $display("  ERROR!"); errors = errors + 1;
        end

        // ==========================================================
        // Summary
        // ==========================================================
        $display("");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

    initial begin
        #500_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
