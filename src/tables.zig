const std = @import("std");
const config = @import("config.zig");
const tables = @import("tables.zig");
const System = @import("system.zig").System;
const Defines = @import("system.zig").Defines;

const instructions = @import("instructions.zig").instructions;
const instructionmap = @import("instructions.zig").instructionmap;

pub const TestIndex = switch (config.test_cases) {
    0 => unreachable,
    1...256 => u8,
    257...65536 => u16,
    else => u32, // good luck with that
};

pub const base_defines: Defines = blk: {
    var def = Defines{};

    var test_system = System{};
    config.test_generate(&test_system, 0);
    def.a = if (test_system.a != 0) 1 else 0;
    def.x = if (test_system.x != 0) 1 else 0;
    def.y = if (test_system.y != 0) 1 else 0;
    def.carry = if (test_system.flags.carry != 0) 1 else 0;
    def.zero = if (test_system.flags.zero != 0) 1 else 0;
    def.overflow = if (test_system.flags.overflow != 0) 1 else 0;
    def.negative = if (test_system.flags.negative != 0) 1 else 0;

    for (def.memory[0..], 0..) |*mem, i| {
        mem.* = if (test_system.mem[i] != 0) 1 else 0;
    }

    test_system = System{
        // .test_index = 0,
        .a = 1,
        .x = 1,
        .y = 1,
        .mem = @splat(1),
        .flags = .{
            .carry = 1,
            .zero = 1,
            .overflow = 1,
            .negative = 1,
        },
    };
    config.test_generate(&test_system, 0);
    def.a = if (test_system.a != 1) 1 else def.a;
    def.x = if (test_system.x != 1) 1 else def.x;
    def.y = if (test_system.y != 1) 1 else def.y;
    def.carry = if (test_system.flags.carry != 1) 1 else def.carry;
    def.zero = if (test_system.flags.zero != 1) 1 else def.zero;
    def.overflow = if (test_system.flags.overflow != 1) 1 else def.overflow;
    def.negative = if (test_system.flags.negative != 1) 1 else def.negative;

    for (def.memory[0..], 0..) |*mem, i| {
        mem.* = if (test_system.mem[i] != 1) 1 else def.memory[i];
    }

    break :blk def;
};

fn opIsValidToExecute(op: u8) bool {
    const info = instructionmap[op];
    if (!info.implemented) return false;
    if (info.jam or info.nop or info.unstable) return false;
    if (!config.allow_unofficial_opcodes and info.unofficial) return false;

    if (!config.allow_stack) {
        if (op == instructions.pha.op) return false;
        if (op == instructions.php.op) return false;
        if (op == instructions.pla.op) return false;
        if (op == instructions.plp.op) return false;
        if (op == instructions.rts.op) return false;
        if (op == instructions.tsx.op) return false;
        if (op == instructions.txs.op) return false;
        if (op == instructions.jsr.op) return false;
    }

    if (op == instructions.cld.op) return false;
    if (op == instructions.cli.op) return false;
    if (op == instructions.sed.op) return false;
    if (op == instructions.sei.op) return false;
    if (op == instructions.rti.op) return false;

    if (op == instructions.jmp.op) return false;
    if (op == instructions.jmp_ind.op) return false;

    return true;
}

pub fn canUseImm(byte: u8, comptime is_target: bool) bool {
    if (is_target) return imm_allowed_map_trg[byte] == 1;
    return imm_allowed_map[byte] == 1;
}

pub const allowed_imm_constants = config.allowed_imm_constants;

pub const allowed_imm_constants_trg = blk: {
    if (!config.allow_shadow_execution) break :blk [0]u8{};
    var out: [config.allowed_imm_constants.len]u8 = undefined;

    var nm: usize = 0;
    for (config.allowed_imm_constants) |mem| {
        if (!opIsValidToExecute(mem)) continue;
        out[nm] = mem;
        nm += 1;
    }
    break :blk out[0..nm].*;
};

pub const imm_allowed_map = blk: {
    var map: [256]u8 = @splat(0);
    for (config.allowed_imm_constants) |azp| {
        map[azp] = 1;
    }
    break :blk map;
};

pub const imm_allowed_map_trg = blk: {
    var map: [256]u8 = @splat(0);
    for (allowed_imm_constants_trg) |azp| {
        map[azp] = 1;
    }
    break :blk map;
};

pub const memory_size = blk: {
    var mem: [256]bool = @splat(false);
    for (config.allowed_zp_memory) |azp| {
        mem[azp] = true;
    }

    var counter: usize = 0;
    for (mem) |m| {
        if (m) counter += 1;
    }

    //for (config.allowed_zp_memory_readonly) |azp| {
    //    if (mem[azp[0]]) @compileError("Simultaneous readonly and readwrite zeropage memory");
    //}
    break :blk counter;
};

// A mapping table from ZP memory address to storage
pub const zp_memory_map = blk: {
    var mem: [256]bool = @splat(false);
    for (config.allowed_zp_memory) |azp| {
        mem[azp] = true;
    }

    var map: [256]u8 = @splat(255);
    var counter: usize = 0;
    for (mem, 0..) |m, i| {
        if (m) {
            map[i] = counter;
            counter += 1;
        }
    }
    break :blk map;
};

pub const allowed_zp_memory_trg = blk: {
    if (!config.allow_shadow_execution) break :blk [0]u8{};
    var out: [config.allowed_zp_memory.len]u8 = undefined;

    var nm: usize = 0;
    for (config.allowed_zp_memory) |mem| {
        if (!opIsValidToExecute(mem)) continue;
        out[nm] = mem;
        nm += 1;
    }
    break :blk out[0..nm].*;
};

pub fn canReadZp(addr: u8) bool {
    return zp_memory_map[addr] != 0xff;
}

pub fn canWriteZp(addr: u8) bool {
    return zp_memory_map[addr] != 0xff;
}
