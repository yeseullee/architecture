`include "Sysbus.defs"
`include "Alu.defs"
`include "Mem.defs"
module decoder
	(
	  input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  input cur_pc,
	  
	  // outputs
	  output [4:0] rd,
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [31:0] immediate,
	  output [10:0] alu_op,
	  output [5:0] shamt,
	  output reg_write,
	  output [3:0] instr_type,
	  output [1:0] mem_access,
	  output [2:0] mem_size
	);

	logic [6:0] opcode = instruction[6:0];
	logic [2:0] func3 = instruction[14:12];
	logic [6:0] func7 = instruction[31:25];
	logic [31:0] prev_instr;
	logic [31:0] prev_instr_wire;
	logic signed [31:0] jal_imm;
	logic signed [31:0] u_imm, sb_imm;
	logic signed [31:0] i_imm, s_imm;

	//code to ensure each instruction is decoded only once
	always_comb begin
		if(prev_instr != instruction) begin
			opcode = instruction[6:0];
			//$display("The following instruction is: %h", instruction);
		end
		else begin
			opcode = 7'b0000000;
		end
		prev_instr_wire = instruction;
	end

	//decoding happens here
	always_comb begin
		//set outputs
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		rd = instruction[11:7];
		immediate = 32'b0;
		instr_type = `NOTYPE;
		alu_op = 11'b0; //TODO:insert all applicable alu ops below //Note-to-shanshan: all zero means no alu now.
		shamt = instruction[25:20]; //for i instruction type shifting
		reg_write = 1'b0;
		mem_access = `MEM_NO_ACCESS;
		mem_size = `MEM_NO_SIZE;

		//set immediate values
		jal_imm = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:25], instruction[24:21], 1'b0};
		u_imm = {instruction[31:12], 12'b0};
		sb_imm = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
		i_imm = {{21{instruction[31]}}, instruction[30:20]};
		s_imm = {{21{instruction[31]}}, instruction[30:25], instruction[11:7]};

		//begin differntiating
		case(opcode)
			//uj_instr
			7'b1101111: begin
					if(rd == 0) begin
						//pseudo-instruction for "jal x0, offset"
						$display("j %d", jal_imm);
						alu_op = `NOTHING;
					end
					else if(rd == 1) begin
						//pseudo-instruction for "jal x1, offset"
						$display("jal %d", jal_imm);
						alu_op = `NOTHING;
					end
					else begin
						$display("jal $%d, %d", rd, jal_imm);
						alu_op = `NOTHING;
					end
					immediate = jal_imm + cur_pc;
					instr_type = `UJTYPE;
					reg_write = 1;
					//rd = 1; //jal stores address into register, set to $1 by standard convention
				end

			//u_instr
			7'b0110111: begin
					$display("lui $%d, %d", rd, u_imm);
					immediate = u_imm;
					alu_op = `IMMVAL;
					instr_type = `UTYPE;
					reg_write = 1;
				end
			7'b0010111: begin
					$display("auipc $%d, %d", rd, u_imm);
					immediate = u_imm + cur_pc;
					alu_op = `IMMVAL;
					instr_type = `UTYPE;
					reg_write = 1;
				end

			//sb_instr
			//TODO: a lot of these are just simple comparison operations
			7'b1100011: begin
					case(func3)
						3'b000: begin
								if(rs2 == 0) begin
									//pseudo-instruction for "beq rs1, x0, offset"
									$display("beqz $%d, %d", rs1, sb_imm);
									alu_op = `EQUAL;
								end
								else begin
									$display("beq $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `EQUAL;
								end
							end
						3'b001: begin
								if(rs2 == 0) begin
									//pseudo-instruction for "bne rs1, x0, offset"
									$display("bnez $%d, %d", rs1, sb_imm);
									alu_op = `NEQ;
								end
								else begin
									$display("bne $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `NEQ;
								end
							end
						3'b100: begin
								if(rs1 == 0) begin
									//pseudo-instruction for "blt x0, rs2, offset"
									$display("bgtz $%d, %d", rs2, sb_imm);
									alu_op = `LESS;
								end
								else if(rs2 == 0) begin
									//pseudo-instruction for "blt rs1, x0, offset"
									$display("bltz $%d, %d", rs1, sb_imm);
									alu_op = `LESS;
								end
								else begin
									$display("blt $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `LESS;
								end
							end
						3'b101: begin
								if(rs1 == 0) begin
									//pseudo-instruction for "bge x0, rs2, offset"
									$display("blez $%d, %d", rs2, sb_imm);
									alu_op = `GTE;
								end
								else if(rs2 == 0) begin
									//pseudo-instruction for "bge rs1, x0, offset"
									$display("bgez $%d, %d", rs1, sb_imm);
									alu_op = `GTE;
								end
								else begin
									$display("bge $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `GTE;
								end
							end
						3'b110: begin
								$display("bltu $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = `LESSU;
							end
						3'b111: begin
								$display("bgeu $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = `GTEU;
							end
					endcase
					immediate = sb_imm + cur_pc;
					instr_type = `SBTYPE;
				end

			//s_instr
			7'b0100011: begin
					case(func3)
						3'b000: begin
								$display("sb $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_BYTE;
							end
						3'b001: begin
								$display("sh $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = 4`ADD;
								mem_size = `MEM_HALF;
							end
						3'b010: begin
								$display("sw $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_WORD;
							end
						3'b011: begin
								$display("sd $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_DOUBLE;
							end
					endcase
					immediate = s_imm;
					instr_type = `STYPE;
					mem_access = `MEM_WRITE;
				end
			
			//r_instr
			7'b0111011: begin //64R
					case(func3)
						3'b000: begin
								case(func7)
									7'b0000000: begin
											$display("addw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op =4'b0001;
										end
									7'b0000001: begin
											$display("mulw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0011;
										end
									7'b0100000: begin
											if(rs1 == 0) begin
												//pseudo-instruction for "subw rd, x0, rs2"
												$display("negw $%d, $%d", rd, rs2);
												alu_op = 4'd2;
											end
											else begin
												$display("subw $%d, $%d, $%d", rd, rs1, rs2);
												alu_op = 4'd2;
											end
										end
								endcase
							end
						3'b001: begin
								$display("sllw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `SLL;
							end
						3'b100: begin
								$display("divw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = 4'b0100;
							end
						3'b101: begin
								case(func7)
									7'b0000000: begin
											$display("srlw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRL;
										end
									7'b0000001: begin
											$display("divuw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0100;
										end
									7'b0100000: begin
											$display("sraw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRA;
										end
								endcase
							end
						3'b110: begin
								$display("remw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `REM;
							end
						3'b111: begin
								$display("remuw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `REMU;
							end
					endcase
					reg_write = 1;
					instr_type = `RTYPE;
				end
			7'b0110011: begin //32R
					if(func7 == 7'b0000001) begin
						case(func3)
							3'b000: begin
									$display("mul $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MUL;
								end
							3'b001: begin
									$display("mulh $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MULH;
								end
							3'b010: begin
									$display("mulhsu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MULHSU;
								end
							3'b011: begin
									$display("mulhu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MULHU;
								end
							3'b100: begin
									$display("div $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `DIV;
								end
							3'b101: begin
									$display("divu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `DIVU;
								end
							3'b110: begin
									$display("rem $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `REM;
								end
							3'b111: begin
									$display("remu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `REMU;
								end
						endcase
					end
					else begin
						case(func3)
							3'b000: begin
								case(func7)
									7'b0000000: begin
											$display("add $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `ADD;
										end
									7'b0100000: begin
											if(rs1 == 0) begin
												//pseudo-instruction for "sub rd, 0, rs2"
												$display("neg $%d, $%d", rd, rs2);
												alu_op = `SUB;
											end
											else begin
												$display("sub $%d, $%d, $%d", rd, rs1, rs2);
												alu_op = `SUB;
											end
										end
								endcase
							end
							3'b001: begin
									$display("sll $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `SLL;
								end
							3'b010: begin
									if(rs1 == 0) begin
										//pseudo-instruction for "slt rd, x0, rs2"
										$display("sgtz $%d, $%d", rd, rs2);
										alu_op = `LESS;
									end
									else if(rs2 == 0) begin
										//pseudo-instruction for "slt rd, rs1, x0"
										$display("sltz $%d, $%d", rd, rs1);
										alu_op = `LESS;
									end
									else begin
										$display("slt $%d, $%d, $%d", rd, rs1, rs2);
										alu_op = `LESS;
									end
								end
							3'b011: begin
									if(rs1 == 0) begin
										//pseudo-instruction for "sltu rd, x0, rs2"
										$display("snez $%d, $%d", rd, rs2);
										alu_op = `LESSU;
									end
									else begin
										$display("sltu $%d, $%d, $%d", rd, rs1, rs2);
										alu_op = `LESSU;
									end
								end
							3'b100: begin
									$display("xor $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `XOR;
								end
							3'b101: begin
								case(func7)
									7'b0000000: begin
											$display("srl $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRL;
										end
									7'b0100000: begin
											$display("sra $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRA;
										end
								endcase
							end
							3'b110: begin
									$display("or $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `OR;
								end
							3'b111: begin
									$display("and $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `AND;
								end
						endcase
					end
					reg_write = 1;
					instr_type = `RTYPE;
				end

			//i_instr
			7'b1100111: begin
					if(i_imm == 0 && rd == 0 && rs1 == 1) begin
						//pseudo-instruction for "jalr x0, x1, 0"
						$display("ret");
						alu_op = `NOTHING;
					end
					else if(i_imm == 0 && rd == 0) begin
						//pseudo-instruction for "jalr x0, rs1, 0"
						$display("jr $%d", rs1);
						alu_op = `NOTHING;
					end
					else if(i_imm == 0 && rd == 1) begin
						//pseudo-instruction for "jalr x1, rs1, 0"
						$display("jalr $%d", rs1);
						alu_op = `NOTHING;
					end
					else begin
						$display("jalr $%d, $%d", rd, rs1);
						alu_op = `NOTHING;
					end
					immediate = i_imm + cur_pc;
					reg_write = 1;
					instr_type = `ITYPE;
				end
			7'b0000011: begin //load
					case(func3)
						3'b000: begin
								$display("lb $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_BYTE;
							end
						3'b001: begin
								$display("lh $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_HALF;
							end
						3'b010: begin
								$display("lw $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_WORD;
							end
						3'b011: begin
								$display("ld $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_DOUBLE;
							end
						3'b100: begin
								$display("lbu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_US_BYTE;
							end
						3'b101: begin
								$display("lhu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_US_HALF;
							end
						3'b110: begin
								$display("lwu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_US_WORD;
							end
					endcase
					immediate = i_imm;
					instr_type = `ITYPE;
					reg_write = 1;
					mem_access = `MEM_READ;
				end
			7'b0010011: begin //32I
					case(func3)
						3'b000: begin
								if(i_imm == 0 && rd == 0 && rs1 == 0) begin
									//pseudo-instruction for "addi x0, x0, 0"
									$display("nop");
									alu_op = `ADD;
								end
								else if(i_imm == 0) begin
									//pseudo-instruction for "addi rd, rs1, 0"
									$display("mv $%d, $%d", rd, rs1);
									alu_op = `ADD;
								end
								else if(rs1 == 0) begin
									//pseudo-instruction for "addi rd, x0, imm"
									$display("li $%d, %d", rd, i_imm);
									alu_op = `ADD;
								end
								else begin
									$display("addi $%d, $%d, %d", rd, rs1, i_imm);
									alu_op = `ADD;
								end
							end
						3'b001: begin
								$display("slli $%d, $%d %d", rd, rs1, shamt);
								immediate = {26'b0, shamt};
								alu_op = `SLL;
							end
						3'b010: begin
								$display("slti $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = `LESS;
							end
						3'b011: begin
								if(i_imm == 1) begin
									//pseudo-instruction for "slitu rd, rs1, 1"
									$display("seqz $%d, $%d", rd, rs1);
									alu_op = `SLTIU;
								end
								else begin
									$display("sltiu $%d, $%d, %d", rd, rs1, i_imm);
									alu_op = `SLTIU;
								end
							end
						3'b100: begin
								if(&i_imm == 1'b1) begin
									//pseudo-instruction for "xori rd, rs1, -1"
									$display("not $%d, $%d", rd, rs1);
									alu_op = `XOR;
								end
								else begin
									$display("xori $%d, $%d, %d", rd, rs1, i_imm);
									alu_op = `XOR;
								end
							end
						3'b101: begin
								case(func7)
									7'b0000000: begin
											$display("srli $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = `SRL;
										end
									7'b0100000: begin
											$display("srai $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = `SRA;
										end
								endcase
							end
						3'b110: begin
								$display("ori $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = `OR;
							end
						3'b111: begin
								$display("andi $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = `AND;
							end
					endcase
					immediate = i_imm;
					reg_write = 1;
					instr_type = `ITYPE;
				end
			7'b0011011: begin //64I
					case(func3)
						3'b000: begin
								if(i_imm == 0) begin
									//pseudo-instruction for "addiw rd, rs1, x0"
									$display("sext.w $%d, $%d", rd, rs1);
									alu_op = `ADD;
									//since it's a pseudo instructionm, should have same as addiw
								end
								else begin
									$display("addiw $%d, $%d, %d", rd, rs1, i_imm);
									immediate = i_imm;
									alu_op = 4'b0001;
								end
							end
						3'b001: begin
								$display("slliw $%d, $%d %d", rd, rs1, shamt);
								immediate = {26'b0, shamt};
								alu_op = `SLL;
							end
						3'b010: begin
								case(func7)
									7'b0000000: begin
											$display("srliw $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = `SRL;
										end
									7'b0100000: begin
											$display("sraiw $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = `SRA;
										end
								endcase
							end
					endcase
					immediate = i_imm;
					reg_write = 1;
					instr_type = `ITYPE;
				end

			//default cases
			7'b0000000: ;//$display("This instruction has been decoded before: %b|%b|%b|%b|%b|%b", func7, rs2, rs1, func3, rd, opcode);
			default: $display("This instruction is not recognized: %b|%b|%b|%b|%b|%b", func7, rs2, rs1, func3, rd, opcode);
		endcase
		prev_instr_wire = instruction;
	end

	always_ff @ (posedge clk) begin
		prev_instr <= prev_instr_wire;
	end
endmodule
