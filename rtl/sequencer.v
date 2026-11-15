`timescale 1ns/1ps
module sequencer #(parameter integer FIRST_TICKS = 500,
                   parameter integer SECOND_TICKS = 4000)(
    input wire clk, input wire reset, input wire clear, input wire start,
    input wire simultaneous, output reg ir1, output reg ir3);
    reg running, both;
    reg [31:0] ticks;
    always @(posedge clk) begin
        if (reset || clear) begin
            ir1 <= 0; ir3 <= 0; ticks <= 0; running <= 0; both <= 0;
        end else if (start && !ir1 && !ir3 && !running) begin
            running <= 1; ticks <= 0; both <= simultaneous;
        end else if (running) begin
            ticks <= ticks + 1;
            if (ticks == FIRST_TICKS-1) begin
                ir1 <= 1;
                if (both) begin ir3 <= 1; running <= 0; end
            end
            if (ticks == SECOND_TICKS-1) begin ir3 <= 1; running <= 0; end
        end
    end
endmodule
