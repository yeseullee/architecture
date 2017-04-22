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
		READVAL = 3,
		ACKVAL = 4,
		LOOKUP = 5,
		DRAMRD = 6,
		RECEIVE = 7,
		UPDATE = 8,
		RESPOND = 9,
		RESPACK = 10,
		DRAMWREQ = 11,
		DRAMWRT = 12

		//Cache constants
		CACHE_TAG = 55,		//tag = bits in address (64) - bits in offset (4) - bits in index (5)
		CACHE_INDEX = 5,	//index = log2(32) (# sets in the cache)
		NUM_CACHE_LINES = 32,
		OFFSET = 6,			//offset = log2(64) (# addresses in cache line: 8 * 8 sets of 64 bits)
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
	logic [NUM_CACHE_LINES-1:0] dirty_bits;
	logic [NUM_CACHE_LINES-1:0] _dirty_bits;
	logic [NUM_CACHE_LINES-1:0] valid_bits;
	logic [NUM_CACHE_LINES-1:0] _valid_bits;
	logic [CACHE_TAG-1:0] cache_tags[NUM_CACHE_LINES-1:0];
	logic [CACHE_TAG-1:0] _cache_tags[NUM_CACHE_LINES-1:0];
	logic [DATA_LENGTH-1:0] cache_data[NUM_CACHE_LINES-1:0];
	logic [DATA_LENGTH-1:0] _cache_data[NUM_CACHE_LINES-1:0];

	//variables used in RECEIVE and RESPOND to break up content into 8 64-bit blocks
	logic [8:0] ptr;
	logic [8:0] next_ptr;


	//NOTE: multiple always comb blocks used to keep verilator happy
	//	processor resp, ack, and cyc variables cannot be set or used within the same block
   
	//accept requests and values from the processor: INITIAL, ACCEPT, READVAL
	always_comb begin
		case(state)
			INITIAL: begin
					//Initialize the system
					next_state = ACCEPT;
				end
			ACCEPT: begin
					//wait for requests from the processor
					_req_addr = p_bus_req;
					_req_tag = p_bus_reqtag;
					next_ptr = 0;
					if(p_bus_reqcyc == 1) begin
						next_state = ACKPROC;
					end
					else begin
						next_state = ACCEPT;
					end
				end
			READVAL: begin
					//read value to be written from processor
					if(p_bus_reqcyc == 1) begin
						_content[64*ptr +: 63] = p_bus_req;
						next_state = ACKVAL;
					end
					else begin
						next_state = READVAL;
					end
				end
		endcase
	end

	//acknowledge receiving request and values from processor: ACKPROC, ACKVAL
	always_comb begin
		p_bus_reqack = 0;
		case(state)
			ACKPROC: begin
					p_bus_reqack = 1;
					if(req_tag[11] == 0) begin
						_content = 0;
						next_state = READVAL;
					end
					else begin
						next_state = LOOKUP;
					end
				end
			ACKVAL: begin
					p_bus_reqack = 1;
					next_ptr = ptr + 1;
					if(ptr == 7) begin
						next_state = LOOKUP;
						next_ptr = 0;
					end
					else begin
						next_state = READVAL;
					end
				end
		endcase
	end

	//look for requested memory and insert into cache if needed: LOOKUP, DRAMRD, RECEIVE, UPDATE
	always_comb begin
		//misc related variables
		m_bus_reqcyc = 0;
		m_bus_respack = 0;
		_content = content;
		for(int i = 0; i < NUM_CACHE_LINES; i++) begin
			_cache_data[i] = cache_data[i];
			_cache_tags[i] = cache_tags[i];
		end
		_valid_bits = valid_bits;
		_dirty_bits = dirty_bits;
	   
		//extract tag, index, offset from address
		tag = req_addr[63:63-CACHE_TAG+1];
		index = req_addr[63-CACHE_TAG:OFFSET];
		offset = req_addr[OFFSET-1:0];
	   
		case(state)
			LOOKUP: begin
					//compare to existing cache and set next_state and _content respectively
					if(valid_bits[index] == 1) begin
						if(cache_tags[index] == tag) begin

							//cache hit on write (invalidate data)
							if(req_tag[11] == 0) begin
								_valid_bits[index] = 0;
								next_state = UPDATE;
							end

							//cache hit on read
							else begin
								next_state = RESPOND;
								_content = cache_data[index];
							end
						end

						else begin
							//cache miss
							next_state = DRAMRD;
							_content = 0;
						end
					end

					else begin
						//cache miss
						next_state = DRAMRD;
						_content = 0;
					end
				end
			DRAMRD: begin
					//send request to memory
					m_bus_reqcyc = 1;
					m_bus_req = req_addr;
					m_bus_reqtag = req_tag;

					//determine if memory received request
					if(m_bus_reqack == 1) begin
						next_state = RECEIVE;
					end
					else begin
						next_state = DRAMRD;
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
					//insert the new block into the cache
					m_bus_respack = 1;
					if(write == 1) begin
						_dirty_bits[index] == 1;
						if(valid[index] == 1 && dirty_bits[index] == 1) begin
							next_state = DRAMWREQ;
							_content = cache_data[index];
						end
						else
							next_state = ACCEPT;
						end
					end
					else begin
						_dirty_bits[index] == 0;
						next_state = RESPOND;
					end

					_valid_bits[index] = 1;
					_cache_tags[index] = tag;
					_cache_data[index] = content;
				end
			DRAMWREQ: begin
					m_bus_reqcyc = 1;
					m_bus_req = req_addr;
					if(m_bus_reqack == 1) begin
							next_ptr = 0;
							next_state = DRAMWRT;
					end
					else begin
						next_state = DRAMWREQ;
					end
				end
			DRAMWRT: begin
					m_bus_reqcyc = 1;
					m_bus_req = content[64*ptr +: 63];
					if(m_bus_reqack == 1) begin
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_state = ACCEPT;
						end
						else begin
							next_state = DRAMWRT;
						end
					end
		endcase
	end

	//respond to processor: RESPOND
	always_comb begin
		p_bus_respcyc = 0;
		case(state)
			RESPOND:begin
					p_bus_respcyc = 1;
					p_bus_resp = content[64*ptr +: 63];
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
			dirty_bits <= 0;
			valid_bits <= 0;
			for(int i = 0; i < NUM_CACHE_LINES; i++) begin
				cache_data[i] <= 0;
				cache_tags[i] <= 0;
			end
		end

		//write values from wires to register
		state <= next_state;
		req_addr <= _req_addr;
		req_tag <= _req_tag;
		content <= _content;
		ptr <= next_ptr;
		dirty_bits <= _dirty_bits;
		valid_bits <= _valid_bits;
		for(int i = 0; i < NUM_CACHE_LINES; i++) begin
			cache_data[i] <= _cache_data[i];
			cache_tags[i] <= _cache_tags[i];
		end
	end

endmodule
