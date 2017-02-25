`include "Sysbus.defs"

module uj_instr
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13
	)

	(
	  input  clk,
	         reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [19:0] immediate,
	  output [4:0] rd
	);

	always_comb begin
		rd = instruction[11:7];
		immediate = instruction[31:12];
		$display("jal %d", immediate);
	end
endmodule

module u_instr
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13
	)
	
	(
	  input  clk,
	         reset,

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
		case(opcode):
			7'b0110111: $display("lui $%d, %d", rd, immediate);
			7'b0110111: $display("auipc $%d, %d", rd, immediate);
			default: $display("");
	end
endmodule

module sb_instr
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13
	)
	
	(
	  input  clk,
	         reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [19:0] immediate,
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [11:0] offset
	);

	logic opcode = instruction[6:0];
	logic func3 = instruction[14:12];

	always_comb begin
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		offset = instruction[31:25];
		case(func3):
			3'b000: $display("beq $%d, $%d, %d", rs1, rs2, offset);
			3'b001: $display("bne $%d, $%d, %d", rs1, rs2, offset);
			3'b100: $display("blt $%d, $%d, %d", rs1, rs2, offset);
			3'b101: $display("bge $%d, $%d, %d", rs1, rs2, offset);
			3'b110: $display("bltu $%d, $%d, %d", rs1, rs2, offset;
			3'b111: $display("bgeu $%d, $%d, %d", rs1, rs2, offset);
			default: $display("");
	end
endmodule

module s_instr
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13
	)
	
	(
	  input  clk,
	         reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [11:0] offset
	);

	logic func3 = instruction[14:12];

	always_comb begin
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		offset = instruction[31:25];
		case(func3): //TODO: calculate the offsets
			3'b000: $display("sb $%d, %d($%d)", rs1, offset, rs2);
			3'b001: $display("sh $%d, %d($%d)", rs1, offset, rs2);
			3'b010: $display("sw $%d, %d($%d)", rs1, offset, rs2);
			3'b011: $display("sd $%d, %d($%d)", rs1, offset, rs2);
			default: $display("");
	end
endmodule

module r_instr
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13
	)
	
	(
	  input  clk,
	         reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [4:0] rd
	);

	logic opcode = instruction[6:0];
	logic func3 = instruction[14:12];
	logic func7 = instruction[31:25];

	always_comb begin
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		rd = instruction[11:7];
		if(opcode == 7'b0111011) begin //64R
			case(func3):
				3'b000: begin
						case(func7):
							7'b0000000: $display("addw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0000001: $display("mulw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("subw $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
					end
				3'b001: $display("sllw $%d, $%d, $%d", rd, rs1, rs2);
				3'b100: $display("divw $%d, $%d, $%d", rd, rs1, rs2);
				3'b101: begin
						case(func7):
							7'b0000000: $display("srlw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0000001: $display("divuw $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("sraw $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
					end
				3'b110: $display("remw $%d, $%d, $%d", rd, rs1, rs2);
				3'b111: $display("remuw $%d, $%d, $%d", rd, rs1, rs2);
				default: $display("");
		end
		else if(opcode == 7'b0110011) begin //32R
			if(func7 == 7'b0000001) begin
				case(func3):
					3'b000: $display("mul $%d, $%d, $%d", rd, rs1, rs2);
					3'b001: $display("mulh $%d, $%d, $%d", rd, rs1, rs2);
					3'b010: $display("mulhsu $%d, $%d, $%d", rd, rs1, rs2);
					3'b011: $display("mulhu $%d, $%d, $%d", rd, rs1, rs2);
					3'b100: $display("div $%d, $%d, $%d", rd, rs1, rs2);
					3'b101: $display("divu $%d, $%d, $%d", rd, rs1, rs2);
					3'b110: $display("rem $%d, $%d, $%d", rd, rs1, rs2);
					3'b111: $display("remu $%d, $%d, $%d", rd, rs1, rs2);
					default: $display("");
			end
			else begin
				case(func3):
					3'b000: begin
						case(func7):
							7'b0000000: $display("add $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("sub $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
					end
					3'b001: $display("sll $%d, $%d, $%d", rd, rs1, rs2);
					3'b010: $display("slt $%d, $%d, $%d", rd, rs1, rs2);
					3'b011: $display("sltu $%d, $%d, $%d", rd, rs1, rs2);
					3'b100: $display("xor $%d, $%d, $%d", rd, rs1, rs2);
					3'b101: begin
						case(func7):
							7'b0000000: $display("srl $%d, $%d, $%d", rd, rs1, rs2);
							7'b0100000: $display("sra $%d, $%d, $%d", rd, rs1, rs2);
							default: $display("");
					end
					3'b110: $display("or $%d, $%d, $%d", rd, rs1, rs2);
					3'b111: $display("and $%d, $%d, $%d", rd, rs1, rs2);
					default: $display("");
			end
		end
	end
endmodule

module i_instr
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13
	)
	
	(
	  input  clk,
	         reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rs1,
	  output [11:0] immediate,
	  output [4:0] rd
	);

	//variables for all
	logic opcode = instruction[6:0];
	logic func3 = instruction[14:12];

	//variables for shiting
	//TODO: work shifting in below
	logic func7 = instruction[31:25];
	logic shamt = instruction[24:20];

	always_comb begin
		rs1 = instruction[19:15];
		immediate = instruction[31:20];
		rd = instruction[11:7];
		if(opcode == 7'b100111) begin //JALR
			$display("jalr $%d, $%d", rd, rs1);
		end
		else if(opcode == 7'b0000011) begin //load
			case(func3): //TODO: calculate the offsets
				3'b000: $display("lb $%d, %d($%d)", rd, immediate, rs1);
				3'b001: $display("lh $%d, %d($%d)", rd, immediate, rs1);
				3'b010: $display("lw $%d, %d($%d)", rd, immediate, rs1);
				3'b100: $display("lbu $%d, %d($%d)", rd, immediate, rs1);
				3'b101: $display("lhu $%d, %d($%d)", rd, immediate, rs1);
				default: $display("");
		end
		else if(opcode == 7'b0110011) begin //32I
			case(func3):
				3'b000: $display("addi $%d, $%d, %d", rd, rs1, immediate);
				3'b001: begin
						case(func7):
							7'b0000000: //TODO: shift logic
							7'b0100000: //TODO: shift logic
							default: $display("");
					end
				3'b010: $display("slti $%d, $%d, %d", rd, rs1, immediate);
				3'b011: $display("sltiu $%d, $%d, %d", rd, rs1, immediate);
				3'b100: $display("xori $%d, $%d, %d", rd, rs1, immediate);
				3'b101: begin
						case(func7):
							7'b0000000: //TODO: shift logic
							7'b0100000: //TODO: shift logic
							default: $display("");
					end
				3'b110: $display("ori $%d, $%d, %d", rd, rs1, immediate);
				3'b111: $display("andi $%d, $%d, %d", rd, rs1, immediate);
				default: $display("");
		end
		else if(opcode == 7'b0011011) begin //64I
			case(func3):
				3'b000: $display("addi $%d, $%d, %d", rd, rs1, immediate);
				3'b001: //TODO: shift logic
				3'b010: begin
						case(func7):
							7'b0000000: //TODO: shift logic
							7'b0100000: //TODO: shift logic
							default: $display("");
					end
				default: $display("");
		end
	end
endmodule