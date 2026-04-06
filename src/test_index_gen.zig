const std = @import("std");
const System = @import("system.zig").System;
const config = @import("config.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var args = init.minimal.args.iterate();
    _ = args.skip();
    const fname = args.next() orelse unreachable;

    const file = try std.Io.Dir.cwd().createFile(io, fname, .{});
    defer file.close(io);

    var fbuf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &fbuf);
    var w = &file_writer.interface;

    {
        var systems: [config.test_cases]System = undefined;
        for (systems[0..], 0..) |*sys, i| {
            sys.* = System{};
            sys.test_index = @intCast(i);

            var in_sys = System{};
            config.test_generate(&in_sys, i);
            config.test_run(&in_sys, sys);
        }

        std.mem.sort(System, &systems, {}, System.sort);

        var indices: [config.test_cases]u32 = undefined;
        var ridx: u32 = 0;
        var prev_sys: ?*const System = null;
        for (&systems) |*sys| {
            if (prev_sys) |psys| {
                if (System.isEqual(psys, sys)) {
                    indices[sys.test_index] = ridx;
                } else {
                    ridx += 1;
                    indices[sys.test_index] = ridx;
                }
            } else {
                indices[sys.test_index] = ridx;
            }
            prev_sys = sys;
        }

        if (ridx < 256) {
            try w.print("pub const indices = [{}]u8{{", .{indices.len});
        } else if (ridx < 65536) {
            try w.print("pub const indices = [{}]u16{{", .{indices.len});
        } else {
            try w.print("pub const indices = [{}]u32{{", .{indices.len});
        }

        for (indices, 0..) |ind, i| {
            try w.print("{}", .{ind});
            if (i != indices.len - 1) {
                try w.writeAll(",");
            }
        }
        try w.writeAll("};\n");
    }

    try w.flush();
}
