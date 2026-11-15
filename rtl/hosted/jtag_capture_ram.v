// SPDX-License-Identifier: GPL-3.0-or-later
// Freeze-before-read dual-clock RAM. JTAG never reads a buffer being written.
`timescale 1ns/1ps
module jtag_capture_ram #(
    parameter integer ADDR_WIDTH=13, SAMPLE_COUNT=8192, SAMPLE_DIV=1
)(
    input wire clk, reset, clear, start,
    input wire [21:0] probes,
    input wire read_clock,
    input wire [ADDR_WIDTH-1:0] read_address,
    output wire [31:0] read_data,
    output reg busy, done
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [21:0] input_meta, input_sync;
    (* ram_style="block" *) reg [21:0] memory [0:SAMPLE_COUNT-1];
    reg [21:0] read_word;
    reg [ADDR_WIDTH-1:0] write_address;
    reg [31:0] divider;
    always @(posedge clk) begin
        if(reset) begin input_meta<=0; input_sync<=0; end
        else begin input_meta<=probes; input_sync<=input_meta; end
    end
    always @(posedge read_clock) read_word<=memory[read_address];
    assign read_data={10'b0,read_word};
    always @(posedge clk)
        if(busy && divider==SAMPLE_DIV-1 && !reset && !clear)
            memory[write_address]<=input_sync;
    always @(posedge clk) begin
        done<=0;
        if(reset || clear) begin busy<=0; write_address<=0; divider<=0; end
        else if(start && !busy) begin busy<=1; write_address<=0; divider<=0; end
        else if(busy) begin
            if(divider==SAMPLE_DIV-1) begin
                divider<=0;
                if(write_address==SAMPLE_COUNT-1) begin busy<=0; done<=1; end
                else write_address<=write_address+1'b1;
            end else divider<=divider+1'b1;
        end
    end
endmodule
