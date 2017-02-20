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
  output bus_respack, //
  output [BUS_DATA_WIDTH-1:0] bus_req,//the address I wanna read
  output [BUS_TAG_WIDTH-1:0] bus_reqtag, //what you are requesting.
  input  bus_respcyc, //it should become 1 if it is ready to respond.
  input  bus_reqack, 
  input  [BUS_DATA_WIDTH-1:0] bus_resp, //the instruction read.
  input  [BUS_TAG_WIDTH-1:0] bus_resptag
);

  logic [63:0] pc;
  enum { INIT=2'b00, FETCH=2'b01, WAIT=2'b10, DECODE=2'b11, IDLE=3'b100} state, next_state;
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
    case(state)

      INIT: begin
              $display("init state");
              bus_reqcyc = 0;
              if(!reset) begin
                $display("calling fetch");
                next_state = FETCH;
              end
              else begin
                next_state = INIT;
              end
            end
      FETCH: begin
               $display("requack %d", bus_reqack);
               $display("reqcyc = %d",bus_reqcyc);
               if(bus_reqcyc) begin //requested previously
                 bus_reqcyc = 0;
               end
               else begin
                 $display("fetch - requesting");
                 bus_reqcyc = 1;
                 bus_req = pc;
                 bus_reqtag = {`SYSBUS_MEMORY,8'b0};
               end
               next_state = WAIT;
             end
      WAIT:  begin
               $display("waiting");
               if(bus_respcyc == 1) begin
                 $display("read");
                 next_state = DECODE;
               end
               else begin
                 next_state = WAIT;
               end
             end
      //WAIT: next_state = DECODE;
      DECODE: next_state = IDLE;
      //default next_state = IDLE;
    endcase
  end

  always_ff @ (posedge clk) begin
    if(reset) begin
      pc <= entry;
      state <= INIT;
    end
    state <= next_state;
    //$display("state = %d",state);
    //$display("pc value %x", pc);
  end

  initial begin
    $display("Initializing top, entry point = 0x%x", entry);
    //assign state = IDLE;
  end
endmodule
