module cpu(clock, reset);
	input clock;
	input reset;

	reg [31:0] pc;
	wire [31:0] next_pc;

	always @(posedge clock) begin
		if (reset) begin
			pc <= 32'd0;
		end else begin
			pc <= next_pc;
		end
	end

	wire [15:0] inst;
	pmem pmem(.addr(pc), .data(inst));

	wire [4:0] Rm, Rs, Rd;
	wire [31:0] Rm_data, Rs_data, immediate;
	wire [31:0] new_value;
	wire is_immediate;
	wire [9:0] alu_op;
	wire is_jmp, jmp_if_zero, jmp_absolute;

	decoder decoder(
		.inst(inst),
		.Rm(Rm), .Rs(Rs), .Rd(Rd), .immediate(immediate),
		.is_immediate(is_immediate), .alu_op(alu_op), // alu_ctl
		.is_jmp(is_jmp), .jmp_if_zero(jmp_if_zero), .jmp_absolute(jmp_absolute) // jmp_ctl
	);

	regs regs(
		.clock(clock), .reset(reset),
		.Rm(Rm), .Rs(Rs), .Rd(Rd),
		.Rm_data(Rm_data), .Rs_data(Rs_data), .Rd_data(new_value)
	);

	wire [31:0] alu_in2 = is_immediate ? immediate : Rs_data;
	wire [31:0] alu_answer;
	wire alu_is_zero;

	alu alu(
		.in1(Rm_data), .in2(alu_in2), .op(alu_op), .answer(alu_answer), .is_zero(alu_is_zero)
	);

	wire [31:0] jmp_base = jmp_absolute ? Rm_data : pc;
	wire [31:0] jmp_target_raw = jmp_base + immediate;
	wire [31:0] jmp_target = {jmp_target_raw[31:1], 1'b0};
	wire [31:0] pc_next_inst = pc + 32'd2;

	wire jmp_taken = is_jmp & (alu_is_zero ^ ~jmp_if_zero);
	assign next_pc = jmp_taken ? jmp_target : pc_next_inst;

	assign new_value = is_jmp ? pc_next_inst : alu_answer;

endmodule

module pmem(addr, data);
	input[31:0] addr;
	output[15:0] data;

	reg [15:0] mem[0:1023];

	assign data = mem[addr[10:1]];

endmodule

module decoder(inst, Rm, Rs, Rd, immediate, is_immediate, alu_op, is_jmp, jmp_if_zero, jmp_absolute);
	input [15:0] inst;
	output [4:0] Rm, Rs, Rd;
	output [31:0] immediate;
	output is_immediate;
	output [9:0] alu_op; // (LSB) + - & | ^ << >> >>> < LTU (MSB)
	output is_jmp, jmp_if_zero, jmp_absolute;

	wire [4:0] Rd_normal = inst[11:7];
	wire [4:0] Rm_normal = inst[6:2];
	wire [4:0] Rd_prime = {2'b0, inst[9:7]} + 5'd8;
	wire [4:0] Rm_prime = {2'b0, inst[4:2]} + 5'd8;
	wire [31:0] n6 = {{27{inst[12]}}, inst[6:2]};
	wire [31:0] n18 = {{15{inst[12]}}, inst[6:2], 12'b0}; // c.lui
	wire [31:0] u10 = {22'b0, inst[10:7], inst[12:11], inst[5], inst[6], 2'b0}; // c.addi4spn
	wire [31:0] n10 = {{23{inst[12]}}, inst[4:3], inst[5], inst[2], inst[6], 4'b0}; // c.addi16sp
	wire [31:0] n9 = {{24{inst[12]}}, inst[6:5], inst[2], inst[11:10], inst[4:3], 1'b0}; // c.beqz c.bnez
	wire [31:0] n12_c = {{21{inst[12]}}, inst[8], inst[10:9], inst[6], inst[7], inst[2], inst[11], inst[5:3], 1'b0}; // c.j c.jal

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

	wire c_beqz = inst[15:13] == 3'b110 && inst[1:0] == 2'b01;
	wire c_bnez = inst[15:13] == 3'b111 && inst[1:0] == 2'b01;
	wire c_j = inst[15:13] == 3'b101 && inst[1:0] == 2'b01;
	wire c_jr = inst[15:12] == 4'b1000 && inst[6:0] == 7'b0000010;
	wire c_jal = inst[15:13] == 3'b001 && inst[1:0] == 2'b01;
	wire c_jalr = inst[15:12] == 4'b1001 && inst[6:0] == 7'b0000010;

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
		c_beqz || c_bnez ? Rd_prime :
		c_j || c_jal ? 5'd0 :
		c_jr || c_jalr ? Rd_normal :
		c_mv ? Rm_normal :
		c_addi || c_slli || c_add ? Rd_normal :
		c_other_calc ? Rd_prime :
		5'd0;

	assign Rs =
		c_beqz || c_bnez ? 5'd0 :
		c_mv ? 5'd0 :
		c_add ? Rm_normal :
		c_other_calc_use_Rm ? Rm_prime :
		5'd0;

	assign Rd =
		c_addi4spn ? Rm_prime :
		c_addi16sp ? 5'd2 :
		c_beqz || c_bnez || c_j || c_jr ? 5'd0 :
		c_jal || c_jalr ? 5'd1 :
		c_li || c_lui || c_mv || c_addi || c_slli || c_add ? Rd_normal :
		c_other_calc ? Rd_prime :
		5'd0;

	assign immediate =
		c_addi4spn ? u10 :
		c_addi16sp ? n10 :
		c_beqz || c_bnez ? n9 :
		c_j || c_jal ? n12_c :
		c_jr || c_jalr ? 32'd0 :
		c_li || c_addi || c_slli || c_other_calc_use_n6 ? n6 :
		c_lui ? n18 :
		32'd0;

	assign is_immediate =
		c_li || c_lui || c_addi || c_slli || c_other_calc_use_n6 || c_addi4spn || c_addi16sp;

	assign alu_op =
		c_beqz || c_bnez ? 10'b0000000001 :
		c_j || c_jal || c_jr || c_jalr ? 10'b0000000000 :
		c_li || c_lui || c_mv || c_addi || c_add || c_addi4spn || c_addi16sp ? 10'b0000000001 :
		c_slli ? 10'b0000100000 :
		c_other_calc ? c_other_calc_op :
		10'd0;

	assign is_jmp =
		c_beqz || c_bnez || c_j || c_jr || c_jal || c_jalr;

	assign jmp_if_zero =
		c_beqz || c_j || c_jr || c_jal || c_jalr;

	assign jmp_absolute =
		c_jr || c_jalr;

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

module alu(in1, in2, op, answer, is_zero);
	input [31:0] in1, in2;
	input [9:0] op;
	output [31:0] answer;
	output is_zero;

	wire signed [31:0] in1_signed = $signed(in1);
	wire signed [31:0] in2_signed = $signed(in2);

	wire [31:0] shamt = {27'd0, in2[4:0]};
	// >>> operator didn't work for some reason
	wire [63:0] arith_shift = {{32{in1[31]}}, in1} >> {32'd0, shamt};

	assign answer =
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

	assign is_zero = answer == 32'd0;

endmodule
