// =============================================================================
//                           COPYRIGHT NOTICE
// Copyright 2011 (c) Lattice Semiconductor Corporation
// ALL RIGHTS RESERVED
// This confidential and proprietary software may be used only as authorised by
// a licensing agreement from Lattice Semiconductor Corporation.
// The entire notice above must be reproduced on all authorized copies and
// copies may only be made to the extent permitted by a licensing agreement from
// Lattice Semiconductor Corporation.
//
// Lattice Semiconductor Corporation        TEL : 1-800-Lattice (USA and Canada)
// 5555 NE Moore Court                            408-826-6000 (other locations)
// Hillsboro, OR 97124                     web  : http://www.latticesemi.com/
// U.S.A                                   email: techsupport@lscc.com
// =============================================================================

`timescale 1 ns / 100 ps

module ice40_himax_video_process_64 (
input		clk           , 
input		pclk          , 
input		resetn        , 

// Camera interface
input           i_cam_de      ,
input           i_cam_vsync   ,
input  [3:0]    i_cam_data    ,

output reg[7:0]	o_width       ,
output reg[7:0]	o_height      ,

// video out for debugging (clk domain)
input     [2:0] i_frame_sel   ,
input           i_frame_req   ,
output          o_subpix_vld  ,
output    [7:0] o_subpix_out  ,

// ML engine interface
input           i_rd_rdy      ,
output reg      o_rd_done     ,

output reg	o_we          ,
output reg[15:0]o_waddr       ,
output 	[15:0]	o_dout        
);

parameter SUBPIX  = "565";

// dynamic parameter {{{
reg	[9:0]	sb_l;
reg	[9:0]	sb_r;
reg	[8:0]	vb_u;
reg	[8:0]	vb_b;

reg		block_size;
// dynamic parameter }}}

// counters & masks {{{
reg		de_d;
reg	[3:0]	vsync_d;

reg	[9:0]	pcnt; // bit[0] indicate upper/lower nibble (0: upper nibble, 1: lower nibble) (max: 324 * 2 = 648)
reg	[8:0]	lcnt; // line counter (max: 324)

reg	[1:0]	bpcnt; // block pixel counter
wire	[1:0]	blcnt; // block line counter

wire	[1:0]	bmask; // block mask

reg	[6:0]	rbcnt; // read block counter (block index)
wire	[6:0]	wbcnt; // write block counter (block index)

reg		hmask;
reg		vmask;

reg	[3:0]	cam_data_d;
reg	[3:0]	cam_data_d2;

wire	[7:0]	raw_l; // latch R/G/B component value

wire	[7:0]	r_l; // masked value of raw_l during red time
wire	[7:0]	g_l; // masked value of raw_l during green time
wire	[7:0]	b_l; // masked value of raw_l during blue time

reg	[2:0]	vsync_clk;
reg		ro_re;
reg	[7:0]	ro_raddr;
wire	[31:0]	ro_rdata;
reg	[7:0]	ro_waddr;
wire	[31:0]	ro_wdata;

reg		end_line_toggle;
reg		end_line_toggle_clk;
reg		end_line_toggle_d_clk;

reg		running;
reg		running_d;

always @(posedge pclk)
begin
    de_d         <= i_cam_de;
    vsync_d      <= {vsync_d[2:0], !i_cam_vsync};
    cam_data_d   <= i_cam_data;
    cam_data_d2  <= cam_data_d;
end

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0)
	end_line_toggle <= 1'b0;
    else if(!vmask)
	end_line_toggle <= 1'b0;
    else if(({de_d, i_cam_de} == 2'b10) && (blcnt[0] && (blcnt[1] | (~block_size))))
	end_line_toggle <= ~end_line_toggle;
end

always @(posedge pclk)
begin
    if(i_cam_de)
	pcnt <= pcnt + 10'd1;
    else 
	pcnt <= 10'd0;
end

always @(posedge pclk)
begin
    case(i_frame_sel)
	3'd0: begin // 0
	    sb_l <= 10'd71;
	    sb_r <= 10'd327;
	    //vb_u <= 9'd32;
	    //vb_b <= 9'd160;
	    vb_u <= 9'd96;
	    vb_b <= 9'd224;

	    block_size <= 1'b0;
	end
	3'd1: begin 
	    sb_l <= 10'd327;
	    sb_r <= 10'd583;
	    //vb_u <= 9'd32;
	    //vb_b <= 9'd160;
	    vb_u <= 9'd96;
	    vb_b <= 9'd224;

	    block_size <= 1'b0;
	end
	3'd2: begin
	    sb_l <= 10'd71;
	    sb_r <= 10'd327;
	    vb_u <= 9'd160;
	    vb_b <= 9'd288;

	    block_size <= 1'b0;
	end
	3'd3: begin 
	    sb_l <= 10'd327;
	    sb_r <= 10'd583;
	    vb_u <= 9'd160;
	    vb_b <= 9'd288;

	    block_size <= 1'b0;
	end
	3'd4: begin // Center zoom
	    sb_l <= 10'd199;
	    sb_r <= 10'd455;
	    vb_u <= 9'd96;
	    vb_b <= 9'd224;

	    block_size <= 1'b0;
	end
	default: begin // full
	    sb_l <= 10'd71;
	    sb_r <= 10'd583;
	    vb_u <= 9'd32;
	    vb_b <= 9'd288;

	    block_size <= 1'b1;
	end
    endcase
end

assign bmask = {block_size, 1'b1};

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0)
	hmask <= 1'b0;
    else if(pcnt == sb_l)
	hmask <= 1'b1;
    else if(pcnt == sb_r)
	hmask <= 1'b0;
end

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0)
	vmask <= 1'b0;
    else if(lcnt == vb_u)
	vmask <= 1'b1;
    else if(lcnt == vb_b)
	vmask <= 1'b0;
end

always @(posedge pclk)
begin
    if({de_d, i_cam_de} == 2'b10)
	o_width <= pcnt[7:0];
end

always @(posedge pclk)
begin
    if({de_d, i_cam_de} == 2'b10)
	lcnt <= lcnt + 9'd1;
    else if(vsync_d[3])
	lcnt <= 9'b0;
end

always @(posedge pclk)
begin
    if(vsync_d[3:2] == 2'b01)
	o_height <= lcnt[7:0];
end

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0)
	bpcnt <= 2'd0;
    else if(vsync_d[3] || (!hmask) || (!vmask))
	bpcnt <= 2'd0;
    else if(pcnt[0])
	bpcnt <= bpcnt + 2'd1;
end

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0)
	rbcnt <= 7'b0;
    else if((!hmask) || (!vmask) || vsync_d[3])
	rbcnt <= 7'b0;
    else if(((bpcnt & bmask) == 2'd0) && pcnt[0])
	rbcnt <= rbcnt + 7'd1;
end

assign wbcnt = rbcnt - 7'd1;

assign blcnt = lcnt[1:0];

// counters & masks }}}

// downscale {{{

wire		c_we ;

wire	[9:0]	r_rdata;
reg	[9:0]	r_accu; 

wire	[10:0]	g_rdata;
reg	[10:0]	g_accu; 

wire	[9:0]	b_rdata;
reg	[9:0]	b_accu;

wire	[7:0]	r_mod;
wire	[7:0]	g_mod;
wire	[7:0]	b_mod;

wire	[31:0]	rdata;
wire	[31:0]	wdata;

assign wdata = {1'b0, r_accu[9:0], g_accu[10:0], b_accu[9:0]};

assign r_rdata = rdata[30:21];
assign g_rdata = rdata[20:10];
assign b_rdata = rdata[ 9: 0];

// accumulator buffer
dpram256x32 u_ram256x32_accu0 (
    .wr_clk_i   (pclk         ),
    .rd_clk_i   (pclk         ),
    .wr_clk_en_i(1'b1         ),
    .rd_en_i    (1'b1         ),
    .rd_clk_en_i(1'b1         ),
    .wr_en_i    (c_we         ),
    .wr_data_i  (wdata        ), 
    .wr_addr_i  ({1'b0, wbcnt}),
    .rd_addr_i  ({1'b0, rbcnt}),
    .rd_data_o  (rdata        )
);

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0) begin
	r_accu <= 12'b0;
	g_accu <= 13'b0;
	b_accu <= 12'b0;
    end else if(hmask && vmask && ((bpcnt & bmask) == 2'd0) && (!pcnt[0])) begin // first horizontal pixel
	r_accu <= (((blcnt & bmask) == 2'd0) ? 10'b0 : r_rdata);
	g_accu <= (((blcnt & bmask) == 2'd0) ? 11'b0 : g_rdata);
	b_accu <= (((blcnt & bmask) == 2'd0) ? 10'b0 : b_rdata);
    end else if(pcnt[0] && hmask && vmask) begin
	r_accu <= r_accu + {2'b0, r_l};
	g_accu <= g_accu + {3'b0, g_l};
	b_accu <= b_accu + {2'b0, b_l};
    end
end

assign raw_l = {cam_data_d, cam_data_d2};

assign r_l = ({pcnt[1],lcnt[0]} == 2'b11) ? raw_l : 8'b0;
assign g_l = (({pcnt[1],lcnt[0]} == 2'b10) || ({pcnt[1],lcnt[0]} == 2'b01)) ? raw_l : 8'b0;
assign b_l = ({pcnt[1],lcnt[0]} == 2'b00) ? raw_l : 8'b0;

wire	pix_wr;

assign c_we = (wbcnt != 7'h7f) && ((bpcnt & bmask) == 2'd0) && (!pcnt[0]);
assign pix_wr = blcnt[0] && (blcnt[1] | (~block_size)) && c_we;

always @(posedge pclk or negedge resetn)
begin
    if(resetn == 1'b0)
	ro_waddr <= 8'd0;
    else if(!de_d)
	ro_waddr <= 8'd0;
    else if(pix_wr)
	ro_waddr <= ro_waddr + 8'd1;
end

assign r_mod = block_size ? r_accu[9:2] : r_accu[7:0];
assign g_mod = block_size ? g_accu[10:3] : g_accu[8:1];
assign b_mod = block_size ? (b_accu[9] ? 8'hff : b_accu[8:1]) : (b_accu[7] ? 8'hff : {b_accu[6:0], 1'b0});

assign ro_wdata = {8'b0, r_mod, g_mod, b_mod};

// downscale }}}

// readout {{{
reg	[1:0]	color_sel;   // 2'b11 for idle wait
reg	[1:0]	color_sel_d; // one cycle delay of color_sel

wire	[7:0]	sel_channel;

reg	[11:0]	r_waddr00;
reg	[11:0]	r_waddr01;
reg	[12:0]	r_waddr10;

always @(posedge clk)
begin
    vsync_clk             <= {vsync_clk[1:0], vsync_d[0]};
    color_sel_d           <= color_sel;
    running_d             <= running;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) begin
	end_line_toggle_clk   <= 1'b0;
	end_line_toggle_d_clk <= 1'b0;
    end else if(vsync_clk) begin
	end_line_toggle_clk   <= 1'b0;
	end_line_toggle_d_clk <= 1'b0;
    end else begin
	end_line_toggle_clk   <= end_line_toggle;
	end_line_toggle_d_clk <= end_line_toggle_clk;
    end
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	running <= 1'b0;
    else if(vsync_clk[0] == 1'b1)
	running <= (i_rd_rdy == 1'b1);
    else if((color_sel == 2'b10) && (r_waddr10[12]))
	running <= 1'b0;
end

always @(posedge clk)
begin
    if(vsync_clk[0] == 1'b1)
	o_waddr <= 16'b0;
    else case(color_sel_d)
	2'b00:   o_waddr <= {4'h0, r_waddr00[11:0]};
	2'b01:   o_waddr <= {4'h1, r_waddr01[11:0]};
	2'b10:   o_waddr <= {4'h2, r_waddr10[11:0]};
	default: o_waddr <= 16'd0;
    endcase
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	ro_raddr <= 8'd0;
    else if(running == 1'b0)
	ro_raddr <= 8'd0;
    else if((color_sel != color_sel_d) || (color_sel == 2'b11))
	ro_raddr <= 8'd0;
    else 
	ro_raddr <= ro_raddr + 8'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	color_sel <= 2'b11;
    else if(running == 1'b0)
	color_sel <= 2'b11;
    else if((end_line_toggle_clk != end_line_toggle_d_clk) && (running == 1'b1))
	color_sel <= 2'b00;
    else if((color_sel != 2'b11) && (ro_raddr == 8'd64))
	color_sel <= color_sel + 2'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	ro_re <= 1'b0;
    else if(running == 1'b0)
	ro_re <= 1'b0;
    else if((color_sel != color_sel_d) && (color_sel != 2'b11))
	ro_re <= 1'b1;
    else if(ro_raddr == 8'd63)
	ro_re <= 1'b0;
end

always @(posedge clk)
begin
    o_we <= ro_re;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	r_waddr00 <= 12'b0;
    else if(running == 1'b0)
	r_waddr00 <= 12'b0;
    else if((color_sel_d == 2'b00) && (ro_re == 1'b1))
	r_waddr00 <= r_waddr00 + 12'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	r_waddr01 <= 12'b0;
    else if(running == 1'b0)
	r_waddr01 <= 12'b0;
    else if((color_sel_d == 2'b01) && (ro_re == 1'b1))
	r_waddr01 <= r_waddr01 + 12'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	r_waddr10 <= 13'b0;
    else if(running == 1'b0)
	r_waddr10 <= 13'b0;
    else if((color_sel_d == 2'b10) && (ro_re == 1'b1))
	r_waddr10 <= r_waddr10 + 13'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	o_rd_done <= 1'b0;
    else if({running_d, running} == 2'b10)
	o_rd_done <= 1'b1;
    else if((i_rd_rdy == 1'b0) || vsync_clk[0])
	o_rd_done <= 1'b0;
end

assign sel_channel = (color_sel_d == 2'b10) ? ro_rdata[23:16] :
                     (color_sel_d == 2'b01) ? ro_rdata[15: 8] : ro_rdata[ 7:0];

//assign o_dout = ({3'b0, sel_channel, 5'b0} - 16'd4096);
assign o_dout = ({4'b0, sel_channel, 4'b0} - 16'd2048);

// readout line buffer
dpram256x32 u_ram256x32_ro (
    .wr_clk_i   (pclk     ),
    .rd_clk_i   (clk      ),
    .wr_clk_en_i(1'b1     ),
    .rd_en_i    (ro_re    ),
    .rd_clk_en_i(1'b1     ),
    .wr_en_i    (pix_wr   ),
    .wr_data_i  (ro_wdata ),
    .wr_addr_i  (ro_waddr ),
    .rd_addr_i  (ro_raddr ),
    .rd_data_o  (ro_rdata )
);

// readout }}}

// frame out {{{

generate if(SUBPIX != "NONE")
begin: g_on_frame_out
    reg		frame_req_l;
    reg		vsync_re_clk;
    reg		vsync_fe_clk;
    reg		frame_reading;
    reg		pix_vld_tg_pclk;
    reg	[23:0]	pix_lat_pclk;

    reg	[2:0]	pix_vld_tg_clk;
    reg	[23:0]	pix_lat_clk;

    reg	[1:0]	sub_pix_cnt;

    reg		r_subpix_vld;
    reg	[7:0]	r_subpix_out;

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    frame_req_l <= 1'b0;
	else if(i_frame_req)
	    frame_req_l <= 1'b1;
	else if(frame_reading)
	    frame_req_l <= 1'b0;
    end

    always @(posedge clk)
    begin
	vsync_re_clk <= (vsync_clk[2:1] == 2'b01);
	vsync_fe_clk <= (vsync_clk[2:1] == 2'b10);
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    frame_reading <= 1'b0;
	else if(vsync_fe_clk && frame_req_l)
	    frame_reading <= 1'b1;
	else if(vsync_re_clk)
	    frame_reading <= 1'b0;
    end

    always @(posedge pclk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    pix_vld_tg_pclk <= 1'b0;
	else if(pix_wr)
	    pix_vld_tg_pclk <= ~pix_vld_tg_pclk;
    end

    always @(posedge pclk)
    begin
	if(pix_wr)
	    pix_lat_pclk <= {r_mod, g_mod, b_mod};
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    pix_vld_tg_clk <= 3'b0;
	else 
	    pix_vld_tg_clk <= {pix_vld_tg_clk[1:0], pix_vld_tg_pclk};
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    sub_pix_cnt <= 2'b0;
	else if(pix_vld_tg_clk[2] != pix_vld_tg_clk[1])
	    sub_pix_cnt <= (SUBPIX == "888") ? 2'd3 : 2'd2;
	else if(sub_pix_cnt != 2'b0)
	    sub_pix_cnt <= sub_pix_cnt - 2'd1;
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    pix_lat_clk <= 24'b0;
	else if(pix_vld_tg_clk[2] != pix_vld_tg_clk[1])
	    pix_lat_clk <= pix_lat_pclk;
	else if((sub_pix_cnt != 2'b0) && (SUBPIX == "888"))
	    pix_lat_clk <= {8'b0, pix_lat_clk[23:8]};
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    r_subpix_vld <= 1'b0;
	else if(frame_reading)
	    r_subpix_vld <= (sub_pix_cnt != 2'b0);
	else
	    r_subpix_vld <= 1'b0;
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    r_subpix_out <= 8'b0;
	else
	    r_subpix_out <= (SUBPIX == "888") ? pix_lat_clk[7:0] :
			    (sub_pix_cnt == 2'd1) ? {pix_lat_clk[23:19], pix_lat_clk[15:13]} : 
						    {pix_lat_clk[12:10], pix_lat_clk[ 7: 3]};
    end

    assign o_subpix_vld = r_subpix_vld;
    assign o_subpix_out = r_subpix_out;
end
else
begin
    assign o_subpix_vld = 1'b0;
    assign o_subpix_out = 8'b0;
end
endgenerate

// frame out }}}

endmodule

// vim:foldmethod=marker:
//
