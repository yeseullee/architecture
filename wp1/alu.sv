`include "Sysbus.defs"
`include "Alu.defs"
module alu
	(
	  input  clk,
	  input [10:0] opcode,
	  input signed [63:0] value1,
	  input signed [63:0] value2,
	  input signed [31:0] immediate,
	  input [5:0] shamt,
	  input [3:0] instr_type,
	  output signed [63:0] result
	);

	logic signed [63:0] firstVal = 0;
	logic unsigned [63:0] u_firstVal = 0;
	logic signed [63:0] secondVal = 0;
	logic unsigned [63:0] u_secondVal = 0;

	//TODO: Deal with firstval and secondval.
	//TODO: W instructions and Unsigned instructions.

	always_comb begin	
		if(immediate != 0)begin
			secondVal = immediate;
		end else if((opcode >= 4'd9) && (opcode <= 4'd12)) begin 
			secondVal = shamt;
		end else begin
			secondVal = value2;
		end
		
		case(opcode)
			`ADD: result = value1 + secondVal;
			`SUB: result = value1 - secondVal;
			`MUL: result = value1 * secondVal;
			`DIV: result = value1 / secondVal;
			`XOR: result = value1 ^ secondVal;
			`AND: result = value1 & secondVal;
			`OR: result = value1 | secondVal;
			`REM:result = value1 % secondVal;
			`NOT: result = ~value1;
			//`LOGLEFT: result = value1 << secondVal;
			//`LOGRIGHT: result = value1 >> secondVal;
			//`ARTHRIGHT: result = value1 >>> secondVal;
			`LESS: begin
				if(value1 < secondVal)begin
					result = 1;
				end else begin
					result = 0;
				end
			       end
			`NOTHING: ;//_result = result;
			//default: _result = value1;
		endcase
	end

	always_ff @ (posedge clk) begin
		
		if(opcode != `NOTHING) begin
			$display("Opcode %d First num %d Second num %d Immediate %d, Result %d", opcode, value1, value2, immediate, result);
		end
	end

endmodule
