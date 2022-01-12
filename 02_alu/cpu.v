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

	wire [4:0] Rm, Rs, Rd;
	wire [31:0] Rm_data, Rs_data, immediate;
	wire [31:0] new_value;
	wire [9:0] alu_op;

	decoder decoder(
		.inst(inst), .Rm(Rm), .Rs(Rs), .Rd(Rd),
		.immediate(immediate), .is_immediate(is_immediate),
		.alu_op(alu_op)
	);

	regs regs(
		.clock(clock), .reset(reset),
		.Rm(Rm), .Rs(Rs), .Rd(Rd),
		.Rm_data(Rm_data), .Rs_data(Rs_data), .Rd_data(new_value)
	);

	wire [31:0] alu_in2 = is_immediate ? immediate : Rs_data;

	alu alu(
		.in1(Rm_data), .in2(alu_in2), .op(alu_op), .out(new_value)
	);

endmodule

module pmem(addr, data);
	input[31:0] addr;
	output[15:0] data;

	reg [15:0] mem[0:1023];

	assign data = mem[addr[10:1]];

endmodule

module decoder(inst, Rm, Rs, Rd, immediate, is_immediate, alu_op);
	input [15:0] inst;
	output [4:0] Rm, Rs, Rd;
	output [31:0] immediate;
	output is_immediate;
	output [9:0] alu_op; // (LSB) + - & | ^ << >> >>> < LTU (MSB)

	wire [4:0] Rd_normal = inst[11:7];
	wire [4:0] Rm_normal = inst[6:2];
	wire [4:0] Rd_prime = {2'b0, inst[9:7]} + 5'd8;
	wire [4:0] Rm_prime = {2'b0, inst[4:2]} + 5'd8;
	wire [31:0] n6 = {{27{inst[12]}}, inst[6:2]};
	wire [31:0] n18 = {{15{inst[12]}}, inst[6:2], 12'b0}; // c.lui
	wire [31:0] u10 = {22'b0, inst[10:7], inst[12:11], inst[5], inst[6], 2'b0}; // c.addi4spn
	wire [31:0] n10 = {{23{inst[12]}}, inst[4:3], inst[5], inst[2], inst[6], 4'b0}; // c.addi16sp

	wire c_li = inst[15:13] == 3'b010 && inst[1:0] == 2'b01;
	wire c_lui = inst[15:13] == 3'b011 && inst[1:0] == 2'b01;
	wire c_mv = inst[15:12] == 4'b1000 && inst[1:0] == 2'b10;
	wire c_addi = inst[15:13] == 3'b000 && inst[1:0] == 2'b01;
	wire c_slli = inst[15:12] == 4'b0000 && inst[1:0] == 2'b10;
	wire c_add = inst[15:12] == 4'b1001 && inst[1:0] == 2'b10;
	wire c_other_calc = inst[15:13] == 3'b100 && inst[1:0] == 2'b01 && (inst[12] == 1'b0 || inst[11:10] == 2'b10);
	wire c_other_calc_use_n6 = c_other_calc && inst[11:10] != 2'b11;
	wire c_other_calc_use_Rm = c_other_calc && inst[11:10] == 2'b11;
	wire c_addi4spn = inst[15:13] == 3'b000 && inst[1:0] == 2'b00;
	wire c_addi16sp = inst[15:13] == 3'b011 && inst[11:7] == 5'b00010 && inst[1:0] == 2'b01;

	wire [9:0] c_other_calc_op_11 =
		inst[6:5] == 2'b00 ? 10'b0000000010 : // c.sub
		inst[6:5] == 2'b01 ? 10'b0000010000 : // c.xor
		inst[6:5] == 2'b10 ? 10'b0000001000 : // c.or
		10'b0000000100; // c.and

	wire [9:0] c_other_calc_op =
		inst[11:10] == 2'b00 ? 10'b0001000000 : // c.srli
		inst[11:10] == 2'b01 ? 10'b0010000000 : // c.srai
		inst[11:10] == 2'b10 ? 10'b0000000100 : // c.andi
		c_other_calc_op_11;

	assign Rm =
		c_addi4spn || c_addi16sp ? 5'd2 :
		c_li || c_lui ? 5'd0 :
		c_mv ? Rm_normal :
		c_addi || c_slli || c_add ? Rd_normal :
		c_other_calc ? Rd_prime :
		5'd0;

	assign Rs =
		c_mv ? 5'd0 :
		c_add ? Rm_normal :
		c_other_calc_use_Rm ? Rm_prime :
		5'd0;

	assign Rd =
		c_addi4spn ? Rm_prime :
		c_addi16sp ? 5'd2 :
		c_li || c_lui || c_mv || c_addi || c_slli || c_add ? Rd_normal :
		c_other_calc ? Rd_prime :
		5'd0;

	assign immediate =
		c_addi4spn ? u10 :
		c_addi16sp ? n10 :
		c_li || c_addi || c_slli || c_other_calc_use_n6 ? n6 :
		c_lui ? n18 :
		32'd0;

	assign is_immediate =
		c_li || c_lui || c_addi || c_slli || c_other_calc_use_n6 || c_addi4spn || c_addi16sp;

	assign alu_op =
		c_li || c_lui || c_mv || c_addi || c_add || c_addi4spn || c_addi16sp ? 10'b0000000001 :
		c_slli ? 10'b0000100000 :
		c_other_calc ? c_other_calc_op :
		10'd0;

endmodule

module regs(clock, reset, Rm, Rs, Rd, Rm_data, Rs_data, Rd_data);
	input clock, reset;
	input[4:0] Rm, Rs, Rd;
	output[31:0] Rm_data, Rs_data;
	input[31:0] Rd_data;

	reg [31:0] regs[0:31];

	assign Rm_data = Rm == 5'd0 ? 0 : regs[Rm];
	assign Rs_data = Rs == 5'd0 ? 0 : regs[Rs];

	integer i;
	always @(posedge clock) begin
		if (reset) begin
			for (i = 0; i < 32; i++) begin
				regs[i] <= 32'd0;
			end
		end else begin
			if (Rd != 5'd0) begin
				regs[Rd] <= Rd_data;
			end
		end
	end

endmodule

module alu(in1, in2, op, out);
	input [31:0] in1, in2;
	input [9:0] op;
	output [31:0] out;

	wire signed [31:0] in1_signed = $signed(in1);
	wire signed [31:0] in2_signed = $signed(in2);

	wire [31:0] shamt = {27'd0, in2[4:0]};
	// >>> operator didn't work for some reason
	wire [63:0] arith_shift = {{32{in1[31]}}, in1} >> {32'd0, shamt};

	assign out =
		op[0] ? in1 + in2 :
		op[1] ? in1 - in2 :
		op[2] ? in1 & in2 :
		op[3] ? in1 | in2 :
		op[4] ? in1 ^ in2 :
		op[5] ? in1 << shamt :
		op[6] ? in1 >> shamt :
		op[7] ? arith_shift[31:0] :
		op[8] ? (in1_signed < in2_signed ? 32'd1 : 32'd0):
		op[9] ? (in1 < in2 ? 32'd1 : 32'd0) :
		32'd0;

endmodule
