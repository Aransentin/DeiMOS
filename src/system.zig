const tables = @import("tables.zig");

pub const Defines = struct {
    a: u1 = 0,
    x: u1 = 0,
    y: u1 = 0,
    carry: u1 = 0,
    zero: u1 = 0,
    overflow: u1 = 0,
    negative: u1 = 0,
    memory: [tables.memory_size]u1 = @splat(0),

    pub fn getMem(self: *Defines, p: u8) bool {
        if (tables.memory_size == 0) return false;
        return self.memory[tables.zp_memory_map[p]] == 1;
    }

    pub fn setMem(self: *Defines, p: u8) void {
        if (tables.memory_size == 0) return;
        self.memory[tables.zp_memory_map[p]] = 1;
    }
};

pub const Flags = packed struct(u8) {
    carry: u1 = 0,
    zero: u1 = 0,
    interrupt_disable: u1 = 0,
    decimal: u1 = 0,
    pad0: u1 = 0,
    pad1: u1 = 0,
    overflow: u1 = 0,
    negative: u1 = 0,
};

pub const System = struct {
    // test_index: if (in_warp) tables.TestIndex else void,
    // pc: if (!in_warp) u8 else void,
    // defines: if (!in_warp) Defines else void,

    test_index: tables.TestIndex = 0,
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    flags: Flags = .{},
    mem: [tables.memory_size]u8 = @splat(0),

    pub fn readZp(self: *const System, addr: u8) u8 {
        if (tables.memory_size == 0) unreachable;
        if (!tables.canReadZp(addr)) unreachable;

        const offset = tables.zp_memory_map[addr];
        return self.mem[offset];
    }

    pub fn writeZp(self: *System, addr: u8, data: u8) void {
        if (tables.memory_size == 0) unreachable;
        if (!tables.canWriteZp(addr)) unreachable;
        const offset = tables.zp_memory_map[addr];
        self.mem[offset] = data;
    }

    pub fn setZN(self: *System, byte: u8) void {
        self.flags.zero = if (byte == 0) 1 else 0;
        self.flags.negative = if (byte >= 128) 1 else 0;
    }

    pub fn sort(_: void, lhs: System, rhs: System) bool {
        if (lhs.a != rhs.a) return lhs.a < rhs.a;
        if (lhs.x != rhs.x) return lhs.x < rhs.x;
        if (lhs.y != rhs.y) return lhs.y < rhs.y;

        const lflags = @as(u8, @bitCast(lhs.flags)) & 0b11110011;
        const rflags = @as(u8, @bitCast(rhs.flags)) & 0b11110011;
        if (lflags != rflags) return lflags < rflags;

        for (0..tables.memory_size) |i| {
            if (lhs.mem[i] != rhs.mem[i]) return lhs.mem[i] < rhs.mem[i];
        }

        return lhs.test_index < rhs.test_index;
    }

    pub fn isEqual(lhs: *const System, rhs: *const System) bool {
        if (lhs.a != rhs.a) return false;
        if (lhs.x != rhs.x) return false;
        if (lhs.y != rhs.y) return false;

        const lflags = @as(u8, @bitCast(lhs.flags)) & 0b11001111;
        const rflags = @as(u8, @bitCast(rhs.flags)) & 0b11001111;

        if (lflags != rflags) return false;

        for (0..tables.memory_size) |i| {
            if (lhs.mem[i] != rhs.mem[i]) return false;
        }

        return true;
    }
};
