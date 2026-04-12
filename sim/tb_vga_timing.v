`timescale 1ns / 1ps

// Testbench for VGA timing generator
// Verifies 640x480 @ 60Hz timing parameters

module tb_vga_timing;

    reg        clk = 0;
    reg        rst = 1;
    wire       hsync;
    wire       vsync;
    wire       video_active;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;

    // 25 MHz clock -> 40 ns period
    always #20 clk = ~clk;

    vga_timing uut (
        .clk          (clk),
        .rst          (rst),
        .hsync        (hsync),
        .vsync        (vsync),
        .video_active (video_active),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y)
    );

    // Measurement counters
    integer h_total_count;
    integer h_active_count;
    integer h_sync_count;
    integer v_total_count;
    integer v_active_count;
    integer v_sync_count;
    integer frame_pixel_count;
    integer errors;

    reg hsync_prev, vsync_prev;

    initial begin
        $dumpfile("tb_vga_timing.vcd");
        $dumpvars(0, tb_vga_timing);

        errors = 0;

        // Release reset after a few clocks
        repeat (5) @(posedge clk);
        rst = 0;

        // =====================================================
        // Test 1: Measure horizontal line length
        // Wait for start of a line (h_count wraps)
        // =====================================================
        @(posedge clk);
        // Wait until we see pixel_x == 0
        wait (pixel_x == 0);
        @(posedge clk);
        // Now count clocks until pixel_x == 0 again
        h_total_count = 0;
        begin : h_line_measure
            forever begin
                @(posedge clk);
                h_total_count = h_total_count + 1;
                if (pixel_x == 0 && h_total_count > 1)
                    disable h_line_measure;
            end
        end

        $display("H total clocks per line: %0d (expected 800)", h_total_count);
        if (h_total_count != 800) begin
            $display("ERROR: Horizontal total mismatch!");
            errors = errors + 1;
        end

        // =====================================================
        // Test 2: Count active pixels per line
        // =====================================================
        // Wait for start of visible area
        wait (pixel_x == 0 && pixel_y == 0);
        @(posedge clk);
        h_active_count = 0;
        h_sync_count = 0;
        begin : h_active_measure
            integer i;
            for (i = 0; i < 800; i = i + 1) begin
                @(posedge clk);
                if (video_active) h_active_count = h_active_count + 1;
                if (~hsync)       h_sync_count   = h_sync_count + 1;
            end
        end

        $display("H active pixels per line: %0d (expected 640)", h_active_count);
        if (h_active_count != 640) begin
            $display("ERROR: Horizontal active mismatch!");
            errors = errors + 1;
        end

        $display("H sync clocks per line: %0d (expected 96)", h_sync_count);
        if (h_sync_count != 96) begin
            $display("ERROR: Horizontal sync width mismatch!");
            errors = errors + 1;
        end

        // =====================================================
        // Test 3: Measure full frame (count lines)
        // =====================================================
        // Wait for vsync falling edge (start of vsync pulse)
        wait (vsync == 1);
        wait (vsync == 0);

        v_total_count = 0;
        v_active_count = 0;
        v_sync_count = 0;
        frame_pixel_count = 0;

        begin : frame_measure
            // Count complete lines until next vsync falling edge
            reg seen_vsync_end;
            seen_vsync_end = 0;
            forever begin
                @(posedge clk);
                if (pixel_x == 0) begin
                    // Detect vsync state per line
                    if (~vsync) v_sync_count = v_sync_count + 1;
                end
                if (h_total_count > 0 && pixel_x == 799) begin
                    v_total_count = v_total_count + 1;
                end
                if (video_active) begin
                    v_active_count = v_active_count + 1;
                    frame_pixel_count = frame_pixel_count + 1;
                end
                // Wait for vsync to go high (end of pulse)
                if (vsync && ~seen_vsync_end && v_total_count > 10)
                    seen_vsync_end = 1;
                // Then wait for next vsync falling edge
                if (seen_vsync_end && ~vsync && v_total_count > 100)
                    disable frame_measure;
            end
        end

        $display("V total lines per frame: %0d (expected 525)", v_total_count);
        if (v_total_count != 525) begin
            $display("ERROR: Vertical total mismatch!");
            errors = errors + 1;
        end

        $display("V sync lines: %0d (expected 2)", v_sync_count);
        // Note: v_sync_count counts lines where vsync is low at pixel_x==0

        $display("Total active pixels per frame: %0d (expected %0d)",
                 frame_pixel_count, 640 * 480);
        if (frame_pixel_count != 640 * 480) begin
            $display("ERROR: Total active pixel count mismatch!");
            errors = errors + 1;
        end

        // =====================================================
        // Test 4: Verify pixel coordinates during active area
        // =====================================================
        wait (pixel_x == 0 && pixel_y == 0);
        @(posedge clk); #1; // let NBA resolve
        // Check first few pixels
        if (pixel_x != 1 || pixel_y != 0) begin
            $display("ERROR: Pixel coordinates wrong at start!");
            errors = errors + 1;
        end

        // =====================================================
        // Summary
        // =====================================================
        $display("");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #100_000_000; // 100 ms
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
