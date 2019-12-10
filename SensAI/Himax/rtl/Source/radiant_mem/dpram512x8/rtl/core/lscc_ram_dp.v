// =============================================================================
// >>>>>>>>>>>>>>>>>>>>>>>>> COPYRIGHT NOTICE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
// -----------------------------------------------------------------------------
//   Copyright (c) 2017 by Lattice Semiconductor Corporation
//   ALL RIGHTS RESERVED
// -----------------------------------------------------------------------------
//
//   Permission:
//
//      Lattice SG Pte. Ltd. grants permission to use this code
//      pursuant to the terms of the Lattice Reference Design License Agreement.
//
//
//   Disclaimer:
//
//      This VHDL or Verilog source code is intended as a design reference
//      which illustrates how these types of functions can be implemented.
//      It is the user's responsibility to verify their design for
//      consistency and functionality through the use of formal
//      verification methods.  Lattice provides no warranty
//      regarding the use or functionality of this code.
//
// -----------------------------------------------------------------------------
//
//                  Lattice SG Pte. Ltd.
//                  101 Thomson Road, United Square #07-02
//                  Singapore 307591
//
//
//                  TEL: 1-800-Lattice (USA and Canada)
//                       +65-6631-2000 (Singapore)
//                       +1-503-268-8001 (other locations)
//
//                  web: http://www.latticesemi.com/
//                  email: techsupport@latticesemi.com
//
// -----------------------------------------------------------------------------
//
// =============================================================================
//                         FILE DETAILS
// Project               : iCE40 UltraPlus
// File                  : lscc_ram_dp.v
// Title                 :
// Dependencies          :
// Description           : Implements a pseudo Dual Port RAM implementing EBR.
// =============================================================================
//                        REVISION HISTORY
// Version               : 1.0.0.
// Author(s)             :
// Mod. Date             :
// Changes Made          : Initial release.
// =============================================================================

`ifndef LSCC_RAM_DP
`define LSCC_RAM_DP
module lscc_ram_dp #
(
parameter                     WADDR_DEPTH      = 512,
parameter                     WADDR_WIDTH      = clog2(WADDR_DEPTH),
parameter                     WDATA_WIDTH      = 36,
parameter                     RADDR_DEPTH      = 512,
parameter                     RADDR_WIDTH      = clog2(RADDR_DEPTH),
parameter                     RDATA_WIDTH      = 36,
parameter                     REGMODE          = "reg",
parameter                     GSR              = "",
parameter                     RESETMODE        = "sync",
parameter                     OPTIMIZATION     = "", 
parameter                     INIT_FILE        = "none",
parameter                     INIT_FILE_FORMAT = "binary",
parameter                     FAMILY           = "",
parameter                     MODULE_TYPE      = "ram_dp",
parameter                     INIT_MODE        = "none",
parameter                     BYTE_ENABLE      = 0,
parameter                     BYTE_SIZE        = 8,
parameter                     BYTE_WIDTH       = 0,
parameter                     PIPELINES        = 0,
parameter                     ECC_ENABLE       = ""
)
// -----------------------------------------------------------------------------
// Input/Output Ports
// -----------------------------------------------------------------------------
(
input                         wr_clk_i,
input                         rd_clk_i,
input                         rst_i,
input                         wr_clk_en_i,
input                         rd_clk_en_i,
input                         rd_out_clk_en_i,

input                         wr_en_i,
input [WDATA_WIDTH-1:0]       wr_data_i,
input [WADDR_WIDTH-1:0]       wr_addr_i,
input 						  rd_en_i,
input [RADDR_WIDTH-1:0]       rd_addr_i,

output reg [RDATA_WIDTH-1:0]  rd_data_o
);

// -----------------------------------------------------------------------------
// Local Parameters
// -----------------------------------------------------------------------------
// Memory size = (addr_depth_a x data_width_a) = (addr_depth_b x data_width_b)
localparam                    MEM_DEPTH = (WDATA_WIDTH * (1 << WADDR_WIDTH));

wire                         rd_en;
wire                         wr_en;

// -----------------------------------------------------------------------------
// Register Declarations
// -----------------------------------------------------------------------------
reg [RDATA_WIDTH-1:0]        dataout_reg;
reg [RDATA_WIDTH-1:0]        mem[2 ** RADDR_WIDTH-1:0] /* synthesis syn_ramstyle="rw_check" */;

// -----------------------------------------------------------------------------
// Assign Statements
// -----------------------------------------------------------------------------
assign                       rd_en = rd_en_i & rd_clk_en_i;
assign                       wr_en = wr_en_i & wr_clk_en_i;

// -----------------------------------------------------------------------------
// Initial Block
// -----------------------------------------------------------------------------
initial begin
  if (INIT_MODE == "mem_file" && INIT_FILE != "none") begin
    if (INIT_FILE_FORMAT == "hex") begin
      $readmemh(INIT_FILE, mem);
    end
    else begin
  	  $readmemb(INIT_FILE, mem);
    end
  end
end

// -----------------------------------------------------------------------------
// Generate Sequential Blocks
// -----------------------------------------------------------------------------
generate
  if (REGMODE == "noreg") begin

    always @(posedge wr_clk_i) begin
      if (wr_en == 1'b1) begin
          mem[wr_addr_i] <= wr_data_i;
      end
    end

    always @(posedge rd_clk_i) begin
      if (rd_en == 1'b1) begin
        rd_data_o <= mem[rd_addr_i];
      end
    end
		
  end //if (REGMODE == "noreg")  
endgenerate

generate
  if (REGMODE == "reg") begin

    always @(posedge wr_clk_i) begin
      if (wr_en == 1'b1) begin
          mem[wr_addr_i] <= wr_data_i;
      end
    end
    
    always @(posedge rd_clk_i) begin
      if (rd_en == 1'b1) begin
        dataout_reg <= mem[rd_addr_i];
      end
	end

	if (RESETMODE == "sync") begin 
    
	always @ (posedge rd_clk_i) begin
        if (rst_i == 1'b1) begin
          rd_data_o <= 'h0;
	    end
        else if (rd_out_clk_en_i == 1'b1) begin
		  rd_data_o <= dataout_reg;
        end
      end
    
	end //if (RESETMODE == "sync")

	if (RESETMODE == "async") begin 
	
      always @ (posedge rd_clk_i or posedge rst_i) begin
        if (rst_i == 1'b1) begin
          rd_data_o <= 'h0;
	    end
        else if (rd_out_clk_en_i == 1'b1) begin
		  rd_data_o <= dataout_reg;
        end
      end 
    
	end //if (RESETMODE == "async") 
	
  end //if (REGMODE == "reg")
endgenerate	
  
//------------------------------------------------------------------------------
// Function Definition
//------------------------------------------------------------------------------
function [31:0] clog2;
  input [31:0] value;
  reg   [31:0] num;
  begin
    num = value - 1;
    for (clog2=0; num>0; clog2=clog2+1) num = num>>1;
  end
endfunction

endmodule
//=============================================================================
// lscc_ram_dp.v
// Local Variables:
// verilog-library-directories: ("../../common")
// End:
//=============================================================================
`endif