module cpu(clock, reset);
	input clock;
	input reset;

	reg [31:0] pc;

	always @(posedge clock) begin
		if (reset) begin
			pc <= 32'd0;
		end else begin
			pc <= pc + 32'd2;
		end
	end

endmodule
