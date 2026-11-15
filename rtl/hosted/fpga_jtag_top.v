// SPDX-License-Identifier: GPL-3.0-or-later
// Programming and capture readout share the existing USB-JTAG cable.
`timescale 1ns/1ps
module fpga_jtag_top #(
    parameter integer DEBOUNCE_TICKS=125000
)(
    input wire clk_50, reset_btn,
    output wire busy_led, ready_led,
    input wire [3:0] board_switches,
    input wire start_button,
    output wire [3:0] lcd_data,
    output wire lcd_enable, lcd_rs, lcd_rw, flash_disable,
    output wire lcd_return
);
    wire clk, reset;
    wire tap_reset, capture, shift, update, select_control, select_data, tdi;
    wire control_raw, data_raw, drck_control, drck_data;
    wire tdo_control, tdo_data;
    wire board_enabled, board_start, board_simultaneous, display_simultaneous;
    wire [1:0] board_mode, display_mode;
    wire [2:0] display_state;
    // LCD header pin 3 (V0/return) must not float. UG257 assigns E3.
    assign lcd_return=1'b0;
    hosted_clocking clocks(clk_50,reset_btn,clk,reset);
    board_controls #(.DEBOUNCE_TICKS(DEBOUNCE_TICKS)) controls(
        clk,reset,board_switches,start_button,board_enabled,board_mode,board_start,board_simultaneous);
    lcd_status display(clk,reset,board_enabled,display_mode,display_state,display_simultaneous,
        lcd_data,lcd_enable,lcd_rs,lcd_rw,flash_disable);
    BSCAN_SPARTAN3 scan(
        .CAPTURE(capture), .DRCK1(control_raw), .DRCK2(data_raw),
        .RESET(tap_reset), .SEL1(select_control), .SEL2(select_data),
        .SHIFT(shift), .TDI(tdi), .UPDATE(update),
        .TDO1(tdo_control), .TDO2(tdo_data)
    );
    BUFG control_buffer(.I(control_raw),.O(drck_control));
    BUFG data_buffer(.I(data_raw),.O(drck_data));
    fpga_jtag_system system(
        clk,reset,tap_reset,capture,shift,update,select_control,select_data,
        drck_control,drck_data,tdi,tdo_control,tdo_data,busy_led,ready_led,
        board_enabled,board_start,board_mode,display_mode,display_state,board_simultaneous,display_simultaneous);
endmodule
