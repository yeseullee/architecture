`include "Sysbus.defs"

module uj_instr
	(
	  //input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [19:0] immediate,
	  output [4:0] rd
	);

	logic[6:0] opcode = instruction[6:0];

	always_comb begin
		rd = instruction[11:7];
		immediate = instruction[31:12];
		if(opcode == 7'b1100111)
			$display("jal %d", immediate);
	end
endmodule

module u_instr
	(
	  //input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [19:0] immediate,
	  output [4:0] rd
	);

	logic opcode = instruction[6:0];

	always_comb begin
		rd = instruction[11:7];
		immediate = instruction[31:12];
		case(opcode)
			7'b0110111: $display("lui $%d, %d", rd, immediate);
			7'b0010111: $display("auipc $%d, %d", rd, immediate);
			default: $display("");
		endcase
	end
endmodule

module sb_instr
	(
	  //input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] immediate, //TODO: figure out how these immediate values work
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [6:0] offset
	);

	logic [6:0] opcode = instruction[6:0];
	logic [2:0] func3 = instruction[14:12];

	always_comb begin
		if(opcode != 7'b1100011)
			func3 = 3'b010;
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		offset = instruction[31:25];
		immediate = instruction[11:7];
		case(func3)
			3'b000: $display("beq $%d, $%d, %d", rs1, rs2, offset);
			3'b001: $display("bne $%d, $%d, %d", rs1, rs2, offset);
			3'b100: $display("blt $%d, $%d, %d", rs1, rs2, offset);
			3'b101: $display("bge $%d, $%d, %d", rs1, rs2, offset);
			3'b110: $display("bltu $%d, $%d, %d", rs1, rs2, offset);
			3'b111: $display("bgeu $%d, $%d, %d", rs1, rs2, offset);
			default: $display(""); 
		endcase
	end
endmodule

module s_instr
	(
	  //input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [11:0] offset
	);

	logic [2:0] func3 = instruction[14:12];
	logic [6:0] opcode = instruction[6:0];

	always_comb begin
		if(opcode != 7'b0100011)
			func3 = 3'b111;
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		offset = {instruction[31:25], instruction[11:7]};
		case(func3) //TODO: calculate the offsets
			3'b000: $display("sb $%d, %d($%d)", rs1, offset, rs2);
			3'b001: $display("sh $%d, %d($%d)", rs1, offset, rs2);
			3'b010: $display("sw $%d, %d($%d)", rs1, offset, rs2);
			3'b011: $display("sd $%d, %d($%d)", rs1, offset, rs2);
			default: $display("");
		endcase
	end
endmodule

module r_instr
	(
	  //input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [4:0] rd
	);

	logic [6:0] opcode = instruction[6:0];
	logic [2:0] func3 = instruction[14:12];
	logic [6:0] func7 = instruction[31:25];

	always_comb begin
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		rd = instruction[11:7];
		if(opcode == 7'b0111011) begin //64R
			case(func3)
				3'b000: begin
						case(func7)
							7'b0000000: $display("addw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0000001: $display("mulw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("subw $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
						endcase
					end
				3'b001: $display("sllw $%d, $%d, $%d", rd, rs1, rs2);
				3'b100: $display("divw $%d, $%d, $%d", rd, rs1, rs2);
				3'b101: begin
						case(func7)
							7'b0000000: $display("srlw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0000001: $display("divuw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("sraw $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
						endcase
					end
				3'b110: $display("remw $%d, $%d, $%d", rd, rs1, rs2);
				3'b111: $display("remuw $%d, $%d, $%d", rd, rs1, rs2);
				default: $display("");
			endcase
		end
		else if(opcode == 7'b0110011) begin //32R
			if(func7 == 7'b0000001) begin
				case(func3)
					3'b000: $display("mul $%d, $%d, $%d", rd, rs1, rs2);
					3'b001: $display("mulh $%d, $%d, $%d", rd, rs1, rs2);
					3'b010: $display("mulhsu $%d, $%d, $%d", rd, rs1, rs2);
					3'b011: $display("mulhu $%d, $%d, $%d", rd, rs1, rs2);
					3'b100: $display("div $%d, $%d, $%d", rd, rs1, rs2);
					3'b101: $display("divu $%d, $%d, $%d", rd, rs1, rs2);
					3'b110: $display("rem $%d, $%d, $%d", rd, rs1, rs2);
					3'b111: $display("remu $%d, $%d, $%d", rd, rs1, rs2);
					default: $display("");
				endcase
			end
			else begin
				case(func3)
					3'b000: begin
						case(func7)
							7'b0000000: $display("add $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("sub $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
						endcase
					end
					3'b001: $display("sll $%d, $%d, $%d", rd, rs1, rs2);
					3'b010: $display("slt $%d, $%d, $%d", rd, rs1, rs2);
					3'b011: $display("sltu $%d, $%d, $%d", rd, rs1, rs2);
					3'b100: $display("xor $%d, $%d, $%d", rd, rs1, rs2);
					3'b101: begin
						case(func7)
							7'b0000000: $display("srl $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("sra $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
						endcase
					end
					3'b110: $display("or $%d, $%d, $%d", rd, rs1, rs2);
					3'b111: $display("and $%d, $%d, $%d", rd, rs1, rs2);
					default: $display("");
				endcase
			end
		end
	end
endmodule

module i_instr
	(
	  //input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rs1,
	  output [11:0] immediate,
	  output [4:0] rd
	);

	//variables for all
	logic [6:0] opcode = instruction[6:0];
	logic [2:0] func3 = instruction[14:12];

	//variables for shiting
	//TODO: work shifting in below
	logic [6:0] func7 = instruction[31:25];
	logic [4:0] shamt = instruction[24:20];

	always_comb begin
		rs1 = instruction[19:15];
		immediate = instruction[31:20];
		rd = instruction[11:7];
		if(opcode == 7'b100111) begin //JALR
			$display("jalr $%d, $%d", rd, rs1);
		end
		else if(opcode == 7'b0000011) begin //load
			case(func3) //TODO: calculate the offsets
				3'b000: $display("lb $%d, %d($%d)", rd, immediate, rs1);
				3'b001: $display("lh $%d, %d($%d)", rd, immediate, rs1);
				3'b010: $display("lw $%d, %d($%d)", rd, immediate, rs1);
				3'b100: $display("lbu $%d, %d($%d)", rd, immediate, rs1);
				3'b101: $display("lhu $%d, %d($%d)", rd, immediate, rs1);
				default: $display("");
			endcase
		end
		else if(opcode == 7'b0110011) begin //32I
			case(func3)
				3'b000: $display("addi $%d, $%d, %d", rd, rs1, immediate);
				3'b001: begin
						case(func7)
							7'b0000000: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
							7'b0100000: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
							default: $display("");
						endcase
					end
				3'b010: $display("slti $%d, $%d, %d", rd, rs1, immediate);
				3'b011: $display("sltiu $%d, $%d, %d", rd, rs1, immediate);
				3'b100: $display("xori $%d, $%d, %d", rd, rs1, immediate);
				3'b101: begin
						case(func7)
							7'b0000000: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
							7'b0100000: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
							default: $display("");
						endcase
					end
				3'b110: $display("ori $%d, $%d, %d", rd, rs1, immediate);
				3'b111: $display("andi $%d, $%d, %d", rd, rs1, immediate);
				default: $display("");
			endcase
		end
		else if(opcode == 7'b0011011) begin //64I
			case(func3)
				3'b000: $display("addi $%d, $%d, %d", rd, rs1, immediate);
				3'b001: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
				3'b010: begin
						case(func7)
							7'b0000000: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
							7'b0100000: $display("Not yet supported, shamt = %d", shamt);//TODO: shift logic
							default: $display("");
						endcase
					end
				default: $display("");
			endcase
		end
	end
endmodule

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
	  //       reset,

	  //inputs
	  input [7:0] opcode,
	  input [63:0] value1,
	  input [63:0] value2,
	  
	  // outputs
	  output [63:0] result
	);

	logic [63:0] ans;

	always_comb begin
		if (|value2 != 0) begin
			case(opcode)
				ADD: ans = value1 + value2;
				SUB: ans = value1 - value2;
				MUL: ans = value1 * value2;
				DIV: ans = value1 / value2;
				XOR: ans = value1 ^ value2;
				AND: ans = value1 & value2;
				OR: ans = value1 | value2;
				REM: ans = value1 % value2;
				NOT: ans = ~value1;
				default: ans = ans;
			endcase
		end
		else
			ans = ans;
	end

	always_ff @(posedge clk) begin
		result <= ans;
	end
endmodule
