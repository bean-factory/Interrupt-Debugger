// SPDX-License-Identifier: GPL-3.0-or-later
// The integrated Zet path did not meet 50 MHz. Use a DCM-derived 12.5 MHz clock.
`timescale 1ns/1ps
module hosted_clocking (
    input wire clk_50, reset_btn,
    output wire clk, reset
);
    wire feedback_raw, feedback, divided_raw, locked;
    DCM_SP #(.CLKDV_DIVIDE(4.0), .CLKIN_PERIOD(20.0), .CLK_FEEDBACK("1X"),
             .STARTUP_WAIT("FALSE")) divider (
        .CLKIN(clk_50), .CLKFB(feedback), .RST(reset_btn), .DSSEN(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0),
        .CLK0(feedback_raw), .CLKDV(divided_raw), .LOCKED(locked)
    );
    BUFG feedback_buffer(.I(feedback_raw), .O(feedback));
    BUFG system_buffer(.I(divided_raw), .O(clk));
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] reset_sync;
    wire asynchronous_reset=reset_btn || !locked;
    always @(posedge clk or posedge asynchronous_reset)
        if(asynchronous_reset) reset_sync<=2'b11;
        else reset_sync<={reset_sync[0],1'b0};
    assign reset=reset_sync[1];
endmodule
