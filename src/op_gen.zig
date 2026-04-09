const std = @import("std");
const config = @import("config.zig");
const tables = @import("tables.zig");
const BranchInfo = @import("branch_template.zig").BranchTemplate.Info;
const Program = @import("program.zig").Program;

pub const OpClass = enum {
    uninitialized,
    implied,
    branch,
    immediate,
    zeropage_read,
    zeropage_write,
    zeropage_x_read,
    zeropage_x_write,
    zeropage_y_read,
    zeropage_y_write,

    // Not implemented
    absolute,
    absolute_x,
    absolute_y,
    indirect,
    indirect_x,
    indirect_y,

    finished,
};

pub fn incOp(state: anytype, pc: u8, candidate: *Program, branch_info: [config.max_length]BranchInfo) bool {
    const ins = @import("instructions.zig").instructions;

    // Generate branches if we are on a branch
    if (branch_info[pc].is_branch) {
        state.op_class = .branch;
        const ops = [_]u8{
            ins.bcc.op,
            ins.bcs.op,
            ins.beq.op,
            ins.bne.op,
            ins.bmi.op,
            ins.bpl.op,
            ins.bvc.op,
            ins.bvs.op,
        };

        if (state.op_meta0 == ops.len) {
            return false;
        }
        candidate.bytes[pc] = ops[state.op_meta0];
        state.op_meta0 += 1;
        return true;
    }

    // Byte 0 locked, we are a shadow instruction. Generate arguments only.
    if (state.lock0 == false) {
        std.log.err("A case I thought was impossible in practice turns out not to be!", .{});
        candidate.print() catch {};
        std.os.linux.exit(0);
        return false;
    }

    const last_instruction = pc + 1 == candidate.size;

    const arg0: u8 = if (last_instruction) 0 else candidate.bytes[pc + 1];
    const arg0_is_masked = if (last_instruction) false else candidate.mask[pc + 1] == 1;
    const arg0_is_branch = if (last_instruction) false else branch_info[pc + 1].is_branch;
    const arg0_is_target = if (last_instruction) false else branch_info[pc + 1].is_target;

    while (true) switch (state.op_class) {
        .uninitialized => {
            state.op_class = .implied;
            state.op_meta0 = 0;
            state.op_meta1 = 0;
        },
        .implied => {
            const ops = [_]u8{
                ins.txa.op,
                ins.tya.op,
                ins.clc.op,
                ins.clv.op,
                ins.sec.op,
                ins.asl.op,
                ins.lsr.op,
                ins.rol.op,
                ins.ror.op,
            } ++ (if (config.allow_x) [_]u8{
                ins.tax.op,
                ins.inx.op,
                ins.dex.op,
            } else [0]u8{}) ++ (if (config.allow_y) [_]u8{
                ins.tay.op,
                ins.iny.op,
                ins.dey.op,
            } else [0]u8{});

            if (state.op_meta0 == ops.len) {
                if (last_instruction or arg0_is_branch) {
                    state.op_class = .finished;
                    continue;
                }

                if (!arg0_is_masked) {
                    candidate.mask[pc + 1] = 1;
                    state.lock1 = true;
                }
                state.op_class = .immediate;
                state.op_meta0 = 0;
                continue;
            }
            candidate.bytes[pc] = ops[state.op_meta0];
            state.op_meta0 += 1;
            return true;
        },
        .immediate => {
            const ops = [_]u8{
                ins.lda_imm.op,
                ins.adc_imm.op,
                ins.sbc_imm.op,
                ins.cmp_imm.op,
                ins.cpx_imm.op,
                ins.cpy_imm.op,
                ins.and_imm.op,
                ins.eor_imm.op,
                ins.ora_imm.op,
            } ++ (if (config.allow_x) [_]u8{
                ins.ldx_imm.op,
            } else [0]u8{}) ++ (if (config.allow_y) [_]u8{
                ins.ldy_imm.op,
            } else [0]u8{}) ++ (if (config.allow_unofficial_opcodes) [_]u8{
                ins.alr_imm.op,
                ins.arr_imm.op,
            } else [0]u8{}) ++ (if (config.allow_unofficial_opcodes and config.allow_x) [_]u8{
                ins.sbx_imm.op,
            } else [0]u8{}) ++ (if (config.allow_unofficial_opcodes and config.allow_ANC_0x0B) [_]u8{
                ins.anc_imm.op,
            } else [0]u8{}) ++ (if (config.allow_unofficial_opcodes and config.allow_ANC_0x2B) [_]u8{
                ins.anc_imm_2.op,
            } else [0]u8{}) ++ (if (config.allow_unofficial_opcodes and config.allow_SBC_0xEB) [_]u8{
                ins.sbc_imm_2.op,
            } else [0]u8{});

            const args_allowed: []const u8 = if (arg0_is_target) &tables.allowed_imm_constants_trg else &tables.allowed_imm_constants;

            if (args_allowed.len == 0 or state.op_meta0 >= ops.len) {
                state.op_class = .zeropage_read;
                state.op_meta0 = 0;
                state.op_meta1 = 0;
                continue;
            }

            if (state.op_meta0 == 0 or state.op_meta1 >= args_allowed.len) {
                candidate.bytes[pc] = ops[state.op_meta0];
                state.op_meta0 += 1;
                state.op_meta1 = 0;
            }

            // if we don't own the argument, check if we can use it anyway
            if (!state.lock1) {
                if (tables.canUseImm(arg0, false)) {
                    state.op_meta1 = 0xffff;
                    return true;
                } else {
                    state.op_class = .zeropage_read;
                    state.op_meta0 = 0;
                    continue;
                }
            }

            candidate.bytes[pc + 1] = args_allowed[state.op_meta1];
            state.op_meta1 += 1;
            return true;
        },
        .zeropage_read => {
            const ops = [_]u8{
                ins.lda_zp.op,
                ins.adc_zp.op,
                ins.sbc_zp.op,
                ins.cmp_zp.op,
                ins.cpx_zp.op,
                ins.cpy_zp.op,
                ins.bit_zp.op,
                ins.and_zp.op,
                ins.eor_zp.op,
                ins.ora_zp.op,
            } ++ (if (config.allow_x) [_]u8{
                ins.ldx_zp.op,
            } else [0]u8{}) ++ (if (config.allow_y) [_]u8{
                ins.ldy_zp.op,
            } else [0]u8{}) ++ (if (config.allow_unofficial_opcodes and config.allow_x) [_]u8{
                ins.lax_zp.op,
            } else [0]u8{});

            const args_allowed: []const u8 = if (arg0_is_target) &tables.allowed_zp_memory_trg else &config.allowed_zp_memory;

            if (args_allowed.len == 0 or state.op_meta0 >= ops.len) {
                state.op_class = .zeropage_write;
                state.op_meta0 = 0;
                state.op_meta1 = 0;
                continue;
            }

            if (state.op_meta0 == 0 or state.op_meta1 >= args_allowed.len) {
                candidate.bytes[pc] = ops[state.op_meta0];
                state.op_meta0 += 1;
                state.op_meta1 = 0;
            }

            if (!state.lock1) {
                if (tables.canReadZp(arg0)) {
                    state.op_meta1 = 0xffff;
                    return true;
                } else {
                    state.op_class = .zeropage_write;
                    state.op_meta0 = 0;
                    continue;
                }
            }

            candidate.bytes[pc + 1] = args_allowed[state.op_meta1];
            state.op_meta1 += 1;
            return true;
        },
        .zeropage_write => {
            const ops = [_]u8{
                ins.sta_zp.op,
                ins.stx_zp.op,
                ins.sty_zp.op,
                ins.inc_zp.op,
                ins.dec_zp.op,
                ins.asl_zp.op,
                ins.lsr_zp.op,
                ins.rol_zp.op,
                ins.ror_zp.op,
            } ++ (if (config.allow_unofficial_opcodes) [_]u8{
                ins.dcp_zp.op,
                ins.isc_zp.op,
                ins.rla_zp.op,
                ins.rra_zp.op,
                ins.sax_zp.op,
                ins.slo_zp.op,
                ins.sre_zp.op,
            } else [0]u8{});

            const args_allowed: []const u8 = if (arg0_is_target) &tables.allowed_zp_memory_trg else &config.allowed_zp_memory;

            if (args_allowed.len == 0 or state.op_meta0 >= ops.len) {
                state.op_class = .zeropage_y_read;
                state.op_meta0 = 0;
                state.op_meta1 = 0;
                continue;
            }

            if (state.op_meta0 == 0 or state.op_meta1 >= args_allowed.len) {
                candidate.bytes[pc] = ops[state.op_meta0];
                state.op_meta0 += 1;
                state.op_meta1 = 0;
            }

            if (!state.lock1) {
                if (tables.canWriteZp(arg0)) {
                    state.op_meta1 = 0xffff;
                    return true;
                } else {
                    state.op_class = .zeropage_y_read;
                    state.op_meta0 = 0;
                    continue;
                }
            }

            candidate.bytes[pc + 1] = args_allowed[state.op_meta1];
            state.op_meta1 += 1;
            return true;
        },
        .zeropage_y_read => {
            if (!config.allow_zp_xy or !config.allow_x) {
                state.op_class = .zeropage_y_write;
                continue;
            }

            const ops = [_]u8{
                ins.ldx_zpy.op,
            } ++ (if (config.allow_unofficial_opcodes) [_]u8{
                ins.lax_zpy.op,
            } else [0]u8{});

            const args_allowed: []const u8 = if (arg0_is_target) &tables.allowed_zp_memory_trg else &config.allowed_zp_memory;

            if (args_allowed.len == 0 or state.op_meta0 >= ops.len) {
                state.op_class = .zeropage_y_write;
                state.op_meta0 = 0;
                state.op_meta1 = 0;
                continue;
            }

            if (state.op_meta0 == 0 or state.op_meta1 >= args_allowed.len) {
                candidate.bytes[pc] = ops[state.op_meta0];
                state.op_meta0 += 1;
                state.op_meta1 = 0;
            }

            const sys0 = state.warp.systems[0];

            if (!state.lock1) {
                if (tables.canReadZp(arg0 +% sys0.y)) {
                    state.op_meta1 = 0xffff;
                    return true;
                } else {
                    state.op_class = .zeropage_y_write;
                    state.op_meta0 = 0;
                    continue;
                }
            }

            var args_allowed_adjbuf: [config.allowed_zp_memory.len]u8 = undefined;
            for (args_allowed, 0..) |arg, i| {
                args_allowed_adjbuf[i] = arg -% sys0.y;
            }
            const args_allowed_adj = args_allowed_adjbuf[0..args_allowed.len];

            candidate.bytes[pc + 1] = args_allowed_adj[state.op_meta1];
            state.op_meta1 += 1;
            return true;
        },
        .zeropage_y_write => {
            if (!config.allow_zp_xy or !config.allow_y) {
                state.op_class = .finished;
                continue;
            }

            const ops = [_]u8{
                ins.stx_zpy.op,
            } ++ (if (config.allow_unofficial_opcodes) [_]u8{
                ins.sax_zpy.op,
            } else [0]u8{});

            const args_allowed: []const u8 = if (arg0_is_target) &tables.allowed_zp_memory_trg else &config.allowed_zp_memory;

            if (args_allowed.len == 0 or state.op_meta0 >= ops.len) {
                state.op_class = .finished;
                state.op_meta0 = 0;
                state.op_meta1 = 0;
                continue;
            }

            if (state.op_meta0 == 0 or state.op_meta1 >= args_allowed.len) {
                candidate.bytes[pc] = ops[state.op_meta0];
                state.op_meta0 += 1;
                state.op_meta1 = 0;
            }

            const sys0 = state.warp.systems[0];

            if (!state.lock1) {
                if (tables.canReadZp(arg0 +% sys0.y)) {
                    state.op_meta1 = 0xffff;
                    return true;
                } else {
                    state.op_class = .finished;
                    state.op_meta0 = 0;
                    continue;
                }
            }

            var args_allowed_adjbuf: [config.allowed_zp_memory.len]u8 = undefined;
            for (args_allowed, 0..) |arg, i| {
                args_allowed_adjbuf[i] = arg -% sys0.y;
            }
            const args_allowed_adj = args_allowed_adjbuf[0..args_allowed.len];

            candidate.bytes[pc + 1] = args_allowed_adj[state.op_meta1];
            state.op_meta1 += 1;
            return true;
        },
        else => return false,
    };
}
