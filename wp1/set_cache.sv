`include "Sysbus.defs"
module direct_cache
	#(
		//Memory bus constants
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13,

		//State values
		INITIAL = 0,
		ACCEPT = 1,
		ACKPROC = 2,
		LOOKUP = 3,
		DRAM = 4,
		RECEIVE = 5,
		UPDATE = 6,
		RESPOND = 7,
		RESPACK = 8,

		//Cache constants
		CACHE_TAG = 57,		//tag = bits in address (64) - bits in offset (3) - bits in index (4)
		CACHE_INDEX = 5,	//index = log2(16) (# sets in the cache: 16 2-way sets)
		NUM_CACHE_SETS = 32,
		NUM_SET_WAYS = 2,
		OFFSET = 3,			//offset = log2(8) (# bytes in address)
		CACHE_LENGTH = 570,	//length = recent (1) + valid (1) + tag (56) + data length (512)
		DATA_LENGTH = 512
	)
	(
		input  clk,
		input reset,


		// interface to connect to the bus on the procesor side
		input p_bus_reqcyc,				//set to 1 when a read is requested
		output  p_bus_reqack,				//acknowledgement of request from processor
		input [BUS_DATA_WIDTH-1:0] p_bus_req,		//the address I wanna read
		input [BUS_TAG_WIDTH-1:0] p_bus_reqtag,		//tag associated with request (useful in superscalar)

		output  p_bus_respcyc,				//set to 1 when ready to respond
		input p_bus_respack, 				//acknowledgement by processor when receiving the data
		output  [BUS_DATA_WIDTH-1:0] p_bus_resp,	//content of requested address
		output  [BUS_TAG_WIDTH-1:0] p_bus_resptag,	//tag associated with response (useful in superscalar)


		// interface to connect to the bus on the dram(memory) side
		output m_bus_reqcyc,				//set to 1 to request a read from memory
		input  m_bus_reqack,				//acknowledgement by memory when request received
		output [BUS_DATA_WIDTH-1:0] m_bus_req,		//the address I wanna read
		output [BUS_TAG_WIDTH-1:0] m_bus_reqtag,	//tag associated with request (useful in superscalar)

		input  m_bus_respcyc,				//set to 1 when memory has requested information
		output m_bus_respack,				//acknowlegement of response sent to memory
		input  [BUS_DATA_WIDTH-1:0] m_bus_resp,		//the contents of the requested address
		input  [BUS_TAG_WIDTH-1:0] m_bus_resptag	//tag associated with request (useful in superscalar)
	);

	//variables used in all states
	logic [63:0] req_addr;
	logic [63:0] _req_addr;
	logic [12:0] req_tag;
	logic [12:0] _req_tag;
	logic [3:0] state;
	logic [3:0] next_state;
	logic [DATA_LENGTH-1:0] content;
	logic [DATA_LENGTH-1:0] _content;

	//cache management-related variables
	logic [CACHE_TAG-1:0] tag;
	logic [CACHE_INDEX-1:0] index;
	logic [OFFSET-1:0] offset;
	logic [CACHE_LENGTH-1:0] cache[NUM_CACHE_SETS-1:0];
	logic [CACHE_LENGTH-1:0] _cache[NUM_CACHE_SETS-1:0];
	//logic [15:0] cache_rand;	//boolean primarily used in UPDATE, and only when NUM_CACHE_SETS > 2

	//variables used in RECEIVE and RESPOND to break up content into 8 64-bit blocks
	logic [8:0] ptr;
	logic [8:0] next_ptr;
	logic [63:0] cur_data;		//denotes data currently being transmitted


	//NOTE: multiple always comb blocks used to keep verilator happy
	//	processor resp, ack, and cyc variables cannot be set or used within the same block
   
	//accept requests from the processor: INITIAL, ACCEPT
	always_comb begin
		case(state)
			INITIAL: begin
					//Initialize the system
					next_state = ACCEPT;
				end
			ACCEPT: begin	//wait for requests from the processor
					_req_addr = p_bus_req;
					_req_tag = p_bus_reqtag;
					//_content = 0;
					next_ptr = 0;
					if(p_bus_reqcyc == 1) begin
						next_state = ACKPROC;
					end
					else begin
						next_state = ACCEPT;
					end
				end
		endcase
	end

	//acknowledge receiving request from processor: ACKPROC
	always_comb begin
		p_bus_reqack = 0;
		case(state)
			ACKPROC: begin
					p_bus_reqack = 1;
					next_state = LOOKUP;
				end
		endcase
	end

	//look for requested memory and insert into cache if needed: LOOKUP, DRAM, RECEIVE, UPDATE
	always_comb begin
		//misc related variables
		m_bus_reqcyc = 0;
		m_bus_respack = 0;
		_content = content;
		for(int i = 0; i < NUM_CACHE_SETS; i++) begin
			_cache[i] = cache[i];
		end
	   
		//extract tag, index, offset from address
		tag = req_addr[63:63-CACHE_TAG+1];
		index = req_addr[63-CACHE_TAG:OFFSET];
		offset = req_addr[OFFSET-1:0];
	   
		case(state)
			LOOKUP: begin
					//compare to existing cache and set next_state and _content respectively
					next_state = DRAM;
					_content = 0;
					for(int i = 0; i < NUM_SET_WAYS; i++) begin
						if(cache[index+i][CACHE_LENGTH-2] == 1) begin
							if(cache[index+i][CACHE_LENGTH-3:DATA_LENGTH] == tag) begin
								next_state = RESPOND;
								_content = cache[index+i][DATA_LENGTH-2:0];
							end
						end
					end
				end
			DRAM: begin
					//send request to memory
					m_bus_reqcyc = 1;
					m_bus_req = req_addr;
					m_bus_reqtag = req_tag;

					//determine if memory received request
					if(m_bus_reqack == 1) begin
						next_state = RECEIVE;
					end
					else begin
						next_state = DRAM;
					end
				end
			RECEIVE: begin
					//receive reponse from memory if present
					if(m_bus_respcyc == 1) begin
						m_bus_respack = 1;
						//_content[(DATA_LENGTH-1)-(64*ptr):(DATA_LENGTH-1)-(64*(ptr+1)] = m_bus_resp;
						_content[64*ptr +: 63] = m_bus_resp;
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
					   	m_bus_respack = 0;
						next_state = RECEIVE;
					end
				end
			UPDATE: begin
					//insert the new block into the cache and flip recent bits
					//acknowledge last response from dram
					m_bus_respack = 1;

					//LRU solution, given NUM_SET_WAYS == 2
					if(cache[index][CACHE_LENGTH-1] == 1) begin
						_cache[index][CACHE_LENGTH-1] = 0;
						_cache[index+1] = {1'b1, 1'b1, tag, content};
					end
					else begin
						_cache[index] = {1'b1, 1'b1, tag, content};
						_cache[index+1][CACHE_LENGTH-1] = 0;
					end

					/*NMRU solution, given NUM_SET_WAYS > 2
					//find the first non-recent block found: follow NMRU
					//TODO: think through if this creates loop
					cache_rand = 0;
					for(int i = 0; i < NUM_SET_WAYS; i++) begin

						//set the previous most recent to be old
						if(cache[index+i][CACHE_LENGTH-1] == 1) begin
							_cache[index+i][CACHE_LENGTH-1] = 0;
						end

						//skip if replacement has been done
						else if (cache_rand == 1) begin
						end

						//replace the first non-recent block found, and set as most recent
						else if(cache[index+i][CACHE_LENGTH-1] == 0) begin
							_cache[index+i] = {1'b1, 1'b1, tag, content};
							cache_rand = 1;
						end
					end
					*/

					//continue to next state
					next_state = RESPOND;
				end
		endcase
	end

	//respond to processor: RESPOND
	always_comb begin
		p_bus_respcyc = 0;
		case(state)
			RESPOND:begin
					p_bus_respcyc = 1;
					p_bus_resp = _content[64*ptr +: 63];
					next_ptr = ptr;
					next_state = RESPACK;
				end
		endcase
	end

	//determine if processor received response: RESPACK
	always_comb begin
		case(state)
			RESPACK: begin
					if(p_bus_respack == 1) begin
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_state = ACCEPT;
						end
						else begin
							next_state = RESPOND;
						end
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
			for(int i = 0; i < NUM_CACHE_SETS; i++) begin
				cache[i] <= 0;
			end
		end

		//write values from wires to register
		state <= next_state;
		req_addr <= _req_addr;
		req_tag <= _req_tag;
		content <= _content;
		ptr <= next_ptr;
		for(int i = 0; i < NUM_CACHE_SETS; i++) begin
			cache[i] <= _cache[i];
		end
	end

endmodule
