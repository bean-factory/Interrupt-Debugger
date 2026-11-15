// SPDX-License-Identifier: GPL-3.0-or-later
// UG257 16x2 LCD, write-only 4-bit interface. Never read the 5 V LCD bus.
// SF_CE0 is held high to disable the StrataFlash device sharing SF_D[11:8].
`timescale 1ns/1ps
module lcd_status #(
    parameter integer CLOCK_HZ=12500000,
    parameter integer POWER_WAIT_US=40000,
    parameter integer REFRESH_US=100000
)(
    input wire clk, reset, board_enabled,
    input wire [1:0] mode,
    input wire [2:0] status,
    input wire simultaneous,
    output reg [3:0] data,
    output reg enable, register_select,
    output wire read_write, flash_disable
);
    localparam integer US_TICKS=(CLOCK_HZ+999999)/1000000;
    localparam SCHEDULE=0, SETUP=1, HIGH=2, LOW=3, GAP=4;
    reg [2:0] state;
    reg [31:0] divider, wait_us, byte_delay;
    reg [3:0] initialization;
    reg [5:0] position;
    reg [7:0] byte_value;
    reg second_nibble, single_nibble;
    reg [127:0] line1, line2;
    assign read_write=1'b0;
    assign flash_disable=1'b1;

    function [127:0] mode_text;
        input [1:0] selected;
        input together;
        reg [95:0] condition_text;
        begin
            case(selected)
                0: condition_text="Normal      ";
                1: condition_text="IRQ1 masked ";
                2: condition_text="IRQ3 masked ";
                3: condition_text="No IRQ1 EOI ";
            endcase
            mode_text={condition_text, " ", together ? "SIM" : "SEQ"};
        end
    endfunction
    function [127:0] state_text;
        input physical;
        input [2:0] current;
        begin
            case(current)
                1: state_text="Capturing...    ";
                2: state_text="Done: read GUI  ";
                3: state_text="Reading to GUI  ";
                4: state_text="CPU startup fail";
                5: state_text="Read OK         ";
                default: state_text=physical ? "Idle: push NORTH" : "Disarmed: SW3 ON";
            endcase
        end
    endfunction
    task send_byte;
        input [7:0] value;
        input rs, single;
        input [31:0] delay_us;
        begin
            byte_value<=value; register_select<=rs; single_nibble<=single;
            second_nibble<=0; data<=single ? value[3:0] : value[7:4];
            enable<=0; byte_delay<=delay_us; state<=SETUP;
        end
    endtask
    always @(posedge clk) begin
        if(reset) begin
            divider<=0; wait_us<=POWER_WAIT_US; state<=GAP;
            initialization<=0; position<=0; byte_value<=0;
            second_nibble<=0; single_nibble<=0; byte_delay<=0;
            enable<=0; register_select<=0; data<=0; line1<=0; line2<=0;
        end else if(divider==US_TICKS-1) begin
            divider<=0;
            case(state)
                GAP: if(wait_us!=0) wait_us<=wait_us-1'b1; else state<=SCHEDULE;
                SCHEDULE: begin
                    if(initialization<9) begin
                        initialization<=initialization+1'b1;
                        case(initialization)
                            0: send_byte(8'h03,0,1,5000);
                            1,2: send_byte(8'h03,0,1,200);
                            3: send_byte(8'h02,0,1,200);
                            4: send_byte(8'h28,0,0,50);
                            5: send_byte(8'h08,0,0,50);
                            6: send_byte(8'h01,0,0,2000);
                            7: send_byte(8'h06,0,0,50);
                            8: send_byte(8'h0c,0,0,50);
                        endcase
                    end else if(position==34) begin
                        position<=0; wait_us<=REFRESH_US; state<=GAP;
                    end else begin
                        position<=position+1'b1;
                        if(position==0) begin
                            line1<=mode_text(mode,simultaneous); line2<=state_text(board_enabled,status);
                            send_byte(8'h80,0,0,50);
                        end else if(position==17) send_byte(8'hc0,0,0,50);
                        else if(position<17) send_byte(line1 >> ((16-position)*8),1,0,50);
                        else send_byte(line2 >> ((33-position)*8),1,0,50);
                    end
                end
                SETUP: begin enable<=1; state<=HIGH; end
                HIGH: begin enable<=0; state<=LOW; end
                LOW: if(single_nibble || second_nibble) begin wait_us<=byte_delay; state<=GAP; end
                     else begin data<=byte_value[3:0]; second_nibble<=1; state<=SETUP; end
                default: begin enable<=0; state<=GAP; wait_us<=POWER_WAIT_US; initialization<=0; end
            endcase
        end else divider<=divider+1'b1;
    end
endmodule
