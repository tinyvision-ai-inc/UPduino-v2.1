
module ice40_himax_HP_clkgen (
input		i_oclk_in  ,
input           i_pclk_in  ,

input           i_init_done,
input           i_cam_vsync,
input           i_load_done,
input           i_ml_rdy   ,
input           i_vid_rdy  ,
input           i_mask_ovr ,

output reg   	o_init     ,
output          o_oclk     ,
output          o_clk      ,
output          o_pclk     ,
output          o_clk_init ,

output [1:0]    o_debug    ,

input		resetn     
);

parameter EN_CLKMASK    = 1'b1;
parameter EN_SINGLE_CLK = 1'b1;

parameter	[2:0]
	    S_WAIT_INIT    = 3'b000,
	    S_WAIT_FRAME   = 3'b001,
	    S_WAIT_VID     = 3'b010,
	    S_WAIT_ML_RUN  = 3'b011,
	    S_WAIT_ML_DONE = 3'b111,
	    S_WAIT_BUDGET  = 3'b110;

wire		g_pclk;
wire		g_clk;
wire		w_clk; // GB output
wire		g_clk_init;

reg 	[1:0]	vsync_d;
reg	[21:0]	pclk_cnt;
reg	[21:0]	vsync_period;
reg		pre_video;

reg	[1:0]	frame_cnt;
reg		frame_done;

always @(posedge i_pclk_in)
begin
    vsync_d = {vsync_d[0], i_cam_vsync};
end

always @(posedge i_pclk_in)
begin
    if(vsync_d == 2'b01)
	pclk_cnt <= 22'b0;
    else 
	pclk_cnt <= pclk_cnt + 22'd1;
end

always @(posedge i_pclk_in)
begin
    if(vsync_d == 2'b01)
	vsync_period <= pclk_cnt;
end

always @(posedge i_pclk_in)
begin
    if(pclk_cnt == 22'd0)
	pre_video <= 1'b0;
    else if(pclk_cnt == (vsync_period - 22'd2048))
	pre_video <= 1'b1;
end

always @(posedge i_pclk_in or negedge resetn)
begin
    if(resetn == 1'b0)
	frame_cnt <= 2'b0;
    else if((vsync_d == 2'b01) && frame_cnt != 2'b11)
	frame_cnt <= frame_cnt + 2'd1;
end

always @(posedge i_pclk_in or negedge resetn)
begin
    if(resetn == 1'b0)
	frame_done <= 1'b0;
    else
	frame_done <= (frame_cnt == 2'b11);
end

generate if(EN_CLKMASK == 1'b1)
begin: g_on_en_clkmask
    reg		init_mask;
    reg		core_mask;
    reg		vid_mask;
    reg		pre_video_lat;
    reg		vid_rdy_lat;
    reg		ml_rdy_lat;

    reg		vid_mask_pclk;

    reg	[2:0]	state;
    reg	[2:0]	nstate;

    always @(posedge o_oclk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    state <= S_WAIT_INIT;
	else
	    state <= nstate;
    end

    always @(*)
    begin
	case(state)
	    S_WAIT_INIT:
		nstate <= ((i_init_done == 1'b1) && (i_load_done == 1'b1)) ? S_WAIT_FRAME : S_WAIT_INIT;
	    S_WAIT_FRAME:
		nstate <= frame_done ? S_WAIT_BUDGET : S_WAIT_FRAME;
	    S_WAIT_VID:
		nstate <= vid_rdy_lat ? S_WAIT_ML_RUN : S_WAIT_VID;
	    S_WAIT_ML_RUN:
		nstate <= ml_rdy_lat ? S_WAIT_ML_RUN : S_WAIT_ML_DONE;
	    S_WAIT_ML_DONE:
		nstate <= ml_rdy_lat ? S_WAIT_BUDGET : S_WAIT_ML_DONE;
	    S_WAIT_BUDGET:
		nstate <= pre_video_lat ? S_WAIT_VID : S_WAIT_BUDGET;
	    default:
		nstate <= S_WAIT_INIT ;
	endcase
    end

    always @(posedge o_oclk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    init_mask <= 1'b0;
	else if(i_init_done)
	    init_mask <= 1'b1;
    end

    always @(posedge o_oclk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    core_mask <= 1'b0;
	else 
	    core_mask <= (state == S_WAIT_BUDGET);
    end

    always @(posedge o_oclk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    vid_mask <= 1'b0;
	else if(EN_SINGLE_CLK == 1'b1)
	    vid_mask <= (state == S_WAIT_BUDGET);
	else
	    vid_mask <= (state == S_WAIT_BUDGET) || (state == S_WAIT_ML_DONE);
    end

    always @(posedge o_oclk or negedge resetn)
    begin
	if(resetn == 1'b0) begin
	    pre_video_lat <= 1'b0;
	    vid_rdy_lat   <= 1'b0;
	    ml_rdy_lat    <= 1'b0;
	end else begin
	    pre_video_lat <= pre_video;
	    vid_rdy_lat   <= i_vid_rdy;
	    ml_rdy_lat    <= i_ml_rdy;
	end
    end

    always @(posedge i_pclk_in or negedge resetn)
    begin
	if(resetn == 1'b0)
	    vid_mask_pclk <= 1'b0;
	else
	    vid_mask_pclk <= vid_mask;
    end

    assign g_pclk     = i_pclk_in | vid_mask_pclk;
    assign g_clk      = o_oclk    | core_mask;
    assign g_clk_init = o_oclk    | init_mask;
    assign o_clk_init = g_clk_init;
    assign w_clk = g_clk;
    assign o_debug = 2'b00;

end 
else
begin
   // assign g_pclk     = i_pclk_in;
    assign g_pclk     = i_pclk_in | i_mask_ovr;
   // assign w_clk      = o_oclk   ;
    assign w_clk      = o_oclk | i_mask_ovr  ;
    //assign o_clk_init = o_oclk   ;
    assign o_clk_init = o_oclk | i_mask_ovr  ;
    assign o_debug = 2'b00; //{o_pclk, o_clk};
end
endgenerate

assign o_oclk = i_oclk_in;
assign o_pclk = g_pclk;

generate if(EN_SINGLE_CLK)
begin: g_on_en_single_clk
    assign o_clk = o_pclk;
end
else
begin
    assign o_clk = w_clk;
end
endgenerate

always @(posedge o_oclk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_init <= 1'b0;
    else 
	o_init <= 1'b1;
end

endmodule
