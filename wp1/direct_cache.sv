`include "Sysbus.defs"
module direct_cache
	#(
		BUS_DATA_WIDTH = 64,
		BUS_TAG_WIDTH = 13,

		INITIAL = 0,
		ACCEPT = 1,
		ACKPROC = 2,
		LOOKUP = 3,
		DRAM = 4,
		RECEIVE = 5,
		UPDATE = 6,
		RESPOND = 7,
		RESPACK = 8,

		CACHE_TAG = 56,		//tag = bits in address (64) - bits in offset (3) - bits in index (5)
		CACHE_INDEX = 5,	//index = log2(32) (# sets in the cache)
		NUM_CACHE_SETS = 32,
		OFFSET = 3,			//offset = log2(8) (# bytes in address)
		CACHE_LENGTH = 569,	//length = valid (1) + tag (56) + data length (512)
		DATA_LENGTH = 512
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
		output  [BUS_TAG_WIDTH-1:0] p_bus_resptag,	//tag associated with response (useful in superscalar)


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

	//variables used in all states
	logic [63:0] req_addr = 64'b0;
	logic [63:0] _req_addr = 64'b0;
	logic [12:0] req_tag = 13'b0;
	logic [12:0] _req_tag = 13'b0;
	logic [3:0] state = INITIAL;
	logic [3:0] next_state = INITIAL;
	logic [DATA_LENGTH-1:0] content = 512'b0;
	logic [DATA_LENGTH-1:0] _content = 512'b0;

	//cache management-related variables
	logic [CACHE_TAG-1:0] tag;
	logic [CACHE_INDEX-1:0] index;
	logic [OFFSET-1:0] offset;
	logic [CACHE_LENGTH-1:0] cache[NUM_CACHE_SETS-1:0];
	logic [CACHE_LENGTH-1:0] _cache[NUM_CACHE_SETS-1:0];

	//state specific variables
	logic cache_hit;			//used in LOOKUP only (1 = hit, 0 = miss)
	logic [8:0] ptr = 0;		//used in RECEIVE and RESPOND to break up content into 8 64-bit blocks
	logic [8:0] next_ptr = 0;	//used in RECEIVE and RESPOND to break up content into 8 64-bit blocks
	logic [63:0] cur_data;		//used in RECEIVE and RESPOND to denote data currently being transmitted

	//multiple always comb blocks used to keep verilator happy
	//accept requests from the processor: INITIAL, ACCEPT
	always_comb begin
		case(state)
			INITIAL: begin
					next_state = ACCEPT; //Initialize the system
				end
			ACCEPT: begin	//wait for requests from the processor
					_req_addr = p_bus_req;
					_req_tag = p_bus_reqtag;
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

	//check if request is already in the cache: LOOKUP
	always_comb begin
		//extract tag, index, offset from address
		tag = req_addr[63:63-CACHE_TAG+1];
		index = req_addr[63-CACHE_TAG:OFFSET];
		offset = req_addr[OFFSET-1:0];
		case(state)
			LOOKUP: begin
					//compare to existing cache and set cache_hit and _content respectively
					if(cache[index][CACHE_LENGTH-1] == 1) begin
						if(cache[index][CACHE_LENGTH-2:DATA_LENGTH] == tag) begin
							cache_hit = 1;
							_content = cache[index][DATA_LENGTH-1:0];
						end
						else begin
							cache_hit = 0;
							_content = 0;
						end
					end
					else begin
						cache_hit = 0;
						_content = 0;
					end

					//set state depending on results
					if(cache_hit == 1) begin
						next_state = RESPOND;
					end
					else begin
						next_state = DRAM;
					end
				end
		endcase
	end

	//handle interaction with memory upon cache miss: DRAM, RECEIVE
	always_comb begin
		m_bus_reqcyc = 0;
		m_bus_respack = 0;
		case(state)
			DRAM: begin
					//send request to memory
					m_bus_reqcyc = 1;
					m_bus_req = req_addr;
					m_bus_reqtag = req_tag;

					//determine if memory received request
					if(m_bus_reqack == 1) begin
						next_ptr = 0;
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
						next_state = RECEIVE;
					end
				end
		endcase
	end

	//insert new block received from memory into the cache: UPDATE
	always_comb begin
		for(int i = 0; i < NUM_CACHE_SETS; i++) begin
			_cache[i] = cache[i];
		end
		case(state)
			UPDATE: begin	//insert the new block into the cache
					_cache[index] = {1'b1, tag, content};
					next_state = RESPOND;
				end
		endcase
	end

	//respond to processor: RESPOND
	always_comb begin
		_content = content;
		p_bus_respcyc = 0;

		case(state)
			RESPOND:begin
					p_bus_respcyc = 1;
					p_bus_resp = content[(64*ptr)-1 -: 64];
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
							next_ptr = 0;
							next_state = ACCEPT;
						end
						else begin
							next_state = RESPOND;
						end
					end
					else begin
						next_state = RESPOND;
					end
				end
		endcase
	end

	always_ff @ (posedge clk) begin
		if(reset) begin
			state <= INITIAL;
			ptr <= 0;
			for(int i = 0; i < 8; i++) begin
				content[i] <= 0;
			end
		end

		//write values from wires to register
		ptr <= next_ptr;
		state <= next_state;
		req_addr <= _req_addr;
		req_tag <= _req_tag;
		content <= _content;
		for(int i = 0; i < NUM_CACHE_SETS; i++) begin
			cache[i] <= _cache[i];
		end
	end

endmodule
