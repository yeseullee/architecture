`include "Sysbus.defs"
module alu
	#(
		NOTHING = 0,
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
	  input signed [31:0] immediate,

	  output [63:0] result
	);

	reg [63:0] _result = 0;
	
	always_comb begin	
		case(opcode)
			ADD: _result = value1 + value2;
			SUB: _result = value1 - value2;
			MUL: _result = value1 * value2;
			DIV: _result = value1 / value2;
			XOR: _result = value1 ^ value2;
			AND: _result = value1 & value2;
			OR: _result = value1 | value2;
			REM: _result = value1 % value2;
			NOT: _result = ~value1;
			NOTHING: _result = result;
			//default: _result = value1;
		endcase
	end

	always_ff @ (posedge clk) begin
		if(opcode != NOTHING) begin
			$display("First num %d Second num %d Immediate %d, Result %d", value1, value2, immediate, result);
		end
		result <= _result;
	end

endmodule
