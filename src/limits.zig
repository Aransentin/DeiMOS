const std = @import("std");

pub fn init() void {
    var lim = std.posix.getrlimit(.NOFILE) catch unreachable;
    if (lim.max == std.posix.RLIM.INFINITY) {
        lim.cur = 1024 * 128;
        std.posix.setrlimit(.NOFILE, lim) catch unreachable;
        return;
    }

    lim.cur = lim.max;
    std.posix.setrlimit(.NOFILE, lim) catch unreachable;
}
