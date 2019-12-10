
module ice40_audio_fb_storage (
input             clk         , 

// control 
input             i_rst_addr  ,

// input feeding / output reading
input             i_init_addr ,
input             i_wgt_wr    , // weight config
input     [15:0]  i_wgt_in    , // weight config

// data input/output
input             i_rd        ,
output     [15:0] o_weight    ,
output            o_weight_val,

input             resetn
);

parameter ECP5_DEBUG = 0;
parameter MEM_TYPE   = "SPRAM";

reg	[3:0]	rd_d;

reg	[15:0]	raddr;
reg	[14:0]	waddr;

wire	[15:0] w_rdata;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	waddr <= 15'b0;
    else if(i_init_addr == 1'b1)
	waddr <= 15'b0;
    else if((waddr[14] == 1'b0) && (i_wgt_wr == 1'b1))
	waddr <= waddr + 15'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	raddr <= 16'b0;
    else if(i_rst_addr == 1'b1)
	raddr <= 16'b0;
    else if(i_rd)
	raddr <= raddr + 16'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)
	rd_d <= 4'b0;
    else 
	rd_d <= {rd_d[2:0], i_rd};
end

assign o_weight_val = rd_d[0];

assign o_weight = w_rdata;

generate if(ECP5_DEBUG == 1)
begin: g_on_ecp5_debug
    wire	we;
    wire [17:0]	dpram_rdata;

    assign we = i_wgt_wr & (waddr[14] == 1'b0);

    assign w_rdata = dpram_rdata[15:0];

    dpram_16k_18 u_dpram_16k_18 (
	.WrAddress (waddr[13:0]  ), 
	.RdAddress (raddr[13:0]  ), 
	.Data      ({2'b0, i_wgt_in}), 
	.WE        (we           ), 
	.RdClock   (clk          ), 
	.RdClockEn (1'b1         ), 
	.Reset     (!resetn      ), 
	.WrClock   (clk          ), 
	.WrClockEn (1'b1         ), 
	.Q         (dpram_rdata  )
    );

end
else if(MEM_TYPE == "SPRAM")
begin
    wire	[13:0]	w_addr;
    wire		ce;
    wire                we;

    assign w_addr = (we == 1'b1) ? waddr[13:0] : raddr[13:0];

    assign ce = (we | i_rd);
    assign we = i_wgt_wr & (waddr[14] == 1'b0);

`ifdef ICECUBE
    SB_SPRAM256KA u_spram16k_16_0 (
	.DATAIN     (i_wgt_in     ),
	.ADDRESS    (w_addr       ),
	.MASKWREN   (4'b1111      ),
	.WREN       (we           ),
	.CHIPSELECT (ce           ),
	.CLOCK      (clk          ),
	.STANDBY    (1'b0         ),
	.SLEEP      (1'b0         ),
	.POWEROFF   (1'b1         ),
	.DATAOUT    (w_rdata      )
    );
`else // Radiant
    SP256K u_spram16k_16_0 (
	.AD       (w_addr         ),  // I
	.DI       (i_wgt_in       ),  // I
	.MASKWE   (4'b1111        ),  // I
	.WE       (we             ),  // I
	.CS       (ce             ),  // I
	.CK       (clk            ),  // I
	.STDBY    (1'b0           ),  // I
	.SLEEP    (1'b0           ),  // I
	.PWROFF_N (1'b1           ),  // I
	.DO       (w_rdata        )   // O
    );
`endif
end
else  // EBRAM
begin
    wire		we0;
    wire		we1;

    wire	[15:0]	w_rdata0;
    wire	[15:0]	w_rdata1;

    reg		raddr_hi;

    assign we0 = i_wgt_wr & (waddr[14:11] == 4'b0000);
    assign we1 = i_wgt_wr & (waddr[14:11] == 4'b0001);

    always @(posedge clk or negedge resetn)
    begin
	if(resetn == 1'b0)
	    raddr_hi <= 1'b0;
	else
	    raddr_hi <= raddr[11];
    end

    assign w_rdata = raddr_hi ? w_rdata1 : w_rdata0;

`ifdef ICECUBE
    SB_RAM2048x2 u_ram2048x2_0 [7:0](
	.RDATA(w_rdata0       ),
	.RADDR(raddr[10:0]    ),
	.RCLK (clk            ),
	.RCLKE(1'b1           ),
	.RE   (i_rd           ),
	.WADDR(waddr[10:0]    ),
	.WCLK (clk            ),
	.WCLKE(1'b1           ),
	.WDATA(i_wgt_in       ),
	.WE   (we0            )
    );

    SB_RAM2048x2 u_ram2048x2_1 [7:0](
	.RDATA(w_rdata1       ),
	.RADDR(raddr[10:0]    ),
	.RCLK (clk            ),
	.RCLKE(1'b1           ),
	.RE   (i_rd           ),
	.WADDR(waddr[10:0]    ),
	.WCLK (clk            ),
	.WCLKE(1'b1           ),
	.WDATA(i_wgt_in       ),
	.WE   (we1            )
    );
`else // Radiant
    dpram2048x16 u_ram2048x16_0 (
	.wr_clk_i   (clk        ),
	.rd_clk_i   (clk        ),
	.wr_clk_en_i(1'b1       ),
	.rd_en_i    (i_rd       ),
	.rd_clk_en_i(1'b1       ),
	.wr_en_i    (we0        ),
	.wr_data_i  (i_wgt_in   ),
	.wr_addr_i  (waddr[10:0]),
	.rd_addr_i  (raddr[10:0]),
	.rd_data_o  (w_rdata0   )
    );

    dpram2048x16 u_ram2048x16_1 (
	.wr_clk_i   (clk        ),
	.rd_clk_i   (clk        ),
	.wr_clk_en_i(1'b1       ),
	.rd_en_i    (i_rd       ),
	.rd_clk_en_i(1'b1       ),
	.wr_en_i    (we1        ),
	.wr_data_i  (i_wgt_in   ),
	.wr_addr_i  (waddr[10:0]),
	.rd_addr_i  (raddr[10:0]),
	.rd_data_o  (w_rdata1   )
    );
`endif

end
endgenerate

endmodule
