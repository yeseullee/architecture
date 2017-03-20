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
	  input signed [63:0] value1,
	  input signed [63:0] value2,
	  input signed [31:0] immediate,

	  output signed [63:0] result
	);

	reg signed [63:0] _result = 0;
	reg signed [63:0] secondVal;

//TODO: I gotta look into immediate to operate with value 1. 	
	always_comb begin	
		if(immediate != 0)begin
			secondVal = immediate;
		end else begin
			secondVal = value2;
		end
		case(opcode)
			ADD: result = value1 + secondVal;
			SUB: result = value1 - secondVal;
			MUL: result = value1 * secondVal;
			DIV: result = value1 / secondVal;
			XOR: result = value1 ^ secondVal;
			AND: result = value1 & secondVal;
			OR: result = value1 | secondVal;
			REM:result = value1 % secondVal;
			NOT: result = ~value1;
			NOTHING: ;//_result = result;
			//default: _result = value1;
		endcase
	end

	always_ff @ (posedge clk) begin
		if(opcode != NOTHING) begin
			$display("Opcode %d First num %d Second num %d Immediate %d, Result %d", opcode, value1, value2, immediate, result);
		end
	end

endmodule
