// SPDX-License-Identifier: GPL-3.0-or-later
// SW3 arms board control; SW2 selects timing; SW1:SW0 select firmware.
// Inputs settle for 10 ms. A held/bouncing START cannot retrigger an experiment.
`timescale 1ns/1ps
module board_controls #(
    parameter integer DEBOUNCE_TICKS=125000
)(
    input wire clk, reset,
    input wire [3:0] switches,
    input wire start_button,
    output wire enabled,
    output wire [1:0] mode,
    output reg start,
    output wire simultaneous
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [4:0] input_meta, input_sync;
    reg [4:0] candidate, stable;
    reg [31:0] ticks;
    reg released;
    assign enabled=stable[3];
    assign simultaneous=stable[2];
    assign mode=stable[1:0];
    always @(posedge clk) begin
        start<=0;
        if(reset) begin
            input_meta<=0; input_sync<=0; candidate<=0; stable<=0;
            ticks<=0; released<=0;
        end else begin
            input_meta<={start_button,switches};
            input_sync<=input_meta;
            if(input_sync!=candidate) begin candidate<=input_sync; ticks<=0; end
            else if(ticks<DEBOUNCE_TICKS) begin
                ticks<=ticks+1'b1;
                if(ticks==DEBOUNCE_TICKS-1) begin
                    stable<=candidate;
                    if(!candidate[4]) released<=1;
                    else if(released) begin start<=candidate[3]; released<=0; end
                end
            end
        end
    end
endmodule
