// Generated with sv2v v0.0.13 from KF8259 (Kitune-san, MIT).
// Preserve third_party/kf8259/upstream/LICENSE when distributing.
// XST compatibility: generate-localparam aliases replaced by their genvars.
module KF8259 (
	clock,
	reset,
	chip_select_n,
	read_enable_n,
	write_enable_n,
	address,
	data_bus_in,
	data_bus_out,
	data_bus_io,
	cascade_in,
	cascade_out,
	cascade_io,
	slave_program_n,
	buffer_enable,
	slave_program_or_enable_buffer,
	interrupt_acknowledge_n,
	interrupt_to_cpu,
	interrupt_request
);
	reg _sv2v_0;
	input wire clock;
	input wire reset;
	input wire chip_select_n;
	input wire read_enable_n;
	input wire write_enable_n;
	input wire address;
	input wire [7:0] data_bus_in;
	output reg [7:0] data_bus_out;
	output reg data_bus_io;
	input wire [2:0] cascade_in;
	output wire [2:0] cascade_out;
	output wire cascade_io;
	input wire slave_program_n;
	output wire buffer_enable;
	output wire slave_program_or_enable_buffer;
	input wire interrupt_acknowledge_n;
	output wire interrupt_to_cpu;
	input wire [7:0] interrupt_request;
	wire [7:0] internal_data_bus;
	wire write_initial_command_word_1;
	wire write_initial_command_word_2_4;
	wire write_operation_control_word_1;
	wire write_operation_control_word_2;
	wire write_operation_control_word_3;
	wire read;
	KF8259_Bus_Control_Logic u_Bus_Control_Logic(
		.clock(clock),
		.reset(reset),
		.chip_select_n(chip_select_n),
		.read_enable_n(read_enable_n),
		.write_enable_n(write_enable_n),
		.address(address),
		.data_bus_in(data_bus_in),
		.internal_data_bus(internal_data_bus),
		.write_initial_command_word_1(write_initial_command_word_1),
		.write_initial_command_word_2_4(write_initial_command_word_2_4),
		.write_operation_control_word_1(write_operation_control_word_1),
		.write_operation_control_word_2(write_operation_control_word_2),
		.write_operation_control_word_3(write_operation_control_word_3),
		.read(read)
	);
	wire out_control_logic_data;
	wire [7:0] control_logic_data;
	wire level_or_edge_toriggered_config;
	wire special_fully_nest_config;
	wire enable_read_register;
	wire read_register_isr_or_irr;
	wire [7:0] interrupt;
	wire [7:0] highest_level_in_service;
	wire [7:0] interrupt_mask;
	wire [7:0] interrupt_special_mask;
	wire [7:0] end_of_interrupt;
	wire [2:0] priority_rotate;
	wire freeze;
	wire latch_in_service;
	wire [7:0] clear_interrupt_request;
	KF8259_Control_Logic u_Control_Logic(
		.clock(clock),
		.reset(reset),
		.cascade_in(cascade_in),
		.cascade_out(cascade_out),
		.cascade_io(cascade_io),
		.slave_program_n(slave_program_n),
		.slave_program_or_enable_buffer(slave_program_or_enable_buffer),
		.interrupt_acknowledge_n(interrupt_acknowledge_n),
		.interrupt_to_cpu(interrupt_to_cpu),
		.internal_data_bus(internal_data_bus),
		.write_initial_command_word_1(write_initial_command_word_1),
		.write_initial_command_word_2_4(write_initial_command_word_2_4),
		.write_operation_control_word_1(write_operation_control_word_1),
		.write_operation_control_word_2(write_operation_control_word_2),
		.write_operation_control_word_3(write_operation_control_word_3),
		.read(read),
		.out_control_logic_data(out_control_logic_data),
		.control_logic_data(control_logic_data),
		.level_or_edge_toriggered_config(level_or_edge_toriggered_config),
		.special_fully_nest_config(special_fully_nest_config),
		.enable_read_register(enable_read_register),
		.read_register_isr_or_irr(read_register_isr_or_irr),
		.interrupt(interrupt),
		.highest_level_in_service(highest_level_in_service),
		.interrupt_mask(interrupt_mask),
		.interrupt_special_mask(interrupt_special_mask),
		.end_of_interrupt(end_of_interrupt),
		.priority_rotate(priority_rotate),
		.freeze(freeze),
		.latch_in_service(latch_in_service),
		.clear_interrupt_request(clear_interrupt_request)
	);
	wire [7:0] interrupt_request_register;
	KF8259_Interrupt_Request u_Interrupt_Request(
		.clock(clock),
		.reset(reset),
		.level_or_edge_toriggered_config(level_or_edge_toriggered_config),
		.freeze(freeze),
		.clear_interrupt_request(clear_interrupt_request),
		.interrupt_request_pin(interrupt_request),
		.interrupt_request_register(interrupt_request_register)
	);
	wire [7:0] in_service_register;
	KF8259_Priority_Resolver u_Priority_Resolver(
		.priority_rotate(priority_rotate),
		.interrupt_mask(interrupt_mask),
		.interrupt_special_mask(interrupt_special_mask),
		.special_fully_nest_config(special_fully_nest_config),
		.highest_level_in_service(highest_level_in_service),
		.interrupt_request_register(interrupt_request_register),
		.in_service_register(in_service_register),
		.interrupt(interrupt)
	);
	KF8259_In_Service u_In_Service(
		.clock(clock),
		.reset(reset),
		.priority_rotate(priority_rotate),
		.interrupt_special_mask(interrupt_special_mask),
		.interrupt(interrupt),
		.latch_in_service(latch_in_service),
		.end_of_interrupt(end_of_interrupt),
		.in_service_register(in_service_register),
		.highest_level_in_service(highest_level_in_service)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		if (out_control_logic_data == 1'b1) begin
			data_bus_io = 1'b0;
			data_bus_out = control_logic_data;
		end
		else if (read == 1'b0) begin
			data_bus_io = 1'b1;
			data_bus_out = 8'b00000000;
		end
		else if (address == 1'b1) begin
			data_bus_io = 1'b0;
			data_bus_out = interrupt_mask;
		end
		else if ((enable_read_register == 1'b1) && (read_register_isr_or_irr == 1'b0)) begin
			data_bus_io = 1'b0;
			data_bus_out = interrupt_request_register;
		end
		else if ((enable_read_register == 1'b1) && (read_register_isr_or_irr == 1'b1)) begin
			data_bus_io = 1'b0;
			data_bus_out = in_service_register;
		end
		else begin
			data_bus_io = 1'b1;
			data_bus_out = 8'b00000000;
		end
	end
	assign buffer_enable = (slave_program_or_enable_buffer == 1'b1 ? 1'b0 : ~data_bus_io);
	initial _sv2v_0 = 0;
endmodule
module KF8259_Bus_Control_Logic (
	clock,
	reset,
	chip_select_n,
	read_enable_n,
	write_enable_n,
	address,
	data_bus_in,
	internal_data_bus,
	write_initial_command_word_1,
	write_initial_command_word_2_4,
	write_operation_control_word_1,
	write_operation_control_word_2,
	write_operation_control_word_3,
	read
);
	input wire clock;
	input wire reset;
	input wire chip_select_n;
	input wire read_enable_n;
	input wire write_enable_n;
	input wire address;
	input wire [7:0] data_bus_in;
	output reg [7:0] internal_data_bus;
	output wire write_initial_command_word_1;
	output wire write_initial_command_word_2_4;
	output wire write_operation_control_word_1;
	output wire write_operation_control_word_2;
	output wire write_operation_control_word_3;
	output wire read;
	reg prev_write_enable_n;
	wire write_flag;
	reg stable_address;
	always @(negedge clock or posedge reset)
		if (reset)
			internal_data_bus <= 8'b00000000;
		else if (~write_enable_n & ~chip_select_n)
			internal_data_bus <= data_bus_in;
		else
			internal_data_bus <= internal_data_bus;
	always @(negedge clock or posedge reset)
		if (reset)
			prev_write_enable_n <= 1'b1;
		else if (chip_select_n)
			prev_write_enable_n <= 1'b1;
		else
			prev_write_enable_n <= write_enable_n;
	assign write_flag = ~prev_write_enable_n & write_enable_n;
	always @(negedge clock or posedge reset)
		if (reset)
			stable_address <= 1'b0;
		else
			stable_address <= address;
	assign write_initial_command_word_1 = (write_flag & ~stable_address) & internal_data_bus[4];
	assign write_initial_command_word_2_4 = write_flag & stable_address;
	assign write_operation_control_word_1 = write_flag & stable_address;
	assign write_operation_control_word_2 = ((write_flag & ~stable_address) & ~internal_data_bus[4]) & ~internal_data_bus[3];
	assign write_operation_control_word_3 = ((write_flag & ~stable_address) & ~internal_data_bus[4]) & internal_data_bus[3];
	assign read = ~read_enable_n & ~chip_select_n;
endmodule
module KF8259_Control_Logic (
	clock,
	reset,
	cascade_in,
	cascade_out,
	cascade_io,
	slave_program_n,
	slave_program_or_enable_buffer,
	interrupt_acknowledge_n,
	interrupt_to_cpu,
	internal_data_bus,
	write_initial_command_word_1,
	write_initial_command_word_2_4,
	write_operation_control_word_1,
	write_operation_control_word_2,
	write_operation_control_word_3,
	read,
	out_control_logic_data,
	control_logic_data,
	level_or_edge_toriggered_config,
	special_fully_nest_config,
	enable_read_register,
	read_register_isr_or_irr,
	interrupt,
	highest_level_in_service,
	interrupt_mask,
	interrupt_special_mask,
	end_of_interrupt,
	priority_rotate,
	freeze,
	latch_in_service,
	clear_interrupt_request
);
	reg _sv2v_0;
	input wire clock;
	input wire reset;
	input wire [2:0] cascade_in;
	output reg [2:0] cascade_out;
	output wire cascade_io;
	input wire slave_program_n;
	output wire slave_program_or_enable_buffer;
	input wire interrupt_acknowledge_n;
	output reg interrupt_to_cpu;
	input wire [7:0] internal_data_bus;
	input wire write_initial_command_word_1;
	input wire write_initial_command_word_2_4;
	input wire write_operation_control_word_1;
	input wire write_operation_control_word_2;
	input wire write_operation_control_word_3;
	input wire read;
	output reg out_control_logic_data;
	output reg [7:0] control_logic_data;
	output reg level_or_edge_toriggered_config;
	output reg special_fully_nest_config;
	output reg enable_read_register;
	output reg read_register_isr_or_irr;
	input wire [7:0] interrupt;
	input wire [7:0] highest_level_in_service;
	output reg [7:0] interrupt_mask;
	output reg [7:0] interrupt_special_mask;
	output reg [7:0] end_of_interrupt;
	output reg [2:0] priority_rotate;
	output reg freeze;
	output reg latch_in_service;
	output reg [7:0] clear_interrupt_request;
	reg [10:0] interrupt_vector_address;
	reg call_address_interval_4_or_8_config;
	reg single_or_cascade_config;
	reg set_icw4_config;
	reg [7:0] cascade_device_config;
	reg buffered_mode_config;
	reg buffered_master_or_slave_config;
	reg auto_eoi_config;
	reg u8086_or_mcs80_config;
	reg special_mask_mode;
	wire enable_special_mask_mode;
	reg auto_rotate_mode;
	reg [7:0] acknowledge_interrupt;
	reg cascade_slave;
	reg cascade_slave_enable;
	reg cascade_output_ack_2_3;
	reg [31:0] command_state;
	reg [31:0] next_command_state;
	always @(*) begin
		if (_sv2v_0)
			;
		if (write_initial_command_word_1 == 1'b1)
			next_command_state = 32'd1;
		else if (write_initial_command_word_2_4 == 1'b1)
			casez (command_state)
				32'd1:
					if (single_or_cascade_config == 1'b0)
						next_command_state = 32'd2;
					else if (set_icw4_config == 1'b1)
						next_command_state = 32'd3;
					else
						next_command_state = 32'd0;
				32'd2:
					if (set_icw4_config == 1'b1)
						next_command_state = 32'd3;
					else
						next_command_state = 32'd0;
				32'd3: next_command_state = 32'd0;
				default: next_command_state = 32'd0;
			endcase
		else
			next_command_state = command_state;
	end
	always @(negedge clock or posedge reset)
		if (reset)
			command_state <= 32'd0;
		else
			command_state <= next_command_state;
	wire write_initial_command_word_2 = (command_state == 32'd1) & write_initial_command_word_2_4;
	wire write_initial_command_word_3 = (command_state == 32'd2) & write_initial_command_word_2_4;
	wire write_initial_command_word_4 = (command_state == 32'd3) & write_initial_command_word_2_4;
	wire write_operation_control_word_1_registers = (command_state == 32'd0) & write_operation_control_word_1;
	wire write_operation_control_word_2_registers = (command_state == 32'd0) & write_operation_control_word_2;
	wire write_operation_control_word_3_registers = (command_state == 32'd0) & write_operation_control_word_3;
	reg [31:0] next_control_state;
	reg [31:0] control_state;
	reg prev_interrupt_acknowledge_n;
	always @(negedge clock or posedge reset)
		if (reset)
			prev_interrupt_acknowledge_n <= 1'b1;
		else
			prev_interrupt_acknowledge_n <= interrupt_acknowledge_n;
	wire nedge_interrupt_acknowledge = prev_interrupt_acknowledge_n & ~interrupt_acknowledge_n;
	wire pedge_interrupt_acknowledge = ~prev_interrupt_acknowledge_n & interrupt_acknowledge_n;
	reg prev_read_signal;
	always @(negedge clock or posedge reset)
		if (reset)
			prev_read_signal <= 1'b0;
		else
			prev_read_signal <= read;
	wire nedge_read_signal = prev_read_signal & ~read;
	always @(*) begin
		if (_sv2v_0)
			;
		casez (control_state)
			32'd0:
				if ((write_operation_control_word_3_registers == 1'b1) && (internal_data_bus[2] == 1'b1))
					next_control_state = 32'd4;
				else if (write_operation_control_word_2_registers == 1'b1)
					next_control_state = 32'd0;
				else if (nedge_interrupt_acknowledge == 1'b0)
					next_control_state = 32'd0;
				else
					next_control_state = 32'd1;
			32'd1:
				if (pedge_interrupt_acknowledge == 1'b0)
					next_control_state = 32'd1;
				else
					next_control_state = 32'd2;
			32'd2:
				if (pedge_interrupt_acknowledge == 1'b0)
					next_control_state = 32'd2;
				else if (u8086_or_mcs80_config == 1'b0)
					next_control_state = 32'd3;
				else
					next_control_state = 32'd0;
			32'd3:
				if (pedge_interrupt_acknowledge == 1'b0)
					next_control_state = 32'd3;
				else
					next_control_state = 32'd0;
			32'd4:
				if (nedge_read_signal == 1'b0)
					next_control_state = 32'd4;
				else
					next_control_state = 32'd0;
			default: next_control_state = 32'd0;
		endcase
	end
	always @(negedge clock or posedge reset)
		if (reset)
			control_state <= 32'd0;
		else if (write_initial_command_word_1 == 1'b1)
			control_state <= 32'd0;
		else
			control_state <= next_control_state;
	always @(*) begin
		if (_sv2v_0)
			;
		if (write_initial_command_word_1 == 1'b1)
			latch_in_service = 1'b0;
		else if ((control_state == 32'd0) && (next_control_state == 32'd4))
			latch_in_service = 1'b1;
		else if (cascade_slave == 1'b0)
			latch_in_service = (control_state == 32'd0) & (next_control_state != 32'd0);
		else
			latch_in_service = ((control_state == 32'd2) & (cascade_slave_enable == 1'b1)) & (nedge_interrupt_acknowledge == 1'b1);
	end
	wire end_of_acknowledge_sequence = ((control_state != 32'd4) & (control_state != 32'd0)) & (next_control_state == 32'd0);
	wire end_of_poll_command = ((control_state == 32'd4) & (control_state != 32'd0)) & (next_control_state == 32'd0);
	always @(negedge clock or posedge reset)
		if (reset)
			interrupt_vector_address[2:0] <= 3'b000;
		else if (write_initial_command_word_1 == 1'b1)
			interrupt_vector_address[2:0] <= internal_data_bus[7:5];
		else
			interrupt_vector_address[2:0] <= interrupt_vector_address[2:0];
	always @(negedge clock or posedge reset)
		if (reset)
			level_or_edge_toriggered_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			level_or_edge_toriggered_config <= internal_data_bus[3];
		else
			level_or_edge_toriggered_config <= level_or_edge_toriggered_config;
	always @(negedge clock or posedge reset)
		if (reset)
			call_address_interval_4_or_8_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			call_address_interval_4_or_8_config <= internal_data_bus[2];
		else
			call_address_interval_4_or_8_config <= call_address_interval_4_or_8_config;
	always @(negedge clock or posedge reset)
		if (reset)
			single_or_cascade_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			single_or_cascade_config <= internal_data_bus[1];
		else
			single_or_cascade_config <= single_or_cascade_config;
	always @(negedge clock or posedge reset)
		if (reset)
			set_icw4_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			set_icw4_config <= internal_data_bus[0];
		else
			set_icw4_config <= set_icw4_config;
	always @(negedge clock or posedge reset)
		if (reset)
			interrupt_vector_address[10:3] <= 3'b000;
		else if (write_initial_command_word_1 == 1'b1)
			interrupt_vector_address[10:3] <= 3'b000;
		else if (write_initial_command_word_2 == 1'b1)
			interrupt_vector_address[10:3] <= internal_data_bus;
		else
			interrupt_vector_address[10:3] <= interrupt_vector_address[10:3];
	always @(negedge clock or posedge reset)
		if (reset)
			cascade_device_config <= 8'b00000000;
		else if (write_initial_command_word_1 == 1'b1)
			cascade_device_config <= 8'b00000000;
		else if (write_initial_command_word_3 == 1'b1)
			cascade_device_config <= internal_data_bus;
		else
			cascade_device_config <= cascade_device_config;
	always @(negedge clock or posedge reset)
		if (reset)
			special_fully_nest_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			special_fully_nest_config <= 1'b0;
		else if (write_initial_command_word_4 == 1'b1)
			special_fully_nest_config <= internal_data_bus[4];
		else
			special_fully_nest_config <= special_fully_nest_config;
	always @(negedge clock or posedge reset)
		if (reset)
			buffered_mode_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			buffered_mode_config <= 1'b0;
		else if (write_initial_command_word_4 == 1'b1)
			buffered_mode_config <= internal_data_bus[3];
		else
			buffered_mode_config <= buffered_mode_config;
	assign slave_program_or_enable_buffer = ~buffered_mode_config;
	always @(negedge clock or posedge reset)
		if (reset)
			buffered_master_or_slave_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			buffered_master_or_slave_config <= 1'b0;
		else if (write_initial_command_word_4 == 1'b1)
			buffered_master_or_slave_config <= internal_data_bus[2];
		else
			buffered_master_or_slave_config <= buffered_master_or_slave_config;
	always @(negedge clock or posedge reset)
		if (reset)
			auto_eoi_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			auto_eoi_config <= 1'b0;
		else if (write_initial_command_word_4 == 1'b1)
			auto_eoi_config <= internal_data_bus[1];
		else
			auto_eoi_config <= auto_eoi_config;
	always @(negedge clock or posedge reset)
		if (reset)
			u8086_or_mcs80_config <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			u8086_or_mcs80_config <= 1'b0;
		else if (write_initial_command_word_4 == 1'b1)
			u8086_or_mcs80_config <= internal_data_bus[0];
		else
			u8086_or_mcs80_config <= u8086_or_mcs80_config;
	always @(negedge clock or posedge reset)
		if (reset)
			interrupt_mask <= 8'b11111111;
		else if (write_initial_command_word_1 == 1'b1)
			interrupt_mask <= 8'b11111111;
		else if ((write_operation_control_word_1_registers == 1'b1) && (special_mask_mode == 1'b0))
			interrupt_mask <= internal_data_bus;
		else
			interrupt_mask <= interrupt_mask;
	always @(negedge clock or posedge reset)
		if (reset)
			interrupt_special_mask <= 8'b00000000;
		else if (write_initial_command_word_1 == 1'b1)
			interrupt_special_mask <= 8'b00000000;
		else if (special_mask_mode == 1'b0)
			interrupt_special_mask <= 8'b00000000;
		else if (write_operation_control_word_1_registers == 1'b1)
			interrupt_special_mask <= internal_data_bus;
		else
			interrupt_special_mask <= interrupt_special_mask;
	function [7:0] KF8259_Common_Package_num2bit;
		input [2:0] source;
		casez (source)
			3'b000: KF8259_Common_Package_num2bit = 8'b00000001;
			3'b001: KF8259_Common_Package_num2bit = 8'b00000010;
			3'b010: KF8259_Common_Package_num2bit = 8'b00000100;
			3'b011: KF8259_Common_Package_num2bit = 8'b00001000;
			3'b100: KF8259_Common_Package_num2bit = 8'b00010000;
			3'b101: KF8259_Common_Package_num2bit = 8'b00100000;
			3'b110: KF8259_Common_Package_num2bit = 8'b01000000;
			3'b111: KF8259_Common_Package_num2bit = 8'b10000000;
			default: KF8259_Common_Package_num2bit = 8'b00000000;
		endcase
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		if (write_initial_command_word_1 == 1'b1)
			end_of_interrupt = 8'b11111111;
		else if ((auto_eoi_config == 1'b1) && (end_of_acknowledge_sequence == 1'b1))
			end_of_interrupt = acknowledge_interrupt;
		else if (write_operation_control_word_2 == 1'b1)
			casez (internal_data_bus[6:5])
				2'b01: end_of_interrupt = highest_level_in_service;
				2'b11: end_of_interrupt = KF8259_Common_Package_num2bit(internal_data_bus[2:0]);
				default: end_of_interrupt = 8'b00000000;
			endcase
		else
			end_of_interrupt = 8'b00000000;
	end
	always @(negedge clock or posedge reset)
		if (reset)
			auto_rotate_mode <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			auto_rotate_mode <= 1'b0;
		else if (write_operation_control_word_2 == 1'b1)
			casez (internal_data_bus[7:5])
				3'b000: auto_rotate_mode <= 1'b0;
				3'b100: auto_rotate_mode <= 1'b1;
				default: auto_rotate_mode <= auto_rotate_mode;
			endcase
		else
			auto_rotate_mode <= auto_rotate_mode;
	function [2:0] KF8259_Common_Package_bit2num;
		input [7:0] source;
		if (source[0] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b000;
		else if (source[1] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b001;
		else if (source[2] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b010;
		else if (source[3] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b011;
		else if (source[4] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b100;
		else if (source[5] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b101;
		else if (source[6] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b110;
		else if (source[7] == 1'b1)
			KF8259_Common_Package_bit2num = 3'b111;
		else
			KF8259_Common_Package_bit2num = 3'b111;
	endfunction
	always @(negedge clock or posedge reset)
		if (reset)
			priority_rotate <= 3'b111;
		else if (write_initial_command_word_1 == 1'b1)
			priority_rotate <= 3'b111;
		else if ((auto_rotate_mode == 1'b1) && (end_of_acknowledge_sequence == 1'b1))
			priority_rotate <= KF8259_Common_Package_bit2num(acknowledge_interrupt);
		else if (write_operation_control_word_2 == 1'b1)
			casez (internal_data_bus[7:5])
				3'b101: priority_rotate <= KF8259_Common_Package_bit2num(highest_level_in_service);
				3'b11z: priority_rotate <= internal_data_bus[2:0];
				default: priority_rotate <= priority_rotate;
			endcase
		else
			priority_rotate <= priority_rotate;
	always @(negedge clock or posedge reset)
		if (reset)
			special_mask_mode <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			special_mask_mode <= 1'b0;
		else if ((write_operation_control_word_3_registers == 1'b1) && (internal_data_bus[6] == 1'b1))
			special_mask_mode <= internal_data_bus[5];
		else
			special_mask_mode <= special_mask_mode;
	always @(negedge clock or posedge reset)
		if (reset) begin
			enable_read_register <= 1'b1;
			read_register_isr_or_irr <= 1'b0;
		end
		else if (write_initial_command_word_1 == 1'b1) begin
			enable_read_register <= 1'b1;
			read_register_isr_or_irr <= 1'b0;
		end
		else if (write_operation_control_word_3_registers == 1'b1) begin
			enable_read_register <= internal_data_bus[1];
			read_register_isr_or_irr <= internal_data_bus[0];
		end
		else begin
			enable_read_register <= enable_read_register;
			read_register_isr_or_irr <= read_register_isr_or_irr;
		end
	always @(*) begin
		if (_sv2v_0)
			;
		if (single_or_cascade_config == 1'b1)
			cascade_slave = 1'b0;
		else if (buffered_mode_config == 1'b0)
			cascade_slave = ~slave_program_n;
		else
			cascade_slave = ~buffered_master_or_slave_config;
	end
	assign cascade_io = cascade_slave;
	always @(*) begin
		if (_sv2v_0)
			;
		if (cascade_slave == 1'b0)
			cascade_slave_enable = 1'b0;
		else if (cascade_device_config[2:0] != cascade_in)
			cascade_slave_enable = 1'b0;
		else
			cascade_slave_enable = 1'b1;
	end
	wire interrupt_from_slave_device = (acknowledge_interrupt & cascade_device_config) != 8'b00000000;
	always @(*) begin
		if (_sv2v_0)
			;
		if (single_or_cascade_config == 1'b1)
			cascade_output_ack_2_3 = 1'b1;
		else if (cascade_slave_enable == 1'b1)
			cascade_output_ack_2_3 = 1'b1;
		else if ((cascade_slave == 1'b0) && (interrupt_from_slave_device == 1'b0))
			cascade_output_ack_2_3 = 1'b1;
		else
			cascade_output_ack_2_3 = 1'b0;
	end
	always @(*) begin
		if (_sv2v_0)
			;
		if (cascade_slave == 1'b1)
			cascade_out <= 3'b000;
		else if (((control_state != 32'd1) && (control_state != 32'd2)) && (control_state != 32'd3))
			cascade_out <= 3'b000;
		else if (interrupt_from_slave_device == 1'b0)
			cascade_out <= 3'b000;
		else
			cascade_out <= KF8259_Common_Package_bit2num(acknowledge_interrupt);
	end
	always @(negedge clock or posedge reset)
		if (reset)
			interrupt_to_cpu <= 1'b0;
		else if (write_initial_command_word_1 == 1'b1)
			interrupt_to_cpu <= 1'b0;
		else if (interrupt != 8'b00000000)
			interrupt_to_cpu <= 1'b1;
		else if (end_of_acknowledge_sequence == 1'b1)
			interrupt_to_cpu <= 1'b0;
		else if (end_of_poll_command == 1'b1)
			interrupt_to_cpu <= 1'b0;
		else
			interrupt_to_cpu <= interrupt_to_cpu;
	always @(negedge clock or posedge reset)
		if (reset)
			freeze <= 1'b1;
		else if (next_control_state == 32'd0)
			freeze <= 1'b0;
		else
			freeze <= 1'b1;
	always @(*) begin
		if (_sv2v_0)
			;
		if (write_initial_command_word_1 == 1'b1)
			clear_interrupt_request = 8'b11111111;
		else if (latch_in_service == 1'b0)
			clear_interrupt_request = 8'b00000000;
		else
			clear_interrupt_request = interrupt;
	end
	always @(negedge clock or posedge reset)
		if (reset)
			acknowledge_interrupt <= 8'b00000000;
		else if (write_initial_command_word_1 == 1'b1)
			acknowledge_interrupt <= 8'b00000000;
		else if (end_of_acknowledge_sequence)
			acknowledge_interrupt <= 8'b00000000;
		else if (end_of_poll_command == 1'b1)
			acknowledge_interrupt <= 8'b00000000;
		else if (latch_in_service == 1'b1)
			acknowledge_interrupt <= interrupt;
		else
			acknowledge_interrupt <= acknowledge_interrupt;
	reg [7:0] interrupt_when_ack1;
	always @(negedge clock or posedge reset)
		if (reset)
			interrupt_when_ack1 <= 8'b00000000;
		else if (write_initial_command_word_1 == 1'b1)
			interrupt_when_ack1 <= 8'b00000000;
		else if (control_state == 32'd1)
			interrupt_when_ack1 <= interrupt;
		else
			interrupt_when_ack1 <= interrupt_when_ack1;
	always @(*) begin
		if (_sv2v_0)
			;
		if (interrupt_acknowledge_n == 1'b0)
			casez (control_state)
				32'd0:
					if (cascade_slave == 1'b0) begin
						if (u8086_or_mcs80_config == 1'b0) begin
							out_control_logic_data = 1'b1;
							control_logic_data = 8'b11001101;
						end
						else begin
							out_control_logic_data = 1'b0;
							control_logic_data = 8'b00000000;
						end
					end
					else begin
						out_control_logic_data = 1'b0;
						control_logic_data = 8'b00000000;
					end
				32'd1:
					if (cascade_slave == 1'b0) begin
						if (u8086_or_mcs80_config == 1'b0) begin
							out_control_logic_data = 1'b1;
							control_logic_data = 8'b11001101;
						end
						else begin
							out_control_logic_data = 1'b0;
							control_logic_data = 8'b00000000;
						end
					end
					else begin
						out_control_logic_data = 1'b0;
						control_logic_data = 8'b00000000;
					end
				32'd2:
					if (cascade_output_ack_2_3 == 1'b1) begin
						out_control_logic_data = 1'b1;
						if (cascade_slave == 1'b1)
							control_logic_data[2:0] = KF8259_Common_Package_bit2num(interrupt_when_ack1);
						else
							control_logic_data[2:0] = KF8259_Common_Package_bit2num(acknowledge_interrupt);
						if (u8086_or_mcs80_config == 1'b0) begin
							if (call_address_interval_4_or_8_config == 1'b0)
								control_logic_data = {interrupt_vector_address[2:1], control_logic_data[2:0], 3'b000};
							else
								control_logic_data = {interrupt_vector_address[2:0], control_logic_data[2:0], 2'b00};
						end
						else
							control_logic_data = {interrupt_vector_address[10:6], control_logic_data[2:0]};
					end
					else begin
						out_control_logic_data = 1'b0;
						control_logic_data = 8'b00000000;
					end
				32'd3:
					if (cascade_output_ack_2_3 == 1'b1) begin
						out_control_logic_data = 1'b1;
						control_logic_data = interrupt_vector_address[10:3];
					end
					else begin
						out_control_logic_data = 1'b0;
						control_logic_data = 8'b00000000;
					end
				default: begin
					out_control_logic_data = 1'b0;
					control_logic_data = 8'b00000000;
				end
			endcase
		else if ((control_state == 32'd4) && (read == 1'b1)) begin
			out_control_logic_data = 1'b1;
			if (acknowledge_interrupt == 8'b00000000)
				control_logic_data = 8'b00000000;
			else begin
				control_logic_data[7:3] = 5'b10000;
				control_logic_data[2:0] = KF8259_Common_Package_bit2num(acknowledge_interrupt);
			end
		end
		else begin
			out_control_logic_data = 1'b0;
			control_logic_data = 8'b00000000;
		end
	end
	initial _sv2v_0 = 0;
endmodule
module KF8259_In_Service (
	clock,
	reset,
	priority_rotate,
	interrupt_special_mask,
	interrupt,
	latch_in_service,
	end_of_interrupt,
	in_service_register,
	highest_level_in_service
);
	reg _sv2v_0;
	input wire clock;
	input wire reset;
	input wire [2:0] priority_rotate;
	input wire [7:0] interrupt_special_mask;
	input wire [7:0] interrupt;
	input wire latch_in_service;
	input wire [7:0] end_of_interrupt;
	output reg [7:0] in_service_register;
	output reg [7:0] highest_level_in_service;
	wire [7:0] next_in_service_register;
	assign next_in_service_register = (in_service_register & ~end_of_interrupt) | (latch_in_service == 1'b1 ? interrupt : 8'b00000000);
	always @(negedge clock or posedge reset)
		if (reset)
			in_service_register <= 8'b00000000;
		else
			in_service_register <= next_in_service_register;
	reg [7:0] next_highest_level_in_service;
	function [7:0] KF8259_Common_Package_resolv_priority;
		input [7:0] request;
		if (request[0] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00000001;
		else if (request[1] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00000010;
		else if (request[2] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00000100;
		else if (request[3] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00001000;
		else if (request[4] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00010000;
		else if (request[5] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00100000;
		else if (request[6] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b01000000;
		else if (request[7] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b10000000;
		else
			KF8259_Common_Package_resolv_priority = 8'b00000000;
	endfunction
	function [7:0] KF8259_Common_Package_rotate_left;
		input [7:0] source;
		input [2:0] rotate;
		casez (rotate)
			3'b000: KF8259_Common_Package_rotate_left = {source[6:0], source[7]};
			3'b001: KF8259_Common_Package_rotate_left = {source[5:0], source[7:6]};
			3'b010: KF8259_Common_Package_rotate_left = {source[4:0], source[7:5]};
			3'b011: KF8259_Common_Package_rotate_left = {source[3:0], source[7:4]};
			3'b100: KF8259_Common_Package_rotate_left = {source[2:0], source[7:3]};
			3'b101: KF8259_Common_Package_rotate_left = {source[1:0], source[7:2]};
			3'b110: KF8259_Common_Package_rotate_left = {source[0], source[7:1]};
			3'b111: KF8259_Common_Package_rotate_left = source;
			default: KF8259_Common_Package_rotate_left = source;
		endcase
	endfunction
	function [7:0] KF8259_Common_Package_rotate_right;
		input [7:0] source;
		input [2:0] rotate;
		casez (rotate)
			3'b000: KF8259_Common_Package_rotate_right = {source[0], source[7:1]};
			3'b001: KF8259_Common_Package_rotate_right = {source[1:0], source[7:2]};
			3'b010: KF8259_Common_Package_rotate_right = {source[2:0], source[7:3]};
			3'b011: KF8259_Common_Package_rotate_right = {source[3:0], source[7:4]};
			3'b100: KF8259_Common_Package_rotate_right = {source[4:0], source[7:5]};
			3'b101: KF8259_Common_Package_rotate_right = {source[5:0], source[7:6]};
			3'b110: KF8259_Common_Package_rotate_right = {source[6:0], source[7]};
			3'b111: KF8259_Common_Package_rotate_right = source;
			default: KF8259_Common_Package_rotate_right = source;
		endcase
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		next_highest_level_in_service = next_in_service_register & ~interrupt_special_mask;
		next_highest_level_in_service = KF8259_Common_Package_rotate_right(next_highest_level_in_service, priority_rotate);
		next_highest_level_in_service = KF8259_Common_Package_resolv_priority(next_highest_level_in_service);
		next_highest_level_in_service = KF8259_Common_Package_rotate_left(next_highest_level_in_service, priority_rotate);
	end
	always @(negedge clock or posedge reset)
		if (reset)
			highest_level_in_service <= 8'b00000000;
		else
			highest_level_in_service <= next_highest_level_in_service;
	initial _sv2v_0 = 0;
endmodule
module KF8259_Interrupt_Request (
	clock,
	reset,
	level_or_edge_toriggered_config,
	freeze,
	clear_interrupt_request,
	interrupt_request_pin,
	interrupt_request_register
);
	input wire clock;
	input wire reset;
	input wire level_or_edge_toriggered_config;
	input wire freeze;
	input wire [7:0] clear_interrupt_request;
	input wire [7:0] interrupt_request_pin;
	output reg [7:0] interrupt_request_register;
	reg [7:0] low_input_latch;
	wire [7:0] interrupt_request_edge;
	genvar _gv_ir_bit_no_1;
	generate
		for (_gv_ir_bit_no_1 = 0; _gv_ir_bit_no_1 <= 7; _gv_ir_bit_no_1 = _gv_ir_bit_no_1 + 1) begin : Request_Latch
			always @(negedge clock or posedge reset)
				if (reset)
					low_input_latch[_gv_ir_bit_no_1] <= 1'b0;
				else if (clear_interrupt_request[_gv_ir_bit_no_1])
					low_input_latch[_gv_ir_bit_no_1] <= 1'b0;
				else if (~interrupt_request_pin[_gv_ir_bit_no_1])
					low_input_latch[_gv_ir_bit_no_1] <= 1'b1;
				else
					low_input_latch[_gv_ir_bit_no_1] <= low_input_latch[_gv_ir_bit_no_1];
			assign interrupt_request_edge[_gv_ir_bit_no_1] = (low_input_latch[_gv_ir_bit_no_1] == 1'b1) & (interrupt_request_pin[_gv_ir_bit_no_1] == 1'b1);
			always @(negedge clock or posedge reset)
				if (reset)
					interrupt_request_register[_gv_ir_bit_no_1] <= 1'b0;
				else if (clear_interrupt_request[_gv_ir_bit_no_1])
					interrupt_request_register[_gv_ir_bit_no_1] <= 1'b0;
				else if (freeze)
					interrupt_request_register[_gv_ir_bit_no_1] <= interrupt_request_register[_gv_ir_bit_no_1];
				else if (level_or_edge_toriggered_config)
					interrupt_request_register[_gv_ir_bit_no_1] <= interrupt_request_pin[_gv_ir_bit_no_1];
				else
					interrupt_request_register[_gv_ir_bit_no_1] <= interrupt_request_edge[_gv_ir_bit_no_1];
		end
	endgenerate
endmodule
module KF8259_Priority_Resolver (
	priority_rotate,
	interrupt_mask,
	interrupt_special_mask,
	special_fully_nest_config,
	highest_level_in_service,
	interrupt_request_register,
	in_service_register,
	interrupt
);
	reg _sv2v_0;
	input wire [2:0] priority_rotate;
	input wire [7:0] interrupt_mask;
	input wire [7:0] interrupt_special_mask;
	input wire special_fully_nest_config;
	input wire [7:0] highest_level_in_service;
	input wire [7:0] interrupt_request_register;
	input wire [7:0] in_service_register;
	output wire [7:0] interrupt;
	wire [7:0] masked_interrupt_request;
	assign masked_interrupt_request = interrupt_request_register & ~interrupt_mask;
	wire [7:0] masked_in_service;
	assign masked_in_service = in_service_register & ~interrupt_special_mask;
	wire [7:0] rotated_request;
	reg [7:0] rotated_in_service;
	wire [7:0] rotated_highest_level_in_service;
	reg [7:0] priority_mask;
	wire [7:0] rotated_interrupt;
	function [7:0] KF8259_Common_Package_rotate_right;
		input [7:0] source;
		input [2:0] rotate;
		casez (rotate)
			3'b000: KF8259_Common_Package_rotate_right = {source[0], source[7:1]};
			3'b001: KF8259_Common_Package_rotate_right = {source[1:0], source[7:2]};
			3'b010: KF8259_Common_Package_rotate_right = {source[2:0], source[7:3]};
			3'b011: KF8259_Common_Package_rotate_right = {source[3:0], source[7:4]};
			3'b100: KF8259_Common_Package_rotate_right = {source[4:0], source[7:5]};
			3'b101: KF8259_Common_Package_rotate_right = {source[5:0], source[7:6]};
			3'b110: KF8259_Common_Package_rotate_right = {source[6:0], source[7]};
			3'b111: KF8259_Common_Package_rotate_right = source;
			default: KF8259_Common_Package_rotate_right = source;
		endcase
	endfunction
	assign rotated_request = KF8259_Common_Package_rotate_right(masked_interrupt_request, priority_rotate);
	assign rotated_highest_level_in_service = KF8259_Common_Package_rotate_right(highest_level_in_service, priority_rotate);
	always @(*) begin
		if (_sv2v_0)
			;
		rotated_in_service = KF8259_Common_Package_rotate_right(masked_in_service, priority_rotate);
		if (special_fully_nest_config == 1'b1)
			rotated_in_service = (rotated_in_service & ~rotated_highest_level_in_service) | {rotated_highest_level_in_service[6:0], 1'b0};
	end
	always @(*) begin
		if (_sv2v_0)
			;
		if (rotated_in_service[0] == 1'b1)
			priority_mask = 8'b00000000;
		else if (rotated_in_service[1] == 1'b1)
			priority_mask = 8'b00000001;
		else if (rotated_in_service[2] == 1'b1)
			priority_mask = 8'b00000011;
		else if (rotated_in_service[3] == 1'b1)
			priority_mask = 8'b00000111;
		else if (rotated_in_service[4] == 1'b1)
			priority_mask = 8'b00001111;
		else if (rotated_in_service[5] == 1'b1)
			priority_mask = 8'b00011111;
		else if (rotated_in_service[6] == 1'b1)
			priority_mask = 8'b00111111;
		else if (rotated_in_service[7] == 1'b1)
			priority_mask = 8'b01111111;
		else
			priority_mask = 8'b11111111;
	end
	function [7:0] KF8259_Common_Package_resolv_priority;
		input [7:0] request;
		if (request[0] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00000001;
		else if (request[1] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00000010;
		else if (request[2] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00000100;
		else if (request[3] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00001000;
		else if (request[4] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00010000;
		else if (request[5] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b00100000;
		else if (request[6] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b01000000;
		else if (request[7] == 1'b1)
			KF8259_Common_Package_resolv_priority = 8'b10000000;
		else
			KF8259_Common_Package_resolv_priority = 8'b00000000;
	endfunction
	assign rotated_interrupt = KF8259_Common_Package_resolv_priority(rotated_request) & priority_mask;
	function [7:0] KF8259_Common_Package_rotate_left;
		input [7:0] source;
		input [2:0] rotate;
		casez (rotate)
			3'b000: KF8259_Common_Package_rotate_left = {source[6:0], source[7]};
			3'b001: KF8259_Common_Package_rotate_left = {source[5:0], source[7:6]};
			3'b010: KF8259_Common_Package_rotate_left = {source[4:0], source[7:5]};
			3'b011: KF8259_Common_Package_rotate_left = {source[3:0], source[7:4]};
			3'b100: KF8259_Common_Package_rotate_left = {source[2:0], source[7:3]};
			3'b101: KF8259_Common_Package_rotate_left = {source[1:0], source[7:2]};
			3'b110: KF8259_Common_Package_rotate_left = {source[0], source[7:1]};
			3'b111: KF8259_Common_Package_rotate_left = source;
			default: KF8259_Common_Package_rotate_left = source;
		endcase
	endfunction
	assign interrupt = KF8259_Common_Package_rotate_left(rotated_interrupt, priority_rotate);
	initial _sv2v_0 = 0;
endmodule
