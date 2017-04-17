module arbiter
(
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
    
    enum {IDLE=0, BUSY = 1} state, next_state;

    always_comb begin
        
        if(state == IDLE) begin

            //If 0 is requesting
            if(reqcyc0 == 1)begin
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
            //If got response signal.
            if(bus_respcyc == 1)begin
            
                if(channel == 0) begin                
                    //TO BUS
                    bus_respack = respack0; 
                    //FROM BUS
                    resp0 = bus_resp;
                    respcyc1 = bus_respcyc;
                    resptag0 = bus_resptag;
                    reqack0 = bus_reqack;
                    //If got resp acknowledgement, go to IDLE.
                    if(respcyc0 == 1) begin
                        next_state = IDLE;
                    end
                end
                else if(channel == 1) begin
                    //TO BUS
                    bus_respack = respack1;
                    //FROM BUS
                    resp1 = bus_resp;
                    respcyc1 = bus_respcyc;
                    resptag1 = bus_resptag;
                    reqack1 = bus_reqack; 
                    //If got resp acknowledgement, go to IDLE.
                    if(respcyc0 == 1) begin
                        next_state = IDLE;
                    end               
                end
            end
                

        end
    end

    always_ff @ (posedge clk) begin
        state <= next_state;
    end

endmodule
