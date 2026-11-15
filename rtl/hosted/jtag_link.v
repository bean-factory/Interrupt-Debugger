// SPDX-License-Identifier: GPL-3.0-or-later
// USER1: 32-bit command/status mailbox. USER2: complete IRQ2 packet, LSB first.
`timescale 1ns/1ps
module jtag_link #(
    parameter integer ADDR_WIDTH=13, SAMPLE_COUNT=8192, SAMPLE_RATE=50000000
)(
    input wire clk, reset,
    input wire tap_reset, capture, shift, update, select_control, select_data,
    input wire drck_control, drck_data, tdi,
    output wire tdo_control, tdo_data,
    input wire [31:0] status, packet_flags,
    output reg command_valid,
    output reg [7:0] command,
    output wire [ADDR_WIDTH-1:0] read_address,
    input wire [31:0] read_data,
    input wire [95:0] diagnostics
);
    reg [127:0] control_shift;
    reg [31:0] command_shift;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [31:0] status_meta, status_sync;
    reg [7:0] source_command;
    reg source_toggle;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg toggle_meta, toggle_sync, toggle_ready;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [7:0] command_meta, command_sync;
    reg seen_toggle;
    reg [2:0] startup;
    wire [31:0] acknowledged_status=(status & 32'hfffffeff) | (seen_toggle ? 32'h00000100 : 0);
    assign tdo_control=control_shift[0];

    always @(posedge drck_control or posedge tap_reset) begin
        if(tap_reset) begin status_meta<=0; status_sync<=0; control_shift<=0; command_shift<=0; end
        else begin
            status_meta<=acknowledged_status;
            status_sync<=status_meta;
            if(capture && select_control) begin
                control_shift<={diagnostics,status_sync}; command_shift<=0;
            end else if(shift && select_control) begin
                control_shift<={tdi,control_shift[127:1]};
                command_shift<={tdi,command_shift[31:1]};
            end
        end
    end

    function supported_command;
        input [7:0] value;
        begin
            supported_command=(value==8'h52 || value==8'h4e || value==8'h4d ||
                               value==8'h46 || value==8'h43 || value==8'h50 ||
                               value==8'h4c || value==8'h55 || value==8'h41 || value==8'h44);
        end
    endfunction
    // UPDATE is a BSCAN-provided clock event; DRCK is inactive in Update-DR.
    // The host waits for the acknowledged toggle before publishing another byte.
    always @(posedge update or posedge tap_reset) begin
        if(tap_reset) begin source_command<=0; source_toggle<=0; end
        else if(select_control && supported_command(command_shift[7:0])) begin
            source_command<=command_shift[7:0];
            source_toggle<=!source_toggle;
        end
    end
    always @(posedge clk) begin
        command_valid<=0;
        if(reset) begin
            toggle_meta<=0; toggle_sync<=0; toggle_ready<=0; command_meta<=0; command_sync<=0;
            command<=0; seen_toggle<=0; startup<=0;
        end else begin
            toggle_meta<=source_toggle;
            toggle_sync<=toggle_meta;
            toggle_ready<=toggle_sync;
            command_meta<=source_command;
            command_sync<=command_meta;
            // One event stage beyond the data synchronizer gives the bundled
            // command byte a settling cycle before it is consumed.
            if(startup<4) begin startup<=startup+1'b1; seen_toggle<=toggle_ready; end
            else if(toggle_ready!=seen_toggle) begin
                seen_toggle<=toggle_ready;
                if(supported_command(command_sync)) begin command<=command_sync; command_valid<=1; end
            end
        end
    end

    reg [ADDR_WIDTH:0] frame_word;
    reg [4:0] bit_index;
    reg [ADDR_WIDTH-1:0] address;
    reg [31:0] flags_latched;
    reg [15:0] crc;
    reg [31:0] output_word;
    wire [7:0] output_byte=output_word >> {bit_index[4:3],3'b000};
    assign read_address=(capture && select_data) ? {ADDR_WIDTH{1'b0}} : address;
    assign tdo_data=output_word[bit_index];
    always @* begin
        case(frame_word)
            0: output_word=32'h32515249;
            1: output_word=SAMPLE_COUNT;
            2: output_word=SAMPLE_RATE;
            3: output_word=flags_latched;
            default: if(frame_word < SAMPLE_COUNT+4) output_word=read_data;
                     else output_word={16'h0000,crc[7:0],crc[15:8]};
        endcase
    end
    function [15:0] crc_byte;
        input [15:0] previous;
        input [7:0] value;
        reg [15:0] c;
        integer bit_number;
        begin
            c=previous ^ {value,8'h00};
            for(bit_number=0;bit_number<8;bit_number=bit_number+1)
                c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction
    always @(posedge drck_data or posedge tap_reset) begin
        if(tap_reset) begin frame_word<=0; bit_index<=0; address<=0; flags_latched<=0; crc<=16'hffff; end
        else if(capture && select_data) begin
            frame_word<=0; bit_index<=0; address<=0; crc<=16'hffff;
            flags_latched<=packet_flags;
        end else if(shift && select_data) begin
            if(bit_index[2:0]==7 && frame_word<SAMPLE_COUNT+4)
                crc<=crc_byte(crc,output_byte);
            // Prefetch one edge before the final bit. The old word's bit 31 is
            // sampled before the RAM output changes to the next word.
            if(frame_word>=4 && frame_word<SAMPLE_COUNT+3 && bit_index==30)
                address<=address+1'b1;
            if(bit_index==31) begin bit_index<=0; frame_word<=frame_word+1'b1; end
            else bit_index<=bit_index+1'b1;
        end
    end
endmodule
