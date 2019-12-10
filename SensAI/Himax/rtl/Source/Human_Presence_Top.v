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

module lsc_ml_ice40_himax_humandet_top (
//input		clk_in        ,  // 27MHz oscillator

// Camera interface
input		cam_pclk      ,
input           cam_hsync     ,
input           cam_vsync     ,
input  [3:0]    cam_data      ,
output          cam_trig      ,

output          cam_mclk      ,

inout           cam_scl       ,
inout           cam_sda       ,

//output [1:0]	debug_prob    ,
output          uart_txd      ,

// SPI
output    	spi_css       ,
inout    	spi_clk       ,
input     	spi_miso      ,
output    	spi_mosi      ,

// Color LED
output  [5:0]   oled        
);

// Parameters {{{
parameter EN_SINGLE_CLK = 1'b0; // 1: single clock mode (core clk == pclk) 0: independent clock mode (core clk != pclk)
parameter EN_CLKMASK    = 1'b1; // 1: instantiate clock masking block
parameter CODE_MEM      = "DUAL_SPRAM";
// Parameters }}}

// platform signals {{{
// Clocks
wire		clk;		// core clock
wire		oclk_in;	// internal oscillator clock input
wire		oclk;		// internal oscillator clock (global)
wire		pclk_in;
wire		pclk;		// pixel clock
wire		clk_init;	// initialize clock (based on oclk)
wire		resetn;
wire		w_init;
wire		w_init_done;

// SPI loader
wire		w_fill      ;
wire		w_fifo_empty;
wire		w_fifo_low  ;
wire		w_fifo_rd   ;
wire	[31:0]	w_fifo_dout ;
wire		w_load_done ;

wire		w_rd_rdy;
wire		w_rd_rdy_con;
reg		r_rd_rdy_con;
wire		w_rd_done;
reg	[1:0]	r_rd_done_d;
wire		w_we;
wire	[15:0]	w_waddr;
wire	[15:0]	w_dout;

wire	        w_running;
wire	[7:0]	ml_status;

wire	[31:0]	w_cycles;
wire	[31:0]	w_commands;
wire	[31:0]	w_fc_cycles;

wire		w_result_en;
wire	[15:0]	w_result;

reg		r_det;
reg		r_det_filter;
reg	[4:0]	r_det_histo;

reg	[5:0]	r_det_vec;

reg	[7:0]	r_comp_done_d;
wire	[15:0]	w_class0;
reg	[15:0]	r_class0;
reg	[15:0]	r_class1;
reg	[15:0]	r_class2;
reg	[15:0]	r_class3;
reg	[15:0]	r_class4;
reg	[15:0]	r_class5;

// video related signals
wire	[3:0]	cam_data_p;
wire		cam_de_p;
wire		cam_vsync_p;
wire	[3:0]	cam_data_n;
wire		cam_de_n;
wire		cam_vsync_n;

// camera configuration
wire		w_scl_out;
wire		w_sda_out;

// internal UART & SPI
wire		w_spi_clk;
wire		w_spi_mosi;

// platform signals }}}

// I/O cell instantation {{{

assign pclk_in = cam_pclk;

IOL_B
#(
  .LATCHIN ("NONE_DDR"),
  .DDROUT  ("NO")
) u_io_cam_data[3:0] (
  .PADDI  (cam_data[3:0]),  // I
  .DO1    (1'b0),  // I
  .DO0    (1'b0),  // I
  .CE     (1'b1),  // I - clock enabled
  .IOLTO  (1'b1),  // I - tristate enabled
  .HOLD   (1'b0),  // I - hold disabled
  .INCLK  (pclk),  // I
  .OUTCLK (pclk),  // I
  .PADDO  (),  // O
  .PADDT  (),  // O
  .DI1    (cam_data_n[3:0]),  // O
  .DI0    (cam_data_p[3:0])   // O
);

IOL_B
#(
  .LATCHIN ("NONE_REG"),
  .DDROUT  ("NO")
) u_io_cam_vsync (
  .PADDI  (cam_vsync),  // I
  .DO1    (1'b0),  // I
  .DO0    (1'b0),  // I
  .CE     (1'b1),  // I - clock enabled
  .IOLTO  (1'b1),  // I - tristate enabled
  .HOLD   (1'b0),  // I - hold disabled
  .INCLK  (pclk),  // I
  .OUTCLK (pclk),  // I
  .PADDO  (),  // O
  .PADDT  (),  // O
  .DI1    (cam_vsync_n),  // O
  .DI0    (cam_vsync_p)   // O
);

IOL_B
#(
  .LATCHIN ("NONE_DDR"),
  .DDROUT  ("NO")
) u_io_cam_de (
  .PADDI  (cam_hsync),  // I
  .DO1    (1'b0),  // I
  .DO0    (1'b0),  // I
  .CE     (1'b1),  // I - clock enabled
  .IOLTO  (1'b1),  // I - tristate enabled
  .HOLD   (1'b0),  // I - hold disabled
  .INCLK  (pclk),  // I
  .OUTCLK (pclk),  // I
  .PADDO  (),  // O
  .PADDT  (),  // O
  .DI1    (cam_de_n),  // O
  .DI0    (cam_de_p)   // O
);

// I/O cell instantation }}}

// debug signals {{{

wire	[7:0]	w_config_00;
wire	[7:0]	w_config_01;
reg		[2:0]	r_frame_sel ;
wire			w_frame_req ;
wire			w_debug_vld ;

// debug signals }}}

// Platform block {{{

HSOSC # (.CLKHF_DIV("0b01")) u_hfosc (
    .CLKHFEN   (1'b1 ),
    .CLKHFPU   (1'b1 ),
    .CLKHF     (oclk_in )
);


ice40_himax_HP_clkgen #(.EN_CLKMASK(EN_CLKMASK), .EN_SINGLE_CLK(EN_SINGLE_CLK)) u_ice40_humandet_clkgen (
    .i_oclk_in   (oclk_in     ),
    .i_pclk_in   (pclk_in     ),

    .i_init_done (w_init_done ),
    .i_cam_vsync (cam_vsync_p ),
    .i_load_done (w_load_done ),
    .i_ml_rdy    (r_rd_rdy_con),
    .i_vid_rdy   (w_rd_done   ),
    .i_mask_ovr  (1'b0        ),

    .o_init      (w_init      ),
    .o_oclk      (oclk        ), // oscillator clock (always live)
    .o_clk       (clk         ), // core clock
    .o_pclk      (pclk        ), // video clock
    .o_clk_init  (clk_init    ),

    .o_debug     (),

    .resetn      (resetn      )
);

assign debug_prob = 2'b00;

ice40_resetn u_resetn(
    .clk    (oclk  ),
    .resetn (resetn)
);

assign cam_mclk = w_init_done ? 1'b0 : oclk;

lsc_i2cm_himax #(.EN_ALT(1'b0), .CONF_SEL("324x324_dim_maxfps")) u_lsc_i2cm_himax(
    .clk      (clk_init   ),
    .init     (w_init     ),
    .init_done(w_init_done),
    .scl_in   (cam_scl    ),
    .sda_in   (cam_sda    ),
    .scl_out  (w_scl_out  ),
    .sda_out  (w_sda_out  ),
    .resetn   (resetn     )
);

assign cam_scl = w_scl_out ? 1'bz : 1'b0;
assign cam_sda = w_sda_out ? 1'bz : 1'b0;

// Platform block }}}

	assign uart_txd = 1'b1; // loopback

// Debug block }}}

// Code memory {{{
spi_loader_wrap #(.MEM_TYPE(CODE_MEM)) u_spi_loader(
    .clk          (clk          ),
    .resetn       (resetn       ),

    .o_load_done  (w_load_done  ),

    .i_fill       (w_fill       ),
    .i_init       (w_init       ),
    .o_fifo_empty (w_fifo_empty ),
    .o_fifo_low   (w_fifo_low   ),
    .i_fifo_rd    (w_fifo_rd    ),
    .o_fifo_dout  (w_fifo_dout  ),

    .SPI_CLK      (w_spi_clk    ),
    .SPI_CSS      (spi_css      ),
    .SPI_MISO     (spi_miso     ),
    .SPI_MOSI     (w_spi_mosi   )
);

assign spi_clk = w_load_done ? 1'bz : w_spi_clk;
assign spi_mosi = w_load_done ? 1'b0 : w_spi_mosi;
// Code memory }}}

// Video processing {{{

ice40_himax_video_process_64 #(.SUBPIX("NONE")) u_ice40_himax_video_process_64 (
    .clk         (clk         ),
    .pclk        (pclk        ),
    .resetn      (resetn      ),
                 
    .i_cam_de    (cam_de_p    ),
    .i_cam_vsync (cam_vsync_p ),
    .i_cam_data  (cam_data_p  ),

    .o_width     (),
    .o_height    (),

    .i_frame_sel (r_frame_sel ),
    .i_frame_req (1'b0        ),
    .o_subpix_vld(            ),
    .o_subpix_out(            ),

    .i_rd_rdy    (w_rd_rdy_con),
    .o_rd_done   (w_rd_done   ),
                 
    .o_we        (w_we        ),
    .o_waddr     (w_waddr     ),
    .o_dout      (w_dout      )
);

always @(posedge clk)
begin
    r_rd_done_d <= {r_rd_done_d[0], w_rd_done};
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	r_frame_sel <= 3'd0;
    else if(r_rd_done_d == 2'b10)
	r_frame_sel <= (r_frame_sel == 3'b101) ? 3'd0 : (r_frame_sel + 3'd1);
end

assign cam_trig = !w_config_01[0];

reg	[7:0]	waddr2;

always @(posedge clk)
begin
    if(w_we == 1'b0)
	waddr2 <= 8'b0;
    else if(waddr2 != 8'hff)
	waddr2 <= waddr2 + 8'd1;
end


// Video processing }}}

// Result handling {{{

HP_Post_Processing u_speedsignal_post(
    .clk        (clk        ),        
    .init       (w_rd_done  ),      
    .i_we       (w_result_en),       
    .i_dout     (w_result   ),     
    .i_offset   (16'd2800   ),
    .comp_done  (           ),  
    .max_val    (w_class0   ),
    .cnt_val    (           )
);

reg	r_result_en_d;

always @(posedge clk)
begin
    r_result_en_d <= w_result_en;
    r_comp_done_d <= {r_comp_done_d[6:0], ({r_result_en_d, w_result_en} == 2'b10)};
end

always @(posedge clk)
begin
    if(r_comp_done_d[7] == 1'b1)
	case(r_frame_sel)
	    3'd0:    r_class5 <= w_class0;
	    3'd1:    r_class0 <= w_class0;
	    3'd2:    r_class1 <= w_class0;
	    3'd3:    r_class2 <= w_class0;
	    3'd4:    r_class3 <= w_class0;
	    default: r_class4 <= w_class0;
	endcase
end

always @(posedge clk)
begin
    if(r_comp_done_d[7] == 1'b1) begin
		case(r_frame_sel)
			3'd0 :   r_det_vec[5] <= !w_class0[15];
			3'd1 :   r_det_vec[0] <= !w_class0[15];
			3'd2 :   r_det_vec[1] <= !w_class0[15];
			3'd3 :   r_det_vec[2] <= !w_class0[15];
			3'd4 :   r_det_vec[3] <= !w_class0[15];
			default: r_det_vec[4] <= !w_class0[15];
		endcase
    end
end

always @(posedge clk)
begin
    if(r_comp_done_d[7] == 1'b1)
	r_det_histo <= {r_det_histo[3:0], !w_class0[15]};
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
		r_det_filter <= 1'b0;
    else if(r_det_histo[1:0] == 2'b11)
		r_det_filter <= 1'b1;
    else if(r_det_histo[3:0] == 4'b0000)
		r_det_filter <= 1'b0;
end


// Result handling }}}

// NN block {{{
    lsc_ml_ice40_cnn u_lsc_ml (
	.clk         (clk         ),
	.resetn      (resetn      ),
				  
	.o_rd_rdy    (w_rd_rdy    ),
	.i_start     (w_rd_done   ),

	.o_cycles    (w_cycles    ),
	.o_commands  (w_commands  ),
	.o_fc_cycles (w_fc_cycles ),
				  
	.i_we        (w_we        ),
	.i_waddr     (w_waddr     ),
	.i_din       (w_dout      ),

	.o_we        (w_result_en ),
	.o_dout      (w_result    ),

	.i_debug_rdy (1'b1),
	.o_debug_vld (w_debug_vld ),

	.o_fill      (w_fill      ),
	.i_fifo_empty(w_fifo_empty),
	.i_fifo_low  (w_fifo_low  ),
	.o_fifo_rd   (w_fifo_rd   ),
	.i_fifo_dout (w_fifo_dout ),

	.o_status    (ml_status   )
    );

	assign w_rd_rdy_con = w_rd_rdy & (!w_config_00[0]);
    always @(posedge clk or negedge resetn) begin
	if(resetn == 1'b0)
	    r_rd_rdy_con <= 1'b1;
	else if(r_comp_done_d[7])
	    r_rd_rdy_con <= 1'b1;
	else if(w_rd_rdy == 1'b0)
	    r_rd_rdy_con <= 1'b0;
    end

    always @(posedge clk)
    begin
	r_det <= |r_det_vec;
    end
// LEDs {{{

/* UL     */ assign oled[0] = r_det_vec[0] ? 1'bz : 1'b0;
/* UR     */ assign oled[1] = r_det_vec[1] ? 1'bz : 1'b0;
/* LL     */ assign oled[2] = r_det_vec[2] ? 1'bz : 1'b0;
/* LR     */ assign oled[3] = r_det_vec[3] ? 1'bz : 1'b0;
/* CZ     */ assign oled[4] = r_det_vec[4] ? 1'bz : 1'b0;
/* FULL   */ assign oled[5] = r_det_vec[5] ? 1'bz : 1'b0;

// LEDs }}}
endmodule

// vim:foldmethod=marker:
//
