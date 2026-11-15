// SPDX-License-Identifier: GPL-3.0-or-later
// Portable replacement for Zet's Altera-specific registered multiplier.
module zet_signmul17 (
    input wire clk,
    input wire signed [16:0] a,
    input wire signed [16:0] b,
    output reg signed [33:0] p
);
    always @(posedge clk) p <= a * b;
endmodule
