const std = @import("std");
const config = @import("config.zig");
const tables = @import("tables.zig");
const System = @import("system.zig").System;
const Defines = @import("system.zig").Defines;
const test_indices = @import("test_indices");

pub const Warp = struct {
    pc: u8,
    systems_n: u32,
    systems: [config.test_cases]System = undefined,
    defines: Defines,

    filter_used: bool = false,
    reached_candidate_stop: bool = false,
    restart_iteration: u32 = 0,

    tests_complete_n: u32,
    tests_complete: [config.test_cases]u1 = [_]u1{0} ** config.test_cases,

    pub fn initTestIndices(self: *Warp) void {
        for (self.systems[0..self.systems_n], 0..) |*sys, idx| {
            sys.test_index = @intCast(idx);
        }
    }

    pub fn generateTests(self: *Warp) void {
        for (self.systems[0..self.systems_n]) |*sys| {
            const test_index = sys.test_index;
            sys.* = System{};
            config.test_generate(sys, test_index);
            sys.test_index = test_index;
        }
        if (self.sortVerifyAndReduce() == false) unreachable;
    }

    pub fn checkSuccess(self: *Warp) bool {
        for (self.systems[0..self.systems_n]) |sys| {
            var start_sys = System{};
            start_sys.test_index = sys.test_index;
            config.test_generate(&start_sys, sys.test_index);
            if (!config.test_verify(&start_sys, &sys)) return false;
        }
        return true;
    }

    pub fn setCompletionMask(self: *Warp) void {
        for (self.systems[0..self.systems_n]) |sys| {
            self.tests_complete[sys.test_index] = 1;
        }
    }

    pub fn activateIncompleteTests(self: *Warp) void {
        std.mem.sort(System, self.systems[0..], self, incompleteTestSort);

        var nsys: u32 = 0;
        for (self.systems[0..]) |sys| {
            if (self.tests_complete[sys.test_index] == 1) break;
            nsys += 1;
        }

        if (nsys == 0) unreachable;
        self.systems_n = nsys;
    }

    pub fn sortVerifyAndReduce(self: *Warp) bool {
        std.mem.sort(System, self.systems[0..self.systems_n], {}, System.sort);

        for (self.systems[0 .. self.systems_n - 1], 0..) |*sys, idx| {
            const nsys = &self.systems[idx + 1];
            if (System.isEqual(sys, nsys)) {
                const idx0 = test_indices.indices[sys.test_index];
                const idx1 = test_indices.indices[nsys.test_index];
                if (idx0 != idx1) return false;
                nsys.flags.pad0 = 1;
                self.tests_complete[nsys.test_index] = 1;
                self.tests_complete_n += 1;
            }
        }

        self.systems_n = self.sortOnFlag("pad0", false);
        if (self.systems_n == 0) unreachable;

        return true;
    }

    pub fn sortOnFlag(self: *Warp, comptime flag: []const u8, comptime set: bool) u32 {
        const comparator = systemFlagSortComparatorGenerator(flag, set);
        std.mem.sort(System, self.systems[0..self.systems_n], {}, comparator);

        var nsorted: u32 = 0;
        for (self.systems[0..self.systems_n]) |sys| {
            if (@field(sys.flags, flag) != if (set) 1 else 0) break;
            nsorted += 1;
        }
        return nsorted;
    }

    pub fn hash(self: *const Warp) u64 {
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&self.defines));
        for (self.systems[0..self.systems_n]) |sys| {
            hasher.update(std.mem.asBytes(&sys.a));
            hasher.update(std.mem.asBytes(&sys.x));
            hasher.update(std.mem.asBytes(&sys.y));
            hasher.update(std.mem.asBytes(&sys.flags));

            for (sys.mem[0..], self.defines.mem[0..]) |zp, dzp| {
                if (dzp == 0) continue;
                hasher.update(std.mem.asBytes(&zp));
            }
        }

        // 354
        // in practice I can mask with 0x000000000000ffff before it starts colliding
        return hasher.final(); // & 0x000000000000ffff;
    }
};

pub fn systemFlagSortComparatorGenerator(comptime bit: []const u8, comptime set: bool) fn (void, System, System) bool {
    return struct {
        pub fn inner(_: void, lhs: System, rhs: System) bool {
            if (set) {
                return @field(lhs.flags, bit) > @field(rhs.flags, bit);
            } else {
                return @field(lhs.flags, bit) < @field(rhs.flags, bit);
            }
        }
    }.inner;
}

fn incompleteTestSort(warp: *const Warp, lhs: System, rhs: System) bool {
    return warp.tests_complete[lhs.test_index] < warp.tests_complete[rhs.test_index];
}
