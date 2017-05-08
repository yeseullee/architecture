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
    IDLE=4'd9
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

    logic [63:0] pc;
    logic [63:0] _pc;

    reg [3:0] state;
    reg [3:0] next_state;
    reg [31:0] instr;
    reg [31:0] _instr;
    reg [4:0] fetch_count;
    reg [4:0] _fetch_count;

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
    logic [1:0] RD_mem_access;
    logic [1:0] _RD_mem_access;
    logic [2:0] RD_mem_size;
    logic [2:0] _RD_mem_size;


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


    //MEMORY WIRES & REGISTERS
    logic [63:0] _MEM_alu_result;
    logic [63:0] MEM_value;
    logic [63:0] _MEM_value;
    logic [4:0] MEM_write_reg;
    logic [4:0] _MEM_write_reg;
    logic MEM_write_sig;
    logic _MEM_write_sig; 
    logic [31:0] MEM_instr; //For debugging
    logic [31:0] _MEM_instr;
    logic [1:0] _MEM_access;
    logic [2:0] _MEM_size;
    logic [63:0] _MEM_rs2_val;

    //memory stage variables
    logic [1:0] MEM_status;
    logic [1:0] _MEM_status;
    logic [8:0] MEM_ptr;
    logic [8:0] MEM_next_ptr;
    logic [511:0] MEM_read_value;
    logic [511:0] _MEM_read_value;

    //WB pass along
    logic [31:0] WB_instr;
    logic [31:0] _WB_instr;

    //cache variables
    logic cache = 0;  //set to 0 to remove the cache, and comment out cache initialization block
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

    /*//direct_cache IF_cache_mod (
    set_cache IF_cache_mod (
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
    //direct_cache MEM_cache_mod (
    set_cache MEM_cache_mod (
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
    );*/


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

        _MEM_status = 0;
        MEM_next_ptr = MEM_ptr;
        _MEM_value = MEM_value;

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
                            // For the first instr after fetch.
                            next_state = GETINSTR;
                            _instr_index = 0;
                            _fetch_count = 0;
                        end
                        else if(IF_cache_bus_respcyc == 1) begin
                            _instrlist[fetch_count] = IF_cache_bus_resp[31:0];
                            _instrlist[fetch_count + 1] = IF_cache_bus_resp[63:32];

                            // For next time,
                            if(IF_cache_bus_resp != {instrlist[fetch_count-1],instrlist[fetch_count-2]} || IF_cache_bus_resp == 0) begin
                                _fetch_count = fetch_count + 2;
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
                            _instr_index = 0;
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
                    if(instr_index == 0) begin
                        if(cache == 1) begin
                            IF_cache_bus_respack = 1;
                        end
                        else begin
                        IF_arbiter_bus_respack = 1;
                        end
                    end

                    //NEED MORE INSTR (OUT OF INDEX)
                    if(instr_index >= 16) begin
                        next_state = FETCH;
                        _pc = pc + 64;
                    end else begin 

                        //GOOD FOR NOW
                        _instr = instrlist[instr_index];
                        //Get more instructions
                        next_state = GETINSTR;
                        _instr_index = instr_index + 1;
                        //Start decode.
                        _DECODE_state = DECODE;

                        //THE END
                        if(_instr == 32'b0) begin
                            next_state = IDLE;
                        end
                    end
                end
            IDLE: $finish;
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
        if(DECODE_state == DECODE) begin
            _ID_instr = instr;
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

            _EXECUTE_state = EXECUTE;
        end
        if(EXECUTE_state == EXECUTE) begin
            //Passing these as registers to WB.
            _EX_write_sig = RD_write_sig; 
            _EX_write_reg = RD_write_reg;
            _EX_instr = RD_instr;
            _EX_mem_access = RD_mem_access;
            _EX_mem_size = RD_mem_size;

            //To get more instructions.
            _MEM_state = MEM; 
        end
        if(MEM_state == MEM) begin
            //Passing these as registers to WB.
            _MEM_alu_result = EX_alu_result;
            _MEM_write_reg = EX_write_reg;
            _MEM_write_sig = EX_write_sig;
            _MEM_access = EX_mem_access;
            _MEM_instr = EX_instr;
            _MEM_size = EX_mem_size;
            _MEM_rs2_val = EX_rs2_val;
            _MEM_state = MEM;

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
                                        `MEM_BYTE: _MEM_value = {{56{MEM_read_value[MEM_ptr + 7]}}, MEM_read_value[MEM_ptr +: 8]};
                                        `MEM_HALF: _MEM_value = {{48{MEM_read_value[MEM_ptr + 15]}}, MEM_read_value[MEM_ptr +: 16]};
                                        `MEM_WORD: _MEM_value = {{32{MEM_read_value[MEM_ptr + 31]}}, MEM_read_value[MEM_ptr +: 32]};
                                        `MEM_DOUBLE: _MEM_value = {MEM_read_value[MEM_ptr +: 64]};
                                        `MEM_US_BYTE: _MEM_value = {56'b0, MEM_read_value[MEM_ptr +: 8]};
                                        `MEM_US_HALF: _MEM_value = {48'b0, MEM_read_value[MEM_ptr +: 16]};
                                        `MEM_US_WORD: _MEM_value = {32'b0, MEM_read_value[MEM_ptr +: 32]};
                                endcase
                                MEM_next_ptr = 0;
                                _MEM_status = 0;
                                _WRITEBACK_state = WRITEBACK; 
                            end
                            else if(_MEM_access == `MEM_WRITE) begin //store
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
                                        _MEM_status = 0;
                                        _WRITEBACK_state = WRITEBACK; 
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
                                        _MEM_status = 0;
                                        _WRITEBACK_state = WRITEBACK; 
                                    end
                                end
                            end
                        end
                endcase
            end
            else begin
                _MEM_value = EX_alu_result;
                //To get more instructions.
            _WRITEBACK_state = WRITEBACK;
            end
        end
        if(WRITEBACK_state == WRITEBACK) begin
            //To write back to the register file.
            //There should be write signal.
            //TODO
            _WB_instr = MEM_instr;
            //next_state = GETINSTR;
        end
    end


    // In Decode state
    //instantiate decode modules for each instruction
    decoder instr_decode_mod (
                //INPUTS
                .clk(clk), .instruction(instr), .cur_pc(pc),

                //OUTPUTS
                .rd(_ID_rd), .rs1(_ID_rs1), .rs2(_ID_rs2), 
                .immediate(_ID_immediate),
                .alu_op(_ID_alu_op), .shamt(_ID_shamt), 
                .reg_write(_ID_write_sig), .instr_type(_ID_instr_type), 
                .mem_access(_ID_mem_access), .mem_size(_ID_mem_size)
    );

    // In READ state and WRITEBACK state
    //instantiate register file module
    reg_file register_mod (
                //INPUTS
                //Used Only From READ Stage.
                .clk(clk), .reset(reset), .rs1(ID_rs1), 
                .rs2(ID_rs2),  
                //Used Only From WB Stage.
                .write_sig(EX_write_sig), 
                .write_val(EX_alu_result), 
                .write_reg(EX_write_reg),

                //OUTPUTS
                //Used Only From READ Stage.
                .rs1_val(_RD_rs1_val), .rs2_val(_RD_rs2_val)
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
            pc <= entry;
            state <= INIT;
            instr <= 64'h0;
            fetch_count <= 0;
            instr_index <= 0;
            MEM_status <= 0;
            MEM_ptr <= 0;
            MEM_read_value <= 0;

            for (int i = 0; i < 16; i++) begin
                instrlist[i] <= 32'b0;
            end  
        end

        //set IF registers
        state <= next_state;
        pc <= _pc;
        instr <= _instr;
        fetch_count <= _fetch_count;
        instr_index <= _instr_index;
        
        for (int i = 0; i < 16; i++) begin
            instrlist[i] <= _instrlist[i];
        end
        
        DECODE_state <= _DECODE_state;
        READ_state <= _READ_state;
        EXECUTE_state <= _EXECUTE_state;
        WRITEBACK_state <= _WRITEBACK_state;
        MEM_state <= _MEM_state;

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
        ID_mem_access <= _ID_mem_access;
        ID_mem_size <= _ID_mem_size;

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
        RD_mem_access <= _RD_mem_access;
        RD_mem_size <= _RD_mem_size;

        //set EX registers
        EX_alu_result <= _EX_alu_result;
        EX_write_reg <= _EX_write_reg;
        EX_write_sig <= _EX_write_sig;
        EX_instr <= _EX_instr;
        EX_mem_access <= _EX_mem_access;
        EX_mem_size <= _EX_mem_size;
        EX_rs2_val <= _EX_rs2_val;

        //set MEM registers
        MEM_write_reg <= _MEM_write_reg;
        MEM_value <= _MEM_value;
        MEM_write_sig <= _MEM_write_sig;
        MEM_status <= _MEM_status;
        MEM_instr <= _MEM_instr;
        MEM_ptr <= MEM_next_ptr;
        MEM_read_value <= _MEM_read_value;

        //Set WB registers
        WB_instr <= _WB_instr;
    
    end

    initial begin
        $display("Initializing top, entry point = 0x%x", entry);
    end

endmodule

