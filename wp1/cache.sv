module cache
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
		SETRESPZ = 11,
		DRAMWREQ = 12,
		DRAMWRT = 13,
                INVALIDATE = 14,

		//Cache constants
		NUM_CACHE_LINES = 32,
		OFFSET = 6,			//offset = log2(64) (# addresses in cache line: 8 * 8 sets of 64 bits)
		DATA_LENGTH = 512,

		//direct cache variables
		DIR_CACHE_TAG = BUS_DATA_WIDTH - OFFSET - DIR_CACHE_INDEX, // 64-6-5 = 53
		DIR_CACHE_INDEX = 5,	//index = log2(32) (# sets in the cache)

		//set cache variables
		SET_CACHE_TAG = BUS_DATA_WIDTH - OFFSET - SET_CACHE_INDEX, // 54
		SET_CACHE_INDEX = 4,	//index = log2(16) (# sets in the cache) 
		NUM_CACHE_SETS = 16
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
		output [8:0] out_ptr,
                output invalidated,
		input [BUS_DATA_WIDTH-1:0] inv_req,


		// interface to connect to the bus on the dram(memory) side
		output m_bus_reqcyc,				//set to 1 to request a read from memory
		input  m_bus_reqack,				//acknowledgement by memory when request received
		output [BUS_DATA_WIDTH-1:0] m_bus_req,		//the address I wanna read
		output [BUS_TAG_WIDTH-1:0] m_bus_reqtag,	//tag associated with request (useful in superscalar)

		input  m_bus_respcyc,				//set to 1 when memory has requested information
		output m_bus_respack,				//acknowlegement of response sent to memory
		input  [BUS_DATA_WIDTH-1:0] m_bus_resp,		//the contents of the requested address
		input  [BUS_TAG_WIDTH-1:0] m_bus_resptag,	//tag associated with request (useful in superscalar)
		output [8:0] mem_ptr
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
	logic cache_type = 1; //set to 0 for direct, 1 for set
	logic [OFFSET-1:0] offset; // Don't need offset because all requests are 64 byte aligned.
	logic [NUM_CACHE_LINES-1:0] valid_bits;
	logic [NUM_CACHE_LINES-1:0] _valid_bits;
	logic [DATA_LENGTH-1:0] cache_data[NUM_CACHE_LINES-1:0];
	logic [DATA_LENGTH-1:0] _cache_data[NUM_CACHE_LINES-1:0];

	//direct cache management variables
	logic [DIR_CACHE_TAG-1:0] dir_tag;
	logic [DIR_CACHE_INDEX-1:0] dir_index;
	logic [DIR_CACHE_TAG-1:0] dir_cache_tags[NUM_CACHE_LINES-1:0]; // 53 bits. 32 lines.
	logic [DIR_CACHE_TAG-1:0] _dir_cache_tags[NUM_CACHE_LINES-1:0];

	//set cache management variables
	logic [SET_CACHE_TAG-1:0] set_tag;
	logic [SET_CACHE_INDEX-1:0] set_index; // 4 bits
	logic [SET_CACHE_INDEX:0] set_cache_index; // 5 bits -- for indexing 32 cache lines. 
	logic [SET_CACHE_TAG-1:0] set_cache_tags[NUM_CACHE_LINES-1:0]; // 54 bits. 32 lines.
	logic [SET_CACHE_TAG-1:0] _set_cache_tags[NUM_CACHE_LINES-1:0];

	//variables used in RECEIVE and RESPOND to break up content into 8 64-bit blocks
	logic [8:0] ptr;
	logic [8:0] next_ptr;
	logic [8:0] zcounter;
	logic [8:0] _zcounter;

        //variables to use when invalidating
	logic [DIR_CACHE_TAG-1:0] inv_dir_tag;
	logic [DIR_CACHE_INDEX-1:0] inv_dir_index;
	logic [SET_CACHE_TAG-1:0] inv_set_tag;
	logic [SET_CACHE_INDEX-1:0] inv_set_index;

	//NOTE: multiple always comb blocks used to keep verilator happy
	//	processor resp, ack, and cyc variables cannot be set or used within the same block
   
	//accept requests and values from the processor: INITIAL, ACCEPT, READVAL
	always_comb begin

                invalidated = 0;

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
					set_cache_index = 0;
                                        
					if(inv_req != 0) begin
						next_state = INVALIDATE;
					end
					else if(p_bus_reqcyc == 1) begin
						next_state = ACKPROC;
					end
					else begin
						next_state = ACCEPT;
					end
				end
                        INVALIDATE: begin
					//extract tag, index, offset from address
					inv_dir_tag = inv_req[63:63-DIR_CACHE_TAG+1];  // 63:11
					inv_dir_index = inv_req[63-DIR_CACHE_TAG:OFFSET]; //10:6
					inv_set_tag = inv_req[63:63-SET_CACHE_TAG+1]; // 63:10
					inv_set_index = inv_req[63-SET_CACHE_TAG:OFFSET]; // 9:6

					if(cache_type == 0) begin // Direct Mapped
						if(valid_bits[inv_dir_index] == 1) begin
							if(dir_cache_tags[inv_dir_index] == inv_dir_tag) begin
								_valid_bits[inv_dir_index] = 0;
								_dir_cache_tags[inv_dir_index] = 0;
                                	                        _cache_data[inv_dir_index] = 0;
							end
						end
						invalidated = 1;
						next_state= ACCEPT;
					end else begin // Set Associative
						if(valid_bits[2*inv_set_index] == 1 && set_cache_tags[2*inv_set_index] == inv_set_tag) begin
							set_cache_index = 2*inv_set_index;
							_valid_bits[set_cache_index] = 0;
							_set_cache_tags[set_cache_index] = 0;
                                	                _cache_data[set_cache_index] = 0;
						end
						else if(valid_bits[2*inv_set_index + 1] == 1 && set_cache_tags[2*inv_set_index + 1] == inv_set_tag) begin
							set_cache_index = 2*inv_set_index + 1;
							_valid_bits[set_cache_index] = 0;
							_set_cache_tags[set_cache_index] = 0;
                                	                _cache_data[set_cache_index] = 0;
						end 
						invalidated = 1;
						next_state= ACCEPT;
					end
				end
			READVAL: begin
					//read value to be written from processor
					if(p_bus_reqcyc == 1) begin
						_content[64*ptr +: 64] = p_bus_req;
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
					if(req_tag[12] == `SYSBUS_WRITE) begin
						// Writing
						_content = 0;
						next_state = READVAL;
					end
					else begin
						// Reading
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
		_valid_bits = valid_bits;
	   
		//extract tag, index, offset from address
		dir_tag = req_addr[63:63-DIR_CACHE_TAG+1];  // 63:11
		dir_index = req_addr[63-DIR_CACHE_TAG:OFFSET]; //10:6
		set_tag = req_addr[63:63-SET_CACHE_TAG+1]; // 63:10
		set_index = req_addr[63-SET_CACHE_TAG:OFFSET]; // 9:6
		offset = req_addr[OFFSET-1:0]; // 5:0 
	   
		case(state)
			LOOKUP: begin
					//cache miss with writing should also go to UPDATE, since all 512 bits are given
					//goes to RESPOND or DRAMRD otherwise
					//compare to existing cache and set next_state and _content respectively

					//ON WRITE, need to update first.
					if(req_tag[12] == `SYSBUS_WRITE) begin

						// Set the cache index to update.
						if(cache_type == 1) begin // set cache
							if(valid_bits[2*set_index] == 1 && set_cache_tags[2*set_index] == set_tag) begin
								set_cache_index = 2*set_index;
							end
							else if(valid_bits[2*set_index + 1] == 1 && set_cache_tags[2*set_index + 1] == set_tag) begin
								set_cache_index = 2*set_index + 1;
							end 
							else begin
								// Just choose randomly.
								set_cache_index = 2*set_index + req_addr[0]; 
							end
						end

						next_state = UPDATE;
					end
					//On READ
					else if(cache_type == 0) begin //direct cache
						// Valid bit == 1
						if(valid_bits[dir_index] == 1 && dir_cache_tags[dir_index] == dir_tag) begin
							//cache hit on read
							next_state = RESPOND;
							_content = cache_data[dir_index];
						end
						else begin
							//cache miss on read
							next_state = DRAMRD;
							_content = 0;
						end
					end
					else begin //set cache
						// Valid bit == 1
						if(valid_bits[2*set_index] == 1 && set_cache_tags[2*set_index] == set_tag) begin
							//cache hit on read
							next_state = RESPOND;
							_content = cache_data[2*set_index];
							set_cache_index = 2*set_index;
						end
						else if(valid_bits[2*set_index + 1] == 1 && set_cache_tags[2*set_index + 1] == set_tag) begin
							//cache hit on read
							next_state = RESPOND;
							_content = cache_data[2*set_index + 1];
							set_cache_index = 2*set_index + 1;
						end
						else begin
							//cache miss on read
							next_state = DRAMRD;
							_content = 0;
							// Just choose randomly.
							set_cache_index = 2*set_index + req_addr[0]; 
						end
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
					if(ptr == 8 || (ptr == 7 && zcounter > 2)) begin
						next_state = UPDATE;
						next_ptr = 0;
						_zcounter = 0;
					end
					else if(m_bus_respcyc == 1) begin
						m_bus_respack = 1;
						_content[64*mem_ptr +: 64] = m_bus_resp;
						next_state = RECEIVE;
						if(mem_ptr == 7) begin
							next_state = UPDATE;
							next_ptr = 0;
						end
					end
					else begin
					   	m_bus_respack = 0;
						next_state = RECEIVE;
						if(zcounter != 0) begin
							_zcounter = zcounter + 1;
						end
					end
				end
			UPDATE: begin
					m_bus_respack = 1;
					//insert the new block into the cache
					if(cache_type == 0) begin //direct cache
						_valid_bits[dir_index] = 1; // saying its valid to retrieve.
						_dir_cache_tags[dir_index] = dir_tag; // marking new tag.
						_cache_data[dir_index] = content; // write the content retrieved back to cache block.
					end
					else begin //set cache
						_valid_bits[set_cache_index] = 1; 
						_set_cache_tags[set_cache_index] = set_tag; 
						_cache_data[set_cache_index] = content; 
					end

					if(req_tag[12] == `SYSBUS_WRITE) begin
						next_state = DRAMWREQ;
					end
					else begin
						next_state = RESPOND;
					end
				end
			DRAMWREQ: begin
					m_bus_reqcyc = 1;
					m_bus_reqtag = req_tag;
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
					m_bus_req = content[64*ptr +: 64];
					if(m_bus_reqack == 1) begin
						next_ptr = ptr + 1;
						if(ptr == 7) begin
							next_state = ACCEPT;
						end
						else begin
							next_state = DRAMWRT;
						end
					end
				end
		endcase
	end

	//respond to processor: RESPOND
	always_comb begin
		out_ptr = ptr;
		case(state)
			RESPOND:begin
					p_bus_respcyc = 1;
					p_bus_resp = content[64*ptr +: 64];
					p_bus_resptag = req_tag;
					next_ptr = ptr;
					next_state = RESPACK;
				end
			SETRESPZ: begin
					//third state solely to keep verilator happy
					next_ptr = ptr + 1;
					p_bus_respcyc = 0;
					if(ptr == 7) begin
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
					if(p_bus_respack == 1) begin
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
			zcounter <= 0;
			valid_bits <= 0;
			for(int i = 0; i < NUM_CACHE_LINES; i++) begin
				cache_data[i] <= 0;
				dir_cache_tags[i] <= 0;
				set_cache_tags[i] <= 0;
			end
		end

		//write values from wires to register
		state <= next_state;
		req_addr <= _req_addr;
		req_tag <= _req_tag;
		content <= _content;
		ptr <= next_ptr;
		zcounter <= _zcounter;
		valid_bits <= _valid_bits;
		for(int i = 0; i < NUM_CACHE_LINES; i++) begin
			cache_data[i] <= _cache_data[i];
			dir_cache_tags[i] <= _dir_cache_tags[i];
			set_cache_tags[i] <= _set_cache_tags[i];
		end
	end

endmodule
