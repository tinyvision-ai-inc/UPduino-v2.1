module audio_post (
input            clk       , // 
input            i_init    , // 
input            i_we      , // 
input     [15:0] i_dout    , // 
output reg[15:0] o_diff    , // diff between 1st and 2nd max value
output reg[2:0]  o_max_idx , // index of maxium value, 111 is invalid 
output reg       o_validp  , // one cycle pulse for further processing
input            resetn
);

reg	[2:0]	r_max_idx;
reg	[15:0]	r_1st_max_value;
reg	[15:0]	r_2nd_max_value;

reg	[2:0]	idx_cnt;
reg	[2:0]	r_we_d;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	r_we_d <= 2'b0;
    else
	r_we_d <= {r_we_d[1:0], i_we};
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	idx_cnt <= 3'b0;
    else if(i_init)
	idx_cnt <= 3'b0;
    else if(i_we)
	idx_cnt <= idx_cnt + 3'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) begin
	r_1st_max_value <= 16'b0; // consider positive value only for max
	r_2nd_max_value <= 16'b0;
	r_max_idx       <= 3'b111; // invalid idx
    end else if(i_init == 1'b1) begin
	r_1st_max_value <= 16'b0; // consider positive value only for max
	r_2nd_max_value <= 16'b0;
	r_max_idx       <= 3'b111; // invalid idx
    end else if(i_we && (!i_dout[15]) && (r_1st_max_value < i_dout)) begin
	r_1st_max_value <= i_dout;
        r_2nd_max_value <= r_1st_max_value;
	r_max_idx       <= idx_cnt;
    end else if(i_we && (!i_dout[15]) && (r_2nd_max_value < i_dout)) begin
        r_2nd_max_value <= i_dout;
    end
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) begin
	o_diff    <= 16'b0;
	o_max_idx <= 3'b111;
    end else if(r_we_d[2:1] == 2'b10) begin // falling edge
	o_diff    <= (r_1st_max_value - r_2nd_max_value);
	o_max_idx <= r_max_idx;
    end
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_validp <= 1'b0;
    else
	o_validp <= (r_we_d[2:1] == 2'b10);
end

endmodule
