// SPDX-License-Identifier: GPL-3.0-or-later
// Testable system below the device-specific BSCAN primitive.
`timescale 1ns/1ps
module fpga_jtag_system #(
    parameter integer ADDR_WIDTH=13, SAMPLE_COUNT=8192, SAMPLE_DIV=1,
    parameter integer FIRST_TICKS=125, SECOND_TICKS=1000,
    parameter integer CLOCK_HZ=12500000,
    parameter integer READ_OK_TICKS=CLOCK_HZ*2
)(
    input wire clk, reset,
    input wire tap_reset, capture, shift, update, select_control, select_data,
    input wire drck_control, drck_data, tdi,
    output wire tdo_control, tdo_data,
    output wire busy_led, ready_led,
    input wire board_enabled, board_start,
    input wire [1:0] board_mode,
    output wire [1:0] display_mode,
    output wire [2:0] display_state,
    input wire board_simultaneous,
    output wire display_simultaneous
);
    wire command_valid;
    wire [7:0] command;
    wire [ADDR_WIDTH-1:0] read_address;
    wire [31:0] read_data;
    wire [21:0] probes;
    wire [19:0] debug_pc;
    wire [31:0] debug_bus;
    wire [15:0] debug_progress;
    reg [95:0] diagnostics;
    wire marker_valid;
    wire [7:0] marker;
    wire cpu_ready, ir1, ir3, capture_busy, capture_done;
    reg running, issued, simultaneous, frozen;
    reg [1:0] selected_scenario, active_scenario;
    reg capture_start;
    reg board_origin, manual_pending, readout_lock, capture_read;
    reg [31:0] read_notice_ticks;
    wire host_clear=command_valid && command==8'h52;
    wire lock_command=command_valid && command==8'h4c;
    wire manual_go=board_enabled && board_start && !capture_busy && !manual_pending && !readout_lock && !lock_command;
    wire clear=host_clear || manual_go;
    wire sequence_go=running && cpu_ready && !issued;
    wire [31:0] flags=simultaneous ? 32'd8 : 32'd0;
    wire [31:0] status={16'h4953,4'h3,active_scenario,simultaneous,1'b0,
                       readout_lock,board_origin,board_enabled,1'b1,
                       (ir1|ir3),cpu_ready,frozen,capture_busy};
    // After confirmed read + notice, show the next selection while preserving
    // frozen data for an optional reread. Only NORTH starts a new capture.
    wire read_notice=read_notice_ticks!=0;
    wire display_active=manual_pending || capture_busy || (running && !frozen) ||
                        (frozen && (!cpu_ready || !capture_read || read_notice || readout_lock));
    assign display_mode=display_active ? active_scenario : board_mode;
    assign display_simultaneous=display_active ? simultaneous : board_simultaneous;
    assign display_state=readout_lock ? 3'd3 : (capture_busy || manual_pending || (running && !frozen)) ? 3'd1 :
                          frozen ? (!cpu_ready ? 3'd4 : capture_read ? (read_notice ? 3'd5 : 3'd0) : 3'd2) : 3'd0;

    hosted_soc system(clk,reset|!running,active_scenario,
        {4'b0000,ir3,1'b0,ir1,1'b0},probes,debug_pc,cpu_ready,marker_valid,marker,
        debug_bus,debug_progress);
    sequencer #(.FIRST_TICKS(FIRST_TICKS),.SECOND_TICKS(SECOND_TICKS)) stimulus(
        clk,reset,clear,sequence_go,simultaneous,ir1,ir3);
    jtag_capture_ram #(.ADDR_WIDTH(ADDR_WIDTH),.SAMPLE_COUNT(SAMPLE_COUNT),.SAMPLE_DIV(SAMPLE_DIV)) recorder(
        clk,reset,clear,capture_start,probes,drck_data,read_address,read_data,capture_busy,capture_done);
    jtag_link #(.ADDR_WIDTH(ADDR_WIDTH),.SAMPLE_COUNT(SAMPLE_COUNT),.SAMPLE_RATE(CLOCK_HZ/SAMPLE_DIV)) link(
        clk,reset,tap_reset,capture,shift,update,select_control,select_data,
        drck_control,drck_data,tdi,tdo_control,tdo_data,status,flags,
        command_valid,command,read_address,read_data,diagnostics);

    always @(posedge clk) begin
        capture_start<=0;
        if(reset) begin
            running<=0; issued<=0; simultaneous<=0; frozen<=0;
            selected_scenario<=0; active_scenario<=0;
            diagnostics<=0;
            board_origin<=0; manual_pending<=0; readout_lock<=0; capture_read<=0;
            read_notice_ticks<=0;
        end else if(host_clear) begin
            running<=0; issued<=0; frozen<=0; diagnostics<=0;
            board_origin<=0; manual_pending<=0; readout_lock<=0; capture_read<=0;
            read_notice_ticks<=0;
        end
        else if(manual_go) begin
            running<=0; issued<=0; frozen<=0; diagnostics<=0;
            active_scenario<=board_mode;
            simultaneous<=board_simultaneous; board_origin<=1; manual_pending<=1; capture_read<=0;
            read_notice_ticks<=0;
        end else if(manual_pending) begin
            // Give the core a complete reset edge before starting the new boot.
            running<=1; capture_start<=1; manual_pending<=0;
            if(lock_command) readout_lock<=1;
        end
        else begin
            if(lock_command) readout_lock<=1;
            else if(command_valid && command==8'h55) readout_lock<=0;
            if(read_notice && !readout_lock) read_notice_ticks<=read_notice_ticks-1'b1;
            if(command_valid && command==8'h44 && frozen && readout_lock && board_origin) begin
                capture_read<=1;
                read_notice_ticks<=READ_OK_TICKS;
            end
            if(capture_done) begin
                frozen<=1;
                // Stable until reset/clear. Extended USER1 snapshots do not
                // change IRQ2 waveforms or substitute inferred CPU activity.
                diagnostics<={debug_bus,8'b0,issued,running,cpu_ready,1'b1,debug_pc,
                              16'hd149,debug_progress};
            end
            if(sequence_go) issued<=1;
            if(command_valid && !capture_busy) begin
                case(command)
                    8'h4e: if(!running && !board_enabled) selected_scenario<=0;
                    8'h41: if(!running && !board_enabled) selected_scenario<=1;
                    8'h4d: if(!running && !board_enabled) selected_scenario<=2;
                    8'h46: if(!running && !board_enabled) selected_scenario<=3;
                    8'h43,8'h50: if(!running && !frozen && !board_enabled && !readout_lock) begin
                        active_scenario<=selected_scenario;
                        simultaneous<=command==8'h50;
                        running<=1; issued<=0; capture_start<=1; board_origin<=0; capture_read<=0;
                        read_notice_ticks<=0;
                    end
                    default: begin end
                endcase
            end
        end
    end
    assign busy_led=capture_busy;
    assign ready_led=frozen;
endmodule
