`include "Sysbus.defs"
`include "Mem.defs"
`include "Alu.defs"

module top
#(
    BUS_DATA_WIDTH = 64,
    BUS_TAG_WIDTH = 13,
    INIT=4'd0,
    FETCH=4'd1,
    WAIT=4'd2,
    GETINSTR = 4'd3,
    DECODE=4'd4,
    READ = 4'd5,
    EXECUTE=4'd6,
    MEM = 4'd7,
    WRITEBACK = 4'd8,
    IDLE=4'd9,
    JUMP= 4'd10
)
(
    input  clk,
           reset,

    // 64-bit address of the program entry point
    input  [63:0] entry,
    input  [63:0] stackptr,
    input  [63:0] satp,
 
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

    logic [63:0] pc;
    logic [63:0] _pc;
    logic [63:0] cur_pc;
    logic [63:0] _cur_pc;

    //For stalls
    reg [31:0] stall_instr;
    reg [31:0] _stall_instr;
    reg [3:0] stallstate;
    reg [3:0] _stallstate;

    //For jumps
    reg jumpbit; 
    reg _jumpbit;
    reg [31:0] jump_to_addr;
    reg [31:0] _jump_to_addr;
    reg [3:0] index_from_pc;
    reg [3:0] _index_from_pc;
    reg [3:0] nop_state;
    reg [3:0] _nop_state;
    reg jumpNOW;
    reg _jumpNOW;

    reg firstFETCH;
    reg _firstFETCH;

    //The index is the register.
    // [32] = Is written to; [31:0] = The instruction writing. 
    reg [32:0] writinglist[31:0];
    reg [32:0] _writinglist[31:0];

    reg [3:0] state;
    reg [3:0] next_state;
    reg [31:0] instr;
    reg [31:0] _instr;
    reg [4:0] fetch_count;
    reg [4:0] _fetch_count;
    reg getinstr_ready;
    reg _getinstr_ready;
    reg [31:0] instr_before_fetch;
    reg [31:0] _instr_before_fetch;
    reg [32:0] last_instr;
    reg [32:0] _last_instr;

    //handle incoming instructions
    //setup inputs & outputs for all modules

    //instruction decode output registers and wires
    logic [4:0] ID_rd;
    logic [4:0] _ID_rd;
    logic [4:0] ID_rs1;
    logic [4:0] _ID_rs1;
    logic [4:0] ID_rs2;
    logic [4:0] _ID_rs2;
    logic signed [31:0] ID_immediate;
    logic signed [31:0] _ID_immediate;
    logic [10:0] ID_alu_op;
    logic [10:0] _ID_alu_op;
    logic [5:0] ID_shamt;
    logic [5:0] _ID_shamt;
    logic ID_write_sig;
    logic _ID_write_sig;
    logic [3:0] ID_instr_type;
    logic [3:0] _ID_instr_type;
    logic [31:0] ID_instr; //This is just for debugging.
    logic [31:0] _ID_instr;
    logic [1:0] ID_mem_access;
    logic [1:0] _ID_mem_access;
    logic [2:0] ID_mem_size;
    logic [2:0] _ID_mem_size;
    logic [1:0] ID_ecall;
    logic [1:0] _ID_ecall;
    logic [2:0] ID_isBranch;
    logic [2:0] _ID_isBranch;
    logic [63:0] ID_pc;
    logic [63:0] _ID_pc;

    //READ WIRES & REGISTERS  
    //Pass along REGISTERS (8)
    logic [31:0] RD_immediate;
    logic [31:0] _RD_immediate;
    logic [10:0] RD_alu_op;
    logic [10:0] _RD_alu_op; 
    logic [5:0] RD_shamt;
    logic [5:0] _RD_shamt; 
    logic RD_write_sig;
    logic _RD_write_sig; 
    logic [4:0] RD_write_reg;
    logic [4:0] _RD_write_reg;
    logic [3:0] RD_instr_type;
    logic [3:0] _RD_instr_type;
    // Also pass these .. (from Reg file output)
    logic [63:0] RD_rs1_val;
    logic [63:0] _RD_rs1_val;
    logic [63:0] RD_rs2_val;
    logic [63:0] _RD_rs2_val;
    logic [31:0] RD_instr; //For debugging
    logic [31:0] _RD_instr;
    logic [4:0] RD_rs1;
    logic [4:0] _RD_rs1;
    logic [4:0] RD_rs2;
    logic [4:0] _RD_rs2;// up to here for debugging.
    logic [1:0] RD_mem_access;
    logic [1:0] _RD_mem_access;
    logic [2:0] RD_mem_size;
    logic [2:0] _RD_mem_size;
    logic [2:0] RD_isBranch;
    logic [2:0] _RD_isBranch;
    logic [63:0] RD_pc;
    logic [63:0] _RD_pc;
    //ECALL wires and registers
    logic [1:0] RD_ecall;
    logic [1:0] _RD_ecall;
    logic [63:0] RD_a0;
    logic [63:0] _RD_a0;
    logic [63:0] RD_a1;
    logic [63:0] _RD_a1;
    logic [63:0] RD_a2;
    logic [63:0] _RD_a2;
    logic [63:0] RD_a3;
    logic [63:0] _RD_a3;
    logic [63:0] RD_a4;
    logic [63:0] _RD_a4;
    logic [63:0] RD_a5;
    logic [63:0] _RD_a5;
    logic [63:0] RD_a6;
    logic [63:0] _RD_a6;
    logic [63:0] RD_a7;
    logic [63:0] _RD_a7;

    //EXECUTE stage WIRES & REGISTERS
    // Pass along REGISTERS (3)
    logic [63:0] EX_rs2_val;
    logic [63:0] _EX_rs2_val;
    logic [63:0] EX_alu_result;
    logic [63:0] _EX_alu_result;
    logic [4:0] EX_write_reg;
    logic [4:0] _EX_write_reg;
    logic EX_write_sig;
    logic _EX_write_sig; 
    logic [31:0] EX_instr; //For debugging
    logic [31:0] _EX_instr;
    logic [1:0] EX_mem_access;
    logic [1:0] _EX_mem_access;
    logic [2:0] EX_mem_size;
    logic [2:0] _EX_mem_size;
    logic [2:0] EX_isBranch;
    logic [2:0] _EX_isBranch;
    logic [31:0] EX_immediate;
    logic [31:0] _EX_immediate;
    logic [63:0] EX_pc;
    logic [63:0] _EX_pc;
    //ECALL wires and registers
    logic [1:0] EX_ecall;
    logic [1:0] _EX_ecall;
    logic [63:0] EX_a0;
    logic [63:0] _EX_a0;
    logic [63:0] EX_a1;
    logic [63:0] _EX_a1;
    logic [63:0] EX_a2;
    logic [63:0] _EX_a2;
    logic [63:0] EX_a3;
    logic [63:0] _EX_a3;
    logic [63:0] EX_a4;
    logic [63:0] _EX_a4;
    logic [63:0] EX_a5;
    logic [63:0] _EX_a5;
    logic [63:0] EX_a6;
    logic [63:0] _EX_a6;
    logic [63:0] EX_a7;
    logic [63:0] _EX_a7;

    //MEMORY WIRES & REGISTERS
    //logic [63:0] MEM_alu_result;
    logic [63:0] _MEM_alu_result;
    logic [63:0] MEM_value;
    logic [63:0] _MEM_value;
    logic [4:0] MEM_write_reg;
    logic [4:0] _MEM_write_reg;
    logic MEM_write_sig;
    logic _MEM_write_sig; 
    logic [31:0] MEM_instr; //For debugging
    logic [31:0] _MEM_instr;
    logic [1:0] MEM_access;
    logic [1:0] _MEM_access;
    logic [2:0] MEM_size;
    logic [2:0] _MEM_size;
    logic [63:0] _MEM_rs2_val;
    logic [63:0] MEM_rs2_val;
    logic [2:0] MEM_isBranch;
    logic [2:0] _MEM_isBranch;
    logic [63:0] MEM_pc;
    logic [63:0] _MEM_pc;
    //ECALL wires and registers
    logic [1:0] MEM_ecall;
    logic [1:0] _MEM_ecall;
    logic [63:0] MEM_a0;
    logic [63:0] _MEM_a0;
    logic [63:0] MEM_a1;
    logic [63:0] _MEM_a1;
    logic [63:0] MEM_a2;
    logic [63:0] _MEM_a2;
    logic [63:0] MEM_a3;
    logic [63:0] _MEM_a3;
    logic [63:0] MEM_a4;
    logic [63:0] _MEM_a4;
    logic [63:0] MEM_a5;
    logic [63:0] _MEM_a5;
    logic [63:0] MEM_a6;
    logic [63:0] _MEM_a6;
    logic [63:0] MEM_a7;
    logic [63:0] _MEM_a7;
    //memory stage variables
    logic [2:0] MEM_status;
    logic [2:0] _MEM_status;
    logic [8:0] MEM_ptr;
    logic [8:0] MEM_next_ptr;
    logic [511:0] MEM_read_value;
    logic [511:0] _MEM_read_value;
    logic [63:0] MEM_str_value;
    logic [63:0] _MEM_str_value;

    //WB pass along
    logic [31:0] WB_instr; //For debuggin
    logic [31:0] _WB_instr;
    logic [4:0] WB_write_reg; 
    logic [4:0] _WB_write_reg;
    logic [63:0] WB_write_val;
    logic [63:0] _WB_write_val;
    logic WB_write_sig;
    logic _WB_write_sig;
    logic _WB_mem_access;
    logic _WB_mem_size;
    logic _WB_alu_result;
    logic [63:0] _WB_rs2_value;
    //ECALL wires and registers
    logic [1:0] _WB_ecall;
    logic [63:0] _WB_a0;
    logic [63:0] _WB_a1;
    logic [63:0] _WB_a2;
    logic [63:0] _WB_a3;
    logic [63:0] _WB_a4;
    logic [63:0] _WB_a5;
    logic [63:0] _WB_a6;
    logic [63:0] _WB_a7;

    //cache variables
    logic cache = 1;  //set to 0 to remove the cache, and comment out cache initialization block
    logic IF_cache_bus_reqcyc;
    logic IF_cache_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] IF_cache_bus_req;
    logic [BUS_TAG_WIDTH-1:0] IF_cache_bus_reqtag;
    logic IF_cache_bus_respcyc;
    logic IF_cache_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] IF_cache_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] IF_cache_bus_resptag;

    logic MEM_cache_bus_reqcyc;
    logic MEM_cache_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] MEM_cache_bus_req;
    logic [BUS_TAG_WIDTH-1:0] MEM_cache_bus_reqtag;
    logic MEM_cache_bus_respcyc;
    logic MEM_cache_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] MEM_cache_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] MEM_cache_bus_resptag;

    cache IF_cache_mod (
        //INPUTS
        .clk(clk),// .reset(reset),
        .p_bus_reqcyc(IF_cache_bus_reqcyc), .p_bus_req(IF_cache_bus_req), 
        .p_bus_reqtag(IF_cache_bus_reqtag), .p_bus_respack(IF_cache_bus_respack),
        .m_bus_reqack(IF_arbiter_bus_reqack), .m_bus_respcyc(IF_arbiter_bus_respcyc), 
        .m_bus_resp(IF_arbiter_bus_resp), .m_bus_resptag(IF_arbiter_bus_resptag),

        //OUTPUTS
        .p_bus_reqack(IF_cache_bus_reqack), .p_bus_respcyc(IF_cache_bus_respcyc), 
        .p_bus_resp(IF_cache_bus_resp), .p_bus_resptag(IF_cache_bus_resptag),
        .m_bus_reqcyc(IF_arbiter_bus_reqcyc), .m_bus_req(IF_arbiter_bus_req),
        .m_bus_reqtag(IF_arbiter_bus_reqtag), .m_bus_respack(IF_arbiter_bus_respack)
    );
    cache MEM_cache_mod (
        //INPUTS
        .clk(clk),// .reset(reset),
        .p_bus_reqcyc(MEM_cache_bus_reqcyc), .p_bus_req(MEM_cache_bus_req), 
        .p_bus_reqtag(MEM_cache_bus_reqtag), .p_bus_respack(MEM_cache_bus_respack),
        .m_bus_reqack(MEM_arbiter_bus_reqack), .m_bus_respcyc(MEM_arbiter_bus_respcyc), 
        .m_bus_resp(MEM_arbiter_bus_resp), .m_bus_resptag(MEM_arbiter_bus_resptag),

        //OUTPUTS
        .p_bus_reqack(MEM_cache_bus_reqack), .p_bus_respcyc(MEM_cache_bus_respcyc), 
        .p_bus_resp(MEM_cache_bus_resp), .p_bus_resptag(MEM_cache_bus_resptag),
        .m_bus_reqcyc(MEM_arbiter_bus_reqcyc), .m_bus_req(MEM_arbiter_bus_req),
        .m_bus_reqtag(MEM_arbiter_bus_reqtag), .m_bus_respack(MEM_arbiter_bus_respack)
    );


    //arbiter variables
    logic IF_arbiter_bus_reqcyc;
    logic IF_arbiter_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] IF_arbiter_bus_req;
    logic [BUS_TAG_WIDTH-1:0] IF_arbiter_bus_reqtag;
    logic IF_arbiter_bus_respcyc;
    logic IF_arbiter_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] IF_arbiter_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] IF_arbiter_bus_resptag;
    logic MEM_arbiter_bus_reqcyc;
    logic MEM_arbiter_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] MEM_arbiter_bus_req;
    logic [BUS_TAG_WIDTH-1:0] MEM_arbiter_bus_reqtag;
    logic MEM_arbiter_bus_respcyc;
    logic MEM_arbiter_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] MEM_arbiter_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] MEM_arbiter_bus_resptag;

    arbiter arbiter_mod (
        //INPUTS
        .clk(clk),
        .req0(IF_arbiter_bus_req), .reqcyc0(IF_arbiter_bus_reqcyc), .reqtag0(IF_arbiter_bus_reqtag), 
        .respack0(IF_arbiter_bus_respack),
        .req1(MEM_arbiter_bus_req), .reqcyc1(MEM_arbiter_bus_reqcyc), .reqtag1(MEM_arbiter_bus_reqtag), 
        .respack1(MEM_arbiter_bus_respack),
        .bus_resp(bus_resp), .bus_respcyc(bus_respcyc), .bus_resptag(bus_resptag), .bus_reqack(bus_reqack),
        
        //OUTPUTS
        .resp0(IF_arbiter_bus_resp), .respcyc0(IF_arbiter_bus_respcyc), 
        .resptag0(IF_arbiter_bus_resptag), .reqack0(IF_arbiter_bus_reqack),
        .resp1(MEM_arbiter_bus_resp), .respcyc1(MEM_arbiter_bus_respcyc), 
        .resptag1(MEM_arbiter_bus_resptag), .reqack1(MEM_arbiter_bus_reqack),
        .bus_req(bus_req), .bus_reqcyc(bus_reqcyc), .bus_reqtag(bus_reqtag), .bus_respack(bus_respack)
    );

    
    // FOR FETCHING INSTRUCTIONS
    //OUTPUT
    logic  bus_reqcyc_0; //I need to set to 1 for requesting to read instr
    logic  bus_respack_0; //I acknowledge the response by setting it to 1.
    logic  [BUS_DATA_WIDTH-1:0] bus_req_0;//the address I wanna read
    logic  [BUS_TAG_WIDTH-1:0] bus_reqtag_0; //what you are requesting.
    //INPUT
    logic  bus_respcyc_0; //it should become 1 if it is ready to respond.
    logic  bus_reqack_0;
    logic  [BUS_DATA_WIDTH-1:0] bus_resp_0; //the instruction read.
    logic  [BUS_TAG_WIDTH-1:0] bus_resptag_0;

    // FOR STORING INSTRS (total 16 (each 32 bits))
    logic [31:0] instrlist[15:0];
    logic [31:0] _instrlist[15:0];
    logic [5:0] instr_index;
    logic [5:0] _instr_index;
    
    logic [3:0] DECODE_state;
    logic [3:0] _DECODE_state;
    logic [3:0] READ_state;
    logic [3:0] _READ_state;
    logic [3:0] EXECUTE_state;
    logic [3:0] _EXECUTE_state;
    logic [3:0] MEM_state;
    logic [3:0] _MEM_state;
    logic [3:0] WRITEBACK_state;
    logic [3:0] _WRITEBACK_state;

    always_comb begin
        if(cache == 1) begin
            IF_cache_bus_reqcyc = 0;
            IF_cache_bus_respack = 0;
            IF_cache_bus_req = 64'h0;
            IF_cache_bus_reqtag = 0;
        end
        else begin
            IF_arbiter_bus_reqcyc = 0;
            IF_arbiter_bus_respack = 0;
            IF_arbiter_bus_req = 64'h0;
            IF_arbiter_bus_reqtag = 0;
        end

        //set IF wires (to registers)
        _pc = pc;
        _instr = instr;
        _fetch_count = fetch_count;

        if(firstFETCH) begin
        _index_from_pc = index_from_pc;
        _jumpbit = jumpbit;
        _firstFETCH = 0;
        _cur_pc = cur_pc;
        end

        case(state)
            INIT: begin
                    if(!reset) begin
                        next_state = FETCH;
                    end
                    else begin
                        next_state = INIT;
                    end
                end
            FETCH: begin
                    if(cache == 1) begin
                        IF_cache_bus_reqcyc = 1;
                        IF_cache_bus_req = pc;
                        IF_cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};

                        if(!IF_cache_bus_reqack) begin
                            next_state = FETCH;
                        end               
                        else begin
                            next_state = WAIT;
                        end
                    end
                    else begin
                        IF_arbiter_bus_reqcyc = 1;
                        IF_arbiter_bus_req = pc;
                        IF_arbiter_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};

                        if(!IF_arbiter_bus_reqack) begin
                            next_state = FETCH;
                        end               
                        else begin
                            next_state = WAIT;
                        end
                    end
                end
            WAIT:begin
                    // Getting all 16 instrs (before, we got 2 * 8 times)
                    if(cache == 1) begin
                        if(fetch_count == 16) begin
                            IF_cache_bus_respack = 1;
                            _fetch_count = fetch_count + 1;
                        end
                        else if(fetch_count == 17) begin
                            IF_cache_bus_respack = 1;
                            // For the first instr after fetch.
                            next_state = GETINSTR;
                            _getinstr_ready = 1;
                            _fetch_count = 0;
                        end
                        else if(IF_cache_bus_respcyc == 1) begin
                            _instrlist[fetch_count] = IF_cache_bus_resp[31:0];
                            _instrlist[fetch_count + 1] = IF_cache_bus_resp[63:32];

                            // For next time,
                            if(IF_cache_bus_resp != {instrlist[fetch_count-1],instrlist[fetch_count-2]}) begin// || IF_cache_bus_resp == 0) begin
                                _fetch_count = fetch_count + 2;
                            end
                            else if(IF_cache_bus_resp == 0) begin
                                _fetch_count = fetch_count + 1;
				if(fetch_count == 14) begin
					_fetch_count = fetch_count + 2;
				end
                            end
                            IF_cache_bus_respack = 1;
                            next_state = WAIT;
                        end else begin
                            next_state = WAIT;
                        end
                    end
                    else begin
                        if(fetch_count == 16) begin
                            IF_arbiter_bus_respack = 1;
                            // For the first instr after fetch.
                            next_state = GETINSTR;
                            _getinstr_ready = 1;
                            _fetch_count = 0;
                        end
                        else if(IF_arbiter_bus_respcyc == 1) begin
                            _instrlist[fetch_count] = IF_arbiter_bus_resp[31:0];
                            _instrlist[fetch_count + 1] = IF_arbiter_bus_resp[63:32];

                            // For next time,
                            if(IF_arbiter_bus_resp != {instrlist[fetch_count-1],instrlist[fetch_count-2]} || IF_arbiter_bus_resp == 0) begin
                                _fetch_count = fetch_count + 2;
                            end
                            IF_arbiter_bus_respack = 1;
                            next_state = WAIT;
                        end else begin
                            next_state = WAIT;
                        end
                    end
                 end
            GETINSTR: begin
                    // After fetch, instr_index = 0
                    if(getinstr_ready == 1) begin
                        if(cache == 1) begin
                            IF_cache_bus_respack = 1;
                        end
                        else begin
                        IF_arbiter_bus_respack = 1;
                        end
                        //no more stall (from fetching)
                        _instr_before_fetch = 0;
                        //set this bit to 0 until fetch again.
                        _getinstr_ready = 0;
                        _stallstate = 0;
                        _nop_state = 0;
                        if(jumpbit) begin
                            _jumpbit = 0;
                            _jump_to_addr = 0;
                            _index_from_pc = 0;
                            _instr_index = index_from_pc;
                            _cur_pc = index_from_pc*4 + pc;
                        end else begin
                            _instr_index = 0;
                            _cur_pc = pc;
                        end
                        _instr = instrlist[_instr_index];
                        next_state = GETINSTR;
                        
                        if(_instr == 32'b0) begin
                            _last_instr = {1'b0,instr};
                            next_state = IDLE;
                        end
/*                        if(_instr == 32'h00008067) begin
                            _last_instr = {1'b0, _instr};
                            next_state = IDLE;
                        end
*/
                        for (int i = 0; i < 32; i++) begin
                            _writinglist[i] = 0;
                        end
                    end
                    // instr_index = 1,2,... 
                    else begin
			_instr_index = instr_index + 1;
                        if(_instr_index >= 16) begin
                            //Stall and go fetch more.
                            next_state = FETCH;
                            _pc = pc + 64;
                            _instr_before_fetch = _instr;
                            _instr = 0;
                            _instr_index = 0;
                        end else begin

                            _instr = instrlist[_instr_index];
                            _cur_pc = cur_pc + 4;
                            next_state = GETINSTR;
                            if(_instr == 32'b0) begin
                                _last_instr = {1'b0,instr}; //this is the instr before this.
                                next_state = IDLE;
                            end
/*                          
                            if(_instr == 32'h00008067) begin
                                _last_instr = {1'b0, _instr};
                                next_state = IDLE;
                            end
*/                        end
                    end
                    //Start decode.
                    _DECODE_state = DECODE;
                end
            JUMP: if(jumpbit) begin
                      _pc = jump_to_addr - jump_to_addr%64; //align by 64.
                      next_state = FETCH;
                      _jumpNOW = 0;
                      _WRITEBACK_state = 0;
                  end
            IDLE: if(last_instr[32] == 1) begin
                      $finish;
                  end
        endcase
    end

    always_comb begin
       // _MEM_status = MEM_status;
        MEM_next_ptr = MEM_ptr;
        _MEM_value = MEM_value;
        _MEM_str_value = MEM_str_value;

        if(cache == 1) begin
            MEM_cache_bus_reqcyc = 0;
            MEM_cache_bus_respack = 0;
            MEM_cache_bus_req = 64'h0;
            MEM_cache_bus_reqtag = 0;
        end
        else begin
            MEM_arbiter_bus_reqcyc = 0;
            MEM_arbiter_bus_respack = 0;
            MEM_arbiter_bus_req = 64'h0;
            MEM_arbiter_bus_reqtag = 0;
        end
        if(DECODE_state == DECODE) begin
            _ID_instr = instr;
            _ID_pc = cur_pc;
            _READ_state = READ;
        end
        if(READ_state == READ) begin

            _RD_immediate = ID_immediate;
            _RD_alu_op = ID_alu_op;
            _RD_shamt = ID_shamt;
            _RD_write_sig = ID_write_sig;
            _RD_write_reg = ID_rd;
            _RD_instr_type = ID_instr_type;
            _RD_instr = ID_instr;
            _RD_mem_access = ID_mem_access;
            _RD_mem_size = ID_mem_size;
           
            _RD_rs1 = ID_rs1;
            _RD_rs2 = ID_rs2;
            _RD_isBranch = ID_isBranch;
            _RD_pc = ID_pc;
            _EXECUTE_state = EXECUTE;

            //If it's not the current instr that's writing to it, for rs1 or rs2, stall.
            if(writinglist[ID_rs1][32] && writinglist[ID_rs1][31:0] != ID_instr) begin
                _stall_instr = ID_instr;
                _stallstate = READ;
            end else if (writinglist[ID_rs2][32] && writinglist[ID_rs2][31:0] != ID_instr) begin
                _stall_instr = ID_instr;
                _stallstate = READ;
            end
            //Otherwise, (not stalling)
            else begin
                //set write reg in writinglist.
                if(ID_write_sig && ID_rd != 0) begin
                    _writinglist[ID_rd] = {1'b1,ID_instr};
                end
                //If both registers are free to go, then no more stalling.
                //This checks if this stage initiated the stall.
                if(stall_instr == ID_instr && stall_instr != 0) begin
                    _stallstate = 0;
                    _stall_instr = 0;
                end
            end

        end
        if(EXECUTE_state == EXECUTE) begin
            //Passing these as registers to WB.
            _EX_write_sig = RD_write_sig; 
            _EX_write_reg = RD_write_reg;
            _EX_instr = RD_instr;
            _EX_mem_access = RD_mem_access;
            _EX_mem_size = RD_mem_size;
            _EX_isBranch = RD_isBranch;
            _EX_immediate = RD_immediate;
            _EX_pc = RD_pc;

            _EX_ecall = RD_ecall;
            _EX_a0 = RD_a0;
            _EX_a1 = RD_a1;
            _EX_a2 = RD_a2;
            _EX_a3 = RD_a3;
            _EX_a4 = RD_a4;
            _EX_a5 = RD_a5;
            _EX_a6 = RD_a6;
            _EX_a7 = RD_a7;

            //To get more instructions.
            _MEM_state = MEM; 


            if(stall_instr == _EX_instr && stallstate < EXECUTE && stall_instr != 0) begin
                _stallstate = EXECUTE;
            end
        end
        if(MEM_state == MEM) begin

  
            if(EX_isBranch == `COND) begin
                //conditional branches.
                if(EX_alu_result) begin
                    _jumpbit = 1;  
                    _jump_to_addr = EX_immediate;
                    _index_from_pc = (EX_immediate % 64)/4;
                    _instr_before_fetch = EX_instr;
                    _nop_state = READ;
                    // Should jump after WB... to store the addr to $rd.
                end else begin
                    // Not branching.
                end
            end else if(EX_isBranch == `UNCOND) begin
                //Unconditional branch.
                _jumpbit = 1;
                _jump_to_addr = EX_alu_result;
                _index_from_pc = (EX_alu_result % 64)/4;
                // Should jump after WB... to store the addr to $rd.
                _instr_before_fetch = EX_instr;
                _nop_state = READ;
                _MEM_value = EX_pc + 4;

            end else begin
                _MEM_value = EX_alu_result;
            end 

            //Passing these as registers to WB.
            _MEM_alu_result = EX_alu_result;
            _MEM_write_reg = EX_write_reg;
            _MEM_write_sig = EX_write_sig;
            _MEM_access = EX_mem_access;
            _MEM_instr = EX_instr;
            _MEM_size = EX_mem_size;
            _MEM_rs2_val = EX_rs2_val;
            _MEM_isBranch = EX_isBranch;
            _MEM_pc = EX_pc;
            _MEM_ecall = EX_ecall;
            _MEM_a0 = EX_a0;
            _MEM_a1 = EX_a1;
            _MEM_a2 = EX_a2;
            _MEM_a3 = EX_a3;
            _MEM_a4 = EX_a4;
            _MEM_a5 = EX_a5;
            _MEM_a6 = EX_a6;
            _MEM_a7 = EX_a7;

            //read from memory if store or load, go immediately to writeback otherwise
            if(_MEM_access != `MEM_NO_ACCESS) begin
                case(MEM_status)
                    0: begin  //make request to memory to read
                            if(cache == 1) begin 
                                MEM_cache_bus_reqcyc = 1;
                                MEM_cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                MEM_cache_bus_req = _MEM_alu_result - (_MEM_alu_result % 512); //TODO: find and floor requested address
                                if(MEM_cache_bus_reqack == 1) begin
                                    _MEM_status = 1;
                                    _MEM_read_value = 0;
                                    MEM_next_ptr = 0;
                                end
                            end
                            else begin
                                MEM_arbiter_bus_reqcyc = 1;
                                MEM_arbiter_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                MEM_arbiter_bus_req = _MEM_alu_result - (_MEM_alu_result % 512); //TODO: find and floor requested address
                                if(MEM_arbiter_bus_reqack == 1) begin
                                    _MEM_status = 1;
                                    _MEM_read_value = 0;
                                    MEM_next_ptr = 0;
                                end
                            end
                        end
                    1: begin  //receive response
                            if(cache == 1) begin
                                if(MEM_cache_bus_respcyc == 1) begin
                                    _MEM_read_value[64*MEM_ptr +: 63] = MEM_cache_bus_resp;
                                    MEM_cache_bus_respack = 1;
                                    MEM_next_ptr = MEM_ptr + 1;
                                    if(MEM_ptr == 7) begin
                                        MEM_next_ptr = _MEM_alu_result % 512;
                                        _MEM_status = 2;
                                    end
                                end
                            end
                            else begin
                                if(MEM_arbiter_bus_respcyc == 1) begin
                                    _MEM_read_value[64*MEM_ptr +: 63] = MEM_arbiter_bus_resp;
                                    MEM_arbiter_bus_respack = 1;
                                    MEM_next_ptr = MEM_ptr + 1;
                                    if(MEM_ptr == 7) begin
                                        MEM_next_ptr = _MEM_alu_result % 512;
                                        _MEM_status = 2;
                                    end
                                end
                            end
                        end
                    2: begin  //manipulate read value accordingly and send request to write if needed
                            if(_MEM_access == `MEM_READ) begin //load
                                //Tload value from MEM_read_value to _MEM_value
                                case(_MEM_size)
                                        `MEM_BYTE: _MEM_str_value = {{56{MEM_read_value[MEM_ptr + 7]}}, MEM_read_value[MEM_ptr +: 8]};
                                        `MEM_HALF: _MEM_str_value = {{48{MEM_read_value[MEM_ptr + 15]}}, MEM_read_value[MEM_ptr +: 16]};
                                        `MEM_WORD: _MEM_str_value = {{32{MEM_read_value[MEM_ptr + 31]}}, MEM_read_value[MEM_ptr +: 32]};
                                        `MEM_DOUBLE: _MEM_str_value = {MEM_read_value[MEM_ptr +: 64]};
                                        `MEM_US_BYTE: _MEM_str_value = {56'b0, MEM_read_value[MEM_ptr +: 8]};
                                        `MEM_US_HALF: _MEM_str_value = {48'b0, MEM_read_value[MEM_ptr +: 16]};
                                        `MEM_US_WORD: _MEM_str_value = {32'b0, MEM_read_value[MEM_ptr +: 32]};
                                endcase
                                MEM_next_ptr = 0;
                                _MEM_status = 4; 
                            end
                            else if(_MEM_access == `MEM_WRITE) begin //store
                                _MEM_str_value = MEM_value;
                                //modify _MEM_read_value using _MEM_alu_result
                                case(_MEM_size)
                                    `MEM_BYTE: _MEM_read_value[MEM_ptr +: 8] = _MEM_rs2_val[7:0];
                                    `MEM_HALF: _MEM_read_value[MEM_ptr +: 16] = _MEM_rs2_val[15:0];
                                    `MEM_WORD: _MEM_read_value[MEM_ptr +: 32] = _MEM_rs2_val[31:0];
                                    `MEM_DOUBLE: _MEM_read_value[MEM_ptr +: 64] = _MEM_rs2_val;
                                endcase
                                //request to write to memory
                                if(cache == 1) begin
                                    MEM_cache_bus_reqcyc = 1;
                                    MEM_cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                    MEM_cache_bus_req = 64'h0; //TODO: find and floor requested address
                                    _MEM_status = 3;
                                end
                                else begin
                                    MEM_arbiter_bus_reqcyc = 1;
                                    MEM_arbiter_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                    MEM_arbiter_bus_req = 64'h0; //TODO: find and floor requested address
                                    _MEM_status = 3;
                                end
                            end
                        end
                    3: begin //write to memory
                            if(cache == 1) begin
                                if(MEM_cache_bus_reqack == 1) begin
                                    MEM_cache_bus_reqcyc = 1;
                                    MEM_cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                    MEM_cache_bus_req = MEM_read_value[64*MEM_ptr +: 63];
                                    MEM_next_ptr = MEM_ptr + 1;
                                    if(MEM_ptr == 7) begin
                                        MEM_next_ptr = 0;
                                        _MEM_status = 4; 
                                    end
                                end
                            end
                            else begin
                                if(MEM_arbiter_bus_reqack == 1) begin
                                    MEM_arbiter_bus_reqcyc = 1;
                                    MEM_arbiter_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                    MEM_arbiter_bus_req = MEM_read_value[64*MEM_ptr +: 63];
                                    MEM_next_ptr = MEM_ptr + 1;
                                    if(MEM_ptr == 7) begin
                                        MEM_next_ptr = 0;
                                        _MEM_status = 4;
                                    end
                                end
                            end
                        end
		   4: begin
                        //Can go on to the next stage NOW.
                            _MEM_value = _MEM_str_value;
                        end
                endcase
            end
            else begin
                _WRITEBACK_state = WRITEBACK;

            end

            if(_MEM_access != `MEM_NO_ACCESS && _MEM_status != 4) begin
                _stallstate = MEM;
                _stall_instr = EX_instr;
            end

            if(_MEM_access != `MEM_NO_ACCESS && MEM_status == 4)begin
                if(stall_instr == EX_instr && stall_instr != 0) begin
                    _stallstate = 0;
                    _stall_instr = 0;
                end
                
                _MEM_status = 0;
            end

            if(_MEM_ecall == 1) begin
                _MEM_write_reg = 10;
                do_ecall(_MEM_a7, _MEM_a0, _MEM_a1, _MEM_a2, _MEM_a3, _MEM_a4, _MEM_a5, _MEM_a6, _MEM_a0);
                _MEM_write_sig = 1;
            end

            if(stall_instr == _MEM_instr && stallstate < MEM && stall_instr != 0) begin
                _stallstate = MEM;
            end
        end
        if(WRITEBACK_state == WRITEBACK) begin
            //To write back to the register file.
            //There should be write signal.
            _WB_instr = MEM_instr;
            _WB_write_reg = MEM_write_reg;
            _WB_write_val = MEM_value;
            _WB_write_sig = MEM_write_sig;
            _WB_ecall = MEM_ecall;
            _WB_mem_access = MEM_access;
            _WB_mem_size = MEM_size;
            _WB_rs2_value = MEM_rs2_val;
            _WB_a0 = MEM_a0;
            _WB_a1 = MEM_a1;
            _WB_a2 = MEM_a2;
            _WB_a3 = MEM_a3;
            _WB_a4 = MEM_a4;
            _WB_a5 = MEM_a5;
            _WB_a6 = MEM_a6;
            _WB_a7 = MEM_a7;

            if(_WB_ecall == 1) begin
                _nop_state = WRITEBACK;
            end

            if(_WB_mem_access == `MEM_READ) begin
                do_pending_write(_WB_write_val, _WB_rs2_value, _WB_mem_size);
            end

            if((stall_instr == _WB_instr) && (stallstate < WRITEBACK) && stall_instr != 0) begin
                _stallstate = WRITEBACK;
            end
            
            //This is for Stall...
            //If WB wrote to the reg, then clear it on writinglist.
            if(writinglist[MEM_write_reg][32] && (writinglist[MEM_write_reg][31:0] == MEM_instr)) begin
                _writinglist[MEM_write_reg] = {32'b0};
            end

            //This is for detecting the last instr.
            if(MEM_instr == last_instr[31:0])begin
                _last_instr = {1'b1,MEM_instr};
            end

            //This is for jumping
            if(jumpbit && (state > WAIT) && MEM_instr != 0) begin
                _jumpNOW =1;
                //next_state = JUMP;
              //  _nop_state = READ;
            end
            //This is for calling nop after the last write back (before new fetch).
            if(instr_before_fetch == MEM_instr && instr_before_fetch != 0) begin
                _nop_state = WRITEBACK;
            end

             
        end
    end


    // In Decode state
    //instantiate decode modules for each instruction
    decoder instr_decode_mod (
                //TODO: store each instruction's pc address into instr_list, and pull it back out to feed into decode
                //	potential idea: use pc - 8*instr_count to get the address of the instruction
                //INPUTS
                .clk(clk), .instruction(instr), .cur_pc(cur_pc),

                //OUTPUTS
                .rd(_ID_rd), .rs1(_ID_rs1), .rs2(_ID_rs2), 
                .immediate(_ID_immediate),
                .alu_op(_ID_alu_op), .shamt(_ID_shamt), 
                .reg_write(_ID_write_sig), .instr_type(_ID_instr_type), 
                .mem_access(_ID_mem_access), .mem_size(_ID_mem_size),
                .isECALL(_ID_ecall), .isBranch(_ID_isBranch)
    );

    // In READ state and WRITEBACK state
    //instantiate register file module
    reg_file register_mod (
                //INPUTS
                //Used Only From READ Stage.
                .clk(clk), .reset(reset), .sp_val(stackptr),
                .rs1(ID_rs1), .rs2(ID_rs2),  
                //Used Only From WB Stage.
                .write_sig(MEM_write_sig), 
                .write_val(MEM_value), 
                .write_reg(MEM_write_reg),

                //OUTPUTS
                //Used Only From READ Stage.
                .rs1_val(_RD_rs1_val), .rs2_val(_RD_rs2_val),

                //Used when calling ECALL
                .a0(_RD_a0), .a1(_RD_a1), .a2(_RD_a2), .a3(_RD_a3),
                .a4(_RD_a4), .a5(_RD_a5), .a6(_RD_a6), .a7(_RD_a7)
    );

    //In Execute state
    alu alu_mod (
                //INPUTS
                .clk(clk), .opcode(RD_alu_op), .value1(RD_rs1_val),
                .value2(RD_rs2_val), .immediate(RD_immediate), .shamt(RD_shamt), .instr_type(RD_instr_type),

                //OUTPUTS
                .result(_EX_alu_result)
    );



    always_ff @ (posedge clk) begin
        if(reset) begin //when first starting.
            pc <= entry - entry%64;
            index_from_pc <= (entry%64)/4;
            cur_pc <= entry;
            jumpbit <= 1;
            state <= INIT;
            instr <= 64'h0;
            fetch_count <= 0;
            instr_index <= 0;
            MEM_status <= 0;
            MEM_ptr <= 0;
            MEM_read_value <= 0;
            firstFETCH <= 1;
            for (int i = 0; i < 16; i++) begin
                instrlist[i] <= 32'b0;
            end  
        end else begin /////////

        firstFETCH <= _firstFETCH;

        // The only registers written to no matter what.
        stallstate <= _stallstate;
        stall_instr <= _stall_instr;
        instr_before_fetch <= _instr_before_fetch;

        nop_state <= _nop_state;

        if(_nop_state == WRITEBACK) begin 

            for (int i = 0; i < 32; i++) begin
                writinglist[i] <= 0;
            end

        end else begin

            for (int i = 0; i < 32; i++) begin
                writinglist[i] <= _writinglist[i];
            end

        end

        //

        //If it needs to get more instructions.
        //set IF registers
        jumpNOW <= _jumpNOW;


        if(_jumpNOW) begin
            state <= JUMP;
        end else begin
            state <= next_state;
        end
        pc <= _pc;
        fetch_count <= _fetch_count;
        getinstr_ready <= _getinstr_ready;
        last_instr <= _last_instr;

        // The only place the program jumps is from WB.
        jump_to_addr <= _jump_to_addr;
        jumpbit <= _jumpbit;
        index_from_pc <= _index_from_pc;
        
        for (int i = 0; i < 16; i++) begin
            instrlist[i] <= _instrlist[i];
        end

        DECODE_state <= _DECODE_state;
        READ_state <= _READ_state;
        EXECUTE_state <= _EXECUTE_state;
        WRITEBACK_state <= _WRITEBACK_state;
        MEM_state <= _MEM_state;

        // if nop
        if(_nop_state > GETINSTR) begin
            instr <= 0;
        end else begin
        if(_stallstate < GETINSTR) begin
        instr <= _instr;
        instr_index <= _instr_index;
        cur_pc <= _cur_pc;
        end
        end

        if(_nop_state > DECODE) begin
        //set ID registers
        ID_rd <= 0;
        ID_rs1 <= 0;
        ID_rs2 <= 0;
        ID_immediate <= 0;
        ID_alu_op <= 0;
        ID_shamt <= 0;
        ID_write_sig <= 0;
        ID_instr_type <= 0;
        ID_instr <= 0;
        ID_pc <= 0;
        ID_mem_access <= 0;
        ID_mem_size <= 0;
        ID_ecall <= 0;
        ID_isBranch <= 0;
        end else begin
        if(_stallstate < DECODE) begin
        //set ID registers
        ID_rd <= _ID_rd;
        ID_rs1 <= _ID_rs1;
        ID_rs2 <= _ID_rs2;
        ID_immediate <= _ID_immediate;
        ID_alu_op <= _ID_alu_op;
        ID_shamt <= _ID_shamt;
        ID_write_sig <= _ID_write_sig;
        ID_instr_type <= _ID_instr_type;
        ID_instr <= _ID_instr;
        ID_pc <= _ID_pc;
        ID_mem_access <= _ID_mem_access;
        ID_mem_size <= _ID_mem_size;
        ID_ecall <= _ID_ecall;
        ID_isBranch <= _ID_isBranch;
        end
        end

        if(_nop_state > READ) begin
        //set READ registers
        RD_immediate <= 0;
        RD_alu_op <= 0;
        RD_shamt <= 0;
        RD_write_sig <= 0;
        RD_write_reg <= 0;
        RD_instr_type <= 0;
        RD_rs1_val <= 0;
        RD_rs2_val <= 0;
        RD_instr <= 0;
        RD_mem_access <= 0;
        RD_mem_size <= 0;
        RD_pc <= 0;

        RD_rs1 <= 0;
        RD_rs2 <= 0;
        RD_isBranch <= 0;
        RD_ecall <= 0;
        RD_a0 <= 0;
        RD_a1 <= 0;
        RD_a2 <= 0;
        RD_a3 <= 0;
        RD_a4 <= 0;
        RD_a5 <= 0;
        RD_a6 <= 0;
        RD_a7 <= 0;
        end else begin
        if(_stallstate < READ) begin
        //set READ registers
        RD_immediate <= _RD_immediate;
        RD_alu_op <= _RD_alu_op;
        RD_shamt <= _RD_shamt;
        RD_write_sig <= _RD_write_sig;
        RD_write_reg <= _RD_write_reg;
        RD_instr_type <= _RD_instr_type;
        RD_rs1_val <= _RD_rs1_val;
        RD_rs2_val <= _RD_rs2_val;
        RD_instr <= _RD_instr;
        RD_pc <= _RD_pc;
        RD_mem_access <= _RD_mem_access;
        RD_mem_size <= _RD_mem_size;

        RD_rs1 <= _RD_rs1;
        RD_rs2 <= _RD_rs2;
        RD_isBranch <= _RD_isBranch;
        RD_ecall <= _RD_ecall;
        RD_a0 <= _RD_a0;
        RD_a1 <= _RD_a1;
        RD_a2 <= _RD_a2;
        RD_a3 <= _RD_a3;
        RD_a4 <= _RD_a4;
        RD_a5 <= _RD_a5;
        RD_a6 <= _RD_a6;
        RD_a7 <= _RD_a7;
        end
        end

        if(_nop_state > EXECUTE) begin
        //set EX registers
        EX_alu_result <= 0;
        EX_write_reg <= 0;
        EX_write_sig <= 0;
        EX_instr <= 0;
        EX_mem_access <= 0;
        EX_mem_size <= 0;
        EX_rs2_val <= 0;
        EX_isBranch <= 0;
        EX_immediate <= 0;
        EX_ecall <= 0;
        EX_pc <= 0;

        EX_a0 <= 0;
        EX_a1 <= 0;
        EX_a2 <= 0;
        EX_a3 <= 0;
        EX_a4 <= 0;
        EX_a5 <= 0;
        EX_a6 <= 0;
        EX_a7 <= 0;
        end else begin
        if(_stallstate < EXECUTE) begin
        //set EX registers
        EX_alu_result <= _EX_alu_result;
        EX_write_reg <= _EX_write_reg;
        EX_write_sig <= _EX_write_sig;
        EX_instr <= _EX_instr;
        EX_mem_access <= _EX_mem_access;
        EX_mem_size <= _EX_mem_size;
        EX_rs2_val <= _EX_rs2_val;
        EX_isBranch <= _EX_isBranch;
        EX_immediate <= _EX_immediate;
        EX_pc <= _EX_pc;
        EX_ecall <= _EX_ecall;
        EX_a0 <= _EX_a0;
        EX_a1 <= _EX_a1;
        EX_a2 <= _EX_a2;
        EX_a3 <= _EX_a3;
        EX_a4 <= _EX_a4;
        EX_a5 <= _EX_a5;
        EX_a6 <= _EX_a6;
        EX_a7 <= _EX_a7;
        end
        end

        if(_nop_state > MEM) begin
        //set MEM registers
        MEM_write_reg <= 0;
        MEM_value <= 0;
        MEM_str_value <= 0;
        MEM_write_sig <= 0;
        MEM_status <= 0;
        MEM_instr <= 0;
        MEM_ptr <= 0;
        MEM_read_value <= 0;
        MEM_access <= 0;
        MEM_size <= 0;
        MEM_rs2_val <= 0;
        MEM_pc <= 0;

        MEM_isBranch <= 0;
        MEM_ecall <= 0;
        MEM_a0 <= 0;
        MEM_a1 <= 0;
        MEM_a2 <= 0;
        MEM_a3 <= 0;
        MEM_a4 <= 0;
        MEM_a5 <= 0;
        MEM_a6 <= 0;
        MEM_a7 <= 0;
        end else begin
        if(_stallstate < MEM ) begin
        //set MEM registers
        MEM_write_reg <= _MEM_write_reg;
        MEM_value <= _MEM_value;
        MEM_str_value <= _MEM_str_value;
        MEM_write_sig <= _MEM_write_sig;
        MEM_status <= _MEM_status;
        MEM_instr <= _MEM_instr;
        MEM_ptr <= MEM_next_ptr;
        MEM_read_value <= _MEM_read_value;
        MEM_access <= _MEM_access;
        MEM_size <= _MEM_size;
        MEM_rs2_val <= _MEM_rs2_val;
        MEM_pc <= _MEM_pc;
        MEM_isBranch <= _MEM_isBranch;
        MEM_ecall <= _MEM_ecall;
        MEM_a0 <= _MEM_a0;
        MEM_a1 <= _MEM_a1;
        MEM_a2 <= _MEM_a2;
        MEM_a3 <= _MEM_a3;
        MEM_a4 <= _MEM_a4;
        MEM_a5 <= _MEM_a5;
        MEM_a6 <= _MEM_a6;
        MEM_a7 <= _MEM_a7;
        end
        //If stalling because of mem stage ld/st...
        else if(_MEM_access != `MEM_NO_ACCESS && stall_instr == EX_instr && stall_instr != 0) begin
            MEM_status <= _MEM_status;
            MEM_read_value <= _MEM_read_value;
            MEM_ptr <= MEM_next_ptr;
            MEM_str_value <= _MEM_str_value;
        end

        end

        if(_nop_state > WRITEBACK) begin
        //Set WB registers
        WB_instr <= 0;
        WB_write_reg <= 0;
        WB_write_val <= 0;
        WB_write_sig <= 0;
        end else begin
        if(_stallstate < WRITEBACK) begin
            //Set WB registers
            WB_instr <= _WB_instr;
            WB_write_reg <= _WB_write_reg;
            WB_write_val <= _WB_write_val;
            WB_write_sig <= _WB_write_sig;
        end
        end
    
        end
    end

    initial begin
        $display("Initializing top, entry point = 0x%x", entry);
    end

endmodule

