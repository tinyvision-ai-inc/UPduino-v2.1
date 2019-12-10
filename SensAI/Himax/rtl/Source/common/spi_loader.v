
`timescale 1ns/10ps

module spi_loader (
input		resetn,        // 
input           clk,     // Clock (= RISC-V clock)

// FIFO interface
input           i_fill,
output reg      o_fifo_empty,
output reg      o_fifo_low,
input           i_fifo_rd,
output [31:0]   o_fifo_dout,

output reg      SPI_CSS,     // SPI I/F for flash access
output reg      SPI_CLK,    // 
input           SPI_MISO,     // 
output reg      SPI_MOSI,     // 

output          o_we,
output reg [7:0]o_waddr,
output [31:0]	o_wdata
);
    //================================================================================
    // Parameters
    //================================================================================
    parameter DUMMY_CYCLE = 19'd7;
    parameter IDLE         =  3'd0,         // SPI access FSM
              PREP         =  3'd1,         //
              CMD          =  3'd2,         //
	      SADDR        =  3'd3,         //
	      DUMMY        =  3'd4,         //
	      RDBYTE       =  3'd5,         //
	      WAIT         =  3'd6,         //
	      WAIT10       =  3'd7;         // 10us wait for wake up from power down
    parameter NO_SCK       =  1'b1,         // OR mask for SCK
              ON_SCK       =  1'b0;         //
    parameter FAST_RD      =  8'h0b,        // Fast read flash command
              RLS_DPD      =  8'hab;        // Release from deep power-down
    parameter ST_ADDR      = 24'h020000;    // Starting address of ROM in flash
    parameter IROM_SZ_BITS = 20'h02000;     //  1KB IROM size in bits
    parameter ROM_SZ_BITS  = IROM_SZ_BITS - 1;// 

    reg        prom_wr_en; // - IROM (PROM) write strobe
    reg [31:0] rom_data;   // 

    //================================================================================
    // Internal signals
    //================================================================================
    reg  [2  : 0] cst, nst;
    reg  [19 : 0] cnt;
    reg           sck_msk, sck_msk_pe;
    reg  [4  : 0] bit_cnt;  // Accumulate 32b of data
    reg           en;
    reg           phase;

    reg	[2:0]	cst_d;
    reg	[2:0]	nst_d;

    // FIFO control
    //
    reg	[9:0]	fifo_waddr;
    reg	[9:0]	fifo_raddr;

    wire[31:0]	fifo_wdata;
    wire[31:0]	fifo_rdata;

    wire	fifo_we;
    wire	fifo_re;

    reg		fifo_amfull;

    wire[10:0]	fifo_diff;
    reg	[9:0]	fifo_amt;

    //================================================================================
    // Toggling "en" to make two cycle per state FSM
    // - FSM moves to next state if "en=1"
    //================================================================================
    always @(posedge clk or negedge resetn)
        if(!resetn) en <= 1'b0;
	else if(!fifo_amfull)
	    en <= ~en;

    //================================================================================
    // Flash access FSM
    // - 9 cycles of dummy (not 8) for fast reading
    //================================================================================
    always @(posedge clk or negedge resetn)
        if     (!resetn      ) phase <= 1'b0; // Wake up phase
	else if(cst == WAIT10) phase <= 1'b1; // Read    phase

    always @(posedge clk or negedge resetn)
        if     (!resetn) 
	    cst <= IDLE;
	else if(en  && (!fifo_amfull))
	    cst <= nst;

    always @(*)
        case(cst)
	IDLE   : nst = i_fill ? PREP : IDLE;
	PREP   : nst =           CMD;
	CMD    : nst =  |cnt   ? CMD    : 
	                 phase ? SADDR  : WAIT10;
	SADDR  : nst = ~|cnt   ? DUMMY  : SADDR;
	DUMMY  : nst = ~|cnt   ? RDBYTE : DUMMY;
	RDBYTE : nst = ~i_fill ? IDLE   : RDBYTE;
//	WAIT   : nst = i_fill  ? WAIT : IDLE;
	WAIT10 : nst =  |cnt   ? WAIT10 : IDLE   ;
	default: nst =           PREP;
	endcase

    always @(posedge clk) // or negedge resetn)
//        if(!resetn) cnt <= 20'b0;
//	else 
	if(en && (!fifo_amfull))
	    case(cst)
	    IDLE   : cnt <=                  20'd00;         //  
	    PREP   : cnt <=                  20'd07;         //  8 bits  of CMD
	    CMD    : cnt <= |cnt   ? cnt - 20'd1 : 
	                     phase ? 20'd23  :               // 24 bits  of Start Address
			             20'd500  ;               // 10us+ delay after power up    
	    SADDR  : cnt <= |cnt   ? cnt - 20'd1 : DUMMY_CYCLE;  //  m bits  of DUMMY
	    DUMMY  : cnt <= |cnt   ? cnt - 20'd1 : ROM_SZ_BITS;  //  n bytes of data
	    RDBYTE : cnt <=                    20'd00;
	    WAIT   : cnt <=                    20'd00;
	    default: cnt <= |cnt   ? cnt - 20'd1 : 20'd00;
	    endcase

    //================================================================================
    // SPI signal generation 
    // - SPI_CSS is the CS_B
    //================================================================================
    always @(posedge clk or negedge resetn)
        if(!resetn) {SPI_CSS, SPI_MOSI} <= {1'b1, 1'b1};
	else if(en && (!fifo_amfull))
	    case(cst)
	    IDLE   : begin
		    SPI_CSS  <= 1'b0; 
		    SPI_MOSI  <= 1'b1;
		end
	    PREP   : begin
		    SPI_CSS  <= 1'b0;
		    SPI_MOSI  <= phase ? FAST_RD[7] : RLS_DPD[7];
		end
	    CMD    : if(|cnt) begin // Command
		    SPI_CSS  <= 1'b0; 
		    SPI_MOSI  <= phase ? FAST_RD[cnt-1] : RLS_DPD[cnt-1];
		end else begin      // S-Addr
		    SPI_CSS  <= phase ? 1'b0        : 1'b1; 
		    SPI_MOSI  <= phase ? ST_ADDR[23] : 1'b1;
		end
	    SADDR  : if(|cnt) begin // S-Addr
		    SPI_CSS  <= 1'b0;
		    SPI_MOSI  <= ST_ADDR[cnt-1];
		end else begin      // Dummy
		    SPI_CSS  <= 1'b0; 
		    SPI_MOSI  <= 1'b1; // Dummy
		end
	    DUMMY  : if(|cnt) begin // Dummy
		    SPI_CSS  <= 1'b0;
		    SPI_MOSI  <= 1'b1;
		end else begin      // Read byte
		    SPI_CSS  <= 1'b0; 
		    SPI_MOSI  <= 1'b1; // Don't care
		end
	    RDBYTE : if(i_fill) begin // Read byte
		    SPI_CSS  <= 1'b0;
		    SPI_MOSI  <= 1'b1;
		end else begin   
		    SPI_CSS  <= 1'b1;
		    SPI_MOSI  <= 1'b1;
		end
	    WAIT   : {SPI_CSS, SPI_MOSI} <= {1'b1, 1'b1};
	    default: {SPI_CSS, SPI_MOSI} <= {1'b1, 1'b1};
	    endcase

    always @(posedge clk)// or negedge resetn)
        //if(!resetn) SPI_CLK <= 1'b1;
	//else 
	if(!fifo_amfull)
	    case(cst)
		PREP, SADDR, DUMMY  : SPI_CLK <= ~en;
		CMD                 : SPI_CLK <= phase || |cnt ? ~en : 1'b1;
		RDBYTE              : SPI_CLK <= (i_fill) ? ~en : 1'b1;
		default             : SPI_CLK <= 1'b1;
		endcase

    //================================================================================
    // SPSRAM access (write) FSM
    // - Direct access using rom_acc, prom_wr_en, and rom_data (32b)
    // - If rom_acc & prom_wr_en, rom_data is written to SPSRAM at every cycle w/
    //   auto increased address
    //================================================================================
    always @(posedge clk or negedge resetn)
        if(!resetn) begin
	    bit_cnt    <= 5'd31;
	    prom_wr_en <=  1'b0;
	    rom_data   <= 32'b0;
	end else if(cst == RDBYTE && !en && !fifo_amfull) begin
	    bit_cnt    <= bit_cnt - 5'd1;
	    prom_wr_en <= (~|bit_cnt); 
	    rom_data   <= {rom_data[30 : 0], SPI_MISO};
	end else begin
	    prom_wr_en <=  1'b0;
	end

    always @(posedge clk or negedge resetn)
	if(!resetn)
	    o_waddr <= 8'd0;
	else if(!i_fill)
	    o_waddr <= 8'd0;
	else if(prom_wr_en)
	    o_waddr <= o_waddr + 8'd1;

    assign o_we = prom_wr_en;
    assign o_wdata = rom_data; 

// FIFO control
//
assign fifo_diff = {(fifo_waddr < fifo_raddr), fifo_waddr} - {1'b0, fifo_raddr};

always @(posedge clk)
begin
    fifo_amt    <= fifo_diff[9:0];
end

always @(posedge clk)
begin
    if(i_fill == 1'b0)
	fifo_amfull <= 1'b0;
    else if(fifo_amt == 10'd1020)
	fifo_amfull <= 1'b1;
    else if(fifo_amt == 10'd1010)
	fifo_amfull <= 1'b0;
end

always @(posedge clk)
begin
    if(i_fill == 1'b0)
	o_fifo_low <= 1'b1;
    else if(fifo_amt == 10'd260)
	o_fifo_low <= 1'b0;
    else if(fifo_amt == 10'd256)
	o_fifo_low <= 1'b1;
end

always @(posedge clk)
begin
    if(i_fill == 1'b0)
	fifo_waddr <= 10'd0;
    else if(prom_wr_en)
	fifo_waddr <= fifo_waddr + 10'd1;
end

always @(posedge clk)
begin
    if(i_fill == 1'b0)
	fifo_raddr <= 10'd0;
    else if(fifo_re)
	fifo_raddr <= fifo_raddr + 10'd1;
end

always @(posedge clk)
begin
    if(i_fill == 1'b0)
	o_fifo_empty <= 1'b1;
    else if(i_fifo_rd)
	o_fifo_empty <= !fifo_re;
    else if(fifo_re)
	o_fifo_empty <= 1'b0;
end

assign fifo_wdata = {rom_data[7:0], rom_data[15:8], rom_data[23:16], rom_data[31:24]};
assign fifo_we    = prom_wr_en;

assign fifo_re = (fifo_raddr != fifo_waddr) && (o_fifo_empty || i_fifo_rd);

`ifdef ICECUBE
SB_RAM1024x4 u_ram1024x4_x [7:0](
    .RDATA(fifo_rdata     ),
    .RADDR(fifo_raddr     ),
    .RCLK (clk            ),
    .RCLKE(1'b1           ),
    .RE   (fifo_re        ),
    .WADDR(fifo_waddr     ),
    .WCLK (clk            ),
    .WCLKE(1'b1           ),
    .WDATA(fifo_wdata     ),
    .WE   (fifo_we        )
);
`else // Radiant
sbram1024x4 u_ram1024x4_x [7:0](
    .wr_clk_i   (clk        ),
    .rd_clk_i   (clk        ),
    .wr_clk_en_i(1'b1       ),
    .rd_en_i    (fifo_re    ),
    .rd_clk_en_i(1'b1       ),
    .wr_en_i    (fifo_we    ),
    .wr_data_i  (fifo_wdata ),
    .wr_addr_i  (fifo_waddr ),
    .rd_addr_i  (fifo_raddr ),
    .rd_data_o  (fifo_rdata )
);

`endif

assign o_fifo_dout = fifo_rdata;

endmodule
//================================================================================
// End of file
//================================================================================

// vim: ts=8 sw=4
