
`timescale 1ns/10ps

module i2sm_in (
input           clk         , 
input		resetn      , 
output reg[15:0]o_ld        ,	// left data
output reg[15:0]o_rd        ,   // right data
output reg      o_smp_we    ,   // sample write enable

input [15:0]	i_dc_value  ,
input [15:0]	i_level_th  ,

output reg	o_active    ,

output reg      o_bclk      ,
input           i_sd        ,
output          o_ws  
);

parameter DIV     = 26;
parameter GAIN    = 4;
parameter EN_DIFF = 0;

reg	[7:0]	clk_cnt;
reg	[5:0]	bit_cnt;
reg	[63:0]	shift_reg;

wire	[17:0]	w_l;
wire	[17:0]	w_r;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	clk_cnt <= 8'b0;
    else if(clk_cnt == DIV)
	clk_cnt <= 8'b0;
    else 
	clk_cnt <= clk_cnt + 8'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	bit_cnt <= 6'b0;
    else if(clk_cnt == DIV)
	bit_cnt <= bit_cnt + 6'd1;
end

assign o_ws = bit_cnt[5];

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	shift_reg <= 64'b0;
    else if(clk_cnt == (DIV/2))
	shift_reg <= {shift_reg[62:0], i_sd};
end

generate if(EN_DIFF == 1)
begin: g_on_en_diff
    reg	[2:0]	latch_d;

    reg	[17:0]	r_l_lat;
    reg	[17:0]	r_r_lat;

    reg	[17:0]	r_l_pre;
    reg	[17:0]	r_r_pre;

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    latch_d <= 3'b0;
	else
	    latch_d <= {latch_d[1:0], (clk_cnt == (DIV/2))};
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0) begin
	    r_l_lat <= 18'b0;
	    r_r_lat <= 18'b0;
	    r_l_pre <= 18'b0;
	    r_r_pre <= 18'b0;
	end else if(latch_d[0] && (bit_cnt == 6'd0)) begin
	    r_l_lat <= shift_reg[62:45] - r_l_pre ;
	    r_r_lat <= shift_reg[30:13] - r_r_pre ;
	    r_l_pre <= shift_reg[62:45];
	    r_r_pre <= shift_reg[30:13];
	end
    end

    assign w_l = r_l_lat;
    assign w_r = r_r_lat;
end
else begin
    assign w_l = shift_reg[62:45];
    assign w_r = shift_reg[30:13];
end
endgenerate

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) begin
	o_ld <= 16'b0;
	o_rd <= 16'b0;
    end else if((clk_cnt == DIV) && (bit_cnt == 6'd63)) begin
	if(GAIN == 2) begin
	    o_ld <= (w_l[17] == w_l[16]) ? w_l[16:1] : {w_l[17], {15{!w_l[17]}}} ;
	    o_rd <= (w_r[17] == w_r[16]) ? w_r[16:1] : {w_r[17], {15{!w_r[17]}}} ;
	end else if(GAIN == 16) begin
	    o_ld <= ({4{w_l[17]}} == w_l[16:13]) ? {w_l[13:0],2'b0} : {w_l[17], {15{!w_l[17]}}} ;
	    o_rd <= ({4{w_r[17]}} == w_r[16:13]) ? {w_r[13:0],2'b0} : {w_r[17], {15{!w_r[17]}}} ;
	end else if(GAIN == 8) begin
	    o_ld <= ({3{w_l[17]}} == w_l[16:14]) ? {w_l[14:0],1'b0} : {w_l[17], {15{!w_l[17]}}} ;
	    o_rd <= ({3{w_r[17]}} == w_r[16:14]) ? {w_r[14:0],1'b0} : {w_r[17], {15{!w_r[17]}}} ;
	end else if(GAIN == 4) begin
	    o_ld <= ({2{w_l[17]}} == w_l[16:15]) ? w_l[15:0] : {w_l[17], {15{!w_l[17]}}} ;
	    o_rd <= ({2{w_r[17]}} == w_r[16:15]) ? w_r[15:0] : {w_r[17], {15{!w_r[17]}}} ;
	end else if(GAIN == 0) begin // half
	    o_ld <= {w_l[17], w_l[17:3]};
	    o_rd <= {w_r[17], w_r[17:3]};
	end else begin
	    o_ld <= w_l[17:2];
	    o_rd <= w_r[17:2];
	end
    end
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_smp_we <= 1'b0;
    else 
	o_smp_we <= ((clk_cnt == DIV) && (bit_cnt == 6'd63));
end

wire	[15:0]	ld_rmdc;

assign ld_rmdc = o_ld - i_dc_value;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_active <= 1'b0;
    else 
	o_active <= ((!ld_rmdc[15]) && (ld_rmdc > i_level_th));
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_bclk <= 1'b0;
    else 
	o_bclk <= (clk_cnt >= (DIV/2));
end

endmodule
//================================================================================
// End of file
//================================================================================

// vim: ts=8 sw=4
