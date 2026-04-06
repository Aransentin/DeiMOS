const std = @import("std");
const Program = @import("program.zig").Program;
const BranchTemplate = @import("branch_template.zig").BranchTemplate;
const config = @import("config.zig");
const errno = std.os.linux.errno;

pub const Task = struct {
    branch_template: BranchTemplate,
    program: Program,
};

var fd: std.posix.fd_t = undefined;

pub fn init(addr: []const u8) !void {
    const addr4 = try std.Io.net.Ip4Address.parse(addr, 6502);

    fd = blk: {
        const rc = std.os.linux.socket(std.posix.AF.INET, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0);
        switch (errno(rc)) {
            .SUCCESS => break :blk @intCast(rc),
            else => return error.SocketFailed,
        }
    };
    errdefer _ = std.os.linux.close(fd);

    const sockaddr = std.posix.sockaddr.in{
        .port = std.mem.nativeToBig(u16, 6502),
        .addr = std.mem.readInt(u32, std.mem.asBytes(&addr4.bytes), .little),
    };

    {
        const rc = std.os.linux.connect(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in));
        switch (errno(rc)) {
            .SUCCESS => {},
            else => return error.ConnectFailed,
        }
    }
}

pub fn deinit() void {
    _ = std.os.linux.close(fd);
}

pub fn getTask() !Task {
    var task: Task = undefined;

    const rc = std.os.linux.read(fd, std.mem.asBytes(&task).ptr, @sizeOf(Task));
    const nbr: usize = blk: {
        switch (errno(rc)) {
            .SUCCESS => break :blk @intCast(rc),
            else => return error.ReadFailed,
        }
    };

    if (nbr == 0) return error.Disconnected;
    if (nbr > @sizeOf(Task)) return error.ReadFailed;
    if (nbr != @sizeOf(Task)) return error.ShortRead;

    return task;
}

pub fn sendTaskDone() !void {
    const rc = std.os.linux.write(fd, &[1]u8{0}, 1);
    switch (errno(rc)) {
        .SUCCESS => return,
        else => return error.WriteFailed,
    }
}

pub fn sendSuccess(program: Program, worst_cycles: u32, total_cycles: u32) !void {
    var msg: extern struct {
        id: u8 = 1,
        size: u8,
        bytes: [config.max_length]u8,
        mask: [config.max_length]u8,
        worst_cycles: u32,
        total_cycles: u32,
    } = .{
        .size = program.size,
        .bytes = program.bytes,
        .mask = undefined,
        .worst_cycles = worst_cycles,
        .total_cycles = total_cycles,
    };

    for (program.mask, 0..) |m, i| {
        msg.mask[i] = m;
    }

    const rc = std.os.linux.write(fd, std.mem.asBytes(&msg), @sizeOf(@TypeOf(msg)));
    switch (errno(rc)) {
        .SUCCESS => return,
        else => return error.WriteFailed,
    }
}
