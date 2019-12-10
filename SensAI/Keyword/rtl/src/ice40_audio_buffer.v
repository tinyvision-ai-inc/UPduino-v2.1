
`timescale 1ns/10ps

// assume 8Ksps storing, total 16k sample
module ice40_audio_buffer (
input           clk         , 
input		resetn      , 
input           i_buffer_en , // enable buffering
input           i_burst_wr_en, // enable burst write (test mode)
input           i_rst_waddr , // reset write address
input           i_smp_we    ,
input [15:0]    i_smp_data  ,
input  [7:0]	i_blk_idx   , // start block index (64 sample offset)
input  [1:0]	i_stride    , // stride of sample (0: 1(8Ksps) 1: 2(4ksps) 2: 4(2ksps) 3:8(1ksps)
input  [2:0]	i_blk_len   , // # of samples per read, 0:128 1: 256 2:512 3:1024 4~: manual(use i_smp_rd signal)
input           i_smp_rd    ,
input           i_rd_req    , // request buffer for burst reading
output          o_rd_rdy    , // buffer is ready for burst reading
input  [15:0]	i_level_th  ,

// Debug DMA
input     [15:0]i_debug_wdata,
input     [15:0]i_debug_addr ,
input           i_debug_we   ,
output    [15:0]o_debug_rdata,

output reg      o_active    , // indicate active audio data
output [15:0]	o_dc_value  ,
output [7:0]    o_wr_blk_idx, // current write block index
output [15:0]	o_smp_data  ,
output reg      o_smp_valid

);

parameter ECP5_DEBUG = 1'b0;
parameter EN_DCBLK   = 1'b1;
parameter EN_MAX     = 1'b0;

reg	[13:0]	raddr;
reg     [14:0]  waddr; // current write address
wire	[13:0]	addr;
wire		we;
wire		re;
reg		buffering;
reg		round_flag;

reg		sample_valid;
reg	[15:0]	sample_lat;
wire	[15:0]	sample_lat_rmdc;

wire	[15:0]	w_smp_data;

reg	[9:0]	blk_cnt;

reg	[3:0]	raddr_inc;

reg	[13:0]	last_active_pt;
reg		burst_wr_en_d;

// state machine
parameter [1:0] 
	S_INIT      = 2'b00, // initialize, wait for sample or read request
	S_WRITE     = 2'b01, // write sample
	S_WRITE2    = 2'b11, // read before write sample
	S_READ      = 2'b10; // read one burst

reg     [1:0]   state;
reg     [1:0]   nstate;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	buffering <= 1'b0;
    else if(i_buffer_en == 1'b1)
	buffering <= 1'b1;
    else if(waddr[6:0] == 7'b0)
	buffering <= 1'b0;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	sample_valid <= 1'b0;
    else if(buffering == 1'b0)
	sample_valid <= 1'b0;
    else if(i_smp_we)
	sample_valid <= 1'b1;
    else if(state == S_WRITE)
	sample_valid <= 1'b0;
end

always @(posedge clk)
begin
    if(i_smp_we)
	sample_lat <= i_smp_data;
end

always @(posedge clk)
begin
    burst_wr_en_d <= i_burst_wr_en;
end

always @(posedge clk or negedge resetn) 
begin
    if(resetn == 1'b0) 
	state <= S_INIT;
    else               
	state <= nstate;
end

always @(*)
begin
    case(state)
	S_INIT:
	    nstate = i_rd_req ? S_READ : (sample_valid | i_burst_wr_en) ? (EN_DCBLK ? S_WRITE2 : S_WRITE) : S_INIT;
	S_WRITE2:
	    nstate = S_WRITE;
	S_WRITE:
	    nstate = i_burst_wr_en ? S_WRITE : S_INIT;
	S_READ:
	    nstate = (((blk_cnt == 10'd0) && (!i_blk_len[2])) || (o_smp_valid &&  (!i_smp_rd))) ? S_INIT : S_READ;
	default:
	    nstate = S_INIT;
    endcase
end

assign o_rd_rdy = (state == S_READ);

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	waddr <= 15'b0;
    else if(i_rst_waddr == 1'b1)
	waddr <= 15'b0;
    else if(we)
	waddr <= waddr + 15'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	blk_cnt <= 10'd0;
    else if(state == S_READ)
	blk_cnt <= blk_cnt - 10'd1;
    else case (i_blk_len)
	3'd0: 
	    blk_cnt <=  10'd127;
	3'd1: 
	    blk_cnt <=  10'd255;
	3'd2: 
	    blk_cnt <=  10'd511;
	3'd3: 
	    blk_cnt <=  10'd1023;
	default:
	    blk_cnt <=  10'd0;
    endcase
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	raddr_inc <= 4'd0;
    else if(state == S_INIT) case(i_stride)
	2'd1:    raddr_inc <= 4'd2;
	2'd2:    raddr_inc <= 4'd4;
	2'd3:    raddr_inc <= 4'd8;
	default: raddr_inc <= 4'd1;
    endcase
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	raddr <= 14'd0;
    else if((state == S_READ) && re)
	raddr <= raddr + {10'd0, raddr_inc};
    else 
	raddr <= {i_blk_idx, 6'b0};
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_smp_valid <= 1'b0;
    else
	o_smp_valid <= (state == S_READ) && re;
end

assign sample_lat_rmdc = sample_lat - o_dc_value;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_active <= 1'b0;
    else if((EN_DCBLK == 1'b1) && (round_flag == 1'b0))
	o_active <= 1'b1;
    else if(state == S_WRITE) begin
	if ((!sample_lat_rmdc[15]) && (sample_lat_rmdc > i_level_th))
	    o_active <= 1'b1;
	else if (last_active_pt == waddr[13:0])
	    o_active <= 1'b0;
    end
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	last_active_pt <= 14'b0;
    else if((state == S_WRITE) && (!sample_lat_rmdc[15]) && (sample_lat_rmdc > i_level_th))
	last_active_pt <= waddr[13:0];
end

assign addr = ((state == S_WRITE) || (state == S_WRITE2)) ? waddr[13:0] : raddr;
assign we   = (state == S_WRITE) & (!burst_wr_en_d | sample_valid) ;
assign re   = ((state == S_READ) && ((!i_blk_len[2]) | i_smp_rd)) || (state == S_WRITE2) ;

assign o_wr_blk_idx = waddr[13:6];

generate if(EN_DCBLK == 1'b1)
begin: g_en_dcblk_on
    reg	[31:0]	accum;

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    round_flag <= 1'b0;
	else if(i_rst_waddr)
	    round_flag <= 1'b0;
	else if(waddr[14])
	    round_flag <= 1'b1;
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    accum <= 32'b0;
	else if(i_rst_waddr)
	    accum <= 32'b0;
	else if(round_flag && (state == S_WRITE))
	    accum <= accum + {{16{sample_lat[15]}}, sample_lat } - {{16{w_smp_data[15]}}, w_smp_data};
	else if(state == S_WRITE)
	    accum <= accum + {{16{sample_lat[15]}}, sample_lat };
    end

    //assign o_dc_value = round_flag ? accum[30:15] : 16'b0;
    assign o_dc_value = round_flag ? accum[29:14] : 16'b0;
end
else
begin
    assign o_dc_value = 16'b0;
end
endgenerate

assign o_smp_data = w_smp_data - o_dc_value;

generate if(EN_MAX == 1'b1)
begin: g_on_en_max
    reg	[7:0]	max;
    reg	[7:0]	min;

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    max <= 8'd0;
	else if(we) begin
	    if(waddr[6:0] == 7'b0)
		max <= sample_lat[15] ? 8'd0 : sample_lat[15:8];
	end
    end
end
else begin // disable maximum value tracking
end

endgenerate

// memory
generate if(ECP5_DEBUG == 1'b1)
begin: g_ecp5_debug_on
   wire	[13:0] debug_addr_wrap;
   wire	[15:0]	w_debug_rdata;

   assign debug_addr_wrap = waddr[13:0] + i_debug_addr[13:0];

   assign o_debug_rdata = w_debug_rdata - o_dc_value;

   tdpram_32k_16 u_tdpram(
	.DataInA (i_debug_wdata),
	.DataInB (sample_lat   ),
	.AddressA(debug_addr_wrap),
	.AddressB(addr         ),
	.ClockA  (clk          ),
	.ClockB  (clk          ),
	.ClockEnA(1'b1         ),
	.ClockEnB(1'b1         ),
	.ByteEnA (2'b11        ),
	.ByteEnB (2'b11        ),
	.WrA     (i_debug_we   ),
	.WrB     (we           ),
	.ResetA  (!resetn      ),
	.ResetB  (!resetn      ),
	.QA      (w_debug_rdata),
	.QB      (w_smp_data   )
    );

end else begin
    wire		ce;

    assign ce = (re | we);

`ifdef ICECUBE
    SB_SPRAM256KA u_spram16k_16_0 (
	.DATAIN     (sample_lat     ),
	.ADDRESS    (addr           ),
	.MASKWREN   (4'b1111        ),
	.WREN       (we             ),
	.CHIPSELECT (ce             ),
	.CLOCK      (clk            ),
	.STANDBY    (1'b0           ),
	.SLEEP      (1'b0           ),
	.POWEROFF   (1'b1           ),
	.DATAOUT    (w_smp_data     )
    );

`else // Radiant
    SP256K u_spram16k_16_0 (
	.AD       (addr           ),  // I
	.DI       (sample_lat     ),  // I
	.MASKWE   (4'b1111        ),  // I
	.WE       (we             ),  // I
	.CS       (ce             ),  // I
	.CK       (clk            ),  // I
	.STDBY    (1'b0           ),  // I
	.SLEEP    (1'b0           ),  // I
	.PWROFF_N (1'b1           ),  // I
	.DO       (w_smp_data     )   // O
    );
`endif
end
endgenerate

endmodule
//================================================================================
// End of file
//================================================================================

// vim: ts=8 sw=4
