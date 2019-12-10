module ice40_mul16_reg #(parameter ECP5_DEBUG = 1'b0) (
input           Clock   ,
input           ClkEn   ,
input           Aclr    ,
input	[15:0]	DataA   ,
input	[15:0]	DataB   ,
output	[31:0]	Result   
);

generate if(ECP5_DEBUG == 1'b1)
begin: g_on_ecp5_debug
    mul u_ecp5_mul(
	.Clock   (Clock   ),
	.ClkEn   (ClkEn   ),
	.Aclr    (Aclr    ),
	.DataA   (DataA   ), 
	.DataB   (DataB   ), 
	.Result  (Result  )
    );
end
else
begin
`ifdef ICECUBE
    wire[31:0]  w_result;
    reg	[31:0]	r_result;

    SB_MAC16 i_sbmac16
    (
	.A(DataA),
	.B(DataB),
	.C(16'b0),
	.D(16'b0),
	.O(w_result),
	.CLK(Clock),
	.CE(ClkEn),
	.IRSTTOP(Aclr),
	.IRSTBOT(Aclr),
	.ORSTTOP(Aclr),
	.ORSTBOT(Aclr),
	.AHOLD(1'b0),
	.BHOLD(1'b0),
	.CHOLD(1'b0),
	.DHOLD(1'b0),
	.OHOLDTOP(1'b0),
	.OHOLDBOT(1'b0),
	.OLOADTOP(1'b0),
	.OLOADBOT(1'b0),
	.ADDSUBTOP(1'b0),
	.ADDSUBBOT(1'b0),
	.CO(),
	.CI(1'b0),
	//MAC cascading ports.
	.ACCUMCI(1'b0),
	.ACCUMCO(),
	.SIGNEXTIN(1'b0),
	.SIGNEXTOUT()
    );
    // mult_16x16_bypass_signed [24:0] = 110_0000011_0000011_0000_0000
    // Read configuration settings [24:0] from left to right while filling the instance parameters.
    defparam i_sbmac16. B_SIGNED = 1'b1 ;
    defparam i_sbmac16. A_SIGNED = 1'b1 ;
    defparam i_sbmac16. MODE_8x8 = 1'b0 ;
    defparam i_sbmac16. BOTADDSUB_CARRYSELECT = 2'b00 ;
    defparam i_sbmac16. BOTADDSUB_UPPERINPUT = 1'b0 ;
    defparam i_sbmac16. BOTADDSUB_LOWERINPUT = 2'b00 ;
    defparam i_sbmac16. BOTOUTPUT_SELECT = 2'b11 ;
    defparam i_sbmac16. TOPADDSUB_CARRYSELECT = 2'b00 ;
    defparam i_sbmac16. TOPADDSUB_UPPERINPUT = 1'b0 ;
    defparam i_sbmac16. TOPADDSUB_LOWERINPUT = 2'b00 ;
    defparam i_sbmac16. TOPOUTPUT_SELECT = 2'b11 ;
    defparam i_sbmac16. PIPELINE_16x16_MULT_REG2 = 1'b0 ;
    defparam i_sbmac16. PIPELINE_16x16_MULT_REG1 = 1'b0 ;
    defparam i_sbmac16. BOT_8x8_MULT_REG = 1'b0 ;
    defparam i_sbmac16. TOP_8x8_MULT_REG = 1'b0 ;
    defparam i_sbmac16. D_REG = 1'b0 ;
    defparam i_sbmac16. B_REG = 1'b0 ;
    defparam i_sbmac16. A_REG = 1'b0 ;
    defparam i_sbmac16. C_REG = 1'b0 ;

    always @(posedge Clock)
    begin
	if(Aclr == 1'b1)
	    r_result <= 32'b0;
	else if(ClkEn == 1'b1)
	    r_result <= w_result;
    end

    assign Result = r_result;

`else // Radiant
    mle_ice40up_mul16 u_mul16(
	.clk_i   (Clock   ),
	.clk_en_i(ClkEn   ),
	.rst_i   (Aclr    ),
	.data_a_i(DataA   ), 
	.data_b_i(DataB   ), 
	.result_o(Result  )
    );
`endif
end
endgenerate

endmodule
