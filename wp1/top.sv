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
  reg [3:0] count_wire;
  reg [3:0] count_register; 
/*
  always @ (posedge clk)
    if (reset) begin
      $display("Hi");
      pc <= entry;
    end else begin
      $display("Hello World!  @ %x", pc);
      $finish;
    end
*/
  always_comb begin
    bus_reqcyc = 0;
    bus_respack = 0;
    bus_req = 64'h0;
    bus_reqtag = 0;
    count_wire = count_register;
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
               count_wire = 0;
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

                 count_wire = count_register + 1;
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
                $display("instr1 %h", instr[31:0]);
                $display("instr2 %h", instr[63:32]);
                if(count_wire == 8) begin
                  next_state = FETCH;
                end else begin
                  next_state = WAIT;
                end
		end
              end
	IDLE: $finish;

    endcase
  end

  always_ff @ (posedge clk) begin
    if(reset) begin
      pc <= entry;
      state <= INIT;
      count_register <= 0;
      instr <= 64'h0;
    end
    state <= next_state;
    count_register <= count_wire;
    pc <= _pc;
    instr <= _instr;
    //$display("state = %d",state);
    //$display("pc value %x", pc);
  end

  initial begin
    $display("Initializing top, entry point = 0x%x", entry);
    //assign state = IDLE;
  end
endmodule
