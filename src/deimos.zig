const std = @import("std");
const limits = @import("limits.zig");
const signals = @import("signals.zig");
const server = @import("server.zig");
const config = @import("config.zig");
const Program = @import("program.zig").Program;
const BranchTemplate = @import("branch_template.zig").BranchTemplate;
const warp_emulator = @import("warp_emulator.zig");

const tables = @import("tables.zig");
const instructions = @import("instructions.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    limits.init();
    signals.init();

    try server.init();
    defer server.deinit();

    var args = init.args.iterate();
    _ = args.skip();
    if (args.next()) |phobos_path| {
        const num_workers = try std.fmt.parseUnsigned(u32, args.next() orelse "0", 10);
        for (0..num_workers) |_| {
            const npid = std.os.linux.fork();
            if (npid < 0) return error.ForkFailed;
            if (npid > 0) continue;

            const sig_kill: usize = @intFromEnum(std.os.linux.SIG.KILL);
            _ = std.posix.prctl(.SET_PDEATHSIG, .{sig_kill}) catch {};

            const child_args = [_:null]?[*:0]const u8{ "phobos", "127.0.0.1", null };
            const child_env = [_:null]?[*:0]const u8{null};
            const err = std.os.linux.execve(phobos_path, &child_args, &child_env);
            std.log.err("execve failed: {}", .{std.os.linux.errno(err)});
            _ = std.os.linux.close(1);
        }
    }

    const size_start = if (config.min_branches == 0) 0 else 1 + config.min_branches * 2;
    for (size_start..config.max_length + 1) |length| {
        std.log.info("Program size: {}", .{length});

        var btemplate = BranchTemplate.init(@intCast(length));
        while (true) {
            // btemplate.debugPrint();

            const candidates = warp_emulator.run(length, btemplate.info());
            // for (candidates) |cnd| {
            //    cnd.print() catch {};
            // }

            try server.serveCandidates(btemplate, candidates);

            if (signals.flag) return;
            if (!btemplate.next()) break;
        }
    }
}

var best_size: ?usize = null;
var best_cycles_total: usize = 0;
var best_cycles_worst: usize = 0;

pub fn successCallback(program: *const Program, worst_cycles: usize, total_cycles: usize) void {
    const better_size = (best_size == null or program.size < best_size.?);
    const better_cycles_total = (worst_cycles < best_cycles_worst);
    const better_cycles_worst = (total_cycles < best_cycles_total);
    if (!better_size and !better_cycles_total and !better_cycles_worst) return;

    if (best_size == null) {
        best_size = program.size;
        best_cycles_total = total_cycles;
        best_cycles_worst = worst_cycles;
    } else {
        best_size = if (program.size < best_size.?) program.size else best_size.?;
        best_cycles_total = if (total_cycles < best_cycles_total) total_cycles else best_cycles_total;
        best_cycles_worst = if (worst_cycles < best_cycles_worst) worst_cycles else best_cycles_worst;
    }

    std.log.info("Program found: bytes: {}, cycles (total): {}, cycles (worst case): {}", .{ program.size, total_cycles, worst_cycles });
    program.print() catch unreachable;
}
