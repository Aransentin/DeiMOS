const std = @import("std");
const limits = @import("limits.zig");
const signals = @import("signals.zig");
const client = @import("client.zig");
const emulator = @import("emulator.zig");
const Program = @import("program.zig").Program;

pub fn main(init: std.process.Init.Minimal) !void {
    limits.init();
    signals.init();

    var args = init.args.iterate();
    _ = args.skip();
    const master_host = args.next() orelse return error.NoHostSpecified;

    try client.init(master_host);
    defer client.deinit();

    while (!signals.flag) {
        const task = client.getTask() catch break;
        emulator.run(task.program, task.branch_template.info());
        try client.sendTaskDone();
    }
}

var best_size: ?u32 = null;
var best_cycles_total: u32 = 0;
var best_cycles_worst: u32 = 0;

pub fn successCallback(program: *const Program, worst_cycles: u32, total_cycles: u32) void {
    const better_size = (best_size == null or program.size < best_size.?);
    const better_cycles_total = (worst_cycles < best_cycles_worst);
    const better_cycles_worst = (total_cycles < best_cycles_total);
    if (!better_size and !better_cycles_total and !better_cycles_worst) return;

    best_size = if (best_size == null or program.size < best_size.?) program.size else best_size.?;
    best_cycles_total = if (total_cycles < best_cycles_total) total_cycles else best_cycles_total;
    best_cycles_worst = if (worst_cycles < best_cycles_worst) worst_cycles else best_cycles_worst;

    //std.log.info("Program found: bytes: {}, cycles (total): {}, cycles (worst case): {}", .{ program.size, total_cycles, worst_cycles });
    //program.print() catch unreachable;

    client.sendSuccess(program.*, worst_cycles, total_cycles) catch {
        std.os.linux.exit(0);
    };
}
