`include "Sysbus.defs"
module direct_cache
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13,

		INITIAL = 0,
		ACCEPT = 1,
		LOOKUP = 2,
		DRAM = 3,
		RECEIVE = 4,
		UPDATE = 5,
		RESPOND = 6
	)
	(
		input  clk,
		input reset,


		// interface to connect to the bus on the procesor side
		input p_bus_reqcyc,							//set to 1 when a read is requested
		output  p_bus_reqack,						//acknowledgement of request from processor
		input [BUS_DATA_WIDTH-1:0] p_bus_req,		//the address I wanna read
		input [BUS_TAG_WIDTH-1:0] p_bus_reqtag,		//tag associated with request (useful in superscalar)

		output  p_bus_respcyc,						//set to 1 when ready to respond
		input p_bus_respack, 						//acknowledgement by processor when receiving the data
		output  [BUS_DATA_WIDTH-1:0] p_bus_resp,	//content of requested address
		output  [BUS_TAG_WIDTH-1:0] p_bus_resptag	//tag associated with response (useful in superscalar)


		// interface to connect to the bus on the dram(memory) side
		output m_bus_reqcyc,						//set to 1 to request a read from memory
		input  m_bus_reqack,						//acknowledgement by memory when request received
		output [BUS_DATA_WIDTH-1:0] m_bus_req,		//the address I wanna read
		output [BUS_TAG_WIDTH-1:0] m_bus_reqtag,	//tag associated with request (useful in superscalar)

		input  m_bus_respcyc,						//set to 1 when memory has requested information
		output m_bus_respack,						//acknowlegement of response sent to memory
		input  [BUS_DATA_WIDTH-1:0] m_bus_resp,		//the contents of the requested address
		input  [BUS_TAG_WIDTH-1:0] m_bus_resptag	//tag associated with request (useful in superscalar)
	);

	logic [63:0] req_addr = 64'b0;
	logic [63:0] _req_addr = 64'b0;
	logic [63:0] content[7:0];
	logic [63:0] _content = 64'b0;
	logic [2:0] state = INITIAL;
	logic [2:0] next_state = INITIAL;
	logic cache_hit = 0;		//used in LOOKUP only (1 = hit, 0 = miss)
	logic [2:0] ptr = 0			//used in RECEIVE and RESPOND to break up content into 8 64-bit blocks
	logic [2:0] next_ptr = 0	//used in RECEIVE and RESPOND to break up content into 8 64-bit blocks

	always_comb begin
		p_bus_reqack = 0;
		m_bus_respack = 0;
		m_bus_reqcyc = 0;
		m_bus_respcyc = 0;
		case(state)
			INITIAL: next_state = ACCEPT; //Initialize the system
			ACCEPT: begin	//wait for requests from the processor
					if(p_busreqcyc == 1) begin
						_req_addr = p_bus_req;
						p_bus_respack = 1;
						next_state = LOOKUP;
					end
					else begin
						next_state = ACCEPT;
					end
				end
			LOOKUP: begin	//check if requested memory is in cache
					cache_hit = 0;
					//extract tag, index, etc from address
					//compare to existing cache and set cache_hit and _content respectively

					//set state depending on results
					if(cache_hit == 1) begin
						next_state = RESPOND;
					end
					else begin
						next_state = DRAM;
					end
				end
			DRAM: begin		//cache miss, so request from memory
					//send request to memory
					m_bus_reqcyc = 1;
					m_bus_req = req_addr;
					m_bus_reqtag = 64'b0;

					//determine if memory received request
					if(m_bus_reqack = 1) begin
						next_ptr = 0;
						next_state = RECEIVE;
					end
					else begin
						next_state = DRAM;
					end
				end
			RECEIVE: begin		//wait for memory to respond
					//receive reponse from memory if present
					if(m_bus_respcyc == 1) begin
						_content = m_bus_resp;
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_state = UPDATE;
							next_ptr = 0;
						end
						else begin
							next_state = RECEIVE;
						end
					end
					else begin
						next_state = RECEIVE;
					end
				end
			UPDATE: begin	//insert the new block into the cache
					next_state = RESPOND;
				end
			RESPOND:begin	//send data back to processor
					//send response to processor
					p_bus_respcyc = 1;
					p_bus_resp = content[ptr];

					//determine if processor received response
					if(p_bus_respack == 1) begin
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_ptr = 0;
							p_bus_respcyc = 0;
							next_state = ACCEPT;
						end
						else begin
							next_state = RESPOND;
						end
					end
					else begin
						next_ptr = ptr;
						next_state = RESPOND;
					end
				end
		endcase
	end

	always_ff @ (posedge clk) begin
		if(reset) begin
			state <= INITIAL;
			cache_hit <= 1'b0;
			ptr <= 2'b0;
			for(int i = 0; i < 8; i++) begin
				content[i] <= 64'b0;
			end
		end

		//write values from wires to register
		ptr <= next_ptr;
		state <= next_state;
		req_addr <= _req_addr;
		content[ptr] <= _content;
	end

endmodule
