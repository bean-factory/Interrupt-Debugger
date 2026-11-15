// SPDX-License-Identifier: GPL-3.0-or-later
// Zet + KF8259 integration. No external CPU, PIC or DDR controller is required.
`timescale 1ns/1ps
module hosted_soc #(
    parameter integer BUS_TICKS = 12,
    parameter integer ACK_TICKS = 12,
    parameter integer ACK_GAP = 8
)(
    input wire clk,
    input wire reset,
    input wire [1:0] scenario,
    input wire [7:0] requests,
    output wire [21:0] probes,
    output wire [19:0] pc,
    output reg ready,
    output reg marker_valid,
    output reg [7:0] marker,
    output wire [31:0] debug_bus,
    output reg [15:0] debug_progress
);
    wire [19:0] cpu_address;
    wire [15:0] cpu_write_data, cpu_read_data;
    wire [15:0] iid_data;
    wire cpu_byte, cpu_memop, cpu_io, cpu_write, cpu_inta;
    wire bus_block, cpu_block;
    wire [19:1] wb_address;
    wire [15:0] wb_write_data;
    reg [15:0] wb_read_data;
    wire [1:0] wb_select;
    wire wb_write, wb_io, wb_strobe, wb_cycle;
    reg wb_ack;
    wire unused_nmia;

    // Zet exposes a one-cycle interrupt acceptance indication, not pin-level
    // 8086 bus cycles. The adapter stalls its vector-fetch microstep while it
    // performs two actual acknowledge pulses against the PIC.
    reg [2:0] irq_state;
    reg [7:0] irq_ticks;
    reg [7:0] vector_latch;
    reg acknowledge_n;
    localparam IRQ_IDLE=0, IRQ_FIRST=1, IRQ_GAP_STATE=2, IRQ_SECOND=3, IRQ_DONE=4;
    wire irq_wait = cpu_inta || (irq_state != IRQ_IDLE && irq_state != IRQ_DONE);
    assign cpu_block = bus_block || irq_wait;
    assign iid_data = (cpu_inta || irq_state != IRQ_IDLE) ? {8'h00, vector_latch} : cpu_read_data;
    wire pic_interrupt;

    zet_core cpu (
        .clk(clk), .rst(reset), .intr(pic_interrupt), .inta(cpu_inta),
        .nmi(1'b0), .nmia(unused_nmia), .cpu_adr_o(cpu_address),
        .iid_dat_i(iid_data), .cpu_dat_i(cpu_read_data), .cpu_dat_o(cpu_write_data),
        .cpu_byte_o(cpu_byte), .cpu_block(cpu_block), .cpu_mem_op(cpu_memop),
        .cpu_m_io(cpu_io), .cpu_we_o(cpu_write), .pc(pc)
    );
    zet_wb_master bus_master (
        .cpu_byte_o(cpu_byte), .cpu_memop(cpu_memop), .cpu_m_io(cpu_io),
        .cpu_adr_o(cpu_address), .cpu_block(bus_block), .cpu_dat_i(cpu_read_data),
        .cpu_dat_o(cpu_write_data), .cpu_we_o(cpu_write), .wb_clk_i(clk),
        .wb_rst_i(reset), .wb_dat_i(wb_read_data), .wb_dat_o(wb_write_data),
        .wb_adr_o(wb_address), .wb_we_o(wb_write), .wb_tga_o(wb_io),
        .wb_sel_o(wb_select), .wb_stb_o(wb_strobe), .wb_cyc_o(wb_cycle), .wb_ack_i(wb_ack)
    );

    // 8 KiB RAM at 00000h..01FFFh; 2 KiB program page at F0000h.
    // IVT and stack are in RAM. Three ROM pages contain the scenario programs.
    (* ram_style = "block" *) reg [7:0] ram_low [0:4095];
    (* ram_style = "block" *) reg [7:0] ram_high [0:4095];
    (* rom_style = "block" *) reg [15:0] program_rom [0:4095];
    reg [15:0] ram_read, rom_read;
    initial $readmemh("program.hex", program_rom);
    always @(posedge clk) begin
        ram_read <= {ram_high[wb_address[12:1]], ram_low[wb_address[12:1]]};
        rom_read <= program_rom[{scenario, wb_address[10:1]}];
    end
    wire ram_selected = wb_address[19:13] == 0;
    wire rom_selected = wb_address[19:11] == 9'h1e0;
    wire boot_selected = wb_address[19:4] == 16'hffff;
    wire pic_selected = wb_address[15:1] == 15'h0010;
    wire marker_selected = wb_address[15:1] == 15'h0040;
    wire [7:0] write_byte = wb_select[0] ? wb_write_data[7:0] : wb_write_data[15:8];

    reg [2:0] bus_state;
    reg [7:0] bus_ticks;
    reg pic_select_n, pic_read_n, pic_write_n, pic_a0;
    reg [7:0] pic_data_in;
    wire [7:0] pic_data_out;
    wire unused_data_io, unused_cascade_io, unused_buffer, unused_slave_enable;
    wire [2:0] unused_cascade;
    localparam BUS_IDLE=0, BUS_MEMORY=1, BUS_PIC=2, BUS_GAP=3, BUS_RELEASE=4;

    // All KF8259 registers use the falling edge. This clock polarity maps those
    // updates to the common system rising edge; it is not a gated clock.
    KF8259 pic (
        .clock(~clk), .reset(reset), .chip_select_n(pic_select_n),
        .read_enable_n(pic_read_n), .write_enable_n(pic_write_n), .address(pic_a0),
        .data_bus_in(pic_data_in), .data_bus_out(pic_data_out), .data_bus_io(unused_data_io),
        .cascade_in(3'b000), .cascade_out(unused_cascade), .cascade_io(unused_cascade_io),
        .slave_program_n(1'b1), .buffer_enable(unused_buffer),
        .slave_program_or_enable_buffer(unused_slave_enable),
        .interrupt_acknowledge_n(acknowledge_n), .interrupt_to_cpu(pic_interrupt),
        .interrupt_request(requests)
    );

    always @(posedge clk) begin
        marker_valid <= 0;
        if (reset) begin
            bus_state <= BUS_IDLE;
            bus_ticks <= 0;
            wb_ack <= 0;
            wb_read_data <= 0;
            pic_select_n <= 1;
            pic_read_n <= 1;
            pic_write_n <= 1;
            pic_a0 <= 0;
            pic_data_in <= 0;
            ready <= 0;
            marker <= 0;
            debug_progress <= 0;
        end else case (bus_state)
            BUS_IDLE: if (wb_strobe && wb_cycle) begin
                if(debug_progress[7:0]!=8'hff) debug_progress[7:0]<=debug_progress[7:0]+1'b1;
                if (wb_io && pic_selected) begin
                    pic_select_n <= 0;
                    pic_read_n <= wb_write;
                    pic_write_n <= !wb_write;
                    pic_a0 <= !wb_select[0];
                    pic_data_in <= write_byte;
                    bus_ticks <= 0;
                    bus_state <= BUS_PIC;
                end else if (wb_io) begin
                    if (wb_write && marker_selected) begin
                        marker <= write_byte;
                        marker_valid <= 1;
                        if (write_byte == 8'ha0) ready <= 1;
                        if (write_byte == 8'ha0) debug_progress[12]<=1;
                        if (write_byte == 8'hb1) debug_progress[13]<=1;
                        if (write_byte == 8'hb3) debug_progress[14]<=1;
                        if (write_byte == 8'hd0) debug_progress[15]<=1;
                    end
                    wb_read_data <= 16'hffff;
                    wb_ack <= 1;
                    bus_state <= BUS_RELEASE;
                end else begin
                    bus_state <= BUS_MEMORY;
                end
            end
            BUS_MEMORY: begin
                if(boot_selected && !wb_write) debug_progress[8]<=1;
                if(rom_selected && !wb_write) debug_progress[9]<=1;
                if(ram_selected && wb_write) debug_progress[10]<=1;
                if (wb_write && ram_selected) begin
                    if (wb_select[0]) ram_low[wb_address[12:1]] <= wb_write_data[7:0];
                    if (wb_select[1]) ram_high[wb_address[12:1]] <= wb_write_data[15:8];
                end
                if (boot_selected) begin
                    case (wb_address[3:1])
                        0: wb_read_data <= 16'h00ea;
                        1: wb_read_data <= 16'h0000;
                        2: wb_read_data <= 16'h90f0;
                        default: wb_read_data <= 16'h9090;
                    endcase
                end else if (rom_selected) wb_read_data <= rom_read;
                else if (ram_selected) wb_read_data <= ram_read;
                else wb_read_data <= 16'hffff;
                wb_ack <= 1;
                bus_state <= BUS_RELEASE;
            end
            BUS_PIC: begin
                if(!pic_write_n) debug_progress[11]<=1;
                if (bus_ticks == BUS_TICKS-1) begin
                    wb_read_data <= {pic_data_out, pic_data_out};
                    pic_read_n <= 1;
                    pic_write_n <= 1;
                    bus_ticks <= 0;
                    bus_state <= BUS_GAP;
                end else bus_ticks <= bus_ticks + 1'b1;
            end
            BUS_GAP: begin
                if (bus_ticks == 2) begin
                    pic_select_n <= 1;
                    wb_ack <= 1;
                    bus_state <= BUS_RELEASE;
                end else bus_ticks <= bus_ticks + 1'b1;
            end
            // Zet keeps STB asserted across the two beats of an unaligned word.
            // ACK must pulse per beat, not remain high until STB falls.
            BUS_RELEASE: begin
                wb_ack <= 0;
                bus_state <= BUS_IDLE;
            end
            default: bus_state <= BUS_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            irq_state <= IRQ_IDLE;
            irq_ticks <= 0;
            acknowledge_n <= 1;
            vector_latch <= 0;
        end else case (irq_state)
            IRQ_IDLE: if (cpu_inta) begin
                acknowledge_n <= 0;
                irq_ticks <= 0;
                irq_state <= IRQ_FIRST;
            end
            IRQ_FIRST: if (irq_ticks == ACK_TICKS-1) begin
                acknowledge_n <= 1;
                irq_ticks <= 0;
                irq_state <= IRQ_GAP_STATE;
            end else irq_ticks <= irq_ticks + 1'b1;
            IRQ_GAP_STATE: if (irq_ticks == ACK_GAP-1) begin
                acknowledge_n <= 0;
                irq_ticks <= 0;
                irq_state <= IRQ_SECOND;
            end else irq_ticks <= irq_ticks + 1'b1;
            IRQ_SECOND: if (irq_ticks == ACK_TICKS-1) begin
                vector_latch <= pic_data_out;
                acknowledge_n <= 1;
                irq_state <= IRQ_DONE;
            end else irq_ticks <= irq_ticks + 1'b1;
            IRQ_DONE: irq_state <= IRQ_IDLE;
            default: irq_state <= IRQ_IDLE;
        endcase
    end

    wire [7:0] observed_data = (!acknowledge_n || !pic_read_n) ? pic_data_out :
                               (!pic_write_n ? pic_data_in : 8'h00);
    assign probes = {pic_a0, pic_read_n, pic_write_n, pic_select_n,
                     acknowledge_n, pic_interrupt, requests, observed_data};
    // Address is word-addressed (bits 19:1); byte enables identify the lane.
    assign debug_bus={wb_address,wb_select,bus_state,irq_state,
                      wb_strobe,wb_write,wb_io,wb_ack,cpu_block};
endmodule
