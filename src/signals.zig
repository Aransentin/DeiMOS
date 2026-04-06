const std = @import("std");

pub var flag: bool = false;

fn handleSIGINT(_: std.os.linux.SIG) callconv(.c) void {
    if (flag) std.os.linux.exit(1);
    flag = true;
}

pub fn init() void {
    var act_sigint = std.posix.Sigaction{
        .handler = .{ .handler = handleSIGINT },
        .mask = std.posix.sigemptyset(),
        .flags = std.posix.SA.SIGINFO,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act_sigint, null);

    var act_ign = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = std.posix.SA.SIGINFO,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act_ign, null);
    std.posix.sigaction(std.posix.SIG.HUP, &act_ign, null);
    std.posix.sigaction(std.posix.SIG.CHLD, &act_ign, null);
}
