//================================================================================
// Project : ML - Human Detection Post Processing
//
// File    : HP_Post_Processing.v
// Document: Post processing of human detection 
// Language: Verilog HDL
// Author  : Hoon Choi
// Date    : Apr. 20, 2018
//================================================================================
// History :
//
// Apr. 20, 2018 - Started from the post processing for speed signal detection
// Sept. 10, 2018 - Changed name for Human Presence Demo (kw)
//================================================================================

//================================================================================
//================================================================================
//================================================================================
module HP_Post_Processing #(parameter num_layer=4) (
    input                clk,              // 
    input                init,             // Active high init; one cycle pulse when ML engine starts
    input                i_we,             // Active high write enable/valid of output data
    input      [ 15 : 0] i_dout,           // 16b data (blob/activation) from the last layer
    input      [ 15 : 0] i_offset,
    output               comp_done,        // Computation is done (stay high till init comes in)
    output reg [ 15 : 0] max_val,          // max value (12b fraction)
    output reg [  8 : 0] cnt_val
);
    //================================================================================
    // Internal signals
    //================================================================================
    reg    [15 : 0] val;                  //
    reg             valid;                //
    reg    [11 : 0] cnt_384;              // 6*8*8 or 6*4*4

    wire   [16 : 0] w_add;

    assign w_add = {i_dout[15], i_dout} + {1'b0, i_offset};

    //================================================================================
    //================================================================================
    //================================================================================
    always @(posedge clk) // Just a pipeline stage for timing
        if(init) begin
	    valid <=  1'b0;
	    val   <= 16'b0;
	end else begin
	    valid <= i_we;
	    val   <= (w_add[16:15] == 2'b10) ? 16'h7fff : w_add[15:0];
	end

    always @(posedge clk)
        if(init) begin
	    max_val <= 16'h80ff; // -32513
	    cnt_384 <= 12'd0;
	    cnt_val <= 9'd0;
	end else if(valid) begin
	    if(fixed_lte(val, max_val)) begin
		max_val <= val;
	    end
	    cnt_384 <= cnt_384 + 1;
	    cnt_val <= cnt_val + (val[15] ? 9'd0 : 9'd1);
	end

    assign comp_done = cnt_384 == (num_layer == 4 ? 12'd384 : 12'd96);

    //================================================================================
    // Fixed point comparison - left value >= right value
    //================================================================================
    function fixed_lte;
        input [15 : 0] lval;
	input [15 : 0] rval;
    begin
        fixed_lte = (!lval[15] && rval[15]                                  ) || // pos >= neg
	            ( lval[15] ~^ rval[15] ? lval[14:0] >= rval[14:0] : 1'b0);   // same polarity, large is larger
		                                                                 // diff polarity (neg, pos)
    end endfunction
endmodule
//================================================================================
// End of file
//================================================================================
