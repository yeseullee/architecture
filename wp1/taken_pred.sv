`include "Sysbus.defs"
module taken_pred
	#(
	  BTB_SIZE = 32,
	  INSTR_LEN = 5,
	  TARGET_LEN = 10
	)
	(
	  input  clk,
	         reset,

	  //inputs
	  input req_addr[63:0],			//cur_pc
	  input result_cyc,				//high if results present
	  input result_addr[63:0],
	  input result,
	  
	  // outputs
	  output prediction
	);

	//setup registers
	logic [5:0] instr_addr[31:0];
	logic [5:0] _instr_addr[31:0];
	logic [9:0] target_addr[31:0];
	logic [9:0] _target_addr[31:0];
	logic [31:0] valid_bits;
	logic [31:0] _valid_bits;

	always_comb begin
		//set outputs: 	INDEX ADDRESSES BASED ON LOWER 5 BITS (log2(BTB_SIZE)) IN REQ_ADDR, INSTR_ADDR STORES NEXT 5 BITS
		if(valid_bits[req_addr[4:0]] == 1) && (instr_addr[req_addr[4:0]] == req_addr[9:5]) begin
			target_addr = {instr_prefix, target_addr};
		end
		else begin
			//if no prediction present, just predict branch not taken, and go to next address: pc = pc+4
			target_addr = req_addr + 4;
		end

		//update table if needed
		if(result_cyc == 1) begin
			_valid_bits[result_addr[4:0]] = 1;
			_instr_addr[result_addr[4:0]] = result_addr[9:5];
			_target_addr[result_addr[4:0]] = result_target[9:0];
		end
	end

	always_ff @ (posedge clk) begin
		//on system start or reset
		if(reset) begin
			valid_bits <= 0;
			for (int i = 0; i < BTB_SIZE; i++) begin
				instr_addr[i] <= 0;
				target_addr[i] <= 0;
			end
		end

		//write values from wires to registers
		valid_bits <= _valid_bits;
		for (int i = 0; i < 32; i++) begin
			instr_addr[i] <= _instr_addr[i];
			target_addr[i] <= _target_addr[i];
		end
	end
endmodule
