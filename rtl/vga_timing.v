`timescale 1ns / 1ps

// VGA 640x480 @ 60Hz Sync Generator
// Pixel clock: 25.175 MHz (25.0 MHz acceptable)
//
// Horizontal timing (in pixel clocks):
//   Visible:     640
//   Front porch:  16
//   Sync pulse:   96 (active low)
//   Back porch:   48
//   Total:       800
//
// Vertical timing (in lines):
//   Visible:     480
//   Front porch:  10
//   Sync pulse:    2 (active low)
//   Back porch:   33
//   Total:       525

module vga_timing (
    input  wire        clk,        // 25 MHz pixel clock
    input  wire        rst,        // synchronous reset, active high
    output wire        hsync,      // horizontal sync (active low)
    output wire        vsync,      // vertical sync (active low)
    output wire        video_active, // high during visible area
    output wire [9:0]  pixel_x,    // horizontal pixel coordinate (0-639)
    output wire [9:0]  pixel_y     // vertical pixel coordinate (0-479)
);

    // Horizontal timing parameters
    localparam H_VISIBLE    = 640;
    localparam H_FRONT      = 16;
    localparam H_SYNC       = 96;
    localparam H_BACK       = 48;
    localparam H_TOTAL      = 800;  // H_VISIBLE + H_FRONT + H_SYNC + H_BACK

    // Vertical timing parameters
    localparam V_VISIBLE    = 480;
    localparam V_FRONT      = 10;
    localparam V_SYNC       = 2;
    localparam V_BACK       = 33;
    localparam V_TOTAL      = 525;  // V_VISIBLE + V_FRONT + V_SYNC + V_BACK

    // Counters
    reg [9:0] h_count = 0;
    reg [9:0] v_count = 0;

    // Horizontal counter
    always @(posedge clk) begin
        if (rst) begin
            h_count <= 0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 0;
        end else begin
            h_count <= h_count + 1;
        end
    end

    // Vertical counter
    always @(posedge clk) begin
        if (rst) begin
            v_count <= 0;
        end else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)
                v_count <= 0;
            else
                v_count <= v_count + 1;
        end
    end

    // Sync signals (active low)
    // hsync asserted during h_count [H_VISIBLE + H_FRONT, H_VISIBLE + H_FRONT + H_SYNC)
    assign hsync = ~((h_count >= H_VISIBLE + H_FRONT) &&
                     (h_count <  H_VISIBLE + H_FRONT + H_SYNC));

    assign vsync = ~((v_count >= V_VISIBLE + V_FRONT) &&
                     (v_count <  V_VISIBLE + V_FRONT + V_SYNC));

    // Video active when both counters are in visible region
    assign video_active = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    // Pixel coordinates (valid only when video_active is high)
    assign pixel_x = h_count;
    assign pixel_y = v_count;

endmodule
