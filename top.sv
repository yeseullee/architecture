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
    logic [63:0] IF_pc;
    logic [63:0] _IF_pc;

    //For stalls
    reg [3:0] read_stallstate;
    reg [3:0] _read_stallstate;
    reg [3:0] jump_stallstate;
    reg [3:0] _jump_stallstate;
    reg [3:0] mem_stallstate;
    reg [3:0] _mem_stallstate;

    //For ecall
    reg [3:0] ecall_stallstate;
    reg [3:0] _ecall_stallstate;
    reg [2:0] ecall_count;
    reg [2:0] _ecall_count;
    logic [63:0] cur_a0;
    logic [63:0] cur_a1;
    logic [63:0] cur_a2;
    logic [63:0] cur_a3;
    logic [63:0] cur_a4;
    logic [63:0] cur_a5;
    logic [63:0] cur_a6;
    logic [63:0] cur_a7;
    logic ecall_now;
    logic ecall_later;
    logic _ecall_later;
    logic pending_write;

    //For jumps
    reg jumpbit; 
    reg _jumpbit;
    reg [31:0] jump_to_addr;
    reg [31:0] _jump_to_addr;
    reg [3:0] index_from_pc;
    reg [3:0] _index_from_pc;

    reg firstFETCH;
    reg _firstFETCH;

    //For Invalidation
    reg invalidate;

    // This is for keeping in track of which register is being written to, for pipelining.
    //The index is the register.
    // [32] = Is written to; [31:0] = The instruction writing. 
    reg [32:0] writinglist[31:0];
    reg [32:0] _writinglist[31:0];

    reg [3:0] state;
    reg [3:0] next_state;
    reg [31:0] IF_instr;
    reg [31:0] _IF_instr;
    reg [4:0] fetch_count;
    reg [4:0] _fetch_count;
    reg getinstr_ready;
    reg _getinstr_ready;
    reg [32:0] last_instr;
    reg [32:0] _last_instr;
    logic IF_valid_instr;
    logic _IF_valid_instr;
    logic IF_stalled;
    logic _IF_stalled;

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
    logic ID_isW;
    logic _ID_isW;
    logic [63:0] ID_pc;
    logic [63:0] _ID_pc;
    //Valid instruction
    logic ID_valid_instr;
    logic _ID_valid_instr;
    logic ID_stalled;

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
    logic RD_isW;
    logic _RD_isW;
    logic [63:0] RD_pc;
    logic [63:0] _RD_pc;
    //ECALL wires and registers
    logic [1:0] RD_ecall;
    logic [1:0] _RD_ecall;
    //Valid instruction
    logic RD_valid_instr;
    logic _RD_valid_instr;
    logic RD_stalled;

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
    //Valid instruction
    logic EX_valid_instr;
    logic _EX_valid_instr;
    logic EX_stalled;

    //MEMORY WIRES & REGISTERS
    logic [63:0] MEM_alu_result;
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
    //memory stage variables
    logic [2:0] MEM_status;
    logic [2:0] _MEM_status;
    logic [8:0] MEM_ptr;
    logic [8:0] MEM_next_ptr;
    logic [511:0] MEM_read_value;
    logic [511:0] _MEM_read_value;
    logic [63:0] MEM_str_value;
    logic [63:0] _MEM_str_value;
    logic [63:0] MEM_index_from_req;
    logic MEM_finished_instr;
    logic _MEM_finished_instr;
    //Valid instruction
    logic MEM_valid_instr;
    logic _MEM_valid_instr;
    logic MEM_stalled;
    


    //WB pass along
    logic [31:0] WB_instr; //For debuggin
    logic [31:0] _WB_instr;
    logic [4:0] WB_write_reg; 
    logic [4:0] _WB_write_reg;
    logic [63:0] WB_write_val;
    logic [63:0] _WB_write_val;
    logic WB_write_sig;
    logic _WB_write_sig;
    logic [1:0] _WB_mem_access;
    logic [4:0] _WB_mem_size;
    logic [63:0] _WB_rs2_value;
    //ECALL wires and registers
    logic [63:0] _WB_address;
    logic [1:0] _WB_ecall;
    logic [63:0] WB_a0;
    logic [63:0] _WB_a0;
    logic [63:0] _WB_a1;
    logic [63:0] _WB_a2;
    logic [63:0] _WB_a3;
    logic [63:0] _WB_a4;
    logic [63:0] _WB_a5;
    logic [63:0] _WB_a6;
    logic [63:0] _WB_a7;
    logic [63:0] WB_pc;
    logic [63:0] _WB_pc;
    //Valid instruction
    logic WB_valid_instr;
    logic _WB_valid_instr;
    logic WB_stalled;


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
    logic [8:0] IF_cache_ptr;
    logic IF_cache_invalidated; // There's no use. just a place-holder.
    logic [BUS_DATA_WIDTH-1:0] IF_cache_inv_req; // There's no use. just a place-holder.

    logic MEM_cache_bus_reqcyc;
    logic MEM_cache_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] MEM_cache_bus_req;
    logic [BUS_TAG_WIDTH-1:0] MEM_cache_bus_reqtag;
    logic MEM_cache_bus_respcyc;
    logic MEM_cache_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] MEM_cache_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] MEM_cache_bus_resptag;
    logic [8:0] MEM_cache_ptr;
    logic MEM_cache_invalidated; // 1 means the cache line has been invalidated upon request.
    logic _MEM_cache_invalidated;
    logic [BUS_DATA_WIDTH-1:0] MEM_cache_inv_req;

    cache IF_cache_mod (
        //INPUTS
        .clk(clk),
        .p_bus_reqcyc(IF_cache_bus_reqcyc), .p_bus_req(IF_cache_bus_req), 
        .p_bus_reqtag(IF_cache_bus_reqtag), .p_bus_respack(IF_cache_bus_respack),
        .m_bus_reqack(IF_arbiter_bus_reqack), .m_bus_respcyc(IF_arbiter_bus_respcyc), 
        .m_bus_resp(IF_arbiter_bus_resp), .m_bus_resptag(IF_arbiter_bus_resptag),
        .mem_ptr(IF_arbiter_ptr), .invalidated(IF_cache_invalidated),

        //OUTPUTS
        .p_bus_reqack(IF_cache_bus_reqack), .p_bus_respcyc(IF_cache_bus_respcyc), 
        .p_bus_resp(IF_cache_bus_resp), .p_bus_resptag(IF_cache_bus_resptag),
        .m_bus_reqcyc(IF_arbiter_bus_reqcyc), .m_bus_req(IF_arbiter_bus_req),
        .m_bus_reqtag(IF_arbiter_bus_reqtag), .m_bus_respack(IF_arbiter_bus_respack),
        .out_ptr(IF_cache_ptr), .inv_req(IF_cache_inv_req)
    );
    cache MEM_cache_mod (
        //INPUTS
        .clk(clk),
        .p_bus_reqcyc(MEM_cache_bus_reqcyc), .p_bus_req(MEM_cache_bus_req), 
        .p_bus_reqtag(MEM_cache_bus_reqtag), .p_bus_respack(MEM_cache_bus_respack),
        .m_bus_reqack(MEM_arbiter_bus_reqack), .m_bus_respcyc(MEM_arbiter_bus_respcyc), 
        .m_bus_resp(MEM_arbiter_bus_resp), .m_bus_resptag(MEM_arbiter_bus_resptag),
        .mem_ptr(MEM_arbiter_ptr), .invalidated(_MEM_cache_invalidated),  

        //OUTPUTS
        .p_bus_reqack(MEM_cache_bus_reqack), .p_bus_respcyc(MEM_cache_bus_respcyc), 
        .p_bus_resp(MEM_cache_bus_resp), .p_bus_resptag(MEM_cache_bus_resptag),
        .m_bus_reqcyc(MEM_arbiter_bus_reqcyc), .m_bus_req(MEM_arbiter_bus_req),
        .m_bus_reqtag(MEM_arbiter_bus_reqtag), .m_bus_respack(MEM_arbiter_bus_respack),
        .out_ptr(MEM_cache_ptr), .inv_req(MEM_cache_inv_req)
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
    logic [8:0] IF_arbiter_ptr;
    logic [8:0] MEM_arbiter_ptr;
    logic _arbiter_ready;
    logic arbiter_ready;

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
        .bus_req(bus_req), .bus_reqcyc(bus_reqcyc), .bus_reqtag(bus_reqtag), .bus_respack(bus_respack),
        .ptr0(IF_arbiter_ptr), .ptr1(MEM_arbiter_ptr), .ready(_arbiter_ready)
    );

    
    // FOR STORING INSTRS (total 16 (each 32 bits))
    logic [31:0] instrlist[15:0];
    logic [31:0] _instrlist[15:0];
    logic [5:0] instr_index;
    logic [5:0] _instr_index;
    
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

        if(firstFETCH) begin
            _index_from_pc = index_from_pc;
            _jumpbit = jumpbit;
            _firstFETCH = 0;
            _IF_pc = IF_pc;
            _IF_instr = IF_instr;
            _pc = pc;
            _fetch_count = fetch_count;
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
                        if(IF_cache_bus_respcyc == 1) begin
                            _instrlist[2*IF_cache_ptr] = IF_cache_bus_resp[31:0];
                            _instrlist[2*IF_cache_ptr + 1] = IF_cache_bus_resp[63:32];
                            IF_cache_bus_respack = 1;
                            next_state = WAIT;
                            if(IF_cache_ptr == 7) begin
                                next_state = GETINSTR;
                                _getinstr_ready = 1;
                            end
                        end else begin
                            next_state = WAIT;
                        end
                    end
                    else begin
                        if(IF_arbiter_bus_respcyc == 1) begin
                            _instrlist[2*IF_arbiter_ptr] = IF_arbiter_bus_resp[31:0];
                            _instrlist[2*IF_arbiter_ptr + 1] = IF_arbiter_bus_resp[63:32];
                            IF_arbiter_bus_respack = 1;
                            next_state = WAIT;
                            if(IF_arbiter_ptr == 7) begin
                                next_state = GETINSTR;
                                _getinstr_ready = 1;
                            end
                        end else begin
                            next_state = WAIT;
                        end
                    end
                 end
            GETINSTR: begin
                    //If it is being stalled, then don't do anything unless there's jumpbit.
                    if(IF_stalled) begin
                        //Acknowledge the resp again.
                        if(getinstr_ready) begin
                            if(cache) begin
                                IF_cache_bus_respack = 1;
                            end else begin
                                IF_arbiter_bus_respack = 1;
                            end
                        end

                        if(jumpbit) begin
                            _pc = jump_to_addr - jump_to_addr%64; //align by 64.
                            next_state = FETCH;

                            //Clear the buffer.
                            for (int i = 0; i < 16; i++) begin
                                _instrlist[i] = 32'b0;
                            end
          
                            _IF_instr = 0;
                            _instr_index = 0;
                            _IF_pc = 0;
                            _IF_valid_instr = 0; // INVALID //

                            // In case getinstr_ready (fetched just before jump)
                            _getinstr_ready = 0;
                           
                            // stop stalling                      
                            _jump_stallstate = 0; 
                        end else begin
                            next_state = GETINSTR;
                        end
                    end

                    // After fetch, first instr
                    else if(getinstr_ready == 1) begin
                        if(cache == 1) begin
                            IF_cache_bus_respack = 1;
                        end
                        else begin
                            IF_arbiter_bus_respack = 1;
                        end
                        
                        //set this bit to 0 until fetch again.
                        _getinstr_ready = 0;
                      
                        if(jumpbit) begin
                            _jumpbit = 0;
                            _jump_to_addr = 0;
                            _index_from_pc = 0;
                            _instr_index = index_from_pc;
                            _IF_pc = index_from_pc*4 + pc;

                            for (int i = 0; i < 32; i++) begin
                                _writinglist[i] = 0;
                            end
                        end else begin
                            //If not jumping then it should be fetching new instr. so index = 0.
                            _instr_index = 0;
                            _IF_pc = pc;
                        end
                        _IF_instr = instrlist[_instr_index];
                        _IF_valid_instr = 1; // VALID //
                        next_state = GETINSTR;

                        
                        // The last instruction
                        if(_IF_instr == 32'b0) begin
                            _last_instr = {1'b0,IF_instr};
                            _IF_valid_instr = 0; // INVALID //
                            next_state = IDLE;
                        end
                    end
                    // instr_index = 1,2,... 
                    else begin
                        _instr_index = instr_index + 1;
                        
                        if(_instr_index >= 16) begin
                            //Stall and go fetch more.
                            next_state = FETCH;
                            _pc = pc + 64;
                            _IF_instr = 0;
                            _instr_index = 0;
                            _IF_valid_instr = 0; // INVALID //
                              
                        end else begin

                            _IF_instr = instrlist[_instr_index];
                            _IF_valid_instr = 1; // VALID //
                            _IF_pc = IF_pc + 4;
                            next_state = GETINSTR;

                            // The last instruction
                            if(_IF_instr == 32'b0) begin
                                _last_instr = {1'b0,IF_instr}; //this is the instr before this.
                                next_state = IDLE;
                                _IF_valid_instr = 0; // INVALID //
                            end
                        end
                    end
                end
            IDLE: if(last_instr[32] == 1) begin
                      $finish;
                  end
        endcase
    end

    always_comb begin
	
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

        invalidate = 0;
        if(bus_respcyc == 1 && bus_resptag == 12'h800) begin
            invalidate = 1;
        end

        // Decode Stage.

        // If not in stall, get from IF_valid_instr. Else, don't get.
        if(!ID_stalled) begin
            _ID_valid_instr = IF_valid_instr; // For the next instruction.

            if(_ID_valid_instr) begin
                _ID_instr = IF_instr;
                _ID_pc = IF_pc;
    
                if(_ID_isBranch == `COND || _ID_isBranch == `UNCOND) begin
                    //stall here.
                    _jump_stallstate = GETINSTR;
                end
                if(_ID_ecall == 1) begin
                    _ecall_stallstate = GETINSTR;
                end
            end
        end

        // Read Stage.

        // If in stall, you still need to look at the writinglist...
        // If not in stall, do everything and get from ID_valid_instr.

        if(!RD_stalled) begin
            _RD_valid_instr = ID_valid_instr;
        end

        _RD_immediate = ID_immediate;
        _RD_alu_op = ID_alu_op;
        _RD_shamt = ID_shamt;
        _RD_write_sig = ID_write_sig;
        _RD_write_reg = ID_rd;
        _RD_instr_type = ID_instr_type;
        _RD_instr = ID_instr;
        _RD_mem_access = ID_mem_access;
        _RD_mem_size = ID_mem_size;
          
        _RD_ecall = ID_ecall; 
        _RD_rs1 = ID_rs1;
        _RD_rs2 = ID_rs2;
        _RD_isBranch = ID_isBranch;
        _RD_isW = ID_isW;
        _RD_pc = ID_pc;

        //If it's not the current instr that's writing to it, for rs1 or rs2, stall.
        if(writinglist[ID_rs1][32] && writinglist[ID_rs1][31:0] != ID_instr) begin
            _read_stallstate = READ;
        end else if (writinglist[ID_rs2][32] && writinglist[ID_rs2][31:0] != ID_instr) begin
            _read_stallstate = READ;
        end
        //Otherwise, (not stalling)
        else begin
            //set write reg in writinglist.
            if(ID_write_sig && ID_rd != 0) begin
                _writinglist[ID_rd] = {1'b1,ID_instr};
            end
            //If both registers are free to go, then no more stalling.
            //This checks if this stage initiated the stall.
            _read_stallstate = 0;
        end

        // EXECUTE 

        //Always set the valid signal to whatever is passed from RD.

        if(!EX_stalled) begin
            _EX_valid_instr = RD_valid_instr;
        end
        //Passing these as registers to WB.
        _EX_write_sig = RD_write_sig; 
        _EX_write_reg = RD_write_reg;
        _EX_instr = RD_instr;
        _EX_mem_access = RD_mem_access;
        _EX_mem_size = RD_mem_size;
        _EX_isBranch = RD_isBranch;
        _EX_immediate = RD_immediate;
        _EX_rs2_val = RD_rs2_val;
        _EX_pc = RD_pc;

        _EX_ecall = RD_ecall;

    
        // MEM stage.
       
        if(!MEM_stalled) begin
            _MEM_valid_instr = EX_valid_instr;
        end
 
        // If it is a valid instruction passed from EX or stalling, execute this stage.
        if(MEM_stalled || _MEM_valid_instr) begin
            if(EX_isBranch == `COND) begin
                //conditional branches.
                if(EX_alu_result) begin
                    _jumpbit = 1;  
                    _jump_to_addr = EX_immediate;
                    _index_from_pc = (EX_immediate % 64)/4;
                    //Clear the buffer - Done in GETINSTR.
                end else begin
                    // Not branching.
                    _jump_stallstate = 0;
                end
            end else if(EX_isBranch == `UNCOND) begin
                //Unconditional branch.
                _jumpbit = 1;
                _jump_to_addr = EX_alu_result;
                _index_from_pc = (EX_alu_result % 64)/4;
                // Should jump after WB... to store the addr to $rd.
                _MEM_value = EX_pc + 4;
            end else begin
                _MEM_value = EX_alu_result;
            end

            //Passing these as registers to WB.
            _MEM_alu_result = EX_alu_result;
            _MEM_write_reg = EX_write_reg;
            _MEM_write_sig = EX_write_sig;
            _MEM_instr = EX_instr;
            _MEM_size = EX_mem_size;
            _MEM_rs2_val = EX_rs2_val;
            _MEM_isBranch = EX_isBranch;
            _MEM_access = EX_mem_access;
            _MEM_pc = EX_pc;
            _MEM_ecall = EX_ecall;

            if(MEM_finished_instr) begin
                //MEM_status == 0 from status 4.
                _mem_stallstate = 0;
                _MEM_finished_instr = 0;
                _MEM_value = MEM_str_value;
            end

            else if(_MEM_access != `MEM_NO_ACCESS) begin

                _mem_stallstate = MEM;

                case(MEM_status)
                    0: begin  //make request to memory to read
                            if(cache == 1) begin 
                                MEM_cache_bus_reqcyc = 1;
                                MEM_cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                MEM_cache_bus_req = _MEM_alu_result - (_MEM_alu_result % 64); 
                                if(MEM_cache_bus_reqack == 1) begin
                                    _MEM_status = 1;
                                    _MEM_read_value = 0;
                                    MEM_next_ptr = 0;
                                    MEM_index_from_req = _MEM_alu_result - MEM_cache_bus_req;
                                end
                            end
                            else begin
                                MEM_arbiter_bus_reqcyc = 1;
                                MEM_arbiter_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                                MEM_arbiter_bus_req = _MEM_alu_result - (_MEM_alu_result % 64); 
                                if(MEM_arbiter_bus_reqack == 1) begin
                                    _MEM_status = 1;
                                    _MEM_read_value = 0;
                                    MEM_next_ptr = 0;
                                    MEM_index_from_req = _MEM_alu_result - MEM_arbiter_bus_req;
                                end
                            end
                            
                        end
                    1: begin  //receive response
                            if(cache == 1) begin
                                if(MEM_cache_bus_respcyc == 1) begin
                                    _MEM_read_value[64*MEM_cache_ptr +: 64] = MEM_cache_bus_resp;
                                    MEM_cache_bus_respack = 1;
                                    if(MEM_cache_ptr == 7) begin
                                        _MEM_status = 2;
                                    end
                                end
                            end
                            else begin
                                if(MEM_arbiter_bus_respcyc == 1) begin
                                    _MEM_read_value[64*MEM_arbiter_ptr +: 64] = MEM_arbiter_bus_resp;
                                    MEM_arbiter_bus_respack = 1;
                                    if(MEM_arbiter_ptr == 7) begin
                                        _MEM_status = 2;
                                    end
                                end
                            end
                        end
                    2: begin  //manipulate read value accordingly and send request to write if needed
                            if(cache==1) begin
                                MEM_cache_bus_respack = 1;
                            end else begin
                                MEM_arbiter_bus_respack = 1;
                            end

                            if(_MEM_access == `MEM_READ) begin //load
                                //Load value from MEM_read_value to _MEM_value
                                case(_MEM_size) 
                                        `MEM_BYTE: _MEM_str_value = {{56{MEM_read_value[8*MEM_index_from_req + 8 - 1]}}, 
									MEM_read_value[8*MEM_index_from_req +: 8]};
                                        `MEM_HALF: _MEM_str_value = {{48{MEM_read_value[8*MEM_index_from_req + 16 - 1]}}, 
									MEM_read_value[8*MEM_index_from_req +: 16]};
                                        `MEM_WORD: _MEM_str_value = {{32{MEM_read_value[8*MEM_index_from_req + 32 - 1]}}, 
									MEM_read_value[8*MEM_index_from_req +: 32]};
                                        `MEM_DOUBLE: _MEM_str_value = {MEM_read_value[8*MEM_index_from_req +: 64]};
                                        `MEM_US_BYTE: _MEM_str_value = {56'b0, MEM_read_value[8*MEM_index_from_req +: 8]};
                                        `MEM_US_HALF: _MEM_str_value = {48'b0, MEM_read_value[8*MEM_index_from_req +: 16]};
                                        `MEM_US_WORD: _MEM_str_value = {32'b0, MEM_read_value[8*MEM_index_from_req +: 32]};
                                endcase
                                
                                MEM_next_ptr = 0;
                                _MEM_status = 4; 
                            end
                            else if(_MEM_access == `MEM_WRITE) begin //store
                                //modify _MEM_read_value using _MEM_rs2_val
                                case(_MEM_size)
                                    `MEM_BYTE: begin
                                        _MEM_read_value[8*MEM_index_from_req +: 8] = _MEM_rs2_val[7:0];
                                        _MEM_str_value = _MEM_rs2_val[7:0];
                                    end
                                    `MEM_HALF: begin
                                        _MEM_read_value[8*MEM_index_from_req +: 16] = _MEM_rs2_val[15:0];
                                        _MEM_str_value = _MEM_rs2_val[15:0];
                                    end
                                    `MEM_WORD: begin
                                        _MEM_read_value[8*MEM_index_from_req +: 32] = _MEM_rs2_val[31:0];
                                        _MEM_str_value = _MEM_rs2_val[31:0];
                                    end
                                    `MEM_DOUBLE: begin
                                        _MEM_read_value[8*MEM_index_from_req +: 64] = _MEM_rs2_val;
                                        _MEM_str_value = _MEM_rs2_val;
                                    end
                                endcase
                                //request to write to memory
                                if(cache == 1) begin
                                    MEM_cache_bus_reqcyc = 1;
                                    MEM_cache_bus_reqtag = {1'b0,`SYSBUS_MEMORY,8'b0};
                                    MEM_cache_bus_req = _MEM_alu_result - (_MEM_alu_result%64);
                                    if(MEM_cache_bus_reqack == 1) begin
                                        _MEM_status = 3;
                                        MEM_next_ptr = 0;
                                    end
                                    else begin
                                        _MEM_status = 2;
                                    end
                                end
                                else begin
                                    MEM_arbiter_bus_reqcyc = 1;
                                    MEM_arbiter_bus_reqtag = {1'b0,`SYSBUS_MEMORY,8'b0};
                                    MEM_arbiter_bus_req = _MEM_alu_result - (_MEM_alu_result%64);
                                    if(MEM_arbiter_bus_reqack == 1) begin
                                        _MEM_status = 3;
                                        MEM_next_ptr = 0;
                                    end
                                    else begin
                                        _MEM_status = 2;
                                    end
                                end
                            end
                        end
                    3: begin //write to memory
                            if(cache == 1) begin
                                MEM_cache_bus_reqcyc = 1;
                                MEM_cache_bus_reqtag = {1'b0,`SYSBUS_MEMORY,8'b0};
                                MEM_cache_bus_req = MEM_read_value[64*MEM_ptr +: 64];
                                if(MEM_cache_bus_reqack == 1) begin
                                    MEM_next_ptr = MEM_ptr + 1;
                                    if(MEM_ptr == 7) begin
                                        MEM_next_ptr = 0;
                                        _MEM_status = 4; 
                                    end
                                end
                            end
                            else begin
                                MEM_arbiter_bus_reqcyc = 1;
                                MEM_arbiter_bus_reqtag = {1'b0,`SYSBUS_MEMORY,8'b0};
                                MEM_arbiter_bus_req = MEM_read_value[64*MEM_ptr +: 64];
                                if(MEM_arbiter_bus_reqack == 1) begin
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
                            _MEM_value = MEM_str_value;
                            _MEM_read_value = -1;
                            MEM_next_ptr = 0;
                            _MEM_status = 0;
                            _MEM_finished_instr = 1;
                            MEM_index_from_req = 0;
                        end
                endcase
            end
            else begin

                _mem_stallstate = 0;
            end

        end

        // WRITE BACK STAGE.
        _WB_valid_instr = MEM_valid_instr;
 	ecall_now = 0;
        pending_write = 0;
        MEM_cache_inv_req = 0;
        // NOTE: There shouldn't be any stall on WB. 
  
        if(ecall_later) begin
            // Only when arbiter is ready (because invalidation request might come)
    	    if(arbiter_ready) begin
	        ecall_now = 1;
	        _ecall_later = 0;
                _ecall_count = 4;
            end
        end
        else if(ecall_count > 0) begin
	    //arbiter now free and DRAM can receive respack.
            if(bus_resptag == 12'h800 && bus_respcyc) begin
	        
		if(cache) begin
                    MEM_cache_inv_req = bus_resp;
                    if(MEM_cache_invalidated) begin
		        bus_respack = 1; 
                    end
                end else begin
                    bus_respack = 1;
                end

            end 
            else begin 
	        _ecall_count = ecall_count - 1;

                if(_ecall_count == 0) begin
                    _ecall_stallstate = 0;
                end
            end
    
            _WB_write_reg = 10;
            _WB_write_val = WB_a0;
            _WB_write_sig = 1;

        end
        // Else if the instr is not valid
        else if(!_WB_valid_instr) begin
            _WB_write_sig = 0;
        end
        // If it is a valid instruction passed from MEM, execute this stage.
        else begin

            //To write back to the register file.
            //There should be write signal.
            _WB_instr = MEM_instr;
            _WB_write_reg = MEM_write_reg;
            _WB_write_val = MEM_value;
            _WB_write_sig = MEM_write_sig;
            _WB_ecall = MEM_ecall;
            _WB_mem_access = MEM_access;
            _WB_rs2_value = MEM_rs2_val;
            _WB_address = MEM_alu_result;
            _WB_pc = MEM_pc;
            _WB_a0 = cur_a0;
            _WB_a1 = cur_a1;
            _WB_a2 = cur_a2;
            _WB_a3 = cur_a3;
            _WB_a4 = cur_a4;
            _WB_a5 = cur_a5;
            _WB_a6 = cur_a6;
            _WB_a7 = cur_a7;

            case(MEM_size)
                // _WB_mem_size should be in terms of bytes.
                `MEM_BYTE: _WB_mem_size = 1;
                `MEM_US_BYTE: _WB_mem_size = 1;
                `MEM_HALF: _WB_mem_size = 2;
                `MEM_US_HALF: _WB_mem_size = 2;
                `MEM_WORD: _WB_mem_size = 4;
                `MEM_US_WORD: _WB_mem_size = 4;
                `MEM_DOUBLE: _WB_mem_size = 8;
                default: _WB_mem_size = 0;
            endcase

            //This is for Stall...
            //If WB wrote to the reg, then clear it on writinglist.
            if(writinglist[MEM_write_reg][32] && (writinglist[MEM_write_reg][31:0] == MEM_instr)) begin
                _writinglist[MEM_write_reg] = {32'b0};
            end

            if(_WB_ecall) begin
		if(arbiter_ready) begin
	        	ecall_now = 1;
                        _ecall_count = 4;
		end else begin
			_ecall_later = 1;
		end
            end

            if(_WB_mem_access == `MEM_WRITE) begin
                pending_write = 1;
            end

            //This is for detecting the last instr.
            if(MEM_instr == last_instr[31:0])begin
                _last_instr = {1'b1,MEM_instr};
            end

	    //$display("%h",WB_pc);
            //if(jumpbit) $display("jump to %h", jump_to_addr);

        end

    end


    // In Decode state
    //instantiate decode modules for each instruction
    decoder instr_decode_mod (
                //INPUTS
                .clk(clk), .instruction(IF_instr), .cur_pc(IF_pc),

                //OUTPUTS
                .rd(_ID_rd), .rs1(_ID_rs1), .rs2(_ID_rs2), 
                .immediate(_ID_immediate),
                .alu_op(_ID_alu_op), .shamt(_ID_shamt), 
                .reg_write(_ID_write_sig), .instr_type(_ID_instr_type), 
                .mem_access(_ID_mem_access), .mem_size(_ID_mem_size),
                .isECALL(_ID_ecall), .isBranch(_ID_isBranch), .isW(_ID_isW)
    );

    // In READ state and WRITEBACK state
    //instantiate register file module
    reg_file register_mod (
                //INPUTS
                //Used Only From READ Stage.
                .clk(clk), .reset(reset), .sp_val(stackptr),
                .rs1(ID_rs1), .rs2(ID_rs2),  
                //Used Only From WB Stage.
                .write_sig(_WB_write_sig), 
                .write_val(_WB_write_val), 
                .write_reg(_WB_write_reg),

                //OUTPUTS
                //Used Only From READ Stage.
                .rs1_val(_RD_rs1_val), .rs2_val(_RD_rs2_val),

                //Used when calling ECALL
                .a0(cur_a0), .a1(cur_a1), .a2(cur_a2), .a3(cur_a3),
                .a4(cur_a4), .a5(cur_a5), .a6(cur_a6), .a7(cur_a7)
    );

    //In Execute state
    alu alu_mod (
                //INPUTS
                .clk(clk), .opcode(RD_alu_op), .value1(RD_rs1_val),
                .value2(RD_rs2_val), .immediate(RD_immediate), .shamt(RD_shamt), .instr_type(RD_instr_type),
                .isW(RD_isW),

                //OUTPUTS
                .result(_EX_alu_result)
    );



    always_ff @ (posedge clk) begin
        if(reset) begin //when first starting.
            pc <= entry - entry%64;
            index_from_pc <= (entry%64)/4;
            IF_pc <= entry;
            jumpbit <= 1;
            state <= INIT;
            IF_instr <= 64'h0;
            fetch_count <= 0;
            instr_index <= 0;
            MEM_status <= 0;
            MEM_ptr <= 0;
            MEM_read_value <= -1;
            firstFETCH <= 1;
            for (int i = 0; i < 16; i++) begin
                instrlist[i] <= 32'b0;
            end  
        end else begin /////////

        firstFETCH <= _firstFETCH;

        // The only registers written to no matter what.
        read_stallstate <= _read_stallstate;
        jump_stallstate <= _jump_stallstate;
        mem_stallstate <= _mem_stallstate;
        ecall_stallstate <= _ecall_stallstate;
        ecall_count <= _ecall_count;
        ecall_later <= _ecall_later;

        // To avoid UNOPTFLAT
        arbiter_ready <= _arbiter_ready;
        MEM_cache_invalidated <= _MEM_cache_invalidated;

        if (ecall_now) begin
            do_ecall(_WB_a7, _WB_a0, _WB_a1, _WB_a2, _WB_a3, _WB_a4, _WB_a5, _WB_a6, _WB_a0);
        end
        WB_a0 <= _WB_a0;
        if(pending_write) begin
            do_pending_write(_WB_address,_WB_write_val, _WB_mem_size);
        end

        for (int i = 0; i < 32; i++) begin
            writinglist[i] <= _writinglist[i];
        end

        state <= next_state;
 
        pc <= _pc;
        fetch_count <= _fetch_count;
        getinstr_ready <= _getinstr_ready;
        last_instr <= _last_instr;

        //For JUMP
        jump_to_addr <= _jump_to_addr;
        jumpbit <= _jumpbit;
        index_from_pc <= _index_from_pc;
        
        for (int i = 0; i < 16; i++) begin
            instrlist[i] <= _instrlist[i];
        end

        // FETCH //
        if(_read_stallstate < GETINSTR && _jump_stallstate < GETINSTR && _mem_stallstate < GETINSTR && _ecall_stallstate < GETINSTR) begin
            IF_instr <= _IF_instr;
            instr_index <= _instr_index;
            IF_pc <= _IF_pc;
            
            IF_stalled <= 0;
            IF_valid_instr <= _IF_valid_instr;
        end else begin
            // Stalling
            IF_stalled <= 1;
            IF_valid_instr <= 0;
        end
    
        // DECODE //
        if(_read_stallstate < DECODE && _jump_stallstate < DECODE && _mem_stallstate < DECODE) begin
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
            ID_isW <= _ID_isW;

            ID_stalled <= 0;

            ID_valid_instr <= _ID_valid_instr;
        end else begin
            // Stalling
            ID_stalled <= 1;
            ID_valid_instr <= 0;
        end

        // READ //
        if(_read_stallstate < READ && _jump_stallstate < READ && _mem_stallstate < READ) begin
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
            RD_isW <= _RD_isW;

            RD_stalled <= 0;
            RD_valid_instr <= _RD_valid_instr;
        end else begin
            // Stalling
            RD_stalled <= 1;
            RD_valid_instr <= 0;
        end


        if(_read_stallstate < EXECUTE && _jump_stallstate < EXECUTE && _mem_stallstate < EXECUTE) begin
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

            EX_stalled <= 0;
            EX_valid_instr <= _EX_valid_instr;
        end else begin
            // Stalling
            EX_stalled <= 1;
            EX_valid_instr <= 0;
        end


        if(_read_stallstate < MEM && _jump_stallstate < MEM && _mem_stallstate < MEM) begin
            //set MEM registers
            MEM_alu_result <= _MEM_alu_result; // this is the address to store to in mem.
            MEM_write_reg <= _MEM_write_reg;
            MEM_value <= _MEM_value; // This is the value that comes out from mem stage.
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
            MEM_finished_instr <= _MEM_finished_instr;

            MEM_stalled <= 0;
            MEM_valid_instr <= _MEM_valid_instr;
        end
        else begin 
            // Stalling
            MEM_stalled <= 1;
            MEM_valid_instr <= 0;

            //If stalling because of mem stage ld/st...
            if(_MEM_access != `MEM_NO_ACCESS && _mem_stallstate == MEM) begin
                MEM_status <= _MEM_status;
                MEM_read_value <= _MEM_read_value;
                MEM_ptr <= MEM_next_ptr;
                MEM_str_value <= _MEM_str_value;
                MEM_finished_instr <= _MEM_finished_instr;
            end

        end


        if(_read_stallstate < WRITEBACK && _jump_stallstate < WRITEBACK && _mem_stallstate < WRITEBACK) begin
            //Set WB registers
            WB_instr <= _WB_instr;
            WB_pc <= _WB_pc;
            WB_write_reg <= _WB_write_reg;
            WB_write_val <= _WB_write_val;
            WB_write_sig <= _WB_write_sig;

            WB_stalled <= 0; 
            WB_valid_instr <= _WB_valid_instr;
        end else begin
            //Stalling
            WB_stalled <= 1;
            WB_valid_instr <= 0;
        end

        end
    end

    initial begin
        $display("Initializing top, entry point = 0x%x", entry);
    end

endmodule



