`include "Sysbus.defs"

module top
#(
  BUS_DATA_WIDTH = 64,
  BUS_TAG_WIDTH = 13
)
(
  input  clk,
         reset,

  // 64-bit address of the program entry point
  input  [63:0] entry,
  
  // interface to connect to the bus
  output bus_reqcyc, //I should set it to 1 for requesting to read instr
  output bus_respack, //I acknowledge the response by setting it to 1.
  output [BUS_DATA_WIDTH-1:0] bus_req,//the address I wanna read
  output [BUS_TAG_WIDTH-1:0] bus_reqtag, //what you are requesting.
  input  bus_respcyc, //it should become 1 if it is ready to respond.
  input  bus_reqack, 
  input  [BUS_DATA_WIDTH-1:0] bus_resp, //the instruction read.
  input  [BUS_TAG_WIDTH-1:0] bus_resptag
);

  logic [63:0] pc;
  logic [63:0] _pc;
  enum { INIT=3'b000, FETCH=3'b001, WAIT=3'b010, DECODE=3'b011, EXECUTE=3'b100, WRITEBACK = 3'b101, IDLE=3'b111} state, next_state;
  reg [63:0] instr;
  reg [63:0] _instr;
  reg [3:0] _count;
  reg [3:0] count; 
  reg [1:0] instr_num;
  reg [1:0] _instr_num;
  

  always_comb begin
    bus_reqcyc = 0;
    bus_respack = 0;
    bus_req = 64'h0;
    bus_reqtag = 0;
    _count = count;
    _pc = pc;
    _instr = instr;
    _instr_num = instr_num;
    case(state)
      INIT: begin
              bus_reqcyc = 0;
              if(!reset) begin
                next_state = FETCH;
              end
              else begin
                next_state = INIT;
              end
            end
      FETCH: begin
               _pc = pc + 64; 
               _count = 0;
               bus_reqcyc = 1;
               bus_req = pc;
               bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
               if(!bus_reqack) begin
                 next_state = FETCH;
               end               
               else begin
                 next_state = WAIT;
               end
             end
      WAIT:  begin
               if(bus_respcyc == 1) begin
                 _instr = bus_resp;

                 _count = count + 1;
                 next_state = DECODE;
               end
               else begin
                 next_state = WAIT;
               end
             end
      DECODE: begin
                //if both instr are 0s then finish.
                if(instr[31:0] == 32'h0 && instr[63:32] == 32'h0) begin
                  next_state = IDLE;
                end else begin

		  //1 instruction at a time.
                  if(_instr_num == 0) begin
                    //decode, reg file, alu valid bits handle.
                    _instr = {32'b0,  instr[63:32]};
                    _instr_num = instr_num + 1;
                    next_state = EXECUTE;
                  end else begin		
		    //fetch next set
                    _instr_num = 0;
                    bus_respack = 1;
                    if(_count == 8) begin
                      next_state = FETCH;
                    end else begin
                      next_state = WAIT;
                    end
                  end

		end
              end
      EXECUTE: begin
		//To get more instructions.
               	next_state = DECODE;
 		// print the result?
                
               end
      WRITEBACK: begin
		//To write back to the register file.
		//There should be write signal.
		 end
      IDLE: $finish;
    endcase
  end

  //handle incoming instructions
  //setup inputs & outputs for all modules

  //instruction decode output registers and wires
  logic [4:0] ID_rd;
  logic [4:0] _ID_rd;
  logic [4:0] ID_rs1;
  logic [4:0] _ID_rs1;
  logic [4:0] ID_rs2;
  logic [4:0] _ID_rs2;
  logic signed [31:0] ID_immediate;
  logic signed [31:0] _ID_immediate;
  logic [3:0] ID_alu_op;
  logic [3:0] _ID_alu_op;
  logic [5:0] ID_shamt;
  logic [5:0] _ID_shamt;
  logic ID_reg_write_sig;
  logic _ID_reg_write_sig;
  logic ID_new_instr;
  logic _ID_new_instr;

  //execution output registers and wires
  //TODO: does this need to be split into two different stages (a register access and an alu execute)?
  logic [63:0] EX_reg_write_sig;
  logic [63:0] _EX_reg_write_sig;
  logic [63:0] EX_rs1_val;
  logic [63:0] _EX_rs1_val;
  logic [63:0] EX_rs2_val;
  logic [63:0] _EX_rs2_val;
  logic [63:0] EX_alu_result; //@Yeseul: for now, is this the value to be written back to the register? yes.
  logic [63:0] _EX_alu_result;

  logic [63:0] reg_file_rs1;
  logic [63:0] _reg_file_rs1;
  logic [63:0] reg_file_rs2;
  logic [63:0] _reg_file_rs2;
  logic [63:0] reg_file_write_sig;
  logic [63:0] _reg_file_write_sig;
  logic [63:0] reg_file_write_val;
  logic [63:0] _reg_file_write_val;
  logic [63:0] reg_file_write_reg;
  logic [63:0] _reg_file_write_reg;
  logic [63:0] reg_file_rs1_val;
  logic [63:0] _reg_file_rs1_val;
  logic [63:0] reg_file_rs2_val;
  logic [63:0] _reg_file_rs2_val;
  
  // In Decode state
  //instantiate decode modules for each instruction
  decoder instr_decode_mod (
  		.clk(clk), .instruction(instr[31:0]), 					//inputs
  		.rd(_ID_rd), .rs1(_ID_rs1), .rs2(_ID_rs2), .immediate(_ID_immediate), 	//outputs
  		.alu_op(_ID_alu_op), .shamt(_ID_shamt), .reg_write(_ID_reg_write_sig), .new_instr(_ID_new_instr)
  	);

  // In Decode state
  //instantiate register file module
  reg_file register_mod (
  		.clk(clk), .reset(reset), .rs1(ID_rs1), .rs2(ID_rs2), .new_instr(ID_new_instr), 	//inputs
  		.write_sig(ID_reg_write_sig), .write_val(EX_reg_write_val), .write_reg(ID_rd), 
  		.rs1_val(_EX_rs1_val), .rs2_val(_EX_rs2_val)  	//outputs
  	);

   
  //In Execute state
  alu alu_mod (.clk(clk), .opcode(ID_alu_op), .value1(EX_rs1_val), .value2(EX_rs2_val), .immediate(ID_immediate), //INPUTS 
		.result(_EX_alu_result)); //OUTPUT



  always_ff @ (posedge clk) begin
    if(reset) begin //when first starting.
      pc <= entry;
      state <= INIT;
      count <= 0;
      instr <= 64'h0;
      instr_num <= 0;
    end

    //set IF registers
    state <= next_state;
    count <= _count;
    pc <= _pc;
    instr <= _instr;
    instr_num <= _instr_num;

    //set ID registers
	ID_rd <= _ID_rd;
	ID_rs1 <= _ID_rs1;
	ID_rs2 <= _ID_rs2;
	ID_immediate <= _ID_immediate;
	ID_alu_op <= _ID_alu_op;
	ID_shamt <= _ID_shamt;
	ID_reg_write_sig <= _ID_reg_write_sig;
	ID_new_instr <= _ID_new_instr;

	//set EX registers
	EX_reg_write_sig <= _EX_reg_write_sig;
	EX_rs1_val <= _EX_rs1_val;
	EX_rs2_val <= _EX_rs2_val;
	EX_alu_result <= _EX_alu_result;

	reg_file_rs1 <= _reg_file_rs1;
	reg_file_rs2 <= _reg_file_rs2;
	reg_file_write_sig <= _reg_file_write_sig;
	reg_file_write_val <= _reg_file_write_val;
	reg_file_write_reg <= _reg_file_write_reg;
	reg_file_rs1_val <= _reg_file_rs1_val;
	reg_file_rs2_val <= _reg_file_rs2_val;


  end

  initial begin
    $display("Initializing top, entry point = 0x%x", entry);
  end
endmodule

