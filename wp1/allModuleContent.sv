`include "Sysbus.defs"
module reg_file
	(
	  input  clk,
	  //       reset,

	  //reading inputs
	  input [4:0] rs1,
	  input [4:0] rs2,

	  //writing inputs
	  input write_sig, //signal to allow writing to any register
	  input [63:0] write_val, //value to write into register
	  input [4:0] write_reg, //register to write into
	  
	  // outputs
	  output [63:0] rs1_val,
	  output [63:0] rs2_val
	  //output write_ack //unknown if necessary
	);

	//setup registers
	logic [63:0] registers[31:0];
	logic [63:0] value = write_val;

	initial begin
		for (int i = 0; i < 32; i++) begin
			registers[i] = 64'b0;
		end
	end

	//ensure that register $0 is always 0
	always_comb begin
		registers[0] = 0;
		if(write_reg == 0)
			value = 0;
		else
			value = write_val;
	end

	//output the values of the requested registers
	always_ff @ (posedge clk) begin
		rs1_val <= registers[rs1];
		rs2_val <= registers[rs2];
	end

	//write to indicated register if requested
	always_ff @(posedge clk) begin
		if(write_sig == 1)
			registers[write_reg] <= value;
		else
			registers[write_reg] <= registers[write_reg];
	end
endmodule

module alu
	#(
		ADD = 0,
		SUB = 1,
		MUL = 2,
		DIV = 3,
		XOR = 4,
		AND = 5,
		OR = 6,
		REM = 7,
		NOT = 8
	)
	(
	  input  clk,
	  input [4:0] opcode,
	  input [63:0] value1,
	  input [63:0] value2,

	  output [63:0] result
	);

	always_ff @(posedge clk) begin
		case(opcode)
			ADD: result <= value1 + value2;
			SUB: result <= value1 - value2;
			MUL: result <= value1 * value2;
			DIV: result <= value1 / value2;
			XOR: result <= value1 ^ value2;
			AND: result <= value1 & value2;
			OR: result <= value1 | value2;
			REM: result <= value1 % value2;
			NOT: result <= ~value1;
			default: result <= value1;
		endcase
	end

endmodule
