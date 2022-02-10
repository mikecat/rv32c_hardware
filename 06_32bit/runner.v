`timescale 1ns/1ns

module runner();
	reg clock;
	reg reset;

	wire [31:0] paddr, pread, pwrite;
	wire pread_req, pwrite_req;
	wire [2:0] psize;

	cpu CPU(
		.clock(clock), .reset(reset),
		.paddr(paddr), .pread(pread), .pwrite(pwrite),
		.pread_req(pread_req), .pwrite_req(pwrite_req), .psize(psize)
	);

	assign pread = 32'b0;
	reg endsim;

	always @(posedge clock) begin
		if (reset) begin
			endsim <= 1'b0;
		end else begin
			if (pwrite_req) begin
				if (paddr == 32'hc0000000) begin
					$display("%08x", pwrite);
				end else if (paddr == 32'hc0000004) begin
					endsim <= 1'b1;
				end
			end
			if (endsim) begin
				$finish;
			end
		end
	end

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
		#1000000000
		$finish;
	end

	always #50 begin
		clock <= ~clock;
	end

endmodule
