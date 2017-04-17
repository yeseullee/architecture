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
    enum { INIT=3'b000, FETCH=3'b001, WAIT=3'b010, 
            DECODE=3'b011, READ = 3'b100, EXECUTE=3'b101, 
            WRITEBACK = 3'b110, IDLE=3'b111} 
                state, next_state;
    reg [63:0] instr;
    reg [63:0] _instr;
    reg [3:0] _count;
    reg [3:0] count;
    reg [1:0] instr_num;
    reg [1:0] _instr_num;

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
 
    /*direct_cache cache_mod (
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

        _count = count;
        _pc = pc;
        _instr = instr;
        _instr_num = instr_num;

        //set ID wires (to registers)
        _ID_rd = ID_rd;
        _ID_rs1 = ID_rs1;
        _ID_rs2 = ID_rs2;
        _ID_immediate = ID_immediate;
        _ID_alu_op = ID_alu_op;
        _ID_shamt = ID_shamt;
        _ID_write_sig = ID_write_sig;
        _ID_instr_type = ID_instr_type;

        //set RD wires (to registers)
        _RD_immediate = RD_immediate;
        _RD_alu_op = RD_alu_op;
        _RD_shamt = RD_shamt;
        _RD_write_sig = RD_write_sig;
        _RD_write_reg = RD_write_reg;
        _RD_instr_type = RD_instr_type;
        _RD_rs1_val = RD_rs1_val;
        _RD_rs2_val = RD_rs2_val;

        //set EX wires (to registers)
        _EX_alu_result = EX_alu_result;
        _EX_write_reg = EX_write_reg;
        _EX_write_sig = EX_write_sig;

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
                  _pc = pc;
                  _count = 0;

                  if(cache == 1) begin
                      cache_bus_reqcyc = 1;
                      cache_bus_req = pc;
                      cache_bus_reqtag = {1'b1,`SYSBUS_MEMORY,8'b0};
                      if(!cache_bus_reqack) begin
                          _pc = pc + 64; 
                          next_state = FETCH;
                      end               
                      else begin
                          next_state = WAIT;
                      end
                  end
                  else begin
                      _pc = pc + 64; //difference in placement here
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

            WAIT:  begin
                    if(cache == 1) begin
                      if(cache_bus_respcyc == 1) begin
                        _instr = cache_bus_resp;
                        _instr_num = 0;
                        _count = count + 1;
                        next_state = DECODE;
                      end
                      else begin
                        next_state = WAIT;
                      end
                    end
                    else begin
                      if(bus_respcyc == 1) begin
                        _instr = bus_resp;
                        _instr_num = 0;
                        _count = count + 1;
                        next_state = DECODE;
                      end
                      else begin
                        next_state = WAIT;
                      end
                    end
                  end

            DECODE: begin
                    //if both instr are 0s then finish.
                    if(instr[31:0] == 32'h0 && instr[63:32] == 32'h0) begin
                      next_state = IDLE;
                    end else begin
                    
                      next_state = READ;
                    end
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

                    //To get more instructions.
                    next_state = WRITEBACK; 

                   end
            WRITEBACK: begin
                    //To write back to the register file.
                    //There should be write signal.         
                    _WB_val = EX_alu_result;
                    _WB_reg = EX_write_reg;
                    _WB_sig = EX_write_sig;
                    
                    
                    //Directions for all paths.
                    //1 instruction at a time.
                    _instr_num = instr_num + 1;
                    if(_instr_num == 1) begin
                        _instr = {32'b0,  instr[63:32]};
                        next_state = DECODE;
                    end
                    if(_instr_num == 2) begin
                        //fetch the next set
                        _instr_num = 0;
                        
                        if(cache == 1) begin
                          cache_bus_respack = 1;
                        end
                        else begin
                          bus_respack = 1;
                        end

                        next_state = WAIT;

                        if(_count == 8) begin
                          next_state = FETCH;
                        end
                      end
                    end
            IDLE: $finish;
        endcase
    end


    // In Decode state
    //instantiate decode modules for each instruction
    decoder instr_decode_mod (
                //INPUTS
                .clk(clk), .instruction(instr[31:0]),

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
            count <= 0;
            instr <= 64'h0;
            instr_num <= 0;
        end

        //set IF registers
        state <= next_state;
        count <= _count;
        pc <= _pc;
        instr <= _instr;
        instr_num <= _instr_num;
        
        //set ID registers
        ID_rd <= _ID_rd;
        ID_rs1 <= _ID_rs1;
        ID_rs2 <= _ID_rs2;
        ID_immediate <= _ID_immediate;
        ID_alu_op <= _ID_alu_op;
        ID_shamt <= _ID_shamt;
        ID_write_sig <= _ID_write_sig;
	ID_instr_type <= _ID_instr_type;

        //set READ registers
        RD_immediate <= _RD_immediate;
        RD_alu_op <= _RD_alu_op;
        RD_shamt <= _RD_shamt;
        RD_write_sig <= _RD_write_sig;
        RD_write_reg <= _RD_write_reg;
        RD_instr_type <= _RD_instr_type;
        RD_rs1_val <= _RD_rs1_val;
        RD_rs2_val <= _RD_rs2_val;

        //set EX registers
        EX_alu_result <= _EX_alu_result;
        EX_write_reg <= _EX_write_reg;
        EX_write_sig <= _EX_write_sig;
       
    end

    initial begin
        $display("Initializing top, entry point = 0x%x", entry);
    end

endmodule

