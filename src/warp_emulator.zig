const std = @import("std");
const config = @import("config.zig");
const tables = @import("tables.zig");
const BranchInfo = @import("branch_template.zig").BranchTemplate.Info;
const Program = @import("program.zig").Program;
const System = @import("system.zig").System(true);
const Warp = @import("warp.zig").Warp;
const Defines = @import("system.zig").Defines;
const successCallback = @import("root").successCallback;
// const emulator = @import("emulator.zig");
const op_gen = @import("op_gen.zig");
const op_filter = @import("op_filter.zig");

// Static storage for candidates to send onwards to Phobos
var candidate_mem: []Program = &[0]Program{};
var candidates_n: usize = undefined;

pub fn run(length: usize, branch_info: [config.max_length]BranchInfo) []const Program {
    if (length == 0) {
        testZeroLengthEdgeCase();
        return &[0]Program{};
    }

    // Reset the static lists
    candidates_n = 0;
    warp_filter = @TypeOf(warp_filter).init(std.heap.page_allocator);
    defer warp_filter.deinit();

    brute(length, branch_info, true);
    brute(length, branch_info, false);

    return candidate_mem[0..candidates_n];
}

fn testZeroLengthEdgeCase() void {
    var warp = Warp{
        .pc = 0,
        .systems_n = config.test_cases,
        .systems = undefined,
        .defines = tables.base_defines,
        .tests_complete = undefined,
        .tests_complete_n = 0,
    };
    warp.initTestIndices();
    warp.generateTests();
    if (warp.checkSuccess()) {
        const program = Program.init(0);
        successCallback(&program, 0, 0);
    }
}

pub const State = struct {
    active: bool = false,

    lock0: bool = false,
    lock1: bool = false,
    lock2: bool = false,

    parent: u8,
    generation: u8,

    total_cycles: u32,
    worst_cycles: u32,
    cycles: u32,

    op_class: op_gen.OpClass = .uninitialized,
    op_meta0: u8 = 0,
    op_meta1: u16 = 0,

    warp: Warp,
};

var states: [config.max_length]State = undefined;

fn brute(length: usize, branch_info: [config.max_length]BranchInfo, prefilter: bool) void {
    // Reset the warp states
    for (states[0..]) |*ws| {
        ws.active = false;
    }

    // Generate the root warp, adjust warp size to the size of the reduced test cases
    states[0] = .{
        .active = true,
        .lock0 = true,
        .parent = 0xff,
        .generation = 0,
        .cycles = 0,
        .total_cycles = 0,
        .worst_cycles = 0,
        .warp = .{
            .pc = 0,
            .systems_n = config.test_cases,
            .systems = undefined,
            .defines = tables.base_defines,
            .tests_complete_n = 0,
        },
    };
    states[0].warp.initTestIndices();
    states[0].warp.generateTests();

    // Generate the candidate we will modify as we go
    var candidate = Program.init(@intCast(length));
    candidate.mask[0] = 1;

    // Add the initial state to the filter
    if (prefilter) {
        addToFilteredWarps(&states[0].warp, 0, &candidate);
    }

    // Fix the branch arguments
    for (branch_info, 0..) |info, i| {
        if (!info.is_branch) continue;
        candidate.mask[i + 1] = 1;
        const arg: i8 = @as(i8, @intCast(info.target)) - @as(i8, @intCast(i)) - 2;
        candidate.bytes[i + 1] = @bitCast(arg);
    }

    // The pointer to the active warp state
    var state = &states[0];

    while (true) {
        // Increase the op at the current point
        if (!op_gen.incOp(state, state.warp.pc, &candidate, branch_info)) {
            // If that fails, step backwards or return
            if (state.warp.pc == 0) return;

            // Unlock the states
            if (state.lock0) candidate.mask[state.warp.pc + 0] = 0;
            if (state.lock1) candidate.mask[state.warp.pc + 1] = 0;
            if (state.lock2) candidate.mask[state.warp.pc + 2] = 0;

            // Not strictly neccesary, but clean up so printing bytes is less confusing
            if (state.lock0) candidate.bytes[state.warp.pc + 0] = 0;
            if (state.lock1) candidate.bytes[state.warp.pc + 1] = 0;
            if (state.lock2) candidate.bytes[state.warp.pc + 2] = 0;
            state.active = false;

            state = &states[state.parent];
            continue;
        }

        if (step(state, &candidate, branch_info, prefilter)) |nwarpstate| {
            // if the new state has already been seen, trash it, otherwise apply and continue
            state = nwarpstate;
        }
    }
}

fn addCandidate(candidate: *Program) void {
    if (candidates_n == candidate_mem.len) {
        candidate_mem = std.heap.page_allocator.realloc(candidate_mem, candidate_mem.len + 1024 * 1024) catch {
            std.log.err("Out of memory: Failed reallocating candidate_mem!", .{});
            std.os.linux.exit(1);
        };
    }

    candidate_mem[candidates_n] = candidate.*;
    candidates_n += 1;
}

const WarpFilterValue = struct {
    best_cycles: u32,
    best_pc: u8,
    best_cycles_used: bool = false,
    best_pc_used: bool = false,

    // Debug
    candidate: Program,
};

var warp_filter: std.AutoHashMap(u64, WarpFilterValue) = undefined;

fn addToFilteredWarps(warp: *Warp, cycles: u32, candidate: *Program) void {

    // yes this isn't ideal and can result in missed optimizations in some everett branch
    // ... but carrying along 65536 systems for each entry is unworkable.
    // todo: prevent double-hashing
    const result = warp_filter.getOrPut(warp.hash()) catch unreachable;
    const vp = result.value_ptr;

    if (result.found_existing) {
        if (vp.best_cycles > cycles) {
            vp.best_cycles = cycles;
        }
        if (vp.best_pc > warp.pc) {
            vp.best_pc = warp.pc;
        }
        vp.candidate = candidate.*;
    } else {
        vp.* = .{
            .best_cycles = cycles,
            .best_pc = warp.pc,
            .candidate = candidate.*,
        };
    }
}

const FindFilterListResult = enum {
    found_better,
    replaced,
    none,
};

fn findBetterWarpInFilterList(warp: *const Warp, cycles: u32, candidate: *Program, prefilter: bool) FindFilterListResult {
    const result = warp_filter.getPtr(warp.hash()) orelse return .none;

    const is_smaller = result.best_pc < warp.pc;
    const is_faster = result.best_cycles < cycles;
    const is_same_size = result.best_pc == warp.pc;
    const is_same_speed = result.best_cycles == cycles;
    const is_degenerate = (result.best_pc == warp.pc) and (result.best_cycles == cycles);

    if (is_smaller and is_faster) return .found_better;
    if (is_same_size and is_faster) return .found_better;
    if (is_same_speed and is_smaller) return .found_better;

    if (is_degenerate) {
        if (prefilter == true) return .found_better;

        if (result.best_cycles_used != result.best_pc_used) unreachable;
        if (result.best_cycles_used and result.best_pc_used) {
            return .found_better;
        } else {
            result.best_cycles_used = true;
            result.best_pc_used = true;
            return .none;
        }
    }

    // Unclear if these can happen in practice
    if (is_faster and prefilter == false) {
        result.best_cycles_used = true;
        return .none;
    }
    if (is_smaller and prefilter == false) {
        result.best_pc_used = true;
        return .none;
    }

    // Sanity check
    if (prefilter == false) {
        //std.log.info("BOOM!", .{});
        //std.log.info("=== [size: {}, cycles: {}] ===", .{ warp.pc, cycles });
        //candidate.print() catch {};
        //std.log.info("-> size: {}, cycles: {}", .{ fcdw.pc_min, fcdw.cycles_min });
        //fcdw.program.print() catch {};
        unreachable;
    }

    result.best_pc = if (result.best_pc < warp.pc) result.best_pc else warp.pc;
    result.best_cycles = if (result.best_cycles < cycles) result.best_cycles else cycles;
    result.candidate = candidate.*;
    return .replaced;
}

fn step(start_state: *State, candidate: *Program, branch_info: [config.max_length]BranchInfo, prefilter: bool) ?*State {
    const ins = @import("instructions.zig").instructions;
    const insmap = @import("instructions.zig").instructionmap;

    var warp: Warp = start_state.warp;
    var cycles = start_state.cycles;

    // Used to find "pointless" branches that are always or never taken, if they
    // appears before the first target (so it it always just tested once)
    const is_before_first_target = blk: {
        for (branch_info[0 .. warp.pc + 1]) |info| {
            if (info.is_target) break :blk false;
        }
        break :blk true;
    };

    // Filter generally pointless op combinations
    var range_start: usize = 0;
    for (branch_info[0..], 0..) |info, i| {
        if (info.is_target) {
            range_start = i;
        }
        if (i == warp.pc) {
            if (op_filter.run(candidate.bytes[range_start..warp.pc])) return null;
        }
    }

    while (true) {
        const last_instruction = (warp.pc + 1 >= candidate.size) or (candidate.mask[warp.pc + 1] == 0);

        switch (insmap[candidate.bytes[warp.pc]].size()) {
            1 => {},
            2 => {
                if (last_instruction) return null;
            },
            3 => {
                if (last_instruction) return null;
            },
            else => undefined,
        }

        const arg0 = if (last_instruction) 0 else candidate.bytes[warp.pc + 1];

        switch (candidate.bytes[warp.pc]) {

            // Implieds

            ins.tax.op => {
                if (!config.allow_x) return null;
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.x = sys.a;
                    sys.setZN(sys.x);
                }

                warp.defines.x = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },
            ins.txa.op => {
                if (warp.defines.x == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.x;
                    sys.setZN(sys.a);
                }

                warp.defines.a = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },
            ins.tay.op => {
                if (!config.allow_y) return null;
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.y = sys.a;
                    sys.setZN(sys.y);
                }

                warp.defines.y = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },
            ins.tya.op => {
                if (warp.defines.y == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.y;
                    sys.setZN(sys.a);
                }

                warp.defines.a = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.inx.op => {
                if (!config.allow_x) return null;
                if (warp.defines.x == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.x = sys.x +% 1;
                    sys.setZN(sys.x);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.dex.op => {
                if (!config.allow_x) return null;
                if (warp.defines.x == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.x = sys.x -% 1;
                    sys.setZN(sys.x);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.iny.op => {
                if (!config.allow_y) return null;
                if (warp.defines.y == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.y = sys.y +% 1;
                    sys.setZN(sys.y);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.dey.op => {
                if (!config.allow_y) return null;
                if (warp.defines.y == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.y = sys.y -% 1;
                    sys.setZN(sys.y);
                }
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.clc.op => {
                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.flags.carry = 0;
                }

                warp.defines.carry = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.clv.op => {
                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.flags.overflow = 0;
                }
                warp.defines.overflow = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.sec.op => {
                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.flags.carry = 1;
                }

                warp.defines.carry = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.asl.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.flags.carry = if (sys.a >= 128) 1 else 0;
                    sys.a = sys.a << 1;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.lsr.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.flags.carry = if (sys.a & 1 == 1) 1 else 0;
                    sys.a = sys.a >> 1;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.rol.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const ex_carry: u1 = if (sys.a >= 128) 1 else 0;
                    sys.a = (sys.a << 1) + sys.flags.carry;
                    sys.flags.carry = ex_carry;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            ins.ror.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const ex_carry: u1 = if (sys.a & 1 == 1) 1 else 0;
                    sys.a = (sys.a >> 1) + @as(u8, sys.flags.carry) * 128;
                    sys.flags.carry = ex_carry;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 1;
            },

            // Branches

            ins.bcc.op => {
                if (warp.defines.carry == 0) return null;

                const ns = warp.sortOnFlag("carry", true);
                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null;
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.carry == 0) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;

                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.bcs.op => {
                if (warp.defines.carry == 0) return null;

                const ns = warp.sortOnFlag("carry", false);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously

                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.carry == 1) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.beq.op => {
                if (warp.defines.zero == 0) return null;

                const ns = warp.sortOnFlag("zero", false);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.zero == 1) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.bne.op => {
                if (warp.defines.zero == 0) return null;

                const ns = warp.sortOnFlag("zero", true);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.zero == 0) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.bmi.op => {
                if (warp.defines.negative == 0) return null;

                const ns = warp.sortOnFlag("negative", false);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.negative == 1) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.bpl.op => {
                if (warp.defines.negative == 0) return null;

                const ns = warp.sortOnFlag("negative", true);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.negative == 0) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.bvc.op => {
                if (warp.defines.overflow == 0) return null;

                const ns = warp.sortOnFlag("overflow", false);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.overflow == 1) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            ins.bvs.op => {
                if (warp.defines.overflow == 0) return null;

                const ns = warp.sortOnFlag("overflow", true);

                if (is_before_first_target and warp.restart_iteration == 0 and ns == 0 or ns == warp.systems_n) return null; // and not loop 2 obviously
                warp.systems_n = if (ns == 0) warp.systems_n else ns;

                if (warp.systems[0].flags.overflow == 0) {
                    const target = @as(isize, warp.pc + 2) + @as(i8, @bitCast(arg0));
                    if (target < 0 or target > candidate.size) return null;
                    const ppenalty: u8 = if ((config.program_base + @as(u16, warp.pc)) & 0xff00 != (config.program_base + target) & 0xff00) 1 else 0;
                    warp.pc = @intCast(target);
                    cycles += 3 + ppenalty;
                } else {
                    warp.pc += 2;
                    cycles += 2;
                }
            },

            // Immediates

            ins.lda_imm.op => {
                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = arg0;
                    sys.setZN(sys.a);
                }

                warp.defines.a = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.ldx_imm.op => {
                if (!config.allow_x) return null;
                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.x = arg0;
                    sys.setZN(sys.x);
                }

                warp.defines.x = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.ldy_imm.op => {
                if (!config.allow_y) return null;
                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.y = arg0;
                    sys.setZN(sys.y);
                }

                warp.defines.y = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.adc_imm.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const val: u16 = @as(u16, sys.a) + @as(u16, arg0) + @as(u16, sys.flags.carry);
                    const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(arg0)) +% @as(i8, sys.flags.carry);

                    sys.a = @intCast(val & 0xff);
                    sys.flags.carry = if (val > 0xff) 1 else 0;
                    sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.overflow = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.sbc_imm.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;

                const arg0i: u8 = ~arg0;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const val: u16 = @as(u16, sys.a) + @as(u16, arg0i) + @as(u16, sys.flags.carry);
                    const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(arg0i)) +% @as(i8, sys.flags.carry);

                    sys.a = @intCast(val & 0xff);
                    sys.flags.carry = if (val > 0xff) 1 else 0;
                    sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.overflow = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.cmp_imm.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const val = sys.a -% arg0;
                    sys.flags.zero = if (sys.a == arg0) 1 else 0;
                    sys.flags.negative = if (val >= 128) 1 else 0;
                    sys.flags.carry = if (sys.a >= arg0) 1 else 0;
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                warp.defines.carry = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.cpx_imm.op => {
                if (warp.defines.x == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const val = sys.x -% arg0;
                    sys.flags.zero = if (sys.x == arg0) 1 else 0;
                    sys.flags.negative = if (val >= 128) 1 else 0;
                    sys.flags.carry = if (sys.x >= arg0) 1 else 0;
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                warp.defines.carry = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.cpy_imm.op => {
                if (warp.defines.y == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const val = sys.y -% arg0;
                    sys.flags.zero = if (sys.y == arg0) 1 else 0;
                    sys.flags.negative = if (val >= 128) 1 else 0;
                    sys.flags.carry = if (sys.y >= arg0) 1 else 0;
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                warp.defines.carry = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.and_imm.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a & arg0;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.eor_imm.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a ^ arg0;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.ora_imm.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a | arg0;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            // Immediates, unofficial

            ins.alr_imm.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a & arg0;
                    sys.flags.carry = if (sys.a & 1 == 1) 1 else 0;
                    sys.a = sys.a >> 1;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.anc_imm.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a & arg0;
                    sys.flags.carry = if (sys.a >= 128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.anc_imm_2.op => {
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a & arg0;
                    sys.flags.carry = if (sys.a >= 128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            ins.arr_imm.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.a & arg0;
                    sys.a = (sys.a >> 1) + @as(u8, sys.flags.carry) * 128;
                    sys.flags.carry = @intCast((sys.a >> 6) & 1);
                    sys.flags.overflow = @intCast(((sys.a >> 6) ^ (sys.a >> 5)) & 1);
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                warp.defines.overflow = 1;

                cycles += 2;
                warp.pc += 2;
            },

            ins.sbx_imm.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.x == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const ax = sys.a & sys.x;
                    sys.x = ax -% arg0;
                    sys.flags.carry = if (ax >= arg0) 1 else 0;
                    sys.setZN(sys.x);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 2;
                warp.pc += 2;
            },

            // Zeropage, read

            ins.lda_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.a = sys.readZp(arg0);
                    sys.setZN(sys.a);
                }

                warp.defines.a = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;

                cycles += 3;
                warp.pc += 2;
            },

            ins.ldx_zp.op => {
                if (!config.allow_x) return null;
                if (!tables.canReadZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.x = sys.readZp(arg0);
                    sys.setZN(sys.x);
                }

                warp.defines.x = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;

                cycles += 3;
                warp.pc += 2;
            },

            ins.ldy_zp.op => {
                if (!config.allow_y) return null;
                if (!tables.canReadZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.y = sys.readZp(arg0);
                    sys.setZN(sys.y);
                }

                warp.defines.y = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;

                cycles += 3;
                warp.pc += 2;
            },

            ins.adc_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    const val: u16 = @as(u16, sys.a) + @as(u16, byte) + @as(u16, sys.flags.carry);
                    const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(byte)) +% @as(i8, sys.flags.carry);

                    sys.a = @intCast(val & 0xff);
                    sys.flags.carry = if (val > 0xff) 1 else 0;
                    sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.overflow = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 3;
                warp.pc += 2;
            },

            ins.sbc_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = ~sys.readZp(arg0);
                    const val: u16 = @as(u16, sys.a) + @as(u16, byte) + @as(u16, sys.flags.carry);
                    const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(byte)) +% @as(i8, sys.flags.carry);

                    sys.a = @intCast(val & 0xff);
                    sys.flags.carry = if (val > 0xff) 1 else 0;
                    sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.overflow = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 3;
                warp.pc += 2;
            },

            ins.cmp_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    const val = sys.a -% byte;
                    sys.flags.zero = if (sys.a == byte) 1 else 0;
                    sys.flags.negative = if (val >= 128) 1 else 0;
                    sys.flags.carry = if (sys.a >= byte) 1 else 0;
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                warp.defines.carry = 1;
                cycles += 3;
                warp.pc += 2;
            },

            ins.bit_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    const val = sys.a & byte;

                    sys.flags.zero = if (val == 0) 1 else 0;
                    sys.flags.negative = if (byte & 0b10000000 > 0) 1 else 0;
                    sys.flags.overflow = if (byte & 0b01000000 > 0) 1 else 0;
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                warp.defines.overflow = 1;
                cycles += 3;
                warp.pc += 2;
            },

            ins.and_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    sys.a = sys.a & byte;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 3;
                warp.pc += 2;
            },

            ins.eor_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    sys.a = sys.a ^ byte;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 3;
                warp.pc += 2;
            },

            ins.ora_zp.op => {
                if (!tables.canReadZp(arg0)) return null;
                if (warp.defines.a == 0) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    sys.a = sys.a | byte;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 3;
                warp.pc += 2;
            },

            // Zeropage, read, unofficial

            ins.lax_zp.op => {
                if (!config.allow_x) return null;
                if (!tables.canReadZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    sys.a = byte;
                    sys.x = byte;
                    sys.setZN(byte);
                }

                warp.defines.a = 1;
                warp.defines.x = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 3;
                warp.pc += 2;
            },

            // Zeropage, write

            ins.sta_zp.op => {
                if (warp.defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.writeZp(arg0, sys.a);
                }

                warp.defines.setMem(arg0);
                cycles += 3;
                warp.pc += 2;
            },

            ins.stx_zp.op => {
                if (warp.defines.x == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.writeZp(arg0, sys.x);
                }

                warp.defines.setMem(arg0);
                cycles += 3;
                warp.pc += 2;
            },

            ins.sty_zp.op => {
                if (warp.defines.y == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.writeZp(arg0, sys.y);
                }

                warp.defines.setMem(arg0);
                cycles += 3;
                warp.pc += 2;
            },

            ins.inc_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0) +% 1;
                    sys.writeZp(arg0, byte);
                    sys.setZN(byte);
                }

                cycles += 5;
                warp.pc += 2;
            },

            ins.dec_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0) -% 1;
                    sys.writeZp(arg0, byte);
                    sys.setZN(byte);
                }

                cycles += 5;
                warp.pc += 2;
            },

            ins.asl_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    var byte = sys.readZp(arg0);
                    sys.flags.carry = if (byte >= 128) 1 else 0;
                    byte = byte << 1;
                    sys.writeZp(arg0, byte);
                    sys.setZN(byte);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.lsr_zp.op => {
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    var byte = sys.readZp(arg0);
                    sys.flags.carry = if (byte & 1 == 1) 1 else 0;
                    byte = byte >> 1;
                    sys.writeZp(arg0, byte);
                    sys.setZN(byte);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.rol_zp.op => {
                if (warp.defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    var byte = sys.readZp(arg0);
                    const ex_carry: u1 = if (byte >= 128) 1 else 0;
                    byte = (byte << 1) + sys.flags.carry;
                    sys.writeZp(arg0, byte);

                    sys.flags.carry = ex_carry;
                    sys.setZN(byte);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.ror_zp.op => {
                if (warp.defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    var byte = sys.readZp(arg0);
                    const ex_carry: u1 = if (byte & 1 == 1) 1 else 0;
                    byte = (byte >> 1) + (@as(u8, @intCast(sys.flags.carry)) << 7);
                    sys.writeZp(arg0, byte);

                    sys.flags.carry = ex_carry;
                    sys.setZN(byte);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            // Zeropage, write, unofficial

            ins.dcp_zp.op => {
                if (warp.defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0) -% 1;
                    sys.writeZp(arg0, byte);

                    const val = sys.a -% byte;
                    sys.flags.zero = if (sys.a == byte) 1 else 0;
                    sys.flags.negative = if (val >= 128) 1 else 0;
                    sys.flags.carry = if (sys.a >= byte) 1 else 0;
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.isc_zp.op => {
                if (warp.defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0) +% 1;
                    sys.writeZp(arg0, byte);

                    const bytei: u8 = ~byte;
                    const val: u16 = @as(u16, sys.a) + @as(u16, bytei) + @as(u16, sys.flags.carry);
                    const vval: i16 = @as(i8, @bitCast(sys.a)) +% @as(i8, @bitCast(bytei)) +% @as(i8, sys.flags.carry);

                    sys.a = @intCast(val & 0xff);
                    sys.flags.carry = if (val > 0xff) 1 else 0;
                    sys.flags.overflow = if (vval > 127 or vval < -128) 1 else 0;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.rla_zp.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const byte = sys.readZp(arg0);
                    const ex_carry: u1 = if (byte >= 128) 1 else 0;
                    const val = (byte << 1) + sys.flags.carry;
                    sys.flags.carry = ex_carry;
                    sys.writeZp(arg0, val);
                    sys.a &= val;
                    sys.setZN(sys.a);
                }

                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.rra_zp.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.carry == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
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
                }

                warp.defines.overflow = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.sax_zp.op => {
                if (warp.defines.a == 0) return null;
                if (warp.defines.x == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    sys.writeZp(arg0, sys.a & sys.x);
                }

                warp.defines.setMem(arg0);
                cycles += 3;
                warp.pc += 2;
            },

            ins.slo_zp.op => {
                if (warp.defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    // ASL
                    var byte = sys.readZp(arg0);
                    sys.flags.carry = if (byte >= 128) 1 else 0;
                    byte = byte << 1;
                    sys.writeZp(arg0, byte);

                    // ORA
                    sys.a = sys.a | byte;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            ins.sre_zp.op => {
                if (warp.defines.a == 0) return null;
                if (!tables.canWriteZp(arg0)) return null;
                if (!warp.defines.getMem(arg0)) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    // LSR
                    var byte = sys.readZp(arg0);
                    sys.flags.carry = if (byte & 1 == 1) 1 else 0;
                    byte = byte >> 1;
                    sys.writeZp(arg0, byte);

                    // EOR
                    sys.a = sys.a ^ byte;
                    sys.setZN(sys.a);
                }

                warp.defines.carry = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;
                cycles += 5;
                warp.pc += 2;
            },

            // Zeropage Y, read

            ins.ldx_zpy.op => {
                if (!config.allow_x) return null;
                if (warp.defines.y == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const arg_adj = arg0 +% sys.y;

                    if (!tables.canReadZp(arg_adj)) return null;
                    if (!warp.defines.getMem(arg_adj)) return null;

                    sys.x = sys.readZp(arg_adj);
                    sys.setZN(sys.x);
                }

                warp.defines.x = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;

                cycles += 4;
                warp.pc += 2;
            },

            // Zeropage Y, read, unofficial

            ins.lax_zpy.op => {
                if (!config.allow_x) return null;
                if (warp.defines.y == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const arg_adj = arg0 +% sys.y;

                    if (!tables.canReadZp(arg_adj)) return null;
                    if (!warp.defines.getMem(arg_adj)) return null;

                    sys.a = sys.readZp(arg_adj);
                    sys.x = sys.a;
                    sys.setZN(sys.x);
                }

                warp.defines.x = 1;
                warp.defines.a = 1;
                warp.defines.zero = 1;
                warp.defines.negative = 1;

                cycles += 4;
                warp.pc += 2;
            },

            // Zeropage Y, write

            ins.stx_zpy.op => {
                if (warp.defines.y == 0) return null;
                if (warp.defines.x == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const arg_adj = arg0 +% sys.y;

                    if (!tables.canWriteZp(arg_adj)) return null;
                    sys.writeZp(arg_adj, sys.x);

                    // Not ideal... Can lead to false positives -> relevant to all similar instructions
                    warp.defines.setMem(arg_adj);
                }

                cycles += 4;
                warp.pc += 2;
            },

            // Zeropage Y, write, unofficial

            ins.sax_zpy.op => {
                if (warp.defines.y == 0) return null;
                if (warp.defines.x == 0) return null;
                if (warp.defines.a == 0) return null;

                for (warp.systems[0..warp.systems_n]) |*sys| {
                    const arg_adj = arg0 +% sys.y;

                    if (!tables.canWriteZp(arg_adj)) return null;
                    sys.writeZp(arg_adj, sys.a & sys.x);

                    warp.defines.setMem(arg_adj);
                }

                cycles += 4;
                warp.pc += 2;
            },

            else => return null,
        }

        if (cycles > config.max_cycles) return null;

        if (warp.sortVerifyAndReduce() == false) return null;

        // Filter uneccesary ops
        if (is_before_first_target and warp.restart_iteration == 0) {
            if (prefilter) {
                switch (findBetterWarpInFilterList(&warp, cycles, candidate, prefilter)) {
                    .found_better => return null,
                    .replaced => {},
                    .none => {
                        addToFilteredWarps(&warp, cycles, candidate);
                    },
                }
            } else {
                if (findBetterWarpInFilterList(&warp, cycles, candidate, prefilter) == .found_better) {
                    return null;
                }
            }
        }

        // Success?
        if (warp.pc == candidate.size) {
            if (warp.checkSuccess()) {
                warp.tests_complete_n += warp.systems_n;

                // All tests OK?
                if (warp.tests_complete_n == states[0].warp.systems_n) {
                    if (warp.reached_candidate_stop) {
                        if (!prefilter) {
                            addCandidate(candidate);
                        }
                    } else {
                        if (!prefilter) {
                            const cycles_this_batch = cycles * warp.systems_n;
                            const total_cycles = start_state.total_cycles + cycles_this_batch;
                            const worst_cycles = if (start_state.worst_cycles > cycles_this_batch) start_state.worst_cycles else cycles;
                            successCallback(candidate, worst_cycles, total_cycles);
                        }
                    }
                    return null;
                } else {
                    // note: not true as systems_n gets compacted. todo: fix (use complete tests or the like instead)
                    const cycles_this_batch = cycles * warp.systems_n;
                    const worst_cycles = if (start_state.worst_cycles > cycles_this_batch) start_state.worst_cycles else cycles;

                    warp.setCompletionMask();
                    warp.activateIncompleteTests();
                    _ = warp.generateTests();
                    warp.pc = 0;
                    warp.defines = tables.base_defines;
                    warp.restart_iteration += 1;
                    start_state.total_cycles += cycles_this_batch;
                    start_state.worst_cycles = worst_cycles;
                    continue;
                }
            } else {
                return null;
            }
        }

        // Generation termination?
        if (start_state.generation == config.prefix_size - 1 and states[warp.pc].active == false) {
            warp.reached_candidate_stop = true;
            warp.tests_complete_n += warp.systems_n;
            if (warp.tests_complete_n == states[0].warp.systems_n) {
                if (!prefilter) {
                    addCandidate(candidate);
                }
                return null;
            } else {
                warp.setCompletionMask();
                warp.activateIncompleteTests();
                _ = warp.generateTests();
                warp.pc = 0;
                warp.restart_iteration += 1;
                warp.defines = tables.base_defines;
                continue;
            }
        }

        // If we reach an inactive warp, grab it
        if (states[warp.pc].active == false) {

            // if it's masked, check if it's executable and a 1-byte instruction, if so just continue
            if (candidate.mask[warp.pc] == 1) {
                if (config.allow_shadow_execution == false) return null;
                const opsize = insmap[candidate.bytes[warp.pc]].size();

                switch (opsize) {
                    1 => continue,
                    2 => {
                        const is_last_instruction = (warp.pc + 1 >= candidate.size) or (candidate.mask[warp.pc + 1] == 0);
                        if (is_last_instruction) return null;
                        if (candidate.mask[warp.pc + 1] == 1) continue; // We're in previously genned code
                        // OK this case can never happen in practice. Fall through anyway.
                    },
                    3 => return null, //3-byte ops are TODO
                    else => unreachable,
                }
            }

            const new_state = &states[warp.pc];

            new_state.* = .{
                .parent = start_state.warp.pc,
                .active = true,
                .generation = start_state.generation + 1,
                .worst_cycles = start_state.worst_cycles,
                .total_cycles = start_state.total_cycles,
                .cycles = cycles,
                .warp = warp,
            };

            // Lock the first byte if possible
            if (candidate.mask[warp.pc] == 0) {
                new_state.lock0 = true;
                candidate.mask[warp.pc] = 1;
            }

            return new_state;
        }
    }
    return null;
}
