const std = @import("std");
const config = @import("config.zig");
const tables = @import("tables.zig");
const BranchInfo = @import("branch_template.zig").BranchTemplate.Info;
const Program = @import("program.zig").Program;
const System = @import("system.zig").System;
const Defines = @import("system.zig").Defines;
const op_gen = @import("op_gen.zig");
const op_filter = @import("op_filter.zig");

const State = struct {
    active: bool = false,

    lock0: bool = false,
    lock1: bool = false,
    lock2: bool = false,

    parent: u8,

    total_cycles: u32,
    worst_cycles: u32,
    cycles: u32,

    test_idx: usize,

    op_class: op_gen.OpClass = .uninitialized,
    op_meta0: u8 = 0,
    op_meta1: u16 = 0,

    system: System,
    pc: u8,
    defines: Defines,
};

var states: [config.max_length]State = undefined;

pub fn run(prefix: Program, branch_info: [config.max_length]BranchInfo) void {
    // Reset the warp states
    for (states[0..]) |*ss| {
        ss.active = false;
    }

    // Lock the states we shouldn't touch
    for (prefix.mask[0..], 0..) |pm, i| {
        if (pm == 1) {
            states[i].active = true;
        }
    }

    // Generate the root state
    states[0] = .{
        .active = true,
        .lock0 = true,
        .parent = 0xff,
        .cycles = 0,
        .test_idx = 0,
        .worst_cycles = 0,
        .total_cycles = 0,
        .system = undefined,
        .pc = 0,
        .defines = tables.base_defines,
    };

    // The pointer to the active state
    var state = &states[0];
    var candidate = prefix;

    while (true) {
        // todo: don't start with idx 0; do 13 or something and wrap
        states[0].system = System{};
        config.test_generate(&states[0].system, 0);

        while (true) {
            if (step(state, &candidate, branch_info)) |nstate| {
                state = nstate;
            }

            while (true) {
                if (!op_gen.incOp(state, state.pc, &candidate, branch_info)) {
                    if (state.parent == 0) return;
                    if (state.parent == 0xff) return; // this means it failed in the preamble. Should not be possible, but oh well.

                    // Unlock the states
                    if (state.lock0) candidate.mask[state.pc + 0] = 0;
                    if (state.lock1) candidate.mask[state.pc + 1] = 0;
                    if (state.lock2) candidate.mask[state.pc + 2] = 0;

                    // Not strictly neccesary, but clean up so printing bytes is less confusing
                    if (state.lock0) candidate.bytes[state.pc + 0] = 0;
                    if (state.lock1) candidate.bytes[state.pc + 1] = 0;
                    if (state.lock2) candidate.bytes[state.pc + 2] = 0;
                    state.active = false;

                    state = &states[state.parent];
                    continue;
                }
                break;
            }
        }
    }
}

fn step(start_state: *State, candidate: *Program, branch_info: [config.max_length]BranchInfo) ?*State {
    const ins = @import("instructions.zig").instructions;
    const insmap = @import("instructions.zig").instructionmap;

    var sys: System = start_state.system;
    var test_idx: usize = start_state.test_idx;
    var cycles = start_state.cycles;
    var worst_cycles = start_state.worst_cycles;
    var total_cycles = start_state.total_cycles;
    var defines = start_state.defines;
    var pc = start_state.pc;

    // Filter generally pointless op combinations
    var range_start: usize = 0;
    for (branch_info[0..], 0..) |info, i| {
        if (info.is_target) {
            range_start = i;
        }
        if (i == pc) {
            if (op_filter.run(candidate.bytes[range_start..pc])) return null;
        }
    }

    while (true) {
        const last_instruction = (pc + 1 >= candidate.size) or (candidate.mask[pc + 1] == 0);

        switch (insmap[candidate.bytes[pc]].size()) {
            1 => {},
            2 => {
                if (last_instruction) return null;
            },
            3 => {
                if (last_instruction) return null;
            },
            else => undefined,
        }

        const arg0 = if (last_instruction) 0 else candidate.bytes[pc + 1];

        switch (candidate.bytes[pc]) {
            ins.tax.op => {
                if (!config.allow_x) return null;
                if (defines.a == 0) return null;

                sys.x = sys.a;
                sys.setZN(sys.x);

                defines.x = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.txa.op => {
                if (defines.x == 0) return null;

                sys.a = sys.x;
                sys.setZN(sys.a);

                defines.a = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },
            ins.tay.op => {
                if (!config.allow_y) return null;
                if (defines.a == 0) return null;

                sys.y = sys.a;
                sys.setZN(sys.y);

                defines.y = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },
            ins.tya.op => {
                if (defines.y == 0) return null;

                sys.a = sys.y;
                sys.setZN(sys.a);

                defines.a = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.inx.op => {
                if (defines.x == 0) return null;

                sys.x = sys.x +% 1;
                sys.setZN(sys.x);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.dex.op => {
                if (defines.x == 0) return null;

                sys.x = sys.x -% 1;
                sys.setZN(sys.x);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.iny.op => {
                if (defines.y == 0) return null;

                sys.y = sys.y +% 1;
                sys.setZN(sys.y);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.dey.op => {
                if (defines.y == 0) return null;

                sys.y = sys.y -% 1;
                sys.setZN(sys.y);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.clc.op => {
                sys.flags.carry = 0;

                defines.carry = 1;
                cycles += 2;
                pc += 1;
            },

            ins.clv.op => {
                sys.flags.overflow = 0;

                defines.overflow = 1;
                cycles += 2;
                pc += 1;
            },

            ins.sec.op => {
                sys.flags.carry = 1;

                defines.carry = 1;
                cycles += 2;
                pc += 1;
            },

            ins.asl.op => {
                if (defines.a == 0) return null;

                sys.flags.carry = if (sys.a >= 128) 1 else 0;
                sys.a = sys.a << 1;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.lsr.op => {
                if (defines.a == 0) return null;

                sys.flags.carry = if (sys.a & 1 == 1) 1 else 0;
                sys.a = sys.a >> 1;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.rol.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;

                const ex_carry: u1 = if (sys.a >= 128) 1 else 0;
                sys.a = (sys.a << 1) + sys.flags.carry;
                sys.flags.carry = ex_carry;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            ins.ror.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;

                const ex_carry: u1 = if (sys.a & 1 == 1) 1 else 0;
                sys.a = (sys.a >> 1) + @as(u8, sys.flags.carry) * 128;
                sys.flags.carry = ex_carry;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 1;
            },

            // Branches

            ins.bcc.op => {
                if (defines.carry == 0) return null;

                if (sys.flags.carry == 0) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;

                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.bcs.op => {
                if (defines.carry == 0) return null;

                if (sys.flags.carry == 1) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.beq.op => {
                if (defines.zero == 0) return null;

                if (sys.flags.zero == 1) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.bne.op => {
                if (defines.zero == 0) return null;

                if (sys.flags.zero == 0) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.bmi.op => {
                if (defines.negative == 0) return null;

                if (sys.flags.negative == 1) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.bpl.op => {
                if (defines.negative == 0) return null;

                if (sys.flags.negative == 0) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.bvc.op => {
                if (defines.overflow == 0) return null;

                if (sys.flags.overflow == 1) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            ins.bvs.op => {
                if (defines.overflow == 0) return null;

                if (sys.flags.overflow == 0) {
                    const target = @as(isize, pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    pc += 2;
                    cycles += 2;
                }
            },

            // Immediates

            ins.lda_imm.op => {
                sys.a = arg0;
                sys.setZN(sys.a);

                defines.a = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.ldx_imm.op => {
                if (!config.allow_x) return null;
                sys.x = arg0;
                sys.setZN(sys.x);

                defines.x = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.ldy_imm.op => {
                if (!config.allow_y) return null;
                sys.y = arg0;
                sys.setZN(sys.y);

                defines.y = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.adc_imm.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;

                const val: u16 = @as(u16, sys.a) + @as(u16, arg0) + @as(u16, sys.flags.carry);
                const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(arg0)) +% @as(i8, sys.flags.carry);

                sys.a = @intCast(val & 0xff);
                sys.flags.carry = if (val > 0xff) 1 else 0;
                sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                sys.setZN(sys.a);

                defines.overflow = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.sbc_imm.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;

                const arg0i: u8 = ~arg0;

                const val: u16 = @as(u16, sys.a) + @as(u16, arg0i) + @as(u16, sys.flags.carry);
                const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(arg0i)) +% @as(i8, sys.flags.carry);

                sys.a = @intCast(val & 0xff);
                sys.flags.carry = if (val > 0xff) 1 else 0;
                sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                sys.setZN(sys.a);

                defines.overflow = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.cmp_imm.op => {
                if (defines.a == 0) return null;

                const val = sys.a -% arg0;
                sys.flags.zero = if (sys.a == arg0) 1 else 0;
                sys.flags.negative = if (val >= 128) 1 else 0;
                sys.flags.carry = if (sys.a >= arg0) 1 else 0;

                defines.zero = 1;
                defines.negative = 1;
                defines.carry = 1;
                cycles += 2;
                pc += 2;
            },

            ins.cpx_imm.op => {
                if (defines.x == 0) return null;

                const val = sys.x -% arg0;
                sys.flags.zero = if (sys.x == arg0) 1 else 0;
                sys.flags.negative = if (val >= 128) 1 else 0;
                sys.flags.carry = if (sys.x >= arg0) 1 else 0;

                defines.zero = 1;
                defines.negative = 1;
                defines.carry = 1;
                cycles += 2;
                pc += 2;
            },

            ins.cpy_imm.op => {
                if (defines.y == 0) return null;

                const val = sys.y -% arg0;
                sys.flags.zero = if (sys.y == arg0) 1 else 0;
                sys.flags.negative = if (val >= 128) 1 else 0;
                sys.flags.carry = if (sys.y >= arg0) 1 else 0;

                defines.zero = 1;
                defines.negative = 1;
                defines.carry = 1;
                cycles += 2;
                pc += 2;
            },

            ins.and_imm.op => {
                if (defines.a == 0) return null;

                sys.a = sys.a & arg0;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.eor_imm.op => {
                if (defines.a == 0) return null;

                sys.a = sys.a ^ arg0;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.ora_imm.op => {
                if (defines.a == 0) return null;

                sys.a = sys.a | arg0;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            // Immediates, unofficial

            ins.alr_imm.op => {
                if (defines.a == 0) return null;

                sys.a = sys.a & arg0;
                sys.flags.carry = if (sys.a & 1 == 1) 1 else 0;
                sys.a = sys.a >> 1;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.anc_imm.op => {
                if (defines.a == 0) return null;

                sys.a = sys.a & arg0;
                sys.flags.carry = if (sys.a >= 128) 1 else 0;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.anc_imm_2.op => {
                if (defines.a == 0) return null;

                sys.a = sys.a & arg0;
                sys.flags.carry = if (sys.a >= 128) 1 else 0;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            ins.arr_imm.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;

                sys.a = sys.a & arg0;
                sys.a = (sys.a >> 1) + @as(u8, sys.flags.carry) * 128;
                sys.flags.carry = @intCast((sys.a >> 6) & 1);
                sys.flags.overflow = @intCast(((sys.a >> 6) ^ (sys.a >> 5)) & 1);
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                defines.overflow = 1;

                cycles += 2;
                pc += 2;
            },

            ins.sbx_imm.op => {
                if (defines.a == 0) return null;
                if (defines.x == 0) return null;

                const ax = sys.a & sys.x;
                sys.x = ax -% arg0;
                sys.flags.carry = if (ax >= arg0) 1 else 0;
                sys.setZN(sys.x);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 2;
                pc += 2;
            },

            // Zeropage, read

            ins.lda_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                sys.a = sys.readZp(arg0);
                sys.setZN(sys.a);

                defines.a = 1;
                defines.zero = 1;
                defines.negative = 1;

                cycles += 3;
                pc += 2;
            },

            ins.ldx_zp.op => {
                if (!config.allow_x) return null;
                if (!tables.canReadZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                sys.x = sys.readZp(arg0);
                sys.setZN(sys.x);

                defines.x = 1;
                defines.zero = 1;
                defines.negative = 1;

                cycles += 3;
                pc += 2;
            },

            ins.ldy_zp.op => {
                if (!config.allow_y) return null;
                if (!tables.canReadZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                sys.y = sys.readZp(arg0);
                sys.setZN(sys.y);

                defines.y = 1;
                defines.zero = 1;
                defines.negative = 1;

                cycles += 3;
                pc += 2;
            },

            ins.adc_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                const val: u16 = @as(u16, sys.a) + @as(u16, byte) + @as(u16, sys.flags.carry);
                const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(byte)) +% @as(i8, sys.flags.carry);

                sys.a = @intCast(val & 0xff);
                sys.flags.carry = if (val > 0xff) 1 else 0;
                sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                sys.setZN(sys.a);

                defines.overflow = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 3;
                pc += 2;
            },

            ins.sbc_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = ~sys.readZp(arg0);
                const val: u16 = @as(u16, sys.a) + @as(u16, byte) + @as(u16, sys.flags.carry);
                const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(byte)) +% @as(i8, sys.flags.carry);

                sys.a = @intCast(val & 0xff);
                sys.flags.carry = if (val > 0xff) 1 else 0;
                sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                sys.setZN(sys.a);

                defines.overflow = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 3;
                pc += 2;
            },

            ins.cmp_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                const val = sys.a -% byte;
                sys.flags.zero = if (sys.a == byte) 1 else 0;
                sys.flags.negative = if (val >= 128) 1 else 0;
                sys.flags.carry = if (sys.a >= byte) 1 else 0;

                defines.zero = 1;
                defines.negative = 1;
                defines.carry = 1;
                cycles += 3;
                pc += 2;
            },

            ins.bit_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                const val = sys.a & byte;

                sys.flags.zero = if (val == 0) 1 else 0;
                sys.flags.negative = if (byte & 0b10000000 > 0) 1 else 0;
                sys.flags.overflow = if (byte & 0b01000000 > 0) 1 else 0;

                defines.zero = 1;
                defines.negative = 1;
                defines.overflow = 1;
                cycles += 3;
                pc += 2;
            },

            ins.and_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                sys.a = sys.a & byte;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 3;
                pc += 2;
            },

            ins.eor_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                sys.a = sys.a ^ byte;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 3;
                pc += 2;
            },

            ins.ora_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (defines.a == 0) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                sys.a = sys.a | byte;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 3;
                pc += 2;
            },

            // Zeropage, read, unofficial

            ins.lax_zp.op => {
                if (!config.allow_x) return null;
                if (!tables.canReadZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                sys.a = byte;
                sys.x = byte;
                sys.setZN(byte);

                defines.a = 1;
                defines.x = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 3;
                pc += 2;
            },

            // Zeropage, write

            ins.sta_zp.op => {
                if (defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                sys.writeZp(arg0, sys.a);

                defines.setMem(arg0);
                cycles += 3;
                pc += 2;
            },

            ins.stx_zp.op => {
                if (defines.x == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                sys.writeZp(arg0, sys.x);

                defines.setMem(arg0);
                cycles += 3;
                pc += 2;
            },

            ins.sty_zp.op => {
                if (defines.y == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                sys.writeZp(arg0, sys.y);

                defines.setMem(arg0);
                cycles += 3;
                pc += 2;
            },

            ins.inc_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0) +% 1;
                sys.writeZp(arg0, byte);
                sys.setZN(byte);

                cycles += 5;
                pc += 2;
            },

            ins.dec_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0) -% 1;
                sys.writeZp(arg0, byte);
                sys.setZN(byte);

                cycles += 5;
                pc += 2;
            },

            ins.asl_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                var byte = sys.readZp(arg0);
                sys.flags.carry = if (byte >= 128) 1 else 0;
                byte = byte << 1;
                sys.writeZp(arg0, byte);
                sys.setZN(byte);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.lsr_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                var byte = sys.readZp(arg0);
                sys.flags.carry = if (byte & 1 == 1) 1 else 0;
                byte = byte >> 1;
                sys.writeZp(arg0, byte);
                sys.setZN(byte);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.rol_zp.op => {
                if (defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                var byte = sys.readZp(arg0);
                const ex_carry: u1 = if (byte >= 128) 1 else 0;
                byte = (byte << 1) + sys.flags.carry;
                sys.writeZp(arg0, byte);

                sys.flags.carry = ex_carry;
                sys.setZN(byte);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.ror_zp.op => {
                if (defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                var byte = sys.readZp(arg0);
                const ex_carry: u1 = if (byte & 1 == 1) 1 else 0;
                byte = (byte >> 1) + (@as(u8, @intCast(sys.flags.carry)) << 7);
                sys.writeZp(arg0, byte);

                sys.flags.carry = ex_carry;
                sys.setZN(byte);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            // Zeropage, write, unofficial

            ins.dcp_zp.op => {
                if (defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0) -% 1;
                sys.writeZp(arg0, byte);

                const val = sys.a -% byte;
                sys.flags.zero = if (sys.a == byte) 1 else 0;
                sys.flags.negative = if (val >= 128) 1 else 0;
                sys.flags.carry = if (sys.a >= byte) 1 else 0;

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.isc_zp.op => {
                if (defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0) +% 1;
                sys.writeZp(arg0, byte);

                const bytei: u8 = ~byte;
                const val: u16 = @as(u16, sys.a) + @as(u16, bytei) + @as(u16, sys.flags.carry);
                const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(bytei)) +% @as(i8, sys.flags.carry);

                sys.a = @intCast(val & 0xff);
                sys.flags.carry = if (val > 0xff) 1 else 0;
                sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.rla_zp.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                const byte = sys.readZp(arg0);
                const ex_carry: u1 = if (byte >= 128) 1 else 0;
                const val = (byte << 1) + sys.flags.carry;
                sys.flags.carry = ex_carry;
                sys.writeZp(arg0, val);
                sys.a &= val;
                sys.setZN(sys.a);

                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.rra_zp.op => {
                if (defines.a == 0) return null;
                if (defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                // ROR
                var byte = sys.readZp(arg0);
                const ex_carry: u1 = if (byte & 1 == 1) 1 else 0;
                byte = (byte >> 1) + (@as(u8, @intCast(sys.flags.carry)) << 7);
                sys.writeZp(arg0, byte);
                sys.flags.carry = ex_carry;

                // ADC
                const val: u16 = @as(u16, sys.a) + @as(u16, byte) + @as(u16, sys.flags.carry);
                const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(byte)) +% @as(i8, sys.flags.carry);

                sys.a = @intCast(val & 0xff);
                sys.flags.carry = if (val > 0xff) 1 else 0;
                sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                sys.setZN(sys.a);

                defines.overflow = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.sax_zp.op => {
                if (defines.a == 0) return null;
                if (defines.x == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                sys.writeZp(arg0, sys.a & sys.x);

                defines.setMem(arg0);
                cycles += 3;
                pc += 2;
            },

            ins.slo_zp.op => {
                if (defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                // ASL
                var byte = sys.readZp(arg0);
                sys.flags.carry = if (byte >= 128) 1 else 0;
                byte = byte << 1;
                sys.writeZp(arg0, byte);

                // ORA
                sys.a = sys.a | byte;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            ins.sre_zp.op => {
                if (defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!defines.getMem(arg0)) return null;

                // LSR
                var byte = sys.readZp(arg0);
                sys.flags.carry = if (byte & 1 == 1) 1 else 0;
                byte = byte >> 1;
                sys.writeZp(arg0, byte);

                // EOR
                sys.a = sys.a ^ byte;
                sys.setZN(sys.a);

                defines.carry = 1;
                defines.zero = 1;
                defines.negative = 1;
                cycles += 5;
                pc += 2;
            },

            // Zeropage Y, read

            ins.ldx_zpy.op => {
                if (!config.allow_x) return null;
                if (defines.y == 0) return null;

                const arg_adj = arg0 +% sys.y;

                if (!tables.canReadZp(arg_adj)) return null;
                if (!defines.getMem(arg_adj)) return null;

                sys.x = sys.readZp(arg_adj);
                sys.setZN(sys.x);

                defines.x = 1;
                defines.zero = 1;
                defines.negative = 1;

                cycles += 4;
                pc += 2;
            },

            // Zeropage Y, read, unofficial

            ins.lax_zpy.op => {
                if (!config.allow_x) return null;
                if (defines.y == 0) return null;

                const arg_adj = arg0 +% sys.y;

                if (!tables.canReadZp(arg_adj)) return null;
                if (!defines.getMem(arg_adj)) return null;

                sys.a = sys.readZp(arg_adj);
                sys.x = sys.a;
                sys.setZN(sys.x);

                defines.x = 1;
                defines.a = 1;
                defines.zero = 1;
                defines.negative = 1;

                cycles += 4;
                pc += 2;
            },

            // Zeropage Y, write

            ins.stx_zpy.op => {
                if (defines.y == 0) return null;
                if (defines.x == 0) return null;

                const arg_adj = arg0 +% sys.y;

                if (!tables.canWriteZp(arg_adj)) return null;
                sys.writeZp(arg_adj, sys.x);

                // Not ideal... Can lead to false positives -> relevant to all similar instructions
                defines.setMem(arg_adj);

                cycles += 4;
                pc += 2;
            },

            // Zeropage Y, write, unofficial

            ins.sax_zpy.op => {
                if (defines.y == 0) return null;
                if (defines.x == 0) return null;
                if (defines.a == 0) return null;

                const arg_adj = arg0 +% sys.y;

                if (!tables.canWriteZp(arg_adj)) return null;
                sys.writeZp(arg_adj, sys.a & sys.x);

                defines.setMem(arg_adj);

                cycles += 4;
                pc += 2;
            },

            else => return null,
        }

        if (cycles > config.max_cycles) return null;

        if (pc == candidate.size) {
            // Check success
            var start_sys = System{};
            config.test_generate(&start_sys, test_idx);
            if (!config.test_verify(&start_sys, &sys)) {
                return null;
            }

            test_idx += 1;

            worst_cycles = if (worst_cycles > cycles) worst_cycles else cycles;
            total_cycles = total_cycles + cycles;
            if (test_idx == config.test_cases) {
                @import("root").successCallback(candidate, worst_cycles, total_cycles);
                return null;
            }

            cycles = 0;
            pc = 0;
            defines = tables.base_defines;
            config.test_generate(&sys, test_idx);
            continue;
        }

        // If we reach an inactive state, grab it
        if (states[pc].active == false) {

            // if it's masked, check if it's executable and a 1-byte instruction, if so just continue
            // TODO: it can be a 2-byte instruction too
            if (candidate.mask[pc] == 1) {
                if (config.allow_shadow_execution == false) return null;
                const opsize = insmap[candidate.bytes[pc]].size();

                switch (opsize) {
                    1 => continue,
                    2 => {
                        const is_last_instruction = (pc + 1 >= candidate.size) or (candidate.mask[pc + 1] == 0);
                        if (is_last_instruction) return null;
                        if (candidate.mask[pc + 1] == 1) continue; // We're in previously genned code
                        // OK this case can never happen in practice. Fall through anyway.
                    },
                    3 => return null, //3-byte ops are TODO
                    else => unreachable,
                }
            }

            const new_system_state = &states[pc];

            new_system_state.* = .{
                .parent = start_state.pc,
                .active = true,
                .worst_cycles = worst_cycles,
                .total_cycles = total_cycles,
                .cycles = cycles,
                .test_idx = test_idx,
                .system = sys,
                .pc = pc,
                .defines = defines,
            };

            // Lock the first byte if possible
            if (candidate.mask[pc] == 0) {
                new_system_state.lock0 = true;
                candidate.mask[pc] = 1;
            }

            return new_system_state;
        }
    }
}
