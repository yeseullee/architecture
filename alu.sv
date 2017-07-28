`include "Alu.defs"
module alu
	(
	  input  clk,
	  input [10:0] opcode,
	  input [63:0] value1,
	  input [63:0] value2,
	  input [31:0] immediate,
	  input [5:0] shamt,
	  input [3:0] instr_type,
          input isW,
	  output [63:0] result
	);

	logic signed [63:0] firstVal = 0;
	logic unsigned [63:0] u_firstVal = 0;
	logic signed [63:0] secondVal = 0;
	logic unsigned [63:0] u_secondVal = 0;
	logic signed [127:0] long_result = 0;

        logic [5:0] shift_amount = 0;
        logic [63:0] temporary_result = 0;

	always_comb begin	
	    //Both firstVal and secondVal are signed by default.
	    firstVal = $signed(value1);
            u_firstVal = $unsigned(value1);

	    if (instr_type == `ITYPE || instr_type == `STYPE) begin
		secondVal = $signed(immediate);
                u_secondVal = $unsigned(immediate);
	    end else begin
	        secondVal = $signed(value2);
	        u_secondVal = $unsigned(value2);
            end

	    if (opcode == `SLL || opcode == `SRL || opcode == `SRA) begin
		if(instr_type == `RTYPE) begin
                    if(isW)begin
                        shift_amount = {1'b0,value2[4:0]};
                    end else begin
                        shift_amount = value2[5:0];
                    end
                end else if(instr_type == `ITYPE) begin
                    shift_amount = shamt;
                end
	    end		
	    
	    case(opcode)
		`ADD: 
		    begin
			//ADD, ADDI, LI, MV, load, store, etc. use this.
                        if(isW) begin
			    temporary_result = firstVal[31:0] + secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal + secondVal;
                        end
	            end
		`SUB:
		    begin
                        if(isW) begin
			    temporary_result = firstVal[31:0] - secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal - secondVal;
                        end
	            end
		`MUL: 
		    begin
                        if(isW) begin
			    temporary_result = firstVal[31:0] * secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal * secondVal;
                        end
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
                        if(isW) begin
			    temporary_result = firstVal[31:0] / secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal / secondVal;
                        end
		    end
		`DIVU: 
		    begin //Unsigned div
                        if(isW) begin
			    temporary_result = u_firstVal[31:0] / u_secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = u_firstVal / u_secondVal;
                        end
                    end
		`XOR: result = firstVal ^ secondVal;
		`AND: result = firstVal & secondVal;
		`OR:  result = firstVal | secondVal;
			
		`REM: 
		    begin //remainder from signed div.
                        if(isW) begin
			    temporary_result = firstVal[31:0] % secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal % secondVal;
                        end
		    end
		`REMU: 
		    begin //remainder from unsigned div.
                        if(isW) begin
			    temporary_result = u_firstVal[31:0] % u_secondVal[31:0];
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = u_firstVal % u_secondVal;
                        end
		    end
		`NOT: result = ~firstVal;
		`SLL: 
		    begin
			if(isW) begin
			    temporary_result = firstVal[31:0] << shift_amount;
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal << shift_amount;
                        end
                    end
		`SRL:
		    begin
			if(isW) begin
			    temporary_result = firstVal[31:0] >> shift_amount;
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal >> shift_amount;
                        end
                    end
		`SRA:
		    begin
			if(isW) begin
			    temporary_result = firstVal[31:0] >>> shift_amount;
                            result = {{32{temporary_result[31]}}, temporary_result[31:0]};
                        end else begin
			    result = firstVal >>> shift_amount;
                        end
                    end
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
                `IMMVAL:
                    begin
                        //used in lui and auipc: just move sign-extended immediate value ro result
                        result = {{32{immediate[31]}}, immediate[31:0]};
                    end
                `JUMP_UNCOND:
                    begin
                        result = immediate;
                    end
		`NOTHING: ;//_result = result;
	    endcase
	end

	always_ff @ (posedge clk) begin
		
	    if(opcode != `NOTHING) begin
	        //$display("Opcode %d First num %d Second num %d Immediate %d, Result %d", opcode, value1, value2, immediate, result);
	    end
	end

endmodule

