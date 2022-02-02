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
	wire [31:0] daddr, dread, dwrite;
	wire dread_req, dwrite_req;
	wire [2:0] dsize;
	wire dread_se;

	mem mem(
		.clock(clock), .iaddr(pc), .iread(inst),
		.daddr(daddr), .dread(dread), .dwrite(dwrite),
		.dread_req(dread_req), .dwrite_req(dwrite_req), .dsize(dsize), .dread_se(dread_se)
	);

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
		.dread_req(dread_req), .dwrite_req(dwrite_req), .dsize(dsize), .dread_se(dread_se), // mem_ctl
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

	wire [31:0] ex_result = is_jmp ? pc_next_inst : alu_answer;

	assign daddr = ex_result;
	assign dwrite = Rs_data;

	assign new_value = dread_req ? dread : ex_result;

endmodule

module mem(clock, iaddr, iread, daddr, dread, dwrite, dread_req, dwrite_req, dsize, dread_se);
	input clock;
	input [31:0] iaddr;
	output [15:0] iread;
	input [31:0] daddr;
	output [31:0] dread;
	input [31:0] dwrite;
	input dread_req, dwrite_req;
	input [2:0] dsize; // one-hot code (LSB) 1-byte 2-byte 4-byte (MSB)
	input dread_se; // sign extend

	reg [31:0] mem_array[0:511];

	wire [31:0] iaddr1 = { iaddr[31:2], 2'b00 };
	wire [31:0] iread1 = mem_array[iaddr1[10:2]];

	assign iread = iaddr[1] ? iread1[31:16] : iread1[15:0];

	wire [31:0] daddr1 = { daddr[31:2], 2'b00 };
	wire [31:0] daddr2 = daddr1 + 32'b100;
	wire [31:0] dread1 = mem_array[daddr1[10:2]];
	wire [31:0] dread2 = mem_array[daddr2[10:2]];
	wire dreq1 = (dread_req || dwrite_req);
	wire dreq2 = (dread_req || dwrite_req) && ((dsize[1] && daddr[1:0] >= 2'b11) || (dsize[2] && daddr[1:0] >= 2'b01));

	wire [31:0] dwrite1 = dsize[1] ? (
		// 2-byte access
		daddr[1:0] == 2'b00 ? { dread1[31:16], dwrite[15:0] } :
		daddr[1:0] == 2'b01 ? { dread1[31:24], dwrite[15:0], dread1[7:0] } :
		daddr[1:0] == 2'b10 ? { dwrite[15:0], dread1[15:0] } :
		{ dread1[7:0], dread1[23:0] }
	) : dsize[2] ? (
		// 4-byte access
		daddr[1:0] == 2'b00 ? dwrite :
		daddr[1:0] == 2'b01 ? { dwrite[23:0], dread1[7:0] } :
		daddr[1:0] == 2'b10 ? { dwrite[15:0], dread1[15:0] } :
		{ dwrite[7:0], dread1[23:0] }
	) : (
		// 1-byte access
		daddr[1:0] == 2'b00 ? { dread1[31:8], dwrite[7:0] } :
		daddr[1:0] == 2'b01 ? { dread1[31:16], dwrite[7:0], dread1[7:0] } :
		daddr[1:0] == 2'b10 ? { dread1[31:24], dwrite[7:0], dread1[15:0] } :
		{ dwrite[7:0], dread1[23:0] }
	);
	wire [31:0] dwrite2 = dsize[1] ? (
		// 2-byte access
		daddr[1:0] == 2'b11 ? { dread2[31:8], dwrite[15:8] } :
		dread2
	) : dsize[2] ? (
		// 4-byte access
		daddr[1:0] == 2'b00 ? dread2 :
		daddr[1:0] == 2'b01 ? { dread2[31:8], dwrite[31:24] } :
		daddr[1:0] == 2'b10 ? { dread2[31:16], dwrite[31:16] } :
		{ dread2[31:24], dwrite[31:8] }
	) : (
		// 1-byte access
		dread2
	);

	wire [31:0] dread_raw =
		daddr[1:0] == 2'b00 ? dread1 :
		daddr[1:0] == 2'b01 ? { dread2[7:0], dread1[31:8] } :
		daddr[1:0] == 2'b10 ? { dread2[15:0], dread1[31:16] } :
		{ dread2[23:0], dread1[31:24] };

	assign dread =
		dsize[0] ? { {24{dread_raw[7] & dread_se}}, dread_raw[7:0] } :
		dsize[1] ? { {16{dread_raw[15] & dread_se}}, dread_raw[15:0] } :
		dread_raw;

	always @(posedge clock) begin
		if (dreq1 && dwrite_req) begin
			mem_array[daddr1[10:2]] <= dwrite1;
		end
		if (dreq2 && dwrite_req) begin
			mem_array[daddr2[10:2]] <= dwrite2;
		end
	end

endmodule

module decoder(
	inst,
	Rm, Rs, Rd, immediate,
	is_immediate, alu_op, // alu_ctl
	dread_req, dwrite_req, dsize, dread_se, // mem_ctl
	is_jmp, jmp_if_zero, jmp_absolute // jmp_ctl
);
	input [15:0] inst;
	output [4:0] Rm, Rs, Rd;
	output [31:0] immediate;
	output is_immediate;
	output [9:0] alu_op; // (LSB) + - & | ^ << >> >>> < LTU (MSB)
	output dread_req, dwrite_req;
	output [2:0] dsize;
	output dread_se;
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
	wire [31:0] u7 = {25'b0, inst[5], inst[12:10], inst[6], 2'b0}; // c.lw c.sw
	wire [31:0] u8_swsp = {24'b0, inst[8:7], inst[12:9], 2'b0}; // c.swsp
	wire [31:0] u8_lwsp = {24'b0, inst[3:2], inst[12], inst[6:4], 2'b0}; // c.lwsp

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

	wire c_lw = inst[15:13] == 3'b010 && inst[1:0] == 2'b00;
	wire c_sw = inst[15:13] == 3'b110 && inst[1:0] == 2'b00;
	wire c_swsp = inst[15:13] == 3'b110 && inst[1:0] ==2'b10;
	wire c_lwsp = inst[15:13] == 3'b010 && inst[1:0] == 2'b10;

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
		c_lw || c_sw ? Rd_prime :
		c_swsp || c_lwsp ? 5'd2 :
		5'd0;

	assign Rs =
		c_beqz || c_bnez ? 5'd0 :
		c_mv ? 5'd0 :
		c_add ? Rm_normal :
		c_other_calc_use_Rm ? Rm_prime :
		c_sw ? Rm_prime :
		c_swsp ? Rm_normal :
		5'd0;

	assign Rd =
		c_addi4spn ? Rm_prime :
		c_addi16sp ? 5'd2 :
		c_beqz || c_bnez || c_j || c_jr ? 5'd0 :
		c_jal || c_jalr ? 5'd1 :
		c_li || c_lui || c_mv || c_addi || c_slli || c_add ? Rd_normal :
		c_other_calc ? Rd_prime :
		c_lw ? Rm_prime :
		c_lwsp ? Rd_normal :
		c_sw || c_swsp ? 5'd0 :
		5'd0;

	assign immediate =
		c_addi4spn ? u10 :
		c_addi16sp ? n10 :
		c_beqz || c_bnez ? n9 :
		c_j || c_jal ? n12_c :
		c_jr || c_jalr ? 32'd0 :
		c_li || c_addi || c_slli || c_other_calc_use_n6 ? n6 :
		c_lui ? n18 :
		c_lw || c_sw ? u7 :
		c_swsp ? u8_swsp :
		c_lwsp ? u8_lwsp :
		32'd0;

	assign is_immediate =
		c_li || c_lui || c_addi || c_slli || c_other_calc_use_n6 || c_addi4spn || c_addi16sp ||
		c_lw || c_sw || c_swsp || c_lwsp;

	assign alu_op =
		c_beqz || c_bnez ? 10'b0000000001 :
		c_j || c_jal || c_jr || c_jalr ? 10'b0000000000 :
		c_li || c_lui || c_mv || c_addi || c_add || c_addi4spn || c_addi16sp ? 10'b0000000001 :
		c_slli ? 10'b0000100000 :
		c_other_calc ? c_other_calc_op :
		c_lw || c_sw || c_swsp || c_lwsp ? 10'b0000000001 :
		10'd0;

	assign dread_req =
		c_lw || c_lwsp;

	assign dwrite_req =
		c_sw || c_swsp;

	assign dsize = 3'b100;

	assign dread_se = 1'b0;

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
			for (i = 0; i < 32; i = i + 1) begin
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
