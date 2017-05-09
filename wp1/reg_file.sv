module reg_file
	(
	  input  clk,
	         reset,

	  //reading inputs
	  input [4:0] rs1,
	  input [4:0] rs2,
	  //input new_instr,

	  //writing inputs
	  input write_sig, //signal to allow writing to any register
	  input [63:0] write_val, //value to write into register
	  input [4:0] write_reg, //register to write into

          //For setting it at the beginning.
          input [63:0] sp_val,
	  
	  // outputs
	  output [63:0] rs1_val,
	  output [63:0] rs2_val
	);

	//setup registers
	logic [63:0] registers[31:0];
	logic [63:0] _registers[31:0];

	logic debug = 0; //to print out the contents of each register upon ecah new instruction, set to 1

	always_comb begin
                //stack ptr
                _registers[2] = registers[2];

		//set outputs
		rs1_val = registers[rs1];
		rs2_val = registers[rs2];
		//write_ack = 0;

		//write to indicated wire if requested
		if(write_sig == 1) begin
			_registers[write_reg] = write_val;
			//write_ack = 1;
			if(debug == 1) begin
				$display("All register contents:");
				$display("Register $%d: %d", 0, _registers[0]);
				for (int i = 1; i < 32; i++) begin
					$display("Register $%d: %d", i, _registers[i]);
				end
			end
		end
		else begin
			_registers[write_reg] = registers[write_reg];
			//write_ack = 0;
		end
                

	end

	always_ff @ (posedge clk) begin
		//on system start or reset
		if(reset) begin

                        registers[0] <= 64'b0;
                        registers[1] <= 64'b0;                        
                        registers[2] <= sp_val;

			for (int i = 3; i < 32; i++) begin
				registers[i] <= 64'b0;
			end

		end else begin

		//write values from wires to registers, excepting register 0
		for (int i = 1; i < 32; i++) begin
			registers[i] <= _registers[i];
		end
                end

	end
endmodule
