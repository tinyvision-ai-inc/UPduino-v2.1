
module ice40_audio_fb_cu (
// Global inputs
input             clk           ,
input             resetn        ,

// Control signals
input             i_start       , // clk, long pulse
input             i_repeat_run  , // enable repeat run

output            o_init        ,
output            o_rst_raddr   ,
output            o_rst_waddr   ,
output            o_rst_wgt_addr,

input      [7:0]  i_blk_idx     , // current write block index
output            o_rd_req      ,
input             i_rd_rdy      ,
output reg [7:0]  o_blk_idx     ,

output reg [31:0] o_cycles      ,

output reg [5:0]  o_bias_addr   ,

output            o_fc_run      ,
output reg        o_input_rd    , 
output reg        o_wgt_rd      ,
output reg        o_init_bias   ,
output reg        o_fc_ps_shift ,

output            o_done     
);

parameter [3:0]	C_POST_GAP  = 4'd2;

reg	[5:0]	round_cnt;
reg	[5:0]	chunk_cnt;

reg	[11:0]	data_cnt;
reg	[3:0]	output_cnt;
reg	[1:0]	plane_cnt;
reg	[7:0]	start_blk_idx;

wire	[5:0]	num_round;
wire	[5:0]	num_chunk;
wire	[11:0]	num_data;
wire	[3:0]	num_output;
wire	[1:0]	num_plane;
wire	[7:0]	num_stride;

wire		round_done;
wire		chunk_done;
wire		plane_done;
wire		frame_done;
wire		write_done;

// state machine
parameter [3:0] 
	S_INIT       = 4'b0000, // initialize, wait for start
	S_INIT_BIAS  = 4'b0001, // initialize accumulator in MAC
	S_RUN_ROUND  = 4'b0010, // run round (whole input, partial output)
	S_RST_ADDR   = 4'b0011, // reset read addr
	S_NEXT_CHUNK = 4'b0100, // prepare next chunk
	S_NEXT_PLANE = 4'b0101, // prepare next plane
	S_WAIT_WRITE = 4'b0110, // wait for last output writing
	S_HOLD       = 4'b1111; // wait for deassert i_start

reg     [3:0]   state;
reg     [3:0]   nstate;


always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	state <= S_INIT;
    else               
	state <= nstate;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_cycles <= 32'b0;
    else if((state == S_INIT) && i_start)
	o_cycles <= 32'b0;
    else if((state != S_INIT) && (state != S_HOLD))
	o_cycles <= o_cycles + 32'd1;
end

always @(*)
begin
    case(state)
	S_INIT:
	    nstate = i_start ? S_INIT_BIAS : S_INIT;
	S_INIT_BIAS:
	    nstate = i_rd_rdy ? S_RUN_ROUND : S_INIT_BIAS;
	S_RUN_ROUND:
	    nstate = round_done ? (chunk_done ? S_NEXT_CHUNK : S_RST_ADDR) : S_RUN_ROUND;
	S_RST_ADDR:
	    nstate = S_INIT_BIAS;
	S_NEXT_CHUNK:
	    nstate = plane_done ? S_NEXT_PLANE : S_INIT_BIAS;
	S_NEXT_PLANE:
	    nstate = frame_done ? S_WAIT_WRITE : S_INIT_BIAS;
	S_WAIT_WRITE:
	    nstate = write_done ? S_HOLD : S_WAIT_WRITE;
	S_HOLD:
	    nstate = ((!i_repeat_run) & i_start) ? S_HOLD : S_INIT;
	default:
	    nstate = S_INIT;
    endcase
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_bias_addr <= 6'b0;
    else if(state == S_INIT)
	o_bias_addr <= 6'b0;
    else if(o_init_bias)
	o_bias_addr <= o_bias_addr + 6'd1;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	plane_cnt <= 2'b0;
    else if(state == S_INIT)
	plane_cnt <= 2'b0;
    else if(state == S_NEXT_PLANE)
	plane_cnt <= plane_cnt + 2'd1;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	start_blk_idx <= 8'b0;
    else if(state == S_INIT)
	start_blk_idx <= i_blk_idx;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_blk_idx <= 8'd0;
    else if(state == S_INIT)
	o_blk_idx <= i_blk_idx - 8'd130;
    else if(state == S_NEXT_PLANE)
	o_blk_idx <= start_blk_idx - 8'd128;
    else if(state == S_NEXT_CHUNK)
	o_blk_idx <= o_blk_idx + num_stride;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	round_cnt <= 6'b0;
    else if((state == S_INIT) || (state == S_NEXT_CHUNK))
	round_cnt <= 6'b0;
    else if(state == S_RST_ADDR)
	round_cnt <= round_cnt + 6'd1;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	chunk_cnt <= 6'b0;
    else if((state == S_INIT) || (state == S_NEXT_PLANE))
	chunk_cnt <= 6'b0;
    else if(state == S_NEXT_CHUNK)
	chunk_cnt <= chunk_cnt + 6'd1;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	data_cnt <= 12'b0;
    else if((state == S_INIT) || (state == S_INIT_BIAS))
	data_cnt <= 12'b0;
    else if(state == S_RUN_ROUND)
	data_cnt <= data_cnt + 12'd1;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	output_cnt <= 4'd0;
    else if(round_done) 
	output_cnt <= num_output + C_POST_GAP;
    else if(output_cnt != 4'd0)
	output_cnt <= output_cnt - 4'd1;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_fc_ps_shift <= 1'b0;
    else
	o_fc_ps_shift <= (output_cnt != 4'd0) && (output_cnt <= num_output);
end

assign o_fc_run = (state == S_RUN_ROUND);

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_input_rd <= 1'b0;
    else if(state != S_RUN_ROUND)
	o_input_rd <= 1'b0;
    else if(data_cnt == 12'd0)
	o_input_rd <= 1'b1;
    else if(data_cnt == num_data)
	o_input_rd <= 1'b0;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_wgt_rd <= 1'b0;
    else if(state != S_RUN_ROUND)
	o_wgt_rd <= 1'b0;
    else if(data_cnt == 12'b0)
	o_wgt_rd <= 1'b1;
    else if(data_cnt == num_data)
	o_wgt_rd <= 1'b0;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	o_init_bias = 1'b0;
    else 
	o_init_bias = (state == S_INIT_BIAS);
end

assign round_done = (data_cnt == (num_data + 12'd2));
assign chunk_done = (round_cnt == num_round);
assign plane_done = (chunk_cnt == num_chunk);
assign frame_done = (plane_cnt == num_plane);
assign write_done = (state == S_WAIT_WRITE) && (output_cnt == 8'd0);

assign o_init = (state == S_INIT);

assign o_rst_raddr = (state == S_INIT) || (state == S_RST_ADDR);
assign o_rst_waddr = (state == S_INIT) || write_done;
assign o_rst_wgt_addr = (state == S_INIT) || (state == S_NEXT_CHUNK);

assign o_rd_req = (state == S_INIT_BIAS);

assign o_done = (state == S_HOLD);

// programmable parameters {{{

// 8K sample per sec, 64x64x1 
assign num_data   = 12'd256;
assign num_round  = 6'd63;
assign num_chunk  = 6'd63;
assign num_plane  = 2'd0;
assign num_stride = 8'd2;
// 4K sample per sec, 32x32x2
//assign num_data   = 12'd128;
//assign num_round  = 6'd31;
//assign num_chunk  = 6'd31;
//assign num_plane  = 2'd1;
//assign num_stride = 8'd4;

assign num_output = 4'd1;

// programmable parameters }}}

endmodule

// vim:foldmethod=marker:
//
