`include "Sysbus.defs"
module alu
	#(
		ADD = 1,
		SUB = 2,
		MUL = 3,
		DIV = 4,
		XOR = 5,
		AND = 6,
		OR = 7,
		REM = 8,
		NOT = 9
	)
	(
	  input  clk,
	  input [3:0] opcode,
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