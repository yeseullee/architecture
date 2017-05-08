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
	logic signed [127:0] long_result = 0;
	logic unsigned [63:0] check = 0;

	//TODO: Deal with firstval and secondval.
	//TODO: W instructions and Unsigned instructions.
	//TODO: Deal with shifting + use shamt.

	always_comb begin	
	    //Both firstVal and secondVal are signed by default.
	    firstVal = $signed(value1);
	    secondVal = $signed(value2);
            u_firstVal = $unsigned(value1);
            u_secondVal = $unsigned(value2);

	    if (instr_type == `RTYPE) begin
		secondVal = $signed(value2);
                u_secondVal = $unsigned(value2);
	    end
	    if (instr_type == `ITYPE || instr_type == `STYPE) begin
		secondVal = $signed(immediate);
                u_secondVal = $unsigned(immediate);
	    	if (opcode == `SLL || opcode == `SRL || opcode == `SRA) begin
		    u_secondVal = $unsigned(shamt);
		end		
	    end

	    case(opcode)
		`ADD: 
		    begin
			//ADD, ADDI, LI, MV, load, store, etc. use this.
			result = firstVal + secondVal;
	            end
		`SUB: result = firstVal - secondVal;
		`MUL: 
		    begin
			result = firstVal * secondVal;
		    end
		`MULH: 
		    begin
			long_result = firstVal * secondVal;
			result = long_result[127:64];
		    end
		`MULHU: 
		    begin //Unsigned * Unsigned
			long_result = u_firstVal * u_secondVal;
			result = long_result[127:64];
		    end
		`MULHSU: 
		    begin // Signed * Unsigned
			long_result = firstVal * u_secondVal;
			result = long_result[127:64];
		    end
		`DIV: 
		    begin //Signed div
			result = firstVal / secondVal;
		    end
		`DIVU: 
		    begin //Unsigned div
                        result = u_firstVal / u_secondVal;       
                    end
		`XOR: result = firstVal ^ secondVal;
		`AND: result = firstVal & secondVal;
		`OR:  result = firstVal | secondVal;
			
		`REM: 
		    begin //remainder from signed div.
		        result = firstVal % secondVal; 
		    end
		`REMU: 
		    begin //remainder from unsigned div.
                        result = u_firstVal % u_secondVal; 
		    end
		`NOT: result = ~firstVal;
		`SLL: result = u_firstVal << u_secondVal[5:0];
		`SRL: result = u_firstVal >> u_secondVal[5:0];
		`SRA: result = u_firstVal >>> u_secondVal[5:0];
		`LESS:
		    //used by SLTI (both signed numbers) 
		    begin
			if(firstVal < secondVal) begin
			    result = 1;
			end else begin
			    result = 0;
			end
		    end
		`LESSU:
		    begin
			if(u_firstVal < u_secondVal) begin
			    result = 1;
			end else begin
			    result = 0;
			end
		    end
		`SLTIU:
		    //Unsigned less SLTIU
		    //the immediate is sign extended, treated as unsigned.
		    begin
			if(u_firstVal < secondVal) begin
			    result = 1;
			end else begin
			    result = 0;
			end
		    end
		`EQUAL:
		    begin
			if(firstVal == secondVal) begin
			    result = 1;
			end else begin
			    result = 0;
			end
		    end
		`NEQ:
		    begin
			if(firstVal != secondVal) begin
			    result = 1;
			end else begin
			    result = 0;
			end
		    end
		`GTE:
		    begin
			if(firstVal >= secondVal) begin
			    result = 1;
			end else begin
			    result = 0;
			end
		    end
		`GTEU:
		    begin
			if(u_firstVal >= u_secondVal) begin
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
	        //$display("Opcode %d First num %d Second num %d Immediate %d, Result %d", opcode, value1, value2, immediate, result);
	    end
	end

endmodule

