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
  output bus_reqcyc,
  output bus_respack,
  output [BUS_DATA_WIDTH-1:0] bus_req,
  output [BUS_TAG_WIDTH-1:0] bus_reqtag,
  input  bus_respcyc,
  input  bus_reqack,
  input  [BUS_DATA_WIDTH-1:0] bus_resp,
  input  [BUS_TAG_WIDTH-1:0] bus_resptag
);

//constants
logic [6:0] UJ_Op = 7'b1101111;
logic [6:0] SB_Op = 7'b1100011;
logic [6:0] S_Op = 7'b0100011;
logic [6:0] LUI_Op = 7'b0110111;
logic [6:0] AUIPC_Op = 7'b0010111;
logic [6:0] JALR_Op = 7'b1100111;
logic [6:0] load_Op = 7'b0000011;

//variables
logic [63:0] bus;
logic [6:0] opcode;
logic store, branch, regis, imm, shift_op;
integer data_file;
integer is_file_open;

initial begin
  data_file = $fopen("/shared/cse502/tests/wp1/prog1.o", "r");
  if (data_file == 0) begin
    $display("data_file handle was NULL");
    $finish;
  end
end

always_ff @ (posedge clk) begin
  is_file_open = $fscanf(data_file, "%d\n", bus); 
  if ($feof(data_file)) begin
    $display("End of file reached (code %d)", is_file_open);
  end
  opcode = bus[6:0];
  store <= 0;
  branch <= 0;
  shift_op <= 0;
  regis <= 0;
  imm <= 0;
end

always_comb begin //FSM #1
  case(opcode)
    SB_Op: branch = 1;
    S_Op: store = 1;
    7'b011x011: regis=1;
    UJ_Op: $display("jal");
    LUI_Op: $display("lui");
    AUIPC_Op: $display("auipc");
    default: imm = 1;
  endcase
end

string branch_op;
logic valid_branch;
logic branch_imm;

always_comb begin //FSM: branch
  if(branch == 1) begin
	valid_branch = 1;
	case(bus[14:12])
	  3'b000: branch_op="beq";
	  3'b001: branch_op="bne";
	  3'b100: branch_op="blt";
	  3'b101: branch_op="bge";
	  3'b110: branch_op="bltu";
	  3'b111: branch_op="bgeu";
	  default: valid_branch = 0;
	endcase
	if (valid_branch == 1) begin
	  branch_imm = 0;//calculate branch imm value.
	  $display("%s %5d, %5d, %d", branch_op, bus[19:15], bus[24:20], branch_imm);
	end	else begin
	  $display("This is not a valid branch commsnd");
	end
  end
end

string store_op;
logic store_imm;
logic valid_store;
always_comb begin //FSM: store
  if(store == 1) begin
	valid_store = 1;
	case(bus[14:12])
	  3'b000: store_op="sb";
	  3'b001: store_op="sh";
	  3'b011: store_op="sw";
	  default: valid_store = 0;
	endcase
	if (valid_store == 1) begin
	  store_imm = 0; //calculate immediate value
	  $display("%s %5d %d(%5d)", store_op, bus[24:20], store_imm, bus[19:15]);
	end	else begin
	  $display("This is not a valid store commsnd");
	end
  end
end

always_comb begin //FSM: R ops
  if (regis==1) begin
	string r_op;
	if (opcode==7'b0110011) begin
	  if (bus[25]==1'b1) begin
        case(bus[14:12])
		  3'b000: r_op="mul";
		  3'b001: r_op="mulh";
		  3'b010: r_op="mulhsu";
		  3'b011: r_op="mulhu";
		  3'b100: r_op="div";
		  3'b101: r_op="divu";
		  3'b110: r_op="rem";
		  3'b111: r_op="remu";
        endcase
	  end else begin
        case(bus[14:12])
		  3'b000: begin
			if (bus[25]==1'b0) begin
			  r_op="add";
			end else if (bus[29]==1'b1) begin
			  r_op="sub";
			end
		  end
		  3'b001: r_op="sll";
		  3'b010: r_op="slt";
		  3'b011: r_op="sltu";
		  3'b100: r_op="xor";
		  3'b101:  begin
			if (bus[25]==1'b0) begin
			  r_op="srl";
			end else if (bus[29]==1'b1) begin
			  r_op="sra";
			end
		  end
		  3'b110: r_op="or";
		  3'b111: r_op="and";
		endcase
	  end
    end else begin // opcode == 7'b0011001
	  case(bus[14:12])
		  3'b000: begin
			if (bus[25]==1'b0) begin
			  r_op="addw";
			end else if (bus[25]==1'b1) begin
			  r_op="subw";
			end else if (bus[29]==1'b1) begin
			  r_op="mulw";
			end
		  end
		  3'b001: r_op="sllw";
		  3'b100: r_op="divw";
		  3'b101: begin
			if (bus[25]==1'b0) begin
			  r_op="srlw";
			end else if (bus[25]==1'b1) begin
			  r_op="sraw";
			end else if (bus[29]==1'b1) begin
			  r_op="divuw";
			end
		  end
		  3'b110: r_op="remw";
		  3'b111: r_op="remuw";
	  endcase
	end
    $display("%s %5d, %5d, %5d", r_op, bus[11:7], bus[19:15], bus[24:20]);
  end
end

logic load_imm;
always_comb begin //FSM: I ops
  if (imm == 0) begin
  end else if(opcode==JALR_Op)begin
	$display("jarl");
  end else if(opcode==7'b0000011) begin
    string load_op;
    case(bus[14:12])
		  3'b000: load_op="lb";
		  3'b001: load_op="lh";
		  3'b010: load_op="lw";
		  3'b100: load_op="lbu";
		  3'b101: load_op="lhu";
		  default: load_op="nop";
    endcase
    $display("%s %5d, %d(%5d)", load_op, bus[11:7], load_imm, bus[19:0]);
  end else if (opcode==7'b0011011) begin
    if (bus[14:12]==3'b000) begin
      $display("addiw");
    end else begin
      shift_op=1;
	end
  end else if(opcode==7'b0010011) begin
    string i_op;
	shift_op = 0;
    case(bus[14:12])
      3'bx01: shift_op=1;
      3'b000: i_op="addi";
      3'b010: i_op="slti";
      3'b011: i_op="sltiu";
      3'b100: i_op="xori";
      3'b110: i_op="ori";
      3'b111: i_op="andi";
    endcase
    if(shift_op==0) begin
      logic i_imm=0;
      $display("%s %5d, %5d, %d", i_op, bus[11:7], bus[19:15], i_imm);
    end
  end else begin
    $display("This is not a supported function");
  end
end 

string shift_imm;
always_comb begin //FSM: shift ops
  if(shift_op==1) begin
	if(opcode==7'b0010011) begin //32Shift
	  if(bus[14:12]==3'b001) begin
	    shift_op="slli";
	  end else begin
		if(bus[29]==0) begin
		  shift_op="srli";
		end else begin
		  shift_op="srai";
		end
	  end
	end else begin
	  if (bus[14:12]==3'b000) begin
		shift_op="slliw";
	  end else if (bus[14:12]==3'b001) begin
		if (bus[29]==0) begin
		  shift_op="srliw";
		end else begin
		  shift_op="sraiw";
		end
	  end
	end
	shift_imm = 0;
	$display("%s %5d, %5d, %d", shift_op, bus[11:7], bus[19:15], shift_imm);
  end
end  

endmodule
