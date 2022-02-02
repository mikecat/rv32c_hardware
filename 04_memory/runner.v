`timescale 1ns/1ns

module runner();
	reg clock;
	reg reset;

	cpu CPU(.clock(clock), .reset(reset));

	reg [15:0] mem_temp[0:1023];
	integer i;
	initial begin
		$dumpfile("result.vcd");
		$dumpvars(0, runner);
		$readmemb("prog.txt", mem_temp);
		for (i = 0; i < 512; i = i + 1) begin
			CPU.mem.mem_array[i] <= { mem_temp[i * 2 + 1], mem_temp[i * 2] };
		end

		clock <= 1'b0;
		reset <= 1'b1;
		#100
		reset <= 1'b0;
		#4000
		$finish;
	end

	always #50 begin
		clock <= ~clock;
	end

endmodule
