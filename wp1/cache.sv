`include "Sysbus.defs"
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

		//Cache constants
		NUM_CACHE_LINES = 32,
		OFFSET = 6,			//offset = log2(64) (# addresses in cache line: 8 * 8 sets of 64 bits)
		DATA_LENGTH = 512,

		//direct cache variables
		DIR_CACHE_TAG = BUS_DATA_WIDTH - OFFSET - DIR_CACHE_INDEX,
		DIR_CACHE_INDEX = 5,	//index = log2(32) (# sets in the cache)

		//set cache variables
		SET_CACHE_TAG = BUS_DATA_WIDTH - OFFSET - SET_CACHE_INDEX,
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
	logic cache_type = 0; //set to 0 for direct, 1 for set
	logic [OFFSET-1:0] offset;
	logic [NUM_CACHE_LINES-1:0] dirty_bits;
	logic [NUM_CACHE_LINES-1:0] _dirty_bits;
	logic [NUM_CACHE_LINES-1:0] valid_bits;
	logic [NUM_CACHE_LINES-1:0] _valid_bits;
	logic [DATA_LENGTH-1:0] cache_data[NUM_CACHE_LINES-1:0];
	logic [DATA_LENGTH-1:0] _cache_data[NUM_CACHE_LINES-1:0];

	//direct cache management variables
	logic [DIR_CACHE_TAG-1:0] dir_tag;
	logic [DIR_CACHE_INDEX-1:0] dir_index;
	logic [DIR_CACHE_TAG-1:0] dir_cache_tags[NUM_CACHE_LINES-1:0];
	logic [DIR_CACHE_TAG-1:0] _dir_cache_tags[NUM_CACHE_LINES-1:0];

	//set cache management variables
	logic [SET_CACHE_TAG-1:0] set_tag;
	logic [SET_CACHE_INDEX-1:0] set_index;
	logic [SET_CACHE_INDEX:0] update_index; //change to [31:0] if range issues pop up
	logic [NUM_CACHE_LINES-1:0] recent_bits;
	logic [NUM_CACHE_LINES-1:0] _recent_bits;
	logic [SET_CACHE_TAG-1:0] set_cache_tags[NUM_CACHE_LINES-1:0];
	logic [SET_CACHE_TAG-1:0] _set_cache_tags[NUM_CACHE_LINES-1:0];

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
			_dir_cache_tags[i] = dir_cache_tags[i];
		end
		_valid_bits = valid_bits;
		_dirty_bits = dirty_bits;
		_recent_bits = recent_bits;
	   
		//extract tag, index, offset from address
		dir_tag = req_addr[63:63-DIR_CACHE_TAG+1];
		dir_index = req_addr[63-DIR_CACHE_TAG:OFFSET];
		set_tag = req_addr[63:63-DIR_CACHE_TAG+1];
		set_index = req_addr[63-DIR_CACHE_TAG:OFFSET];
		offset = req_addr[OFFSET-1:0];
	   
		case(state)
			LOOKUP: begin
					//compare to existing cache and set next_state and _content respectively
					if(cache_type == 0) begin //direct cache
						if(valid_bits[dir_index] == 1) begin
							if(dir_cache_tags[dir_index] == dir_tag) begin

								//cache hit on write (invalidate data)
								if(req_tag[12] == `SYSBUS_WRITE) begin
									_valid_bits[dir_index] = 0;
									next_state = UPDATE;
								end

								//cache hit on read
								else begin
									next_state = RESPOND;
									_content = cache_data[dir_index];
								end
							end
//TODO:cache miss with writing should also go to UPDATE, since all 512 bits are given
							else if(req_tag[12] == `SYSBUS_WRITE) begin
								//cache miss on write
								next_state = UPDATE;
							end
							else begin
								//cache miss on read
								next_state = DRAMRD;
								_content = 0;
							end
						end
						else if(req_tag[12] == `SYSBUS_WRITE) begin
							//cache miss on write
							next_state = UPDATE;
						end
						else begin
							//cache miss on read
							next_state = DRAMRD;
							_content = 0;
						end
					end
					else begin //set cache
						if(req_tag[12] == `SYSBUS_WRITE) begin
							//cache miss on write
							next_state = UPDATE;
						end
						else begin
							//cache miss on read
							next_state = DRAMRD;
							_content = 0;
						end
						for(int i = 0; i < NUM_CACHE_LINES/NUM_CACHE_SETS; i++) begin
							if(valid_bits[(2*set_index)+i] == 1) begin
								if(set_cache_tags[(2*set_index)+i] == set_tag) begin

									//cache hit on write (invalidate data)
									if(req_tag[12] == 0) begin
										_valid_bits[(2*set_index)+i] = 0;
										next_state = UPDATE;
									end

									//cache hit on read
									else begin
										next_state = RESPOND;
										_content = cache_data[(2*set_index)+i];
									end

									//cache hit; break out of loop
									break;
								end
								else if(req_tag[12] == `SYSBUS_WRITE) begin
									//cache miss on write
									next_state = UPDATE;
								end
								else begin
									//cache miss on read
									next_state = DRAMRD;
									_content = 0;
								end
							end
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
					if(ptr == 8) begin
						next_state = UPDATE;
						next_ptr = 0;
					end
					else if(m_bus_respcyc == 1) begin
						m_bus_respack = 1;
						//_content[(DATA_LENGTH-1)-(64*ptr):(DATA_LENGTH-1)-(64*(ptr+1)] = m_bus_resp;
						_content[64*ptr +: 64] = m_bus_resp;
						next_ptr = ptr;
						if(m_bus_resp != _content[64*(ptr-1) +: 64] || m_bus_resp == 0) begin
							next_ptr = ptr + 1;
						end
						next_state = RECEIVE;
					end
					else begin
					   	m_bus_respack = 0;
						next_state = RECEIVE;
					end
				end
			UPDATE: begin
					//insert the new block into the cache
					if(cache_type == 0) begin //direct cache
						m_bus_respack = 1;
						if(req_tag[12] == 0) begin
							_dirty_bits[dir_index] = 1;
							if(valid_bits[dir_index] == 1 && dirty_bits[dir_index] == 1) begin
								next_state = DRAMWREQ;
								_content = cache_data[dir_index];
							end
							else begin
								next_state = ACCEPT;
							end
						end
						else begin
							_dirty_bits[dir_index] = 0;
							next_state = RESPOND;
						end

						_valid_bits[dir_index] = 1;
						_dir_cache_tags[dir_index] = dir_tag;
						_cache_data[dir_index] = content;
					end
					else begin //set cache
						m_bus_respack = 1;
						update_index = -1;

						//find location
						for(int i = 0; i < NUM_CACHE_LINES/NUM_CACHE_SETS; i++) begin
							//check for valid bit == 0
							if(valid_bits[(2*set_index)+i] == 0) begin
								update_index = (2*set_index) + i;
								break;
							end
							//if valid == 0 not found, replace older line in set
							else if((update_index == -1) && (recent_bits[(2*set_index)+i] == 0)) begin
								update_index = (2*set_index) + i;
								break;
							end
						end

						//replace the cache block as needed
						if(req_tag[12] == 0) begin //cache write
							_dirty_bits[update_index] = 1;
							if(valid_bits[update_index] == 1 && dirty_bits[update_index] == 1) begin
								next_state = DRAMWREQ;
								_content = cache_data[update_index];
							end
							else begin
								next_state = ACCEPT;
							end
						end
						else begin
							_dirty_bits[update_index] = 0;
							next_state = RESPOND;
						end

						_valid_bits[update_index] = 1;
						_set_cache_tags[update_index] = set_tag;
						_cache_data[update_index] = content;

						//set the recent bits
						for(int i = 0; i < NUM_CACHE_LINES/NUM_CACHE_SETS; i++) begin
							if((2*set_index) + i == update_index) begin
								_recent_bits[(2*set_index)+i] = 1;
							end
							else begin
								_recent_bits[(2*set_index)+i] = 0;
							end
						end
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
			dirty_bits <= 0;
			valid_bits <= 0;
			recent_bits <= 0;
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
		dirty_bits <= _dirty_bits;
		valid_bits <= _valid_bits;
		recent_bits <= _recent_bits;
		for(int i = 0; i < NUM_CACHE_LINES; i++) begin
			cache_data[i] <= _cache_data[i];
			dir_cache_tags[i] <= _dir_cache_tags[i];
			set_cache_tags[i] <= _set_cache_tags[i];
		end
	end

endmodule
