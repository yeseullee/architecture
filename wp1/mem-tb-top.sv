`include "Sysbus.defs"

module top
#(
    BUS_DATA_WIDTH = 64,
    BUS_TAG_WIDTH = 13,

	INIT = 0,
	FETCH = 1,
	WAIT = 2,
	WRITE = 3,
	SEND = 4,
	BREAK = 5
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
    //insert cache variables
    logic cache = 1;
    logic cache_bus_reqcyc;
    logic cache_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] cache_bus_req;
    logic [BUS_TAG_WIDTH-1:0] cache_bus_reqtag;
    logic cache_bus_respcyc;
    logic cache_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] cache_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] cache_bus_resptag;
 
    cache DUT (
        //INPUTS
        .clk(clk), .reset(reset),
        .p_bus_reqcyc(cache_bus_reqcyc), .p_bus_req(cache_bus_req), 
        .p_bus_reqtag(cache_bus_reqtag), .p_bus_respack(cache_bus_respack),
        .m_bus_reqack(bus_reqack), .m_bus_respcyc(bus_respcyc), 
        .m_bus_resp(bus_resp), .m_bus_resptag(bus_resptag),

        //OUTPUTS
        .p_bus_reqack(cache_bus_reqack), .p_bus_respcyc(cache_bus_respcyc), 
        .p_bus_resp(cache_bus_resp), .p_bus_resptag(cache_bus_resptag),
        .m_bus_reqcyc(bus_reqcyc), .m_bus_req(bus_req),
        .m_bus_reqtag(bus_reqtag), .m_bus_respack(bus_respack)
    );

	logic [63:0] _pc;
	logic [63:0] pc;
	logic [63:0] _response[7:0];
	logic [63:0] response[7:0];
	logic [3:0] ptr;
	logic [3:0] next_ptr;
	logic [3:0] state;
	logic [3:0] next_state;
 
    always_comb begin
	next_ptr = ptr;
	next_state = state;
	_pc = pc;
	for(int i = 0; i < 7; i++) begin
		_response[i] = response[i];
	end
	if(cache == 1) begin
	        cache_bus_reqcyc = 0;
        	cache_bus_respack = 0;
	        cache_bus_req = 64'h0;
        	cache_bus_reqtag = 0;
	end
	else begin
	        bus_reqcyc = 0;
        	bus_respack = 0;
	        bus_req = 64'h0;
        	bus_reqtag = 0;
	end

        case(state)
            	INIT: begin
                	if(!reset) begin
                		next_state = WRITE;
                	end
                	else begin
                		next_state = INIT;
                	end
                end
            	FETCH: begin
			if(cache == 1) begin
	                      cache_bus_reqcyc = 1;
        	              cache_bus_req = pc;
                	      cache_bus_reqtag = {`SYSBUS_READ,`SYSBUS_MEMORY,8'b0};
	                      if(cache_bus_reqack) begin
        	                  //_pc = pc + 64; 
                	          next_state = WAIT;
				  next_ptr = 0;
	                      end               
        	              else begin
                	          next_state = FETCH;
                     	      end
			end
			else begin
	                      bus_reqcyc = 1;
        	              bus_req = pc;
                	      bus_reqtag = {`SYSBUS_READ,`SYSBUS_MEMORY,8'b0};
	                      if(bus_reqack) begin
        	                  //_pc = pc + 64; 
                	          next_state = WAIT;
				  next_ptr = 0;
	                      end               
        	              else begin
                	          next_state = FETCH;
			      end
			end
                end
            	WAIT:  begin
			if(cache == 1) begin
	                      if(cache_bus_respcyc == 1) begin
				_response[ptr] = cache_bus_resp;
	                        next_ptr = ptr + 1;
				cache_bus_respack = 1;
                	        if(ptr == 7) begin
					$finish;
				end
				else begin
					next_state = WAIT;
				end
	                      end
                	      else begin
        	                next_state = WAIT;
	                      end
			end
			else begin
	                      if(bus_respcyc == 1) begin
				_response[ptr] = bus_resp;
        	                next_ptr = ptr + 1;
				bus_respack = 1;
	                        if(ptr == 7) begin
					$finish;
				end
				else begin
					next_state = WAIT;
				end
	                      end
                	      else begin
        	                next_state = WAIT;
	                      end
			end
                end
		WRITE: begin
			if(cache == 1) begin
                		cache_bus_reqcyc = 1;
                		cache_bus_req = pc;
        	        	cache_bus_reqtag = {`SYSBUS_WRITE,`SYSBUS_MEMORY,8'b0};
	                	if(cache_bus_reqack) begin
                			next_state = SEND;
                		end               
                		else begin
					next_state = WRITE;
				end
			end
			else begin
                		bus_reqcyc = 1;
                		bus_req = pc;
        	        	bus_reqtag = {`SYSBUS_WRITE,`SYSBUS_MEMORY,8'b0};
	                	if(bus_reqack) begin
                			next_state = SEND;
                		end               
                		else begin
					next_state = WRITE;
				end
			end
		end
		SEND: begin
			if(cache == 1) begin
        	        	cache_bus_req = 0-ptr-1;
                		cache_bus_reqtag = {`SYSBUS_WRITE,`SYSBUS_MEMORY,8'b0};
	                	cache_bus_reqcyc = 1;
                		if(cache_bus_reqack) begin
					next_ptr = ptr + 1;
					if(ptr == 7) begin
						next_state = BREAK;
					end
					else begin
						next_state = SEND;
					end
                		end               
	                	else begin
					next_state = SEND;
				end
			end
			else begin
        	        	bus_req = 0-ptr-1;
                		bus_reqtag = {`SYSBUS_WRITE,`SYSBUS_MEMORY,8'b0};
	                	bus_reqcyc = 1;
                		if(bus_reqack) begin
					next_ptr = ptr + 1;
					if(ptr == 7) begin
						next_state = BREAK;
					end
					else begin
						next_state = SEND;
					end
				end
			end
		end
		BREAK: begin
			if(ptr == 0) begin
				next_state = FETCH;
			end
			else begin
				next_state = BREAK;
				next_ptr = ptr - 1;
			end
		end
	endcase
    end

    always_ff @ (posedge clk) begin
        if(reset) begin //when first starting.
        	state <= INIT;
		pc <= entry;
		ptr <= 0;
		for(int i = 0; i < 7; i++) begin
			response[i] <= 0;
		end
        end

	state <= next_state;
	pc <= _pc;
	ptr <= next_ptr;
	for(int i = 0; i < 7; i++) begin
		response[i] <= _response[i];
	end
    end

    initial begin
        $display("Initializing top, entry point = 0x%x", entry);
    end

endmodule

