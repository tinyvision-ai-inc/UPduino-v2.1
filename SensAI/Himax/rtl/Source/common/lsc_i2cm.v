`timescale 1ns / 100ps

module lsc_i2cm(
input		clk,     	// clk 24MHz
input		rw,    		// read/write, 1:read, 0:write
input		run,    	// start (level sensitive for repeat run)
input   [4:0]   interval,
input	[6:0]	dev_addr, 
input	[7:0]	ofs_addr, 
input   [7:0]   wr_data,
input		scl_in, 
input		sda_in,  
output reg	scl_out, 
output reg	sda_out, 
output reg      running,
output reg	done,    	// done (pulse)
output reg [7:0]rd_data, 
input		resetn
);

reg	[4:0]	interval_cnt;
reg	[7:0]   main_cnt;
wire	[1:0]	tick_cnt;
wire	[5:0]	seq_cnt;
wire		tick;

reg	[6:0]	dev_addr_lat;
reg	[7:0]	ofs_addr_lat;
reg	[7:0]	wr_data_lat;
reg		rw_lat;

always @(posedge clk)
begin
    if(running != 1'b1) begin
	dev_addr_lat <= dev_addr;
	ofs_addr_lat <= ofs_addr;
	wr_data_lat  <= wr_data ;
	rw_lat       <= rw;
    end
end

always @(posedge clk)
begin
    if(running == 1'b0)
	interval_cnt <= 5'b0;
    else if(tick)
	interval_cnt <= 5'b0;
    else 
	interval_cnt <= interval_cnt + 5'b1;
end

assign tick = (interval_cnt == interval);

assign tick_cnt = main_cnt[1:0];
assign seq_cnt  = main_cnt[7:2];

always @(posedge clk)
begin
    if(running == 1'b0)
	main_cnt <= 8'b0;
    else if(running && tick && (((rw_lat == 1'b1) && (main_cnt == 8'd159)) || ((rw_lat == 1'b0) && (main_cnt == 8'd115))))
	main_cnt <= 8'b0;
    else if(tick)
	main_cnt <= main_cnt + 8'd1;
end

always @(posedge clk)
begin
    if(resetn == 1'b0) running <= 1'b0;
    else if(done)      running <= 1'b0;
    else if(run)       running <= 1'b1;
end

always @(posedge clk)
begin
    if(running && tick && (((rw_lat == 1'b1) && (main_cnt == 8'd159)) || ((rw_lat == 1'b0) && (main_cnt == 8'd115))))
	done <= 1'b1;
    else
	done <= 1'b0;
end

always @(posedge clk)
begin
    if(resetn == 1'b0) scl_out <= 1'b1;
    else if(rw_lat == 1'b1)
	case(seq_cnt)
	    6'd0, 6'd20: // start
		scl_out <= (tick_cnt == 2'd0) || (tick_cnt == 2'd1) || (tick_cnt == 2'd2);
	    6'd19: // restart
		scl_out <= (tick_cnt == 2'd2) || (tick_cnt == 2'd3);
	    6'd39: // stop
		scl_out <= (tick_cnt == 2'd1) || (tick_cnt == 2'd2) || (tick_cnt == 2'd3);
	    default: // normal bit, restart
		scl_out <= (tick_cnt == 2'd1) || (tick_cnt == 2'd2);
	endcase
    else case (seq_cnt)
	    6'd0: // start
		scl_out <= (tick_cnt == 2'd0) || (tick_cnt == 2'd1) || (tick_cnt == 2'd2);
	    6'd28: // stop
		scl_out <= (tick_cnt == 2'd1) || (tick_cnt == 2'd2) || (tick_cnt == 2'd3);
	    default: // normal bit
		scl_out <= (tick_cnt == 2'd1) || (tick_cnt == 2'd2);
	endcase
end

always @(posedge clk)
begin
    if(resetn == 1'b0) sda_out <= 1'b1;
    else if(rw_lat == 1'b1)
	case(seq_cnt)
	    6'd0: // start
		sda_out <= (tick_cnt == 2'd0) || (tick_cnt == 2'd1);
	    6'd1:
		sda_out <= dev_addr_lat[6];
	    6'd2:
		sda_out <= dev_addr_lat[5];
	    6'd3:
		sda_out <= dev_addr_lat[4];
	    6'd4:
		sda_out <= dev_addr_lat[3];
	    6'd5:
		sda_out <= dev_addr_lat[2];
	    6'd6:
		sda_out <= dev_addr_lat[1];
	    6'd7:
		sda_out <= dev_addr_lat[0];
	    6'd8: // rw - write
		sda_out <= 1'b0;
	    // d9: ack
	    6'd10:
		sda_out <= ofs_addr_lat[7];
	    6'd11:
		sda_out <= ofs_addr_lat[6];
	    6'd12:
		sda_out <= ofs_addr_lat[5];
	    6'd13:
		sda_out <= ofs_addr_lat[4];
	    6'd14:
		sda_out <= ofs_addr_lat[3];
	    6'd15:
		sda_out <= ofs_addr_lat[2];
	    6'd16:
		sda_out <= ofs_addr_lat[1];
	    6'd17:
		sda_out <= ofs_addr_lat[0];
	    // d18: ack
	    6'd19: // restart
		sda_out <= (tick_cnt == 2'd1) || (tick_cnt == 2'd2) || (tick_cnt == 2'd3);
	    6'd20: // start
		sda_out <= (tick_cnt == 2'd0) || (tick_cnt == 2'd1);
	    6'd21:
		sda_out <= dev_addr_lat[6];
	    6'd22:
		sda_out <= dev_addr_lat[5];
	    6'd23:
		sda_out <= dev_addr_lat[4];
	    6'd24:
		sda_out <= dev_addr_lat[3];
	    6'd25:
		sda_out <= dev_addr_lat[2];
	    6'd26:
		sda_out <= dev_addr_lat[1];
	    6'd27:
		sda_out <= dev_addr_lat[0];
	    // d28: rw - read
	    // d29: ack
	    // d30 ~ 37: data read
	    // d38: ack_bar
	    6'd39: // stop
		sda_out <= (tick_cnt == 2'd2) || (tick_cnt == 2'd3);
	    default:
		sda_out <= 1'b1;
	endcase
    else case (seq_cnt)
	    6'd0: // start
		sda_out <= (tick_cnt == 2'd0) || (tick_cnt == 2'd1);
	    6'd1:
		sda_out <= dev_addr_lat[6];
	    6'd2:
		sda_out <= dev_addr_lat[5];
	    6'd3:
		sda_out <= dev_addr_lat[4];
	    6'd4:
		sda_out <= dev_addr_lat[3];
	    6'd5:
		sda_out <= dev_addr_lat[2];
	    6'd6:
		sda_out <= dev_addr_lat[1];
	    6'd7:
		sda_out <= dev_addr_lat[0];
	    6'd8: // rw - write
		sda_out <= 1'b0;
	    // d9: ack
	    6'd10:
		sda_out <= ofs_addr_lat[7];
	    6'd11:
		sda_out <= ofs_addr_lat[6];
	    6'd12:
		sda_out <= ofs_addr_lat[5];
	    6'd13:
		sda_out <= ofs_addr_lat[4];
	    6'd14:
		sda_out <= ofs_addr_lat[3];
	    6'd15:
		sda_out <= ofs_addr_lat[2];
	    6'd16:
		sda_out <= ofs_addr_lat[1];
	    6'd17:
		sda_out <= ofs_addr_lat[0];
	    // d18: ack
	    6'd19:
		sda_out <= wr_data_lat[7];
	    6'd20:
		sda_out <= wr_data_lat[6];
	    6'd21:
		sda_out <= wr_data_lat[5];
	    6'd22:
		sda_out <= wr_data_lat[4];
	    6'd23:
		sda_out <= wr_data_lat[3];
	    6'd24:
		sda_out <= wr_data_lat[2];
	    6'd25:
		sda_out <= wr_data_lat[1];
	    6'd26:
		sda_out <= wr_data_lat[0];
	    // d27: ack
	    6'd28: // stop
		sda_out <= (tick_cnt == 2'd2) || (tick_cnt == 2'd3);
	    default:
		sda_out <= 1'b1;
	endcase
end

always @(posedge clk)
begin
    if(resetn == 1'b0) rd_data <= 8'b0;
    else if((rw_lat == 1'b1) && (tick_cnt == 2'd2) && tick)
	case(seq_cnt)
	    6'd30:
		rd_data[7] <= sda_in;
	    6'd31:
		rd_data[6] <= sda_in;
	    6'd32:
		rd_data[5] <= sda_in;
	    6'd33:
		rd_data[4] <= sda_in;
	    6'd34:
		rd_data[3] <= sda_in;
	    6'd35:
		rd_data[2] <= sda_in;
	    6'd36:
		rd_data[1] <= sda_in;
	    6'd37:
		rd_data[0] <= sda_in;
	endcase
end

endmodule
