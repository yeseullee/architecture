module arbiter
#(
    BUS_DATA_WIDTH = 64,
    BUS_TAG_WIDTH = 13
)
(
    input clk,

    input [BUS_DATA_WIDTH-1:0] req0,
    input reqcyc0,
    input [BUS_TAG_WIDTH-1:0] reqtag0,
    input respack0,
    
    input [BUS_DATA_WIDTH-1:0] req1,
    input reqcyc1,
    input [BUS_TAG_WIDTH-1:0] reqtag1,
    input respack1,
    
    output [BUS_DATA_WIDTH-1:0] resp0,
    output respcyc0,
    output [BUS_TAG_WIDTH-1:0] resptag0,
    output reqack0,
    
    output [BUS_DATA_WIDTH-1:0] resp1,
    output respcyc1,
    output [BUS_TAG_WIDTH-1:0] resptag1,
    output reqack1,
    
    //With the bus
    output [BUS_DATA_WIDTH-1:0]  bus_req, //the address for request
    output bus_reqcyc, //request acknowledged
    output [BUS_TAG_WIDTH-1:0] bus_reqtag, //
    output bus_respack, //acknolwedgement for response. 
    
    input [BUS_DATA_WIDTH-1:0] bus_resp, //the response
    input bus_respcyc, //response acknowledgement
    input [BUS_TAG_WIDTH-1:0] bus_resptag,
    input bus_reqack //acknowledgement for request.
    
);
    logic channel = 0;
    logic [4:0] fetch_count;
    logic [4:0] _fetch_count;
    logic addr;
    logic _addr;
    enum {IDLE=4'd0, FETCH = 4'd1, WAIT = 4'd2, SEND = 4'd3, WAIT_RESP = 4'd4} 
	state, next_state;

    logic [31:0] instrlist[15:0];
    logic [31:0] _instrlist[15:0];
    logic [5:0] instr_index;
    logic [5:0] _instr_index;

    always_comb begin

        bus_reqcyc = 0;
        bus_respack = 0;
        bus_req = 64'h0;
        bus_reqtag = 0;

        _fetch_count = fetch_count;
        _addr = addr;
        _instr_index = instr_index;

        for (int i = 0; i < 16; i++) begin
            _instrlist[i] = instrlist[i];
        end

        case(state)
            IDLE: begin

                //If 0 is requesting
                if(reqcyc0 == 1)begin
                    //Acknolwedge the request
                    reqack0 = 1;
                    next_state = FETCH;
                    channel = 0; 
                
                    //Send request here.
                    bus_req = req0;
                    bus_reqtag = reqtag0;
                    bus_reqcyc = 1;  
                end
            
                //If 1 is requesting
                else if(reqcyc1 == 1)begin
                    //Acknowledge the request
                    reqack1 = 1;
                    next_state = FETCH;
                    channel = 1;
                
                    //Send request here.
                    bus_req = req1;
                    bus_reqtag = reqtag1;
                    bus_reqcyc = 1;
                end
       
            end
            FETCH: begin
                if(!bus_reqack) begin
                    next_state = FETCH;
                end
                else begin
                    next_state = WAIT;
                end
            end
            WAIT: begin

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
                        next_state = SEND;
                        _instr_index = 0;
                        _fetch_count = 0;
                    end
                end else begin
                    next_state = WAIT;
                end
            end
            SEND: begin 
                //Response ready.
                if(channel == 0) begin                
                    //Give the response back
                    respcyc1 = 1;
                    resp0 = instrlist[instr_index];
                    resptag0 = bus_resptag; //Not working.
                end
                else if(channel == 1) begin
                    //Give the response back
                    respcyc1 = 1;
                    resp1 = instrlist[instr_index];
                    resptag1 = bus_resptag; //Not working.
                end
            end
            WAIT_RESP: begin

                //If get respack from client and count == 8, go to IDLE.
                if(channel == 0 && respack0 == 1) begin
                    _instr_index = instr_index + 1; 
                    next_state = SEND;
                    if(_instr_index >= 16) begin
                        next_state = IDLE;
                    end
                end
                else if(channel == 1 && respack1 == 1) begin
                    _instr_index = instr_index + 1; 
                    next_state = SEND;
                    if(_instr_index >= 16) begin
                        next_state = IDLE;
                    end
                end
            end
        endcase
    end

    always_ff @ (posedge clk) begin
        state <= next_state;
        fetch_count <= _fetch_count;
        addr <= _addr;
        instr_index <= _instr_index;

        for (int i = 0; i < 16; i++) begin
            instrlist[i] <= _instrlist[i];
        end

    end

endmodule
