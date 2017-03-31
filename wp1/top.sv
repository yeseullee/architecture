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
  //going to memory
  output bus_reqcyc, //I should set it to 1 for requesting to read instr
  output bus_respack, //I acknowledge the response by setting it to 1.
  output [BUS_DATA_WIDTH-1:0] bus_req,//the address I wanna read
  output [BUS_TAG_WIDTH-1:0] bus_reqtag, //what you are requesting.
  //coming into processor
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
  
  //insert cache variables
  logic cache = 1;  //set to 0 to remove the cache
  logic cache_bus_reqcyc;
  logic cache_bus_respack;
  logic [BUS_DATA_WIDTH-1:0] cache_bus_req;
  logic [BUS_TAG_WIDTH-1:0] cache_bus_reqtag;
  logic cache_bus_respcyc;
  logic cache_bus_reqack;
  logic [BUS_DATA_WIDTH-1:0] cache_bus_resp;
  logic [BUS_TAG_WIDTH-1:0] cache_bus_resptag;

  direct_cache cache_mod (
        //INPUTS
        .p_bus_reqcyc(cache_bus_reqcyc), .p_bus_req(cache_bus_req), 
        .p_bus_reqtag(cache_bus_reqtag), p_bus_respack(cache_bus_respack),
        .m_bus_reqack(bus_reqack), .m_bus_respcyc(bus_respcyc), 
        .m_bus_resp(bus_resp), .m_bus_resptag(bus_resptag),

        //OUTPUTS
        .p_bus_reqack(cache_bus_reqack), .p_bus_respcyc(cache_bus_respcyc), 
        .p_bus_resp(cache_bus_resp), .p_bus_resptag(cache_bus_resptag),
        .m_bus_reqcyc(bus_reqcyc), .m_bus_req(bus_req),
        .m_bus_reqtag(bus_reqtag), .m_bus_respack(bus_respack)
  )



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
              if(cache == 1) begin
                cache_bus_reqcyc = 0;
              end
              else begin
                bus_reqcyc = 0;
              end

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

              if(cache == 1) begin
                cache_bus_reqcyc = 1;
                cache_bus_req = pc;
                cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                if(!cache_bus_reqack) begin
                  next_state = FETCH;
                end               
                else begin
                  next_state = WAIT;
                end
              end
              else begin
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
            end
      WAIT:  begin
              if(cache == 1) begin
                if(cache_bus_respcyc == 1) begin
                  _instr = cache_bus_resp;
                  _instr_num = 0;
                  _count = count + 1;
                  next_state = DECODE;
                end
                else begin
                  next_state = WAIT;
                end
              end
              else begin
                if(bus_respcyc == 1) begin
                  _instr = bus_resp;
                  _instr_num = 0;
                  _count = count + 1;
                  next_state = DECODE;
                end
                else begin
                  next_state = WAIT;
                end
              end
            end
      DECODE: begin
                //if both instr are 0s then finish.
                if(instr[31:0] == 32'h0 && instr[63:32] == 32'h0) begin
                  next_state = IDLE;
                end else begin
            		  next_state = EXECUTE;
            		end
              end
      EXECUTE: begin
		      //To get more instructions.
          next_state = WRITEBACK;
        end
      WRITEBACK: begin
      		//To write back to the register file.
      		//There should be write signal.
      		
      		//Directions for all paths.
    		  //1 instruction at a time.
    		  _instr_num = instr_num + 1;
          if(_instr_num == 1) begin
            _instr = {32'b0,  instr[63:32]};
            next_state = DECODE;
          end
    		  if(_instr_num == 2) begin		
    		    //fetch the next set
            _instr_num = 0;

            if(cache == 1) begin
              cache_bus_respack = 1;
            end
            else begin
              bus_respack = 1;
            end
    		    next_state = WAIT; 
            if(_count == 8) begin
              next_state = FETCH;
            end
          end
    		end
      IDLE: $finish;
    endcase
  end




  //handle incoming instructions
  //setup inputs & outputs for all modules

  //instruction decode output registers and wires (ID and ID_EX))
  logic [4:0] ID_EX_rd;
  logic [4:0] _ID_rd;
  logic [4:0] ID_EX_rs1;
  logic [4:0] _ID_rs1;
  logic [4:0] ID_EX_rs2;
  logic [4:0] _ID_rs2;
  logic signed [31:0] ID_EX_immediate;
  logic signed [31:0] _ID_immediate;
  logic [3:0] ID_EX_alu_op;
  logic [3:0] _ID_alu_op;
  logic [5:0] ID_EX_shamt;
  logic [5:0] _ID_shamt;
  logic ID_EX_reg_write_sig;
  logic _ID_reg_write_sig;
  logic [63:0] ID_EX_rs1_val;
  logic [63:0] _ID_rs1_val;
  logic [63:0] ID_EX_rs2_val;
  logic [63:0] _ID_rs2_val;

  //execution output registers and wires (EX and EX_WB)
  logic [63:0] EX_WB_alu_result;
  logic [63:0] _EX_alu_result;
  logic EX_WB_reg_write_sig;
  logic [4:0] EX_WB_rd;
  
  // In Decode state: decoder and register file
  decoder decoder_mod (
  		.clk(clk), .instruction(instr[31:0]), 					       //inputs
  		.rd(_ID_rd), .rs1(_ID_rs1), .rs2(_ID_rs2), .immediate(_ID_immediate), 	//outputs
  		.alu_op(_ID_alu_op), .shamt(_ID_shamt), .reg_write(_ID_reg_write_sig)
  	);
  reg_file register_mod (
  		.clk(clk), .reset(reset), .rs1(_ID_rs1), .rs2(_ID_rs2),      //inputs
  		.write_sig(EX_WB_reg_write_sig), .write_val(EX_WB_alu_result), .write_reg(EX_WB_rd),
  		.rs1_val(_ID_rs1_val), .rs2_val(_ID_rs2_val)  	     //outputs
  	);

  //In Execute state: alu
  alu alu_mod (.clk(clk), .opcode(ID_EX_alu_op), .value1(ID_EX_rs1_val),  //INPUTS 
    .value2(ID_EX_rs2_val), .immediate(ID_EX_imm),
		.result(_EX_alu_result));           //OUTPUT




  always_ff @ (posedge clk) begin
    if(reset) begin //when first starting.
      pc <= entry;
      state <= INIT;
      count <= 0;
      instr <= 64'h0;
      instr_num <= 0;
    end

    //set IF_ID registers
    state <= next_state;
    count <= _count;
    pc <= _pc;
    instr <= _instr;
    instr_num <= _instr_num;

    //set ID_EX registers
  	ID_EX_rd <= _ID_rd;
  	ID_EX_rs1 <= _ID_rs1;
  	ID_EX_rs2 <= _ID_rs2;
  	ID_EX_immediate <= _ID_immediate;
  	ID_EX_alu_op <= _ID_alu_op;
  	ID_EX_shamt <= _ID_shamt;
  	ID_EX_reg_write_sig <= _ID_reg_write_sig;
    ID_EX_rs1_val <= _ID_rs1_val;
    ID_EX_rs2_val <= _ID_rs2_val;

  	//set EX_WB registers
  	EX_WB_reg_write_sig <= ID_EX_reg_write_sig;
  	EX_WB_alu_result <= _EX_alu_result;
    EX_WB_rd <= ID_EX_rd;

  end

  initial begin
    $display("Initializing top, entry point = 0x%x", entry);
  end
endmodule

