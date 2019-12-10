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

module shield_audio_top (
// mic interface
output		i2s_sck_mic	,
input           i2s_sd_mic      ,
output          i2s_ws_mic      ,

// output led
output  [5:0]   oled            ,

// output detection
output reg      det             ,
output reg [1:0]det_idx         ,

// SPI
output    	spi_css         ,
inout    	spi_clk         ,
inout     	spi_miso        ,
inout    	spi_mosi        ,
                                
// debug i2c                    
inout           debug_scl       ,
inout           debug_sda       ,

input           uart_rxd        ,
output          uart_txd        ,

output          REDn            ,
output          BLUn            ,
output          GRNn
);

// Parameters {{{
parameter ML_TYPE       = "CNN"; // ML engine type
				 // CNN
				 // BNN
				 // BWN
parameter USE_ML        = 1'b1; // instantate ML engine or not
parameter MEM_TYPE      = "SINGLE_SPRAM"; 
                                // EBRAM: use EBR for active memory storage
				// DUAL_SPRAM: use Dual SPRAM for active memory storage
				// otherwise: use single SPRAM for active memory storage
parameter BYTE_MODE     = "UNSIGNED"; 
                                // DISABLE, UNSIGNED
parameter EN_DEBUG      = 1'b0; // 1: enable debug capture feature
parameter BNN_ONEZERO   = 1'b1; // 1: 1,0 activation instead of 1, -1
parameter EN_FILTER     = 1'b1; // 1: enable digital filter for output LED
parameter EN_I2CS       = 1'b0; // 1: instantiate i2c slave for control & debugging, EN_DEBUG are valid only when EN_I2CS == 1
parameter EN_CLKMASK    = 1'b0; // 1: instantiate clock masking block
parameter EN_HIGHTH     = 1'b0; // 1: for two classes 
parameter EN_DEBUG_LED  = 1'b0; // 1: for additional detection LED
parameter EN_FUSION     = 1'b0; // 1: for fusion mode (reduce detection LED)
parameter EN_UART       = 1'b1; // 1: instantiate UART block
parameter EN_DUAL_UART  = 1'b1; // 1: wired AND connection for uart signal
parameter CODE_MEM      = "SINGLE_SPRAM";
                                // EBRAM
				// SINGLE_SPRAM
				// DUAL_SPRAM
				// QUAD_SPRAM
parameter DIV           = 1;    // 1 for 24MHz, 2 for 12MHz

// Parameters }}}

// Platform signals {{{
wire		clk;		// core clock
wire		clk_aon;
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
wire		w_rd_req;
wire		w_rd_done;
wire		w_we;
wire	[15:0]	w_waddr;
wire	[15:0]	w_dout;

wire	        w_running;
wire	[7:0]	ml_status;

wire	[31:0]	w_cycles;
wire	[31:0]	w_commands;
wire	[31:0]	w_fc_cycles;

wire		w_result_en;
reg	[1:0]	r_result_en_d;
wire	[15:0]	w_result;

wire		w_det;
wire		w_det_m;
wire		w_det2;
wire		w_det4;
reg		r_det0;
reg		r_det;
reg		r_det2;
reg	[2:0]	r_det_idx_lat;
wire		w_det_filter;
reg		r_det_filter;
reg	[7:0]	det_cnt;

wire	[15:0]	w_ld;
wire	[15:0]	w_rd;
wire		w_smp_we_mic;
wire		w_active_mic;
wire		w_active_ab;
wire		w_smp_we_ab;
reg		r_active;
wire	[15:0]	w_dc_value;
wire	[15:0]	w_smp_data;
wire		w_smp_valid;

// Filter bank signals
wire		w_rst_wgt_addr;

wire	[5:0]	w_bias_addr   ;

wire		w_fc_run      ;
wire		w_input_rd    ; 
wire		w_wgt_rd      ;
wire		w_init_bias   ;
wire		w_fc_ps_shift ;

wire	[15:0]	w_weight      ;
wire	      	w_weight_val  ;

wire		w_fb_str_init_addr;
wire		w_fb_str_wgt_wr   ;
wire	[15:0]	w_fb_str_wgt_in   ;


// Audio buffer signal
wire	[7:0]	w_blk_idx;
wire	[7:0]	w_wr_blk_idx;
wire	[1:0]	w_fb_stride;
wire	[2:0]	w_fb_blk_len;
wire		w_fb_buffer_en;

wire		w_rd_req_fb_cu;
wire		w_rd_rdy_ab;
wire	[15:0]	w_fc_out;
wire		w_start_fb_cu;
wire		w_fb_cu_done;

wire		fire;
wire	[15:0]	w_level_th;
wire	[15:0]	w_det_th;
wire	[15:0]	w_det_th2;
wire	[7:0]	w_len_th;
wire	[7:0]	w_len_max;

wire		w_ml_start;

wire		w_config_done;

// internal UART & SPI
wire		w_uart_txd;
wire		w_uart_rxd;

wire		w_spi_clk;
wire		w_spi_mosi;

wire		w_uart_req;

// result post process
wire	[15:0]	w_diff;
wire	[2:0]	w_max_idx;
wire		w_validp;

// Platform signals }}}

// debug signals {{{

wire	[7:0]	w_config_00;
wire	[7:0]	w_config_01;
wire	[7:0]	w_config_02;
wire	[7:0]	w_config_03;
wire	[7:0]	w_config_04;
wire	[7:0]	w_status_00;
wire	[7:0]	w_status_01;
wire	[7:0]	w_status_02;
wire	[7:0]	w_status_03;
wire	[7:0]	w_status_04;
wire	[7:0]	w_status_05;
wire	[7:0]	w_status_06;
wire	[7:0]	w_status_07;
wire	[7:0]	w_status_08;
wire	[7:0]	w_status_09;
wire	[7:0]	w_status_0a;
wire		debug_o_sda;

wire		w_we2;
wire	[7:0]	w_waddr2;
wire	[31:0]	w_wdata2;

// debug signals }}}

// Platform blocks {{{

wire		w_clk;

HSOSC # (.CLKHF_DIV((DIV == 2) ? "0b10" : "0b01")) u_hfosc (
    .CLKHFEN   (1'b1  ),
    .CLKHFPU   (1'b1  ),
    .CLKHF     (w_clk )
);

always @(posedge clk_aon) r_active <= w_active_ab | w_active_mic | w_uart_req;

ice40_audio_clkgen #(.EN_CLKMASK(EN_CLKMASK), .DIV(DIV)) u_ice40_audio_clkgen (
    .i_clk_in   (w_clk        ),
    .i_init_done(1'b1         ),
    .i_load_done(w_load_done  ),
    .i_active   (r_active     ),
    .i_done_fb  (w_fb_cu_done ),
    .i_done_ml  (w_rd_rdy_con     ),

    .o_start_fb (w_start_fb_cu),
    .o_start_ml (w_ml_start   ),

    .o_init     (w_init       ),
    .o_clk_aon  (clk_aon      ),
    .o_clk      (clk          ),
    .resetn     (resetn       )
);

ice40_resetn u_resetn(
    .clk    (clk_aon),
    .resetn (resetn )
);

//i2sm_in #(.GAIN(16), .DIV(((DIV == 2) ? 11 : 23))) u_i2sm_in ( // 12MHz, 24MHz, 16k sample/sec
i2sm_in #(.GAIN(16), .DIV(((DIV == 2) ? 23 : 47))) u_i2sm_in ( // 12MHz, 24MHz, 8k sample/sec
    .clk       (clk_aon     ),
    .resetn    (resetn      ),
    .o_ld      (w_ld        ),
    .o_rd      (w_rd        ),
    .o_smp_we  (w_smp_we_mic),

    .i_dc_value(w_dc_value  ),
    .i_level_th(w_level_th  ),

    .o_active  (w_active_mic),

    .o_bclk    (i2s_sck_mic ),
    .i_sd      (i2s_sd_mic  ),
    .o_ws      (i2s_ws_mic  )
);

assign w_fb_stride = 2'b00  ; // 8k sample per sec
assign w_fb_blk_len = 3'b100; // non fixed burst
assign w_fb_buffer_en = 1'b1;

//assign w_smp_we_ab = w_smp_we_mic;

reg		smp_we_mic_tg;

reg	[2:0]	smp_we_mic_tg_d;

always @(posedge clk_aon or negedge resetn)
begin
    if(resetn == 1'b0)
	smp_we_mic_tg <= 1'b0;
    else if(w_smp_we_mic)
	smp_we_mic_tg <= ~smp_we_mic_tg;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	smp_we_mic_tg_d <= 3'b0;
    else 
	smp_we_mic_tg_d <= {smp_we_mic_tg_d[1:0], smp_we_mic_tg};
end

assign w_smp_we_ab = (smp_we_mic_tg_d[2] != smp_we_mic_tg_d[1]);

ice40_audio_buffer #(.EN_DCBLK(1)) u_ice40_audio_buffer (
    .clk          (clk           ), 
    .resetn       (resetn        ), 
    .i_buffer_en  (w_fb_buffer_en),
    .i_burst_wr_en(1'b0          ),
    .i_rst_waddr  (1'b0          ),
                  
    .i_smp_we     (w_smp_we_ab   ),
    .i_smp_data   (w_ld          ),
    //.i_smp_data   (w_rd          ),
    .i_blk_idx    (w_blk_idx     ),
    .i_stride     (w_fb_stride   ),
    .i_blk_len    (w_fb_blk_len  ),
    .i_rd_req     (w_rd_req_fb_cu),
    .o_rd_rdy     (w_rd_rdy_ab   ),
    .i_smp_rd     (w_input_rd    ),
    .i_level_th   (w_level_th    ),

    .o_active     (w_active_ab   ),
    .o_dc_value   (w_dc_value    ),
    .o_wr_blk_idx (w_wr_blk_idx  ),
    .o_smp_data   (w_smp_data    ),
    .o_smp_valid  (w_smp_valid   )
);

assign w_we2 = 1'b0  ;
assign w_wdata2 = 32'b0;
assign w_waddr2 = 8'b0;

ice40_audio_fb_storage u_ice40_audio_fb_storage (
    .clk         (clk           ), 

    .i_rst_addr  (w_rst_wgt_addr),

    .i_init_addr (w_fb_str_init_addr),
    .i_wgt_wr    (w_fb_str_wgt_wr   ),
    .i_wgt_in    (w_fb_str_wgt_in   ),

    .i_rd        (w_wgt_rd      ),
    .o_weight    (w_weight      ),
    .o_weight_val(w_weight_val  ),

    .resetn      (resetn        )
);

audio_ice40_fc_eu #(.BYTE_MODE(BYTE_MODE)) u_dnn_ice40_fc_eu (
    .clk          (clk           ),
    .resetn       (resetn        ),

    .i_bias_addr  (w_bias_addr   ),
    .i_init_bias  (w_init_bias   ),
    .i_shift      (w_fc_ps_shift ),

    .i_run        (w_fc_run      ),
    .i_din        (w_smp_data    ),
    .i_din_val    (w_smp_valid   ),
    .i_weight     (w_weight      ),

    .i_cascade_in (16'd0         ),
    .o_cascade_out(w_fc_out      )
);

ice40_audio_fb_cu u_ice40_audio_fb_cu (
    .clk           (clk            ),
    .resetn        (resetn         ),

    .i_start       (w_start_fb_cu  ),
    .i_repeat_run  (1'b0           ),
                                   
    .o_init        (               ),
    .o_rst_raddr   (               ),
    .o_rst_waddr   (               ),
    .o_rst_wgt_addr(w_rst_wgt_addr ),

    .i_blk_idx     (w_wr_blk_idx   ),
    .o_rd_req      (w_rd_req_fb_cu ),
    .i_rd_rdy      (w_rd_rdy_ab    ),
    .o_blk_idx     (w_blk_idx      ),

    .o_cycles      (),

    .o_bias_addr   (w_bias_addr    ),
                                   
    .o_fc_run      (w_fc_run       ),
    .o_input_rd    (w_input_rd     ), 
    .o_wgt_rd      (w_wgt_rd       ),
    .o_init_bias   (w_init_bias    ),
    .o_fc_ps_shift (w_fc_ps_shift  ),

    .o_done        (w_fb_cu_done   )
);

// ML engine signal
reg	[15:0]	ml_waddr;

`ifdef ASYNC1
reg		ps_shift_tg;
reg	[2:0]	ps_shift_tg_d;
reg	[15:0]	fc_out_lat;

always @(posedge clk_aon or negedge resetn)
begin
    if(resetn == 1'b0)
	fc_out_lat <= 16'b0;
    else if(w_fc_ps_shift)
	fc_out_lat <= w_fc_out;
end

always @(posedge clk_aon or negedge resetn)
begin
    if(resetn == 1'b0)
	ps_shift_tg <= 1'b0;
    else if(w_fc_ps_shift)
	ps_shift_tg <= ~ps_shift_tg;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	ps_shift_tg_d <= 3'b0;
    else
	ps_shift_tg_d <= {ps_shift_tg_d[1:0], ps_shift_tg};
end

assign w_we    = (ps_shift_tg_d[2] != ps_shift_tg_d[1]) ;
assign w_dout  = fc_out_lat      ;
`else

assign w_we    = w_fc_ps_shift;
assign w_dout  = w_fc_out;

`endif

// common
always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	ml_waddr <= 16'b0;
    else if(w_start_fb_cu == 1'b0)
	ml_waddr <= 16'b0;
    else if(w_we)
	ml_waddr <= ml_waddr + 16'd1;
end

assign w_waddr = ml_waddr      ;

// LED output
generate if(EN_FILTER == 1'b1)
begin: g_en_filter_on
    assign oled[0] = w_det_filter ? 1'bz : 1'b0;
end
else begin
    assign oled[0] = r_det ? 1'bz : 1'b0;
end
endgenerate

always @(posedge clk)
begin
    det     <= w_det_filter;
end

always @(posedge clk)
begin
    case(r_det_idx_lat)
	3'd2   : det_idx <= 2'b00;
	3'd3   : det_idx <= 2'b01;
	3'd4   : det_idx <= 2'b10;
	3'd5   : det_idx <= 2'b11;
	default: det_idx <= 2'b00;
    endcase
end

//assign oled[1] = r_active ? 1'bz : 1'b0;

assign oled[4] = (EN_DEBUG_LED & r_det_filter) ? 1'bz : 1'b0;
assign oled[3] = (EN_DEBUG_LED & r_det2      ) ? 1'bz : 1'b0;
assign oled[2] = (EN_DEBUG_LED & r_det       ) ? 1'bz : 1'b0;
assign oled[1] = (EN_DEBUG_LED & r_det0      ) ? 1'bz : 1'b0;

/*
assign oled[4] = (w_det_filter && (r_det_idx_lat == 3'd5)) ? 1'bz : 1'b0;
assign oled[3] = (w_det_filter && (r_det_idx_lat == 3'd4)) ? 1'bz : 1'b0;
assign oled[2] = (w_det_filter && (r_det_idx_lat == 3'd3)) ? 1'bz : 1'b0;
assign oled[1] = (w_det_filter && (r_det_idx_lat == 3'd2)) ? 1'bz : 1'b0;
*/
assign oled[5] = w_active_ab ? 1'bz : 1'b0;

// Platform blocks }}}

// Debug block {{{
generate if(EN_I2CS)
begin: g_on_en_i2cs
    lsc_i2cs_local # (.EN_CAPTURE(1'b1), .EN_DEBUG(EN_DEBUG)) u_lsc_i2cs_local (
	//.clk        (clk_aon    ),     // 
	.clk        (clk        ),     // 
	.resetn     (resetn     ),     // 

	.o_config_00(w_config_00),
	.o_config_01(w_config_01),
	.o_config_02(w_config_02),
	.o_config_03(w_config_03),
	.o_config_04(w_config_04),
	.i_status_00(w_status_00),
	.i_status_01(w_status_01),
	.i_status_02(w_status_02),
	.i_status_03(w_status_03),
	.i_status_04(w_status_04),
	.i_status_05(w_status_05),
	.i_status_06(w_status_06),
	.i_status_07(w_status_07),
	.i_status_08(w_status_08),
	.i_status_09(w_status_09),
	.i_status_0a(w_status_0a),
	
	.i_we       (w_we       ),
	.i_waddr    (w_waddr[13:0]),
	.i_din      ((BYTE_MODE == "DISABLE") ? w_dout[15:8] : w_dout[7:0]),

	.i_we2      (w_we2      ),
	.i_waddr2   (w_waddr2   ),
	.i_din2     (w_wdata2   ),

	.i_scl      (debug_scl  ),     // 
	.i_sda      (debug_sda  ),     // 
	.o_sda      (debug_o_sda)      // 
    );

    assign debug_sda = debug_o_sda ? 1'bz : 1'b0;
end
else
begin
    assign debug_sda = 1'bz;
    assign debug_scl = 1'bz;
    assign w_config_00 = 8'd0;
    assign w_config_01 = 8'd0;
    assign w_config_02 = 8'd0;
    assign w_config_03 = 8'd0;
    assign w_config_04 = 8'd0;
end
endgenerate

generate if(EN_UART)
begin: g_on_en_uart
    wire	[7:0]	w_uart_dout;
    wire	[7:0]	w_uart_din;
    wire		w_result_req;

    reg		result_req_lat;
    wire	w_uart_vld; 
    reg	[2:0]	result_reading_seq;

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    result_req_lat <= 1'b0;
	else if(w_result_req)
	    result_req_lat <= 1'b1;
	else if(w_validp)
	    result_req_lat <= 1'b0;
    end

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    result_reading_seq <= 3'b00;
	else if(result_req_lat  && w_validp)
	    result_reading_seq <= 3'b01;
	else if(result_reading_seq != 3'b0)
	    result_reading_seq <= {result_reading_seq[1:0], 1'b0};
    end

    assign w_uart_vld = (result_reading_seq != 3'b0);

    assign w_uart_din = result_reading_seq[0] ? {12'b0, w_max_idx} :
                        result_reading_seq[1] ? w_diff[ 7:0]       :
                        result_reading_seq[2] ? w_diff[15:8]       : 16'b0;

    assign w_uart_req = result_req_lat;
    
    lsc_uart #(.PERIOD(16'd103)) u_lsc_uart(
	.ref_clk(clk         ),
	.clk    (clk         ),
	.i_din  (w_uart_din  ),
	.i_valid(w_uart_vld  ),

	.o_dout (w_uart_dout ),
	.o_valid(w_result_req),
	.o_empty(w_uart_empty),

	.i_rxd  (w_uart_rxd  ), 
	.o_txd  (w_uart_txd  ),
	.resetn (resetn      )
    );

    assign uart_txd = EN_DUAL_UART ? w_uart_txd : 1'bz;

end
else
begin
    assign w_uart_empty = 1'b1;
    assign w_uart_req   = 1'b0;
end
endgenerate

// Debug block }}}

// Code memory {{{
spi_loader2_single_spram u_spi_loader(
    .clk          (clk          ),
    .resetn       (resetn       ),

    .o_load_done  (w_load_done  ),

    .o_init_addr  (w_fb_str_init_addr),
    .o_wgt_wr     (w_fb_str_wgt_wr   ),
    .o_wgt_out    (w_fb_str_wgt_in   ),

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
assign w_uart_rxd = (spi_clk & w_load_done) & ((EN_DUAL_UART == 1'b0) | uart_rxd);
assign spi_mosi = w_load_done ? w_uart_txd : w_spi_mosi;

// Code memory }}}

// Result handling {{{

// parameters

generate if(EN_HIGHTH == 1)
begin: g_on_highth
    assign w_len_th   = w_config_01 + ((DIV == 2) ? 8'd6 : 8'd12);
    assign w_level_th = {w_config_02 + 8'd5, 8'b0};
    assign w_det_th   = {2'b0, w_config_03 + 8'h40, 6'b0};
    assign w_det_th2  = {2'b0, w_config_04 + 8'h87, 6'd0};
    assign w_len_max  = w_len_th + 8'd3;
end else begin
    assign w_len_th   = w_config_01 + ((DIV == 2) ? 8'd4 : 8'd8);
    assign w_level_th = {w_config_02 + 8'd5, 8'b0};
    assign w_det_th   = {3'b0, w_config_03 + 8'h30, 5'b0};
    assign w_det_th2  = {3'b0, w_config_04 + 8'h80, 5'd0};
    assign w_len_max  = w_len_th + 8'd3;
end
endgenerate

audio_post u_audio_post(
    .clk      (clk         ),
    .i_init   (w_ml_start  ),
    .i_we     (w_result_en ),
    .i_dout   (w_result    ),
    .o_diff   (w_diff      ),
    .o_max_idx(w_max_idx   ),
    .o_validp (w_validp    ),
    .resetn   (resetn      )
);

assign w_det   = (w_max_idx != 3'b111) && (w_max_idx != 3'b000) && (w_max_idx != 3'b001);
assign w_det2 = (w_diff > w_det_th );
assign w_det4 = (w_diff > w_det_th2);

assign fire = (det_cnt >= w_len_th);

always @(posedge clk)
begin
    r_det_filter  <= fire;
end

always @(posedge clk)
begin
    if(w_validp == 1'b1) begin
	if(r_det_idx_lat != w_max_idx)
	    det_cnt <= 8'd0;
	else if((r_det2 == 1'b1) &&  (det_cnt < w_len_max))
	    det_cnt <= det_cnt + 8'd2;
	else if((r_det == 1'b1) && (det_cnt < w_len_max))
	    det_cnt <= det_cnt + 8'd1;
	else if(r_det0 == 1'b1)
	    det_cnt <= det_cnt;
	else if((det_cnt != 8'd0) && (det_cnt != 8'd1))
	    det_cnt <= det_cnt - 8'd2;
	else
	    det_cnt <= 8'd0;
    end
end



always @(posedge clk)
begin
    r_det_idx_lat <= w_max_idx;
end

lsc_led_con #(.CLK_FREQ((DIV == 2) ? 12000 : 24000 ), 
              .ON_TIME(EN_FUSION ? 250 : 400), 
	      .OFF_TIME(EN_FUSION ? 50 : 200)) u_lsc_led_con (
    .clk     (clk           ),
    .resetn  (resetn        ),
    .i_enable(r_active      ),
    .i_fire  (r_det_filter  ),
    .o_on    (w_det_filter  )
);

reg	[3:0]	pwm_cnt;

always @(posedge clk_aon)
begin
    pwm_cnt <= pwm_cnt + 4'd1;
end

wire	w_red;
wire	w_green;
wire	w_blue;

//assign w_green = r_active & (pwm_cnt == 4'd0);
assign w_green = w_active_ab & (pwm_cnt == 4'd0);
assign w_red   = w_det_filter & (pwm_cnt[1:0] == 2'd0);
assign w_blue  = w_det_filter & (pwm_cnt[1:0] == 2'd0);

`ifdef ICECUBE
SB_RGBA_DRV RGB_DRIVER ( 
    .RGBLEDEN (1'b1    ),
    .RGB0PWM  (w_green ), // Green
    .RGB1PWM  (w_red   ), 
    .RGB2PWM  (w_blue  ),
    .CURREN   (1'b1    ), 
    .RGB0     (REDn    ),
    .RGB1     (GRNn    ),
    .RGB2     (BLUn    )
);
defparam RGB_DRIVER.RGB0_CURRENT = "0b000001";
defparam RGB_DRIVER.RGB1_CURRENT = "0b000001";
defparam RGB_DRIVER.RGB2_CURRENT = "0b000001";
`else // Radiant

RGB RGB_DRIVER ( 
    .RGBLEDEN (1'b1    ),
    .RGB0PWM  (w_green ), // Green
    .RGB1PWM  (w_red   ), 
    .RGB2PWM  (w_blue  ),
    .CURREN   (1'b1     ), 
    .RGB0     (REDn     ),
    .RGB1     (GRNn     ),
    .RGB2     (BLUn     )
);
defparam RGB_DRIVER.RGB0_CURRENT = "0b000001";
defparam RGB_DRIVER.RGB1_CURRENT = "0b000001";
defparam RGB_DRIVER.RGB2_CURRENT = "0b000001";

`endif

// Result handling }}}

// NN block {{{
generate if(USE_ML == 1'b1)
begin: g_use_ml_on
    compact_cnn u_lsc_ml (
	.clk         (clk         ),
	.resetn      (resetn      ),
				  
	.o_rd_rdy    (w_rd_rdy    ),
	.i_start     (w_ml_start  ),

	.o_cycles    (w_cycles    ),
	.o_commands  (w_commands  ),
	.o_fc_cycles (w_fc_cycles ),
				  
	.i_we        (w_we        ),
	.i_waddr     (w_waddr     ),
	.i_din       (w_dout      ),

	.o_we        (w_result_en ),
	.o_dout      (w_result    ),

	.o_fill      (w_fill      ),
	.i_fifo_empty(w_fifo_empty),
	.i_fifo_low  (w_fifo_low  ),
	.o_fifo_rd   (w_fifo_rd   ),
	.i_fifo_dout (w_fifo_dout ),

	.o_status    (ml_status   )
    );

    assign w_status_00 = w_commands[7:0];
    assign w_status_01 = w_commands[15:8];

    /*
    assign w_status_02 = result0[ 7:0];
    assign w_status_03 = result0[15:8];
    assign w_status_04 = result1[ 7:0];
    assign w_status_05 = result1[15:8];
    assign w_status_06 = result2[ 7:0];
    assign w_status_07 = result2[15:8];
    */
    assign w_status_02 = 8'b0;
    assign w_status_03 = 8'b0;
    assign w_status_04 = 8'b0;
    assign w_status_05 = 8'b0;
    assign w_status_06 = 8'b0;
    assign w_status_07 = 8'b0;
    assign w_status_08 = w_cycles[ 7: 0];
    assign w_status_09 = w_cycles[15: 8];
    assign w_status_0a = w_cycles[23:16];

    assign w_rd_rdy_con = w_rd_rdy & (!w_config_00[0]);

    always @(posedge clk)
    begin
	r_det0 <= w_det;
	r_det  <= w_det && w_det2;
	r_det2 <= w_det && w_det4;
    end

end
else
begin
    assign w_fill    = w_config_00[4];
    assign w_fifo_rd = (!w_fifo_empty) & w_config_00[5];
    assign w_result_en = 1'b0;
    assign w_rd_rdy_con = (!w_config_00[0]);

    assign w_status_00 = {7'b0, w_load_done};

    assign w_status_02 = w_fifo_dout[ 7: 0];
    assign w_status_03 = w_fifo_dout[15: 8];
    assign w_status_04 = w_fifo_dout[23:16];
    assign w_status_05 = w_fifo_dout[31:24];

    always @(posedge clk)
    begin
	r_det <= !w_fifo_empty;
    end
end
endgenerate

// NN block }}}

endmodule

// vim:foldmethod=marker:
//
