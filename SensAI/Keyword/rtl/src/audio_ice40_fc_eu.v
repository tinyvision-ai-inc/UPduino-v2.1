
module audio_ice40_fc_eu (
// Global inputs
input             clk          ,
input             resetn       ,

// control
input      [5:0]  i_bias_addr  ,
input             i_init_bias  ,
input		  i_shift      , // shift cascade reg

// Data path
input             i_run        , // 
input      [15:0] i_din        , // data input
input             i_din_val    , // data input valid
input      [15:0] i_weight     , // weight input

// cascade read out
input      [15:0] i_cascade_in ,
output reg [15:0] o_cascade_out  // partial sum out
);

parameter ECP5_DEBUG = 0;
parameter BYTE_MODE  = "DISABLE";

reg	[15:0]	din_latch;
reg	[15:0] 	weight_latch;
reg	[2:0]	valid_d;
reg	[1:0]	run_d;

wire	[39:0]	w_bias_ext;
wire	[15:0]  r_bias;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	run_d <= 2'b0;
    else 
	run_d <= {run_d[0], i_run};
end

always @(posedge clk)
begin
    if(i_run) begin
	din_latch    <= i_din_val ? i_din : 16'b0;
	weight_latch <= i_weight;
	valid_d      <= {valid_d[1:0], i_din_val};
    end else begin
	din_latch    <= 16'b0;
	weight_latch <= 16'b0;
	valid_d      <= 3'b0;
    end
end

reg	[39:0]	accu;
wire	[31:0]	mult;

generate if(ECP5_DEBUG == 1)
begin: g_on_ecp5_debug
    mul u_mul16 (
	.Clock (clk         ), 
	.ClkEn (1'b1        ), 
	.Aclr  (~resetn     ), 
	.DataA (din_latch   ), 
	.DataB (weight_latch), 
	.Result(mult        )
    );
end
else begin
    ice40_mul16_reg u_mul16 (
	.Clock (clk         ), 
	.ClkEn (1'b1        ), 
	.Aclr  (~resetn     ), 
	.DataA (din_latch   ), 
	.DataB (weight_latch), 
	.Result(mult        )
    );
end
endgenerate

always @(posedge clk)
begin
    if(i_init_bias)
	accu <= w_bias_ext;
    else if(valid_d[1])
	accu <= accu + {{8{mult[31]}}, mult};
end

wire		overflow;

assign overflow = (BYTE_MODE == "DISABLE") ?  ((|accu[39:30]) != 1'b0) && ((&accu[39:30]) != 1'b1) :
                                              ((|accu[39:26]) != 1'b0) ; // unsigned

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_cascade_out <= 16'b0;
    else if(run_d == 2'b10)
	// Apply relu
	// input 0.15, weight 5.10 --> accu 6.25, output 5.10(signed 16bit) / 1.7(unsigned)
	o_cascade_out <= accu[39] ? 16'b0 : overflow ? {accu[39], {15{~accu[39]}}} : 
	                 (BYTE_MODE == "DISABLE") ? accu[30:15] : {8'b0, accu[25:18]};
    else if(i_shift)
	o_cascade_out <= i_cascade_in;
end

assign r_bias = 16'b0; // preliminary 0 bias assumed
assign w_bias_ext = { {14{r_bias[15]}}, r_bias, 10'b0};

endmodule
