module arbiter
(
    input clk,

    input req0,
    input reqcyc0,
    input reqack0,
    input reqtag0,
    input respack0,
    
    input req1,
    input reqcyc1,
    input reqack1,
    input reqtag1,
    input respack1,
    
    output resp0,
    output respcyc0,
    output resptag0,
    output reqack0,
    
    output resp1,
    output respcyc1,
    output resptag1,
    output reqack1,
    
    //With the bus
    output bus_req, //the address for request
    output bus_reqcyc, //request acknowledged
    output bus_reqtag, //
    output bus_respack, //acknolwedgement for response. 
    
    input bus_resp, //the response
    input bus_respcyc, //response acknowledgement
    input bus_resptag,
    input bus_reqack //acknowledgement for request.
    
);
    logic channel = 0;
    logic count = 0;    
    enum {IDLE=0, BUSY = 1} state, next_state;

    always_comb begin
        
        if(state == IDLE) begin

            //If 0 is requesting
            if(reqcyc0 == 1)begin
                //Acknolwedge the request
                reqack0 = 1;
                next_state = BUSY;
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
                next_state = BUSY;
                channel = 1;
                
                //Send request here.
                bus_req = req1;
                bus_reqtag = reqtag1;
                bus_reqcyc = 1;
            end
            
        end
        else if(state == BUSY) begin
            //Wait for response here.
            //If Bus says it has response
            if(bus_respcyc == 1)begin
                //Pick the correct channel
                if(channel == 0) begin                
                    //Give the response back
                    respcyc1 = 1;
                    resp0 = bus_resp;
                    resptag0 = bus_resptag;
                end
                else if(channel == 1) begin
                    //Give the response back
                    respcyc1 = 1;
                    resp1 = bus_resp;
                    resptag1 = bus_resptag;
                end
            end
             
            //If get respack from client and count == 8, go to IDLE.
            if(channel == 0 && respack0 == 1) begin
                bus_respack = 1;
                next_state = IDLE;
            end
            else if(channel == 1 && respack1 == 1) begin
                bus_respack = 1;
                next_state = IDLE;
            end    

        end
    end

    always_ff @ (posedge clk) begin
        state <= next_state;
    end

endmodule
