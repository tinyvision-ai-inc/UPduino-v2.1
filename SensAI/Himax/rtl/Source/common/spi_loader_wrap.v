
`timescale 1ns/10ps

module spi_loader_wrap #(parameter MEM_TYPE = "DUAL_SPRAM") (
input		resetn      , // 
input           clk         , // Clock (= RISC-V clock)
input           i_init      ,

// FIFO interface
input           i_fill      ,
output          o_fifo_empty,
output          o_fifo_low  ,
input           i_fifo_rd   ,
output [31:0]   o_fifo_dout ,

output          SPI_CSS     , // SPI I/F for flash access
output          SPI_CLK     , // 
input           SPI_MISO    , // 
output          SPI_MOSI    , // 

output          o_load_done
);

generate if(MEM_TYPE == "EBRAM")
begin: g_on_code_ebram
    spi_loader_ebram u_spi_loader(
	.clk          (clk          ),
	.resetn       (resetn       ),

	.o_load_done  (o_load_done  ),

	.i_fill       (i_fill       ),
	.i_init       (i_init       ),
	.o_fifo_empty (o_fifo_empty ),
	.o_fifo_low   (o_fifo_low   ),
	.i_fifo_rd    (i_fifo_rd    ),
	.o_fifo_dout  (o_fifo_dout  ),

	.SPI_CLK      (SPI_CLK      ),
	.SPI_CSS      (SPI_CSS      ),
	.SPI_MISO     (SPI_MISO     ),
	.SPI_MOSI     (SPI_MOSI     )
    );
end
else if(MEM_TYPE == "SINGLE_SPRAM")
begin: g_on_code_single_spram
    spi_loader_single_spram u_spi_loader(
	.clk          (clk          ),
	.resetn       (resetn       ),

	.o_load_done  (o_load_done  ),

	.i_fill       (i_fill       ),
	.i_init       (i_init       ),
	.o_fifo_empty (o_fifo_empty ),
	.o_fifo_low   (o_fifo_low   ),
	.i_fifo_rd    (i_fifo_rd    ),
	.o_fifo_dout  (o_fifo_dout  ),

	.SPI_CLK      (SPI_CLK      ),
	.SPI_CSS      (SPI_CSS      ),
	.SPI_MISO     (SPI_MISO     ),
	.SPI_MOSI     (SPI_MOSI     )
    );
end
else // DUAL_SPRAM
begin: g_on_code_dual_spram
    spi_loader_spram #(.QUAD_SPRAM(1'b0)) u_spi_loader(
	.clk          (clk          ),
	.resetn       (resetn       ),

	.o_load_done  (o_load_done  ),

	.i_fill       (i_fill       ),
	.i_init       (i_init       ),
	.o_fifo_empty (o_fifo_empty ),
	.o_fifo_low   (o_fifo_low   ),
	.i_fifo_rd    (i_fifo_rd    ),
	.o_fifo_dout  (o_fifo_dout  ),

	.SPI_CLK      (SPI_CLK      ),
	.SPI_CSS      (SPI_CSS      ),
	.SPI_MISO     (SPI_MISO     ),
	.SPI_MOSI     (SPI_MOSI     )
    );
end
endgenerate

endmodule
//================================================================================
// End of file
//================================================================================

// vim: ts=8 sw=4
