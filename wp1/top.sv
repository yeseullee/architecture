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
  enum { INIT=2'b00, FETCH=2'b01, WAIT=2'b10, DECODE=2'b11, IDLE=3'b100} state, next_state;
  reg [64:0] instr;
  reg [64:0] _instr;
  reg [3:0] _count;
  reg [3:0] count; 


  always_comb begin
    bus_reqcyc = 0;
    bus_respack = 0;
    bus_req = 64'h0;
    bus_reqtag = 0;
    _count = count;
    _pc = pc;
    _instr = instr;
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
      //WAIT: next_state = DECODE;
      DECODE: begin
                if(instr[31:0] == 32'h0 || instr[63:32] == 32'h0) begin
                  next_state = IDLE;
                end else begin
		bus_respack = 1;

                //$display("instr1 %h", instr[31:0]);
                //$display("instr2 %h", instr[63:32]);

		//fetch next set
                if(_count == 8) begin
                  next_state = FETCH;
                end else begin
                  next_state = WAIT;
                end
		end
              end
	  IDLE: $finish;
    endcase
  end

  //handle incoming instructions
  //setup inputs & outputs for all modules
  logic [4:0] rd;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [31:0] immediate;
  logic [7:0] alu_op;
  logic [5:0] shamt;
  logic reg_write_sig;
  logic [63:0] reg_write_val;
  logic [63:0] rs1_val;
  logic [63:0] rs2_val;

  //instantiate decode modules for each instruction
  decoder instr1_decode_mod (
  		.clk(clk), .instruction(instr[31:0]), 					//inputs
  		.rd(rd), .rs1(rs1), .rs2(rs2), .immediate(immediate), 	//outputs
  		.alu_op(alu_op), .shamt(shamt), .reg_write(reg_write_sig)
  	);
  decoder instr2_decode_mod (
  		.clk(clk), .instruction(instr[63:32]), 					//inputs
  		.rd(rd), .rs1(rs1), .rs2(rs2), .immediate(immediate), 	//outputs
  		.alu_op(alu_op), .shamt(shamt), .reg_write(reg_write_sig)
  	);

  //instantiate register file module
  reg_file register_mod (
  		.clk(clk), .reset(reset), .rs1(rs1), .rs2(rs2), 					//inputs
  		.write_sig(reg_write_sig), .write_val(reg_write_val), .write_reg(rd), 	//outputs
  		.rs1_val(rs1_val), .rs2_val(rs2_val)
  	);

  always_ff @ (posedge clk) begin
    if(reset) begin //when first starting.
      pc <= entry;
      state <= INIT;
      count <= 0;
      instr <= 64'h0;
    end
    state <= next_state;
    count <= _count;
    pc <= _pc;
    instr <= _instr;
  end

  initial begin
    $display("Initializing top, entry point = 0x%x", entry);
  end
endmodule

