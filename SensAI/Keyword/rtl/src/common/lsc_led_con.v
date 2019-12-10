`timescale 1ns / 100ps

module lsc_led_con(
input		clk     , 
input           resetn  ,
input           i_enable,
input           i_fire  ,
output          o_on
);

parameter CLK_FREQ     = 27000;
parameter ON_TIME      = 300;
parameter OFF_TIME     = 500;
parameter OFF_OVERRIDE = 0;

reg	[31:0]	cnt;
reg		r_on;

reg		enable_sync;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	enable_sync <= 1'b0;
    else
	enable_sync <= i_enable;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	cnt <= 32'b0;
    else if(enable_sync == 1'b0)
	cnt <= 32'b0;
    else if((r_on == 1'b0) && i_fire && (cnt == 32'b0))
	cnt <= CLK_FREQ * ON_TIME;
    else if((r_on == 1'b1) && (cnt == 32'd0))
	cnt <= CLK_FREQ * OFF_TIME;
    else if((r_on == 1'b0) && (!i_fire) && (OFF_OVERRIDE == 1))
	cnt <= 32'b0;
    else if(cnt != 32'd0)
	cnt <= cnt - 32'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	r_on <= 1'b0;
    else if(enable_sync == 1'b0)
	r_on <= 1'b0;
    else if((r_on == 1'b0) && i_fire && (cnt == 32'b0))
	r_on <= 1'b1;
    else if((r_on == 1'b1) && (cnt == 32'd0))
	r_on <= 1'b0;
end

assign o_on = r_on & i_enable;

endmodule
