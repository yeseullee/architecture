`include "Alu.defs"
`include "Mem.defs"
module decoder
	(
	  input  clk,

	  // instruction to read
	  input [31:0] instruction,
	  input [63:0] cur_pc,
	  
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
	  output [2:0] mem_size,
          output [1:0] isECALL,
          output [2:0] isBranch,
          output isW
	);

	logic [6:0] opcode = instruction[6:0];
	logic [2:0] func3 = instruction[14:12];
	logic [6:0] func7 = instruction[31:25];
	logic [31:0] prev_instr;
	logic [31:0] prev_instr_wire;
	logic signed [31:0] jal_imm;
	logic signed [31:0] u_imm, sb_imm;
	logic signed [31:0] i_imm, s_imm;
        logic debug = 0;

	//decoding happens here
	always_comb begin
		//set outputs
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		rd = instruction[11:7];
		immediate = 32'b0;
		instr_type = `NOTYPE;
		alu_op = 11'b0; 
		shamt = instruction[25:20]; //for i instruction type shifting
		reg_write = 1'b0;
		mem_access = `MEM_NO_ACCESS;
		mem_size = `MEM_NO_SIZE;
                isECALL = 0;
                isBranch = 0;
                isW = 0;

		//set immediate values
		jal_imm = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};
		u_imm = {instruction[31:12], 12'b0};
		sb_imm = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
		i_imm = {{21{instruction[31]}}, instruction[30:20]};
		s_imm = {{21{instruction[31]}}, instruction[30:25], instruction[11:7]};

		//Begin differentiating
		case(opcode)
			//uj_instr
			7'b1101111: begin
					if(rd == 0) begin
						//pseudo-instruction for "jal x0, offset"
						if(debug) $display("j %d", jal_imm);
						alu_op = `JUMP_UNCOND;
					end
					else if(rd == 1) begin
						//pseudo-instruction for "jal x1, offset"
						if(debug) $display("jal %d", jal_imm);
						alu_op = `JUMP_UNCOND;
					end
					else begin
						if(debug) $display("jal $%d, %d", rd, jal_imm);
						alu_op = `JUMP_UNCOND;
					end
					immediate = jal_imm + cur_pc;
					instr_type = `UJTYPE;
					reg_write = 1;
                                        isBranch = `UNCOND;
					//rd = 1; //jal stores address into register, set to $1 by standard convention
				end

			//u_instr
			7'b0110111: begin
					if(debug) $display("lui $%d, %d", rd, u_imm);
					immediate = u_imm;
					alu_op = `IMMVAL;
					instr_type = `UTYPE;
					reg_write = 1;
				end
			7'b0010111: begin
					if(debug) $display("auipc $%d, %d", rd, u_imm);
					immediate = u_imm + cur_pc;
					alu_op = `IMMVAL;
					instr_type = `UTYPE;
					reg_write = 1;
				end

			//sb_instr
			7'b1100011: begin
					case(func3)
						3'b000: begin
								if(rs2 == 0) begin
									//pseudo-instruction for "beq rs1, x0, offset"
									if(debug) $display("beqz $%d, %d", rs1, sb_imm);
									alu_op = `EQUAL;
								end
								else begin
									if(debug) $display("beq $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `EQUAL;
								end
							end
						3'b001: begin
								if(rs2 == 0) begin
									//pseudo-instruction for "bne rs1, x0, offset"
									if(debug) $display("bnez $%d, %d", rs1, sb_imm);
									alu_op = `NEQ;
								end
								else begin
									if(debug) $display("bne $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `NEQ;
								end
							end
						3'b100: begin
								if(rs1 == 0) begin
									//pseudo-instruction for "blt x0, rs2, offset"
									if(debug) $display("bgtz $%d, %d", rs2, sb_imm);
									alu_op = `LESS;
								end
								else if(rs2 == 0) begin
									//pseudo-instruction for "blt rs1, x0, offset"
									if(debug) $display("bltz $%d, %d", rs1, sb_imm);
									alu_op = `LESS;
								end
								else begin
									if(debug) $display("blt $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `LESS;
								end
							end
						3'b101: begin
								if(rs1 == 0) begin
									//pseudo-instruction for "bge x0, rs2, offset"
									if(debug) $display("blez $%d, %d", rs2, sb_imm);
									alu_op = `GTE;
								end
								else if(rs2 == 0) begin
									//pseudo-instruction for "bge rs1, x0, offset"
									if(debug) $display("bgez $%d, %d", rs1, sb_imm);
									alu_op = `GTE;
								end
								else begin
									if(debug) $display("bge $%d, $%d, %d", rs1, rs2, sb_imm);
									alu_op = `GTE;
								end
							end
						3'b110: begin
								if(debug) $display("bltu $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = `LESSU;
							end
						3'b111: begin
								if(debug) $display("bgeu $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = `GTEU;
							end
					endcase
					immediate = sb_imm + cur_pc;
					instr_type = `SBTYPE;
                                        isBranch = `COND;
				end

			//s_instr
			7'b0100011: begin
					case(func3)
						3'b000: begin
								if(debug) $display("sb $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_BYTE;
							end
						3'b001: begin
								if(debug) $display("sh $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_HALF;
							end
						3'b010: begin
								if(debug) $display("sw $%d, %d($%d)", rs2, s_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_WORD;
							end
						3'b011: begin
								if(debug) $display("sd $%d, %d($%d)", rs2, s_imm, rs1);
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
											if(debug) $display("addw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op =`ADD;
										end
									7'b0000001: begin
											if(debug) $display("mulw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `MUL;
										end
									7'b0100000: begin
											if(rs1 == 0) begin
												//pseudo-instruction for "subw rd, x0, rs2"
												if(debug) $display("negw $%d, $%d", rd, rs2);
												alu_op = `SUB;
											end
											else begin
												if(debug) $display("subw $%d, $%d, $%d", rd, rs1, rs2);
												alu_op = `SUB;
											end
										end
								endcase
							end
						3'b001: begin
								if(debug) $display("sllw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `SLL;
							end
						3'b100: begin
								if(debug) $display("divw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `DIV;
							end
						3'b101: begin
								case(func7)
									7'b0000000: begin
											if(debug) $display("srlw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRL;
										end
									7'b0000001: begin
											if(debug) $display("divuw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `DIVU;
										end
									7'b0100000: begin
											if(debug) $display("sraw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRA;
										end
								endcase
							end
						3'b110: begin
								if(debug) $display("remw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `REM;
							end
						3'b111: begin
								if(debug) $display("remuw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = `REMU;
							end
					endcase
                                        isW = 1;
					reg_write = 1;
					instr_type = `RTYPE;
				end
			7'b0110011: begin //32R
					if(func7 == 7'b0000001) begin
						case(func3)
							3'b000: begin
									if(debug) $display("mul $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MUL;
								end
							3'b001: begin
									if(debug) $display("mulh $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MULH;
								end
							3'b010: begin
									if(debug) $display("mulhsu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MULHSU;
								end
							3'b011: begin
									if(debug) $display("mulhu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `MULHU;
								end
							3'b100: begin
									if(debug) $display("div $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `DIV;
								end
							3'b101: begin
									if(debug) $display("divu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `DIVU;
								end
							3'b110: begin
									if(debug) $display("rem $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `REM;
								end
							3'b111: begin
									if(debug) $display("remu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `REMU;
								end
						endcase
					end
					else begin
						case(func3)
							3'b000: begin
								case(func7)
									7'b0000000: begin
											if(debug) $display("add $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `ADD;
										end
									7'b0100000: begin
											if(rs1 == 0) begin
												//pseudo-instruction for "sub rd, 0, rs2"
												if(debug) $display("neg $%d, $%d", rd, rs2);
												alu_op = `SUB;
											end
											else begin
												if(debug) $display("sub $%d, $%d, $%d", rd, rs1, rs2);
												alu_op = `SUB;
											end
										end
								endcase
							end
							3'b001: begin
									if(debug) $display("sll $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `SLL;
								end
							3'b010: begin
									if(rs1 == 0) begin
										//pseudo-instruction for "slt rd, x0, rs2"
										if(debug) $display("sgtz $%d, $%d", rd, rs2);
										alu_op = `LESS;
									end
									else if(rs2 == 0) begin
										//pseudo-instruction for "slt rd, rs1, x0"
										if(debug) $display("sltz $%d, $%d", rd, rs1);
										alu_op = `LESS;
									end
									else begin
										if(debug) $display("slt $%d, $%d, $%d", rd, rs1, rs2);
										alu_op = `LESS;
									end
								end
							3'b011: begin
									if(rs1 == 0) begin
										//pseudo-instruction for "sltu rd, x0, rs2"
										if(debug) $display("snez $%d, $%d", rd, rs2);
										alu_op = `LESSU;
									end
									else begin
										if(debug) $display("sltu $%d, $%d, $%d", rd, rs1, rs2);
										alu_op = `LESSU;
									end
								end
							3'b100: begin
									if(debug) $display("xor $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `XOR;
								end
							3'b101: begin
								case(func7)
									7'b0000000: begin
											if(debug) $display("srl $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRL;
										end
									7'b0100000: begin
											if(debug) $display("sra $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = `SRA;
										end
								endcase
							end
							3'b110: begin
									if(debug) $display("or $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = `OR;
								end
							3'b111: begin
									if(debug) $display("and $%d, $%d, $%d", rd, rs1, rs2);
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
						if(debug) $display("ret");
						alu_op = `ADD;
                                                isBranch = `UNCOND;
					end
					else if(i_imm == 0 && rd == 0) begin
						//pseudo-instruction for "jalr x0, rs1, 0"
						if(debug) $display("jr $%d", rs1);
						alu_op = `ADD;

                                                isBranch = `UNCOND;
					end
					else if(i_imm == 0 && rd == 1) begin
						//pseudo-instruction for "jalr x1, rs1, 0"
						if(debug) $display("jalr $%d", rs1);
						alu_op = `ADD;
 
                                                isBranch = `UNCOND;
					end
					else begin
						if(debug) $display("jalr $%d, $%d", rd, rs1);
						alu_op = `ADD;

                                                isBranch = `UNCOND;
					end
					immediate = i_imm;
					reg_write = 1;
					instr_type = `ITYPE;
				end
			7'b0000011: begin //load
					case(func3)
						3'b000: begin
								if(debug) $display("lb $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_BYTE;
							end
						3'b001: begin
								if(debug) $display("lh $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_HALF;
							end
						3'b010: begin
								if(debug) $display("lw $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_WORD;
							end
						3'b011: begin
								if(debug) $display("ld $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_DOUBLE;
							end
						3'b100: begin
								if(debug) $display("lbu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_US_BYTE;
							end
						3'b101: begin
								if(debug) $display("lhu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = `ADD;
								mem_size = `MEM_US_HALF;
							end
						3'b110: begin
								if(debug) $display("lwu $%d, %d($%d)", rd, i_imm, rs1);
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
									if(debug) $display("nop");
									alu_op = `ADD;
								end
								else if(i_imm == 0) begin
									//pseudo-instruction for "addi rd, rs1, 0"
									if(debug) $display("mv $%d, $%d", rd, rs1);
									alu_op = `ADD;
								end
								else if(rs1 == 0) begin
									//pseudo-instruction for "addi rd, x0, imm"
									if(debug) $display("li $%d, %d", rd, i_imm);
									alu_op = `ADD;
								end
								else begin
									if(debug) $display("addi $%d, $%d, %d", rd, rs1, i_imm);
									alu_op = `ADD;
								end
							end
						3'b001: begin
								if(debug) $display("slli $%d, $%d %d", rd, rs1, shamt);
								immediate = {26'b0, shamt};
								alu_op = `SLL;
							end
						3'b010: begin
								if(debug) $display("slti $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = `LESS;
							end
						3'b011: begin
								if(i_imm == 1) begin
									//pseudo-instruction for "slitu rd, rs1, 1"
									if(debug) $display("seqz $%d, $%d", rd, rs1);
									alu_op = `SLTIU;
								end
								else begin
									if(debug) $display("sltiu $%d, $%d, %d", rd, rs1, i_imm);
									alu_op = `SLTIU;
								end
							end
						3'b100: begin
								if(i_imm == -1) begin
									//pseudo-instruction for "xori rd, rs1, -1"
									if(debug) $display("not $%d, $%d", rd, rs1);
									alu_op = `XOR;
								end
								else begin
									if(debug) $display("xori $%d, $%d, %d", rd, rs1, i_imm);
									alu_op = `XOR;
								end
							end
						3'b101: begin
								case(func7[6:1])
									6'b000000: begin
											if(debug) $display("srli $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = `SRL;
										end
									6'b010000: begin
											if(debug) $display("srai $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = `SRA;
										end
								endcase
							end
						3'b110: begin
								if(debug) $display("ori $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = `OR;
							end
						3'b111: begin
								if(debug) $display("andi $%d, $%d, %d", rd, rs1, i_imm);
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
									if(debug) $display("sext.w $%d, $%d", rd, rs1);
                                                                        immediate = i_imm;
									alu_op = `ADD;
									//since it's a pseudo instructionm, should have same as addiw
								end
								else begin
									if(debug) $display("addiw $%d, $%d, %d", rd, rs1, i_imm);
									immediate = i_imm;
									alu_op = `ADD;
								end
							end
						3'b001: begin
								if(debug) $display("slliw $%d, $%d %d", rd, rs1, shamt);
                                                                shamt = {1'b0, shamt[4:0]};
								immediate = {26'b0, shamt};
								alu_op = `SLL;
							end
						3'b101: begin
								case(func7)
									7'b0000000: begin
											if(debug) $display("srliw $%d, $%d %d", rd, rs1, shamt);
                                                                                        shamt = {1'b0, shamt[4:0]};
											immediate = {26'b0, shamt};
											alu_op = `SRL;
										end
									7'b0100000: begin
											if(debug) $display("sraiw $%d, $%d %d", rd, rs1, shamt);
                                                                                        shamt = {1'b0, shamt[4:0]};
											immediate = {26'b0, shamt};
											alu_op = `SRA;
										end
								endcase
							end
					endcase
					isW = 1;
					reg_write = 1;
					instr_type = `ITYPE;
				end
                        //Ecall
                        7'b1110011: begin
                                        //For ECALL instruction.
                                        if(instruction == {57'b0, 7'b1110011}) begin
	                                    rd=0;
	                                    rs1=0;
	                                    rs2=0;
	                                    immediate=0;
	                                    alu_op=0;
	                                    shamt=0;
	                                    reg_write=0;
	                                    instr_type=0;
	                                    mem_access=0;
	                                    mem_size=0;
                                            isECALL = 1;
                                            isBranch = 0;
                                        end else begin
			                   // $display("This instruction is not recognized: %b|%b|%b|%b|%b|%b  at %h", func7, rs2, rs1, func3, rd, opcode, cur_pc);
                                        end
                                    end

			//default cases
			7'b0000000: ;//$display("This instruction has been decoded before: %b|%b|%b|%b|%b|%b", func7, rs2, rs1, func3, rd, opcode);
			//default:// $display("This instruction is not recognized: %b|%b|%b|%b|%b|%b at %h", func7, rs2, rs1, func3, rd, opcode, cur_pc);
		endcase


	end

endmodule
