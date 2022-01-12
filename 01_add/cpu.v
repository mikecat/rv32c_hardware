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

	wire [15:0] inst;
	pmem pmem(.addr(pc), .data(inst));

	wire [4:0] select = inst[11:7];
	wire [31:0] immediate_value = {{27{inst[12]}}, inst[6:2]};

	wire [31:0] current_value;
	wire [31:0] new_value = current_value + immediate_value;

	regs regs(.clock(clock), .reset(reset), .select(select), .in_data(new_value), .out_data(current_value));

endmodule

module pmem(addr, data);
	input[31:0] addr;
	output[15:0] data;

	reg [15:0] mem[0:1023];

	assign data = mem[addr[10:1]];

endmodule

module regs(clock, reset, select, in_data, out_data);
	input clock;
	input reset;
	input[4:0] select;
	input[31:0] in_data;
	output[31:0] out_data;

	reg [31:0] regs[0:31];

	assign out_data = select == 5'd0 ? 0 : regs[select];

	integer i;
	always @(posedge clock) begin
		if (reset) begin
			for (i = 0; i < 32; i++) begin
				regs[i] <= 32'd0;
			end
		end else begin
			if (select != 5'd0) begin
				regs[select] <= in_data;
			end
		end
	end

endmodule
