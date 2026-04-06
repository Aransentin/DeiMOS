const std = @import("std");
const config = @import("config.zig");
const il = @import("instructions.zig").instructions;
const ilm = @import("instructions.zig").instructionmap;

pub const Program = struct {
    size: u8,
    bytes: [config.max_length]u8,
    mask: [config.max_length]u1,

    pub fn init(size: u8) Program {
        return Program{
            .size = size,
            .bytes = [_]u8{0} ** config.max_length,
            .mask = [_]u1{0} ** config.max_length,
        };
    }

    pub fn print(self: Program) !void {
        var buf: [1024]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        var w = &writer;

        var visited = [_]bool{false} ** config.max_length;
        var is_arg = [_]bool{false} ** config.max_length;
        scanVisited(self.bytes[0..self.size], self.mask[0..self.size], visited[0..self.size], is_arg[0..self.size], 0);

        for (0..self.size) |p| {
            const byte = self.bytes[p];

            if (self.mask[p] == 0) {
                try w.print("{X:0>4} ???\n", .{config.program_base + p});
                continue;
            }

            try w.print("{X:0>4} {X:0>2}", .{ config.program_base + p, byte });
            if (!visited[p]) {
                try w.writeAll("\n");
                continue;
            }

            const instr = ilm[byte];

            if (instr.unofficial) {
                try w.writeAll(" U");
            } else {
                try w.writeAll("  ");
            }

            if (is_arg[p]) {
                try w.writeAll("S");
            } else {
                try w.writeAll(" ");
            }

            try w.print(" {s}", .{instr.name});

            const arg0: ?u8 = if (p + 1 >= self.size) null else self.bytes[p + 1];
            const arg1: ?u8 = if (p + 2 >= self.size) null else self.bytes[p + 2];

            switch (instr.mode) {
                .implied => {},
                .immediate => {
                    if (arg0) |arg| {
                        try w.print(" #${X:0>2}", .{arg});
                    } else {
                        try w.writeAll(" #$??");
                    }
                },
                .accumulator => {
                    try w.writeAll(" A");
                },
                .absolute, .absolute_x, .absolute_y => {
                    if (arg0 != null and arg1 != null) {
                        try w.print(" ${X:0>2}{X:0>2}", .{ arg1.?, arg0.? });
                    } else if (arg0 == null and arg1 != null) {
                        try w.print(" ${X:0>2}??", .{arg1.?});
                    } else if (arg0 != null and arg1 == null) {
                        try w.print(" $??{X:0>2}", .{arg0.?});
                    } else {
                        try w.writeAll(" $????");
                    }

                    if (instr.mode == .absolute_x) {
                        try w.writeAll(",X");
                    } else if (instr.mode == .absolute_y) {
                        try w.writeAll(",Y");
                    }
                },
                .indirect => {
                    if (arg0 != null and arg1 != null) {
                        try w.print(" (${X:0>2}{X:0>2})", .{ arg1.?, arg0.? });
                    } else if (arg0 == null and arg1 != null) {
                        try w.print(" (${X:0>2}??)", .{arg1.?});
                    } else if (arg0 != null and arg1 == null) {
                        try w.print(" ($??{X:0>2})", .{arg0.?});
                    } else {
                        try w.writeAll(" ($????)");
                    }
                },
                .indirect_x => {
                    if (arg0) |arg| {
                        try w.print(" (${X:0>2},X)", .{arg});
                    } else {
                        try w.writeAll(" ($??,X)");
                    }
                },
                .indirect_y => {
                    if (arg0) |arg| {
                        try w.print(" (${X:0>2}),Y", .{arg});
                    } else {
                        try w.writeAll(" ($??),Y");
                    }
                },
                .zeropage, .zeropage_x, .zeropage_y => {
                    if (arg0) |arg| {
                        try w.print(" ${X:0>2}", .{arg});
                    } else {
                        try w.writeAll(" $??");
                    }

                    if (instr.mode == .zeropage_x) {
                        try w.writeAll(",X");
                    } else if (instr.mode == .zeropage_y) {
                        try w.writeAll(",Y");
                    }
                },
                .relative => {
                    if (arg0) |arg| {
                        const addr_dst_i = @as(isize, @intCast(config.program_base + p + 2)) + @as(i8, @bitCast(arg));
                        const addr_dst: usize = @intCast(addr_dst_i);

                        try w.print(" ${X:0>2} ({X:0>4})", .{ arg, addr_dst });
                    } else {
                        try w.writeAll(" $?? ($????)");
                    }
                },
            }

            try w.writeAll("\n");
        }

        try w.writeAll("\n");

        try w.flush();
        std.debug.print("{s}", .{buf[0..writer.end]});
    }

    fn scanVisited(bytes: []const u8, mask: []const u1, visited: []bool, is_arg: []bool, offset: usize) void {
        var p: usize = offset;
        while (p < bytes.len) {
            if (visited[p]) return;
            if (mask[p] == 0) return;

            visited[p] = true;
            const byte = bytes[p];
            const instr = ilm[byte];

            const nb: usize = switch (instr.mode) {
                .accumulator, .implied => 1,
                .immediate, .indirect_x, .indirect_y, .relative, .zeropage, .zeropage_x, .zeropage_y => 2,
                .absolute, .absolute_x, .absolute_y, .indirect => 3,
            };

            if (nb > 1 and p + 1 < bytes.len) {
                is_arg[p + 1] = true;
            }
            if (nb == 3 and p + 2 < bytes.len) {
                is_arg[p + 2] = true;
            }

            if (instr.mode == .relative) {
                if (p + 1 < bytes.len) {
                    const p_target: isize = @as(isize, @intCast(2 + p)) + @as(i8, @bitCast(bytes[p + 1]));
                    if (p_target >= 0 and p_target < bytes.len) {
                        scanVisited(bytes, mask, visited, is_arg, @intCast(p_target));
                    }
                }
            }

            p += nb;
        }
    }
};
