`include "Sysbus.defs"
module decoder
	(
	  input  clk,
	  //       reset,

	  // instruction to read
	  input [31:0] instruction,
	  
	  // outputs
	  output [4:0] rd,
	  output [4:0] rs1,
	  output [4:0] rs2,
	  output [31:0] immediate,
	  output [3:0] alu_op,
	  output [5:0] shamt,
	  output reg_write
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
		alu_op = 4'b0; //TODO:insert all applicable alu ops below //Note-to-shanshan: all zero means no alu now.
		shamt = instruction[25:20]; //for i instruction type shifting
		reg_write = 1'b0;

		//set immediate values
		jal_imm = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:25], instruction[24:21], 1'b0};
		u_imm = {instruction[31:12], 12'b0};
		sb_imm = {instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
		i_imm = {{21{instruction[31]}}, instruction[30:20]};
		s_imm = {{21{instruction[31]}}, instruction[30:25], instruction[11:7]};

		//begin differntiating
		case(opcode)
			//uj_instr
			7'b1101111: begin
					$display("jal %d", jal_imm);
					immediate = jal_imm;
					alu_op = 4'b0;
					//reg_write = 1;
					//rd = 5'b11111; //jal stores address into register
				end

			//u_instr
			7'b0110111: begin
					$display("lui $%d, %d", rd, u_imm);
					immediate = u_imm;
					alu_op = 4'b0;
					reg_write = 1;
				end
			7'b0010111: begin
					$display("auipc $%d, %d", rd, u_imm);
					immediate = u_imm;
					alu_op = 4'b0001;
					reg_write = 1;
				end

			//sb_instr
			7'b1100011: begin
					case(func3)
						3'b000: begin
								$display("beq $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = 4'b0;
							end
						3'b001: begin
								$display("bne $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = 4'b0;
							end
						3'b100: begin
								$display("blt $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = 4'b0;
							end
						3'b101: begin
								$display("bge $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = 4'b0;
							end
						3'b110: begin
								$display("bltu $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = 4'b0;
							end
						3'b111: begin
								$display("bgeu $%d, $%d, %d", rs1, rs2, sb_imm);
								alu_op = 4'b0;
							end
					endcase
					immediate = sb_imm;
				end

			//s_instr
			7'b0100011: begin
					case(func3)
						3'b000: begin
								$display("sb $%d, %d($%d)", rs1, s_imm, rs2);
								alu_op = 4'b0;
							end
						3'b001: begin
								$display("sh $%d, %d($%d)", rs1, s_imm, rs2);
								alu_op = 4'b0;
							end
						3'b010: begin
								$display("sw $%d, %d($%d)", rs1, s_imm, rs2);
								alu_op = 4'b0;
							end
						3'b011: begin
								$display("sd $%d, %d($%d)", rs1, s_imm, rs2);
								alu_op = 4'b0;
							end
					endcase
					immediate = s_imm;
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
											$display("subw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0010;
										end
								endcase
							end
						3'b001: begin
								$display("sllw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = 4'b0;
							end
						3'b100: begin
								$display("divw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = 4'b0100;
							end
						3'b101: begin
								case(func7)
									7'b0000000: begin
											$display("srlw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0;
										end
									7'b0000001: begin
											$display("divuw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0100;
										end
									7'b0100000: begin
											$display("sraw $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0;
										end
								endcase
							end
						3'b110: begin
								$display("remw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = 4'b0;
							end
						3'b111: begin
								$display("remuw $%d, $%d, $%d", rd, rs1, rs2);
								alu_op = 4'b0;
							end
					endcase
					reg_write = 1;
				end
			7'b0110011: begin //32R
					if(func7 == 7'b0000001) begin
						case(func3)
							3'b000: begin
									$display("mul $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0011;
								end
							3'b001: begin
									$display("mulh $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0011;
								end
							3'b010: begin
									$display("mulhsu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0011;
								end
							3'b011: begin
									$display("mulhu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0011;
								end
							3'b100: begin
									$display("div $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0100;
								end
							3'b101: begin
									$display("divu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0100;
								end
							3'b110: begin
									$display("rem $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0;
								end
							3'b111: begin
									$display("remu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0;
								end
						endcase
					end
					else begin
						case(func3)
							3'b000: begin
								case(func7)
									7'b0000000: begin
											$display("add $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0001;
										end
									7'b0100000: begin
											$display("sub $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0010;
										end
								endcase
							end
							3'b001: begin
									$display("sll $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0;
								end
							3'b010: begin
									$display("slt $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0;
								end
							3'b011: begin
									$display("sltu $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0;
								end
							3'b100: begin
									$display("xor $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0101;
								end
							3'b101: begin
								case(func7)
									7'b0000000: begin
											$display("srl $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0;
										end
									7'b0100000: begin
											$display("sra $%d, $%d, $%d", rd, rs1, rs2);
											alu_op = 4'b0;
										end
								endcase
							end
							3'b110: begin
									$display("or $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0111;
								end
							3'b111: begin
									$display("and $%d, $%d, $%d", rd, rs1, rs2);
									alu_op = 4'b0110;
								end
						endcase
					end
					reg_write = 1;
				end

			//i_instr
			7'b1100111: begin
					$display("jalr $%d, $%d", rd, rs1);
					alu_op = 4'b0;
					reg_write = 1;
				end
			7'b0000011: begin //load
					case(func3)
						3'b000: begin
								$display("lb $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
						3'b001: begin
								$display("lh $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
						3'b010: begin
								$display("lw $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
						3'b011: begin
								$display("ld $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
						3'b100: begin
								$display("lbu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
						3'b101: begin
								$display("lhu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
						3'b110: begin
								$display("lwu $%d, %d($%d)", rd, i_imm, rs1);
								alu_op = 4'b0;
							end
					endcase
					immediate = i_imm;
					reg_write = 1;
				end
			7'b0010011: begin //32I
					immediate = i_imm;
					case(func3)
						3'b000: begin
								$display("addi $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = 4'b0001;
							end
						3'b001: begin
								$display("slli $%d, $%d %d", rd, rs1, shamt);
								immediate = {26'b0, shamt};
								alu_op = 4'b0;
							end
						3'b010: begin
								$display("slti $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = 4'b0;
							end
						3'b011: begin
								$display("sltiu $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = 4'b0;
							end
						3'b100: begin
								$display("xori $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = 4'b0101;
							end
						3'b101: begin
								case(func7)
									7'b0000000: begin
											$display("srli $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = 4'b0;
										end
									7'b0100000: begin
											$display("srai $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = 4'b0;
										end
								endcase
							end
						3'b110: begin
								$display("ori $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = 4'b0111;
							end
						3'b111: begin
								$display("andi $%d, $%d, %d", rd, rs1, i_imm);
								alu_op = 4'b0110;
							end
					endcase
					reg_write = 1;
				end
			7'b0011011: begin //64I
					immediate = i_imm;
					case(func3)
						3'b000: begin
								$display("addi $%d, $%d, %d", rd, rs1, i_imm);
								immediate = i_imm;
								alu_op = 4'b0001;
							end
						3'b001: begin
								$display("slliw $%d, $%d %d", rd, rs1, shamt);
								immediate = {26'b0, shamt};
								alu_op = 4'b0;
							end
						3'b010: begin
								case(func7)
									7'b0000000: begin
											$display("srliw $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = 4'b0;
										end
									7'b0100000: begin
											$display("sraiw $%d, $%d %d", rd, rs1, shamt);
											immediate = {26'b0, shamt};
											alu_op = 4'b0;
										end
								endcase
							end
					endcase
					reg_write = 1;
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
