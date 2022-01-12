`timescale 1ns/1ns

module runner();
	reg clock;
	reg reset;

	cpu CPU(.clock(clock), .reset(reset));

	initial begin
		$dumpfile("result.vcd");
		$dumpvars(0, runner);

		clock <= 1'b0;
		reset <= 1'b1;
		#100
		reset <= 1'b0;
		#10000
		$finish;
	end

	always #50 begin
		clock <= ~clock;
	end

endmodule
