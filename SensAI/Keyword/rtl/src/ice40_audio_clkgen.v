
module ice40_audio_clkgen (
input		i_clk_in   ,

input           i_init_done,
input           i_load_done,
input           i_active   ,
input           i_done_fb  ,
input           i_done_ml  ,

output          o_start_fb ,
output          o_start_ml ,

output reg   	o_init     ,
output          o_clk_aon  ,
output          o_clk      ,

input		resetn     
);

parameter EN_CLKMASK    = 1'b1;
parameter DIV           = 1;

parameter	[2:0]
                S_WAIT_INIT    = 3'b000,
		S_WAIT_ACTIVE  = 3'b001,
		S_WAIT_FB_RUN  = 3'b010,
		S_WAIT_FB_DONE = 3'b011,
		S_WAIT_ML_RUN  = 3'b111,
		S_WAIT_ML_DONE = 3'b110,
		S_WAIT_BUDGET  = 3'b100;

wire		g_clk;
wire		w_clk; // GB output

wire		w_gbuf_in;

generate if(EN_CLKMASK == 1'b1)
begin: g_on_en_clkmask
    reg		core_mask;

    reg		done_fb_lat;
    reg		done_ml_lat;
    reg		init_done_lat;
    reg		load_done_lat;

    reg		r_start_fb_clk;
    reg		r_start_fb_clk27;
    reg		r_start_ml_clk;
    reg		r_start_ml_clk27;

    reg	[2:0]	state;
    reg	[2:0]	nstate;

    always @(posedge o_clk_aon or negedge resetn)
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
		nstate <= ((init_done_lat == 1'b1) && (load_done_lat == 1'b1) && (done_ml_lat == 1'b1)) ? S_WAIT_ACTIVE : S_WAIT_INIT;
	    S_WAIT_ACTIVE:
		nstate <= i_active ? S_WAIT_FB_RUN : S_WAIT_ACTIVE;
	    S_WAIT_FB_RUN:
		nstate <= done_fb_lat ? S_WAIT_FB_RUN : S_WAIT_FB_DONE;
	    S_WAIT_FB_DONE:
		nstate <= done_fb_lat ? S_WAIT_ML_RUN : S_WAIT_FB_DONE;
	    S_WAIT_ML_RUN:
		nstate <= done_ml_lat ? S_WAIT_ML_RUN : S_WAIT_ML_DONE;
	    S_WAIT_ML_DONE:
		nstate <= done_ml_lat ? S_WAIT_BUDGET : S_WAIT_ML_DONE;
	    S_WAIT_BUDGET:
		nstate <= i_active ? S_WAIT_FB_RUN : S_WAIT_ACTIVE;
	    default:
		nstate <= S_WAIT_INIT ;
	endcase
    end

    always @(posedge o_clk_aon or negedge resetn)
    begin
	if(resetn == 1'b0)
	    core_mask <= 1'b0;
	else 
	    core_mask <= (state == S_WAIT_ACTIVE);
    end

    always @(posedge o_clk_aon or negedge resetn)
    begin
	if(resetn == 1'b0) begin
	    done_fb_lat   <= 1'b0;
	    done_ml_lat   <= 1'b0;
	    init_done_lat <= 1'b0;
	    load_done_lat <= 1'b0;
	end else begin
	    done_fb_lat   <= i_done_fb;
	    done_ml_lat   <= i_done_ml;
	    init_done_lat <= i_init_done;
	    load_done_lat <= i_load_done;
	end
    end

    always @(posedge o_clk_aon or negedge resetn)
    begin
	if(resetn == 1'b0) begin
	    r_start_fb_clk27 <= 1'b0;
	    r_start_ml_clk27 <= 1'b0;
	end else begin
	    r_start_fb_clk27 <= (state == S_WAIT_FB_RUN) || (state == S_WAIT_FB_DONE) ; 
	    r_start_ml_clk27 <= (state == S_WAIT_ML_RUN);
	end
    end

    always @(posedge o_clk or negedge resetn)
    begin
	if(resetn == 1'b0) begin
	    r_start_fb_clk <= 1'b0;
	    r_start_ml_clk <= 1'b0;
	end else begin
	    r_start_fb_clk <= r_start_fb_clk27;
	    r_start_ml_clk <= r_start_ml_clk27;
	end
    end

    assign o_start_fb = r_start_fb_clk;
    assign o_start_ml = r_start_ml_clk;

    assign g_clk      = o_clk_aon | core_mask;

`ifdef ICECUBE
    SB_GB u_gb_clk(
	.USER_SIGNAL_TO_GLOBAL_BUFFER(g_clk   ),
	.GLOBAL_BUFFER_OUTPUT        (o_clk   )
    );
`else // Radiant
    assign o_clk = g_clk;
`endif

end 
else
begin
    assign o_clk      = o_clk_aon   ;

    assign o_start_fb = i_done_ml & i_load_done;
    assign o_start_ml = i_done_fb;
end
endgenerate

assign w_gbuf_in = i_clk_in;

`ifdef ICECUBE
SB_GB u_gb_clk (
    .USER_SIGNAL_TO_GLOBAL_BUFFER(w_gbuf_in   ),
    .GLOBAL_BUFFER_OUTPUT        (o_clk_aon   )
);
`else // Radiant
assign o_clk_aon = w_gbuf_in;
`endif

always @(posedge o_clk_aon or negedge resetn)
begin
    if(resetn == 1'b0)
	o_init <= 1'b0;
    else 
	o_init <= 1'b1;
end

endmodule
