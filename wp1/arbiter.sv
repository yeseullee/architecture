module arbiter
	#(
		//Memory bus constants
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13,
		DATA_LENGTH = 512,

		//State values
		INITIAL = 0,
		ACCEPT = 1,
		ACKPROC = 2,

		//write states
		READVAL = 3,
		ACKVAL = 4,
		DRAMWREQ = 5,
		DRAMWRT = 6,

		//read states
		DRAMRD = 7,
		RECEIVE = 8,
		RESPOND = 9,
		RESPACK = 10,
		SETRESPZ = 11
	)
	(
		input  clk,
		input reset,

		//input 1 (instruction fetch)
		input reqcyc0,
		output reqack0,
		output respcyc0,
		input respack0,
		input [BUS_DATA_WIDTH-1:0] req0,
		input [BUS_TAG_WIDTH-1:0] reqtag0,
		output [BUS_DATA_WIDTH-1:0] resp0,
		output [BUS_TAG_WIDTH-1:0] resptag0,
		
		//input 2 (memory access data)
		input reqcyc1,
		output reqack1,
		output respcyc1,
		input respack1,
		input [BUS_DATA_WIDTH-1:0] req1,
		input [BUS_TAG_WIDTH-1:0] reqtag1,
		output [BUS_DATA_WIDTH-1:0] resp1,
		output [BUS_TAG_WIDTH-1:0] resptag1,
		
		//to memory
		output bus_reqcyc,                          //request acknowledged
		input bus_reqack,                           //acknowledgement for request.
		input bus_respcyc,                          //response acknowledgement
		output bus_respack,                         //acknolwedgement for response. 
		output [BUS_DATA_WIDTH-1:0]  bus_req,       //the address to request
		output [BUS_TAG_WIDTH-1:0] bus_reqtag,      //determine read/write
		input [BUS_DATA_WIDTH-1:0] bus_resp,        //the response
		input [BUS_TAG_WIDTH-1:0] bus_resptag       //determine read/write
	);

	//variables to store information
	logic [63:0] req_addr;
	logic [63:0] _req_addr;
	logic [12:0] req_tag;
	logic [12:0] _req_tag;
	logic [3:0] state;
	logic [3:0] next_state;
	logic [DATA_LENGTH-1:0] content;
	logic [DATA_LENGTH-1:0] _content;
	logic [8:0] ptr;
	logic [8:0] next_ptr;
	logic channel;
	logic _channel;


	//NOTE: multiple always comb blocks used to keep verilator happy
	//  processor resp, ack, and cyc variables cannot be set or used within the same block
   
	//accept requests and values from the processor: INITIAL, ACCEPT, READVAL
	always_comb begin
		_channel = channel;
		case(state)
			INITIAL: begin
					//Initialize the system
					next_state = ACCEPT;
				end
			ACCEPT: begin
					//wait for requests from the processor
					_content = 0;
					//receiving requeston on channel 0
					if(reqcyc0 == 1) begin
						_req_addr = req0;
						_req_tag = reqtag0;
						_channel = 0;
						next_ptr = 0;
						next_state = ACKPROC;
					end

					//receiving requests on channel 1
					else if(reqcyc1 == 1) begin
						_req_addr = req1;
						_req_tag = reqtag1;
						_channel = 1;
						next_ptr = 0;
						next_state = ACKPROC;
					end

					//else loop
					else begin
						next_state = ACCEPT;
					end
				end
			READVAL: begin
					//read value to be written from processor
					//read value from channel 0
					if(channel == 0) begin
						if(reqcyc0 == 1) begin
							_content[64*ptr +: 64] = req0;
							next_state = ACKVAL;
						end
						else begin
							next_state = READVAL;
						end
					end

					//read value from channel 1
					else if(channel == 1) begin
						if(reqcyc1 == 1) begin
							_content[64*ptr +: 64] = req1;
							next_state = ACKVAL;
						end
						else begin
							next_state = READVAL;
						end
					end
				end
		endcase
	end


	//acknowledge receiving request and values from processor: ACKPROC, ACKVAL
	always_comb begin
		reqack0 = 0;
		reqack1 = 0;
		case(state)
			ACKPROC: begin
					//acknowledge on channel 0
					if(channel == 0) begin
						reqack0 = 1;
					end

					//acknowledge channel 1
					else if(channel == 1) begin
						reqack1 = 1;
					end

					//transition to next state
					if(req_tag[12] == `SYSBUS_WRITE) begin
						_content = 0;
						next_state = READVAL;
					end
					else begin
						next_state = DRAMRD;
					end
				end
			ACKVAL: begin
					//acknowledge on channel 0
					if(channel == 0) begin
						reqack0 = 1;
					end

					//acknowledge channel 1
					else if(channel == 1) begin
						reqack1 = 1;
					end

					//transition to next state
					next_ptr = ptr + 1;
					if(ptr == 7) begin
						next_state = DRAMWREQ;
						next_ptr = 0;
					end
					else begin
						next_state = READVAL;
					end
				end
		endcase
	end

	//interact with the memory: DRAMWREQ, DRAMWRT, DRAMRD, RECEIVE
	always_comb begin
		//misc related variables
		bus_reqcyc = 0;
		bus_respack = 0;
		_content = content;
	   
		case(state)
			DRAMWREQ: begin
					bus_reqcyc = 1;
					bus_req = req_addr;
					if(bus_reqack == 1) begin
							next_ptr = 0;
							next_state = DRAMWRT;
					end
					else begin
						next_state = DRAMWREQ;
					end
				end
			DRAMWRT: begin
					bus_reqcyc = 1;
					bus_req = content[64*ptr +: 64];
					if(bus_reqack == 1) begin
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_state = ACCEPT;
						end
						else begin
							next_state = DRAMWRT;
						end
					end
				end
			DRAMRD: begin
					//send request to memory
					bus_reqcyc = 1;
					bus_req = req_addr;
					bus_reqtag = req_tag;

					//determine if memory received request
					if(bus_reqack == 1) begin
						next_state = RECEIVE;
					end
					else begin
						next_state = DRAMRD;
					end
				end
			RECEIVE: begin
					//receive reponse from memory if present
					if(bus_respcyc == 1) begin
						bus_respack = 1;
						_content[64*ptr +: 64] = bus_resp;
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_state = RESPOND;
							next_ptr = 0;
						end
						else begin
							next_state = RECEIVE;
						end
					end
					else begin
						bus_respack = 0;
						next_state = RECEIVE;
					end
				end
			RESPOND:begin
					//respond to processor
					if(bus_respcyc == 1) begin
						bus_respack = 1;
					end
					//channel 0
					if(channel == 0) begin
						respcyc0 = 1;
						resptag0 = req_tag;
						resp0 = content[64*ptr +: 64];
					end

					//channel 1
					else if(channel == 1) begin
						respcyc1 = 1;
						resptag1 = req_tag;
						resp1 = content[64*ptr +: 64];
					end

					//transition to next state
					next_ptr = ptr;
					next_state = RESPACK;
				end
			SETRESPZ: begin
					respcyc0 = 0;
					respcyc1 = 0;
					next_ptr = ptr + 1;
					if (ptr == 7) begin
						next_state = ACCEPT;
					end
					else begin
						next_state = RESPOND;
					end
				end
		endcase
	end

	//determine if processor received response: RESPACK
	always_comb begin
		case(state)
			RESPACK: begin
					if(respack0 == 1 || respack1 == 1) begin
						next_state = SETRESPZ;
					end
					else begin
						next_state = RESPACK;
					end
				end
		endcase
	end

	always_ff @ (posedge clk) begin
		if(reset) begin
			state <= INITIAL;
			req_addr <= 0;
			req_tag <= 0;
			content <= 0;
			ptr <= 0;
		end

		//write values from wires to register
		state <= next_state;
		req_addr <= _req_addr;
		req_tag <= _req_tag;
		content <= _content;
		ptr <= next_ptr;
		channel <= _channel;
	end

endmodule
