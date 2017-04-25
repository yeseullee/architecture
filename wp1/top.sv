`include "Sysbus.defs"

module top
#(
    BUS_DATA_WIDTH = 64,
    BUS_TAG_WIDTH = 13
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
    enum { INIT=4'd0, FETCH=4'd1, WAIT=4'd2, GETINSTR = 4'd3, 
            DECODE=4'd4, READ = 4'd5, EXECUTE=4'd6, 
            WRITEBACK = 4'd7, IDLE=4'd8} 
                state, next_state;
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

    //READ WIRES & REGISTERS  
    //No pass along WIRES
    logic [4:0] _RD_rs1;
    logic [4:0] _RD_rs2;
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


    //EXECUTE stage WIRES & REGISTERS
    // No need to pass these.. WIRES
    logic [63:0] _EX_rs1_val;
    logic [63:0] _EX_rs2_val;
    logic [10:0] _EX_alu_op;
    logic [31:0] _EX_immediate;
    logic [5:0] _EX_shamt;
    logic [3:0] _EX_instr_type;
    // Pass along REGISTERS (3)
    logic [63:0] EX_alu_result;
    logic [63:0] _EX_alu_result;
    logic [4:0] EX_write_reg;
    logic [4:0] _EX_write_reg;
    logic EX_write_sig;
    logic _EX_write_sig; 
    logic [31:0] EX_instr; //For debugging
    logic [31:0] _EX_instr;

    //WRITEBACK WIRES
    logic [63:0] _WB_val;
    logic [4:0] _WB_reg;
    logic _WB_sig;


 
    //insert cache variables
    logic cache = 0;  //set to 0 to remove the cache, and comment out cache initialization block
    logic cache_bus_reqcyc;
    logic cache_bus_respack;
    logic [BUS_DATA_WIDTH-1:0] cache_bus_req;
    logic [BUS_TAG_WIDTH-1:0] cache_bus_reqtag;
    logic cache_bus_respcyc;
    logic cache_bus_reqack;
    logic [BUS_DATA_WIDTH-1:0] cache_bus_resp;
    logic [BUS_TAG_WIDTH-1:0] cache_bus_resptag;
 
    direct_cache cache_mod (
    //set_cache cache_mod (
        //INPUTS
        .clk(clk),// .reset(reset),
        .p_bus_reqcyc(cache_bus_reqcyc), .p_bus_req(cache_bus_req), 
        .p_bus_reqtag(cache_bus_reqtag), .p_bus_respack(cache_bus_respack),
        .m_bus_reqack(bus_reqack), .m_bus_respcyc(bus_respcyc), 
        .m_bus_resp(bus_resp), .m_bus_resptag(bus_resptag),

        //OUTPUTS
        .p_bus_reqack(cache_bus_reqack), .p_bus_respcyc(cache_bus_respcyc), 
        .p_bus_resp(cache_bus_resp), .p_bus_resptag(cache_bus_resptag),
        .m_bus_reqcyc(bus_reqcyc), .m_bus_req(bus_req),
        .m_bus_reqtag(bus_reqtag), .m_bus_respack(bus_respack)
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
/*
    arbiter arbiter_mod (
        //INPUTS
        .clk(clk),
        .req0(), .reqcyc0(), .reqack0(), .reqtag0(), .respack0(),
        .req1(), .reqcyc1(), .reqack1(), .reqtag1(), .respack1(),
        .bus_resp(), .bus_respcyc(), .bus_resptag(), .bus_reqack(),
        
        //OUTPUTS
        .resp0(), .respcyc0(), .resptag0(), .reqack0(),
        .resp1(), .respcyc1(), .resptag1(), .reqack1(),
        .bus_req(), .bus_reqcyc(), .bus_reqtag, .bus_respack()
    );
*/
    
    always_comb begin
        if(cache == 1) begin
            cache_bus_reqcyc = 0;
            cache_bus_respack = 0;
            cache_bus_req = 64'h0;
            cache_bus_reqtag = 0;
        end
        else begin
            bus_reqcyc = 0;
            bus_respack = 0;
            bus_req = 64'h0;
            bus_reqtag = 0;
        end

        //set IF wires (to registers)
        _pc = pc;
        _instr = instr;
        _fetch_count = fetch_count;
        _instr_index = instr_index;

        for (int i = 0; i < 16; i++) begin
            _instrlist[i] = instrlist[i];
        end

        //set ID wires (to registers)
        _ID_rd = ID_rd;
        _ID_rs1 = ID_rs1;
        _ID_rs2 = ID_rs2;
        _ID_immediate = ID_immediate;
        _ID_alu_op = ID_alu_op;
        _ID_shamt = ID_shamt;
        _ID_write_sig = ID_write_sig;
        _ID_instr_type = ID_instr_type;
        _ID_instr = ID_instr;

        //set RD wires (to registers)
        _RD_immediate = RD_immediate;
        _RD_alu_op = RD_alu_op;
        _RD_shamt = RD_shamt;
        _RD_write_sig = RD_write_sig;
        _RD_write_reg = RD_write_reg;
        _RD_instr_type = RD_instr_type;
        _RD_rs1_val = RD_rs1_val;
        _RD_rs2_val = RD_rs2_val;
        _RD_instr = RD_instr;

        //set EX wires (to registers)
        _EX_alu_result = EX_alu_result;
        _EX_write_reg = EX_write_reg;
        _EX_write_sig = EX_write_sig;
        _EX_instr = EX_instr;

        case(state)
            INIT: begin
                  /*cache_bus_reqcyc = 0;*/
                  if(cache == 1) begin
                    cache_bus_reqcyc = 0;
                  end
                  else begin
                    bus_reqcyc = 0;
                  end

                  if(!reset) begin
                    next_state = FETCH;
                  end
                  else begin
                    next_state = INIT;
                  end
                end
            FETCH: begin

                  if(cache == 1) begin
                        
                      cache_bus_reqcyc = 1;
                      cache_bus_req = pc;
                      cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};

                      if(!cache_bus_reqack) begin
                          next_state = FETCH;
                      end               
                      else begin
                          next_state = WAIT;
                      end
                  end
                  else begin
                        
                      bus_reqcyc = 1;
                      bus_req = pc;
                      bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};

                      if(!bus_reqack) begin
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

                      if(cache_bus_respcyc == 1) begin
                        _instrlist[fetch_count] = cache_bus_resp[31:0];
                        _instrlist[fetch_count + 1] = cache_bus_resp[63:32];

                        // For next time,
                        _fetch_count = fetch_count + 2;
                        cache_bus_respack = 1;
                        if(_fetch_count < 16) begin
                          next_state = WAIT;
                        end else begin
                          // For the first instr after fetch.
                          next_state = GETINSTR;
                          _instr_index = 0;
                          _fetch_count = 0;
                        end
                      end else begin
                        next_state = WAIT;
                      end

                  end else begin

                      //NOT USING CACHE
                      if(bus_respcyc == 1) begin
                        _instrlist[fetch_count] = bus_resp[31:0];
                        _instrlist[fetch_count + 1] = bus_resp[63:32];

                        // For next time,
                        _fetch_count = fetch_count + 2;
                        bus_respack = 1;
                        if(_fetch_count < 16) begin
                          next_state = WAIT;
                        end else begin
                          // For the first instr after fetch.
                          next_state = GETINSTR;
                          _instr_index = 0;
                          _fetch_count = 0;
                        end
                      end else begin
                        next_state = WAIT;
                      end
                   end

                 end
            GETINSTR: begin

                    //NEED MORE INSTR (OUT OF INDEX)                    
                    if(instr_index >= 16) begin
                      next_state = FETCH;
                      _pc = pc + 64;
                    end else begin 

                      //GOOD FOR NOW
                      _instr = instrlist[instr_index];
                       next_state = DECODE;

                     //THE END
                      if(_instr == 32'b0) begin
                        next_state = IDLE;
                      end
                    end
                  end              
            DECODE: begin
                    _ID_instr = instr;
                    next_state = READ;
                  end
            READ: begin

                      _RD_rs1 = ID_rs1;
                      _RD_rs2 = ID_rs2;
                      _RD_immediate = ID_immediate;
                      _RD_alu_op = ID_alu_op;
                      _RD_shamt = ID_shamt;
                      _RD_write_sig = ID_write_sig;
                      _RD_write_reg = ID_rd;
                      _RD_instr_type = ID_instr_type;
                      _RD_instr = ID_instr;

                      next_state = EXECUTE;
                    end
            EXECUTE: begin
                      //Assuming register file is done, passing parameters for EXECUTE state.
                      //OUTPUT of REG FILE
                      _EX_rs1_val = RD_rs1_val;
                      _EX_rs2_val = RD_rs2_val;
                      //Connecting OTHER PARAMS...
                      _EX_immediate = RD_immediate;
                      _EX_alu_op = RD_alu_op;
                      _EX_shamt = RD_shamt;
		      _EX_instr_type = RD_instr_type;
                      //Passing these as registers to WB.
                      _EX_write_sig = RD_write_sig; 
                      _EX_write_reg = RD_write_reg;
                      _EX_instr = RD_instr;

                    //To get more instructions.
                    next_state = WRITEBACK; 

                   end
            WRITEBACK: begin
                    //To write back to the register file.
                    //There should be write signal.         
                    _WB_val = EX_alu_result;
                    _WB_reg = EX_write_reg;
                    _WB_sig = EX_write_sig;
                    
                    next_state = GETINSTR;
                    _instr_index = instr_index + 1;

                    end
            IDLE: $finish;
        endcase
    end


    // In Decode state
    //instantiate decode modules for each instruction
    decoder instr_decode_mod (
                //INPUTS
                .clk(clk), .instruction(instr),

                //OUTPUTS
                .rd(_ID_rd), .rs1(_ID_rs1), .rs2(_ID_rs2), 
                .immediate(_ID_immediate),
                .alu_op(_ID_alu_op), .shamt(_ID_shamt), 
                .reg_write(_ID_write_sig), .instr_type(_ID_instr_type)
    );

    // In READ state and WRITEBACK state
    //instantiate register file module
    reg_file register_mod (
                //INPUTS
                //Used Only From READ Stage.
                .clk(clk), .reset(reset), .rs1(_RD_rs1), 
                .rs2(_RD_rs2),  
                //Used Only From WB Stage.
                .write_sig(_WB_sig), 
                .write_val(_WB_val), 
                .write_reg(_WB_reg),

                //OUTPUTS
                //Used Only From READ Stage.
                .rs1_val(_RD_rs1_val), .rs2_val(_RD_rs2_val)
    );

    //In Execute state
    alu alu_mod (
                //INPUTS
                .clk(clk), .opcode(_EX_alu_op), .value1(_EX_rs1_val),
                .value2(_EX_rs2_val), .immediate(_EX_immediate), .shamt(_EX_shamt), .instr_type(_EX_instr_type),

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

        //set EX registers
        EX_alu_result <= _EX_alu_result;
        EX_write_reg <= _EX_write_reg;
        EX_write_sig <= _EX_write_sig;
        EX_instr <= _EX_instr;
       
    end

    initial begin
        $display("Initializing top, entry point = 0x%x", entry);
    end

endmodule

