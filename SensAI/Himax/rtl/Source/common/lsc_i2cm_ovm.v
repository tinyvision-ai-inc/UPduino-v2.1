
module lsc_i2cm_ovm(
input             clk    , // 24MHz clk
input             init   ,

input             scl_in ,
input             sda_in ,
output            scl_out,
output            sda_out,
output reg	  init_done,
input             resetn
);

parameter CONF_SEL      = "7692"; // MDP board
parameter [7:0]	NUM_CMD = 8'd128;

// state machine
parameter [3:0] 
	IDLE  = 4'b0000,
	INITS = 4'b0001,
	INITC = 4'b0010,
	MONS  = 4'b0100,
	MONC  = 4'b0101;

reg     [3:0]   state;
reg     [3:0]   nstate;

reg	[7:0]	i2c_cnt;
wire	[15:0]	i2c_cmd;
wire		i2c_set;
wire		i2c_done;
wire    [7:0]   i2c_rd_data;
wire            i2c_running;

reg		init_req;
reg	[1:0]	init_d;

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) init_d <= 2'b0;
    else               init_d <= {init_d[0], init};
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)             init_req <= 1'b1;
    else if(init_d == 2'b01)       init_req <= 1'b1;
    else if(state == INITS)        init_req <= 1'b0;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) 
	state <= IDLE;
    else               
	state <= nstate;
end

always @(*)
begin
    case(state)
	IDLE:
	    nstate <= init_req ? INITS : IDLE;
	INITS:
	    nstate <= INITC;
	INITC:
	    nstate <= i2c_running ? INITC : ((i2c_cnt == NUM_CMD) ? IDLE : INITS);
//	MONS:
//	    nstate <= MONC;
//	MONC:
//	    nstate <= i2c_running ? MONC : IDLE;
	default:
	    nstate <= IDLE ;
    endcase
end

assign i2c_set = ((state == INITS) || (state == MONS));

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0)     i2c_cnt <= 8'd0;
    else if(state == IDLE) i2c_cnt <= 8'd0;
    else if(i2c_done)      i2c_cnt <= i2c_cnt + 8'd1;
end

always @(posedge clk or negedge resetn)
begin
    if(resetn == 1'b0) 
	init_done <= 1'b0;
    else if(init_req == 1'b1)
	init_done <= 1'b0;
    else if(i2c_cnt == NUM_CMD)
	init_done <= 1'b1;
end

lsc_i2cm u_lsc_i2cm(
    .clk     (clk           ),
    .rw      (1'b0          ),
    .run     (i2c_set       ),
    .interval(5'd30         ),
    .dev_addr(CONF_SEL == "7670" ? 7'h21 : 7'h3c),
    .ofs_addr(i2c_cmd[15: 8]),
    .wr_data (i2c_cmd[ 7: 0]),
    .scl_in  (scl_in        ),
    .sda_in  (sda_in        ),
    .scl_out (scl_out       ),
    .sda_out (sda_out       ),
    .running (i2c_running   ),
    .done    (i2c_done      ),
    .rd_data (i2c_rd_data   ),
    .resetn  (resetn        )
);

`ifdef ICECUBE // 7692 only
SB_RAM256x16 u_ram256x16_ovm (
    .RDATA (i2c_cmd ),
    .RADDR (i2c_cnt ),
    .RCLK  (clk     ),
    .RCLKE (1'b1    ),
    .RE    (1'b1    ),
    .WADDR (8'b0    ),
    .WCLK  (clk     ),
    .WCLKE (1'b0    ),
    .WDATA (16'b0   ),
    .WE    (1'b0    ),
    .MASK  (16'hffff)
);

defparam u_ram256x16_ovm.INIT_0 = 256'h1af6_190a_18a4_1765_1206_1200_6210_1603_ff00_b530_ff01_4842_1eb3_6952_0e08_1280; // 16
defparam u_ram256x16_ovm.INIT_1 = 256'h7134_7000_8203_d048_cbe0_ca01_c980_c802_cf80_ce00_cdaa_cc00_813f_6720_6411_3e20; // 32
defparam u_ram256x16_ovm.INIT_2 = 256'h0e00_4c7d_5140_504d_2157_2000_1101_7c00_7b1f_7a4e_79c2_7801_7764_7600_7598_7428;	// 48
defparam u_ram256x16_ovm.INIT_3 = 256'hb705_c11e_c0c5_bfb8_be0e_bd27_bc84_bbab_8b20_8a22_892a_8800_8700_8600_8500_807f; // 64
defparam u_ram256x16_ovm.INIT_4 = 256'ha865_a758_a64a_a529_a415_a30b_26b3_2568_2478_5d42_5c69_5b9f_5a1f_ba18_b900_b809; // 80
defparam u_ram256x16_ovm.INIT_5 = 256'h9299_9122_9050_8f19_8d11_8c56_b214_b1f1_b0e1_afcb_aeb0_ada0_ac8e_ab85_aa7b_a970; // 96
defparam u_ram256x16_ovm.INIT_6 = 256'h96ff_8e92_a20c_a15c_a061_9fff_9ef0_9df0_9cf0_9b50_9a54_992a_9833_951f_9411_938f; // 112
//defparam u_ram256x16_ovm.INIT_7 = 256'h0e00_0e00_0e00_0e00_0e00_d204_d500_d440_d328_2ab0_15ff_1460_1101_0cd6_5e00_9700; // 128 (Org bright control)
//defparam u_ram256x16_ovm.INIT_7 = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_1101_0cd6_5e00_9700; // 128 (Org no brignt control)
defparam u_ram256x16_ovm.INIT_7 = 256'h0e00_0e00_0e00_0e00_0e00_d204_d500_d450_d328_2ab0_15fc_1460_1101_0cd6_5e00_9700; // 128 (Org bright control)
defparam u_ram256x16_ovm.INIT_8 = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_9 = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_A = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_B = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_C = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_D = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_E = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
defparam u_ram256x16_ovm.INIT_F = 256'h0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00_0e00;
`else // Radiant
generate if(CONF_SEL == "7670")
begin: g_on_ov7670
    rom_ov7670_cfg u_rom_ov7670_cfg (
	.clk_i     (clk     ),
	.clk_en_i  (1'b1    ),
	.wr_en_i   (1'b0    ),
	.wr_data_i (16'b0   ),
	.addr_i    (i2c_cnt ),
	.rd_data_o (i2c_cmd )
    );
end
else if(CONF_SEL == "FIXED_MAX")
begin
    rom_ov7692_fixed_max_cfg u_rom_ov7692_fixed_max_cfg (
	.clk_i     (clk     ),
	.clk_en_i  (1'b1    ),
	.wr_en_i   (1'b0    ),
	.wr_data_i (16'b0   ),
	.addr_i    (i2c_cnt ),
	.rd_data_o (i2c_cmd )
    );
end
else
begin // Default: ov7692
    sbram_256x16_ovm u_ram256x16_ovm (
	.wr_clk_i   (clk     ),
	.rd_clk_i   (clk     ),
	.wr_clk_en_i(1'b0    ),
	.rd_en_i    (1'b1    ),
	.rd_clk_en_i(1'b1    ),
	.wr_en_i    (1'b0    ),
	.wr_data_i  (16'b0   ),
	.wr_addr_i  (8'b0    ),
	.rd_addr_i  (i2c_cnt ),
	.rd_data_o  (i2c_cmd )
    );
end
endgenerate

`endif

endmodule
