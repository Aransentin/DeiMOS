// Largest program to investigate before giving up.
pub const max_length = 10;

// The maximum amount of branches allowed in the program. Does not count shadow instructions.
pub const max_branches = 1;

// If branches are forbidden to branch backwards. Prevents loops if enabled.
pub const branch_forward_only = false;

// Where the program will reside in memory. Affects the timing of some instructions.
pub const program_base = 0xc000;

// How large the precomputed prefixes should be
pub const prefix_size = 3;

// The number of cycles to emulate before giving up.
pub const max_cycles: usize = 256;

// Allow generation and execution of instructions that affect the stack. Unimplemented for now.
pub const allow_stack = false;

// Allow generation of X & Y - offset zero-page instructions
pub const allow_zp_xy = false;

// Allow generation of absolute reads & writes. Unimplemented for now.
pub const allow_abs = false;

// Allow the unofficial opcodes.
pub const allow_unofficial_opcodes = true;

// The unofficial opcode ANC has two identical forms, 0x0B and 0x2B. Here you can disable one (or both, if you want) of them.
pub const allow_ANC_0x0B = true;
pub const allow_ANC_0x2B = false;

// The immediate version of the official opcode SBC has an unofficial clone (0xEB) that does the same thing. You can enable it here.
pub const allow_SBC_0xEB = false;

// Allow branches to jump into the middle of instructions, treating the arguments as opcodes.
pub const allow_shadow_execution = true;

// The ZP memory addresses that may be accessed for reading / writing
pub const allowed_zp_memory = [_]u8{0x00};

// allowed IMM-constants
pub const allowed_imm_constants = [_]u8{};

// The number of test cases to evaluate
pub const test_cases = 256;

// Test generation & verification functions
const System = @import("system.zig").System;

pub fn test_generate(system: *System, idx: usize) void {
    system.a = @intCast(idx);
}

pub fn test_run(in: *const System, out: *System) void {
    out.a = @popCount(in.a);
}

pub fn test_verify(in: *const System, out: *const System) bool {
    if (out.a == @popCount(in.a)) return true;
    return false;
}
