const std = @import("std");
const config = @import("config.zig");

pub const BranchTemplate = struct {
    size: u8,
    branches_n: u8 = config.min_branches,
    branches: [config.max_branches][2]u8 = undefined,

    pub const Info = struct {
        is_branch: bool = false,
        is_argument: bool = false,
        is_target: bool = false,
        target: u8 = 0,
    };

    pub fn init(size: u8) BranchTemplate {
        return BranchTemplate{ .size = size };
    }

    pub fn next(self: *BranchTemplate) bool {
        if (config.max_branches == 0) return false;

        for (0..self.branches_n) |sbi| {
            const bi: u8 = @intCast(self.branches_n - sbi - 1);
            if (self.incrementTarget(bi)) return true;
            self.setFirstValidTarget(bi);
        }

        for (0..self.branches_n) |sbi| {
            const bi: u8 = @intCast(self.branches_n - sbi - 1);
            if (self.incrementPosition(bi)) {
                for (0..self.branches_n) |i| {
                    self.setFirstValidTarget(@intCast(i));
                }
                return true;
            }
        }

        if (self.branches_n == config.max_branches) return false;
        if ((self.branches_n + 1) * 2 + 1 > self.size) return false;
        self.branches_n += 1;

        for (0..self.branches_n) |i| {
            self.branches[i][0] = @intCast(i * 2);
            self.branches[i][1] = 0;
        }

        for (0..self.branches_n) |i| {
            self.setFirstValidTarget(@intCast(i));
        }

        return true;
    }

    fn setFirstValidTarget(self: *BranchTemplate, branch: u8) void {
        var pb = [_]u8{0} ** (config.max_length + 1);
        for (self.branches[0..self.branches_n]) |br| {
            pb[br[0] + 1] = 1;
        }

        for (0..self.size + 1) |i| {
            if (config.branch_forward_only and i < self.branches[branch][0]) continue;

            if (pb[i] == 0 and i != self.branches[branch][0] and i != self.branches[branch][0] + 2) {
                self.branches[branch][1] = @intCast(i);
                return;
            }
        }
    }

    fn incrementTarget(self: *BranchTemplate, branch: u8) bool {
        if (self.branches[branch][1] > self.size) return false;

        var pb = [_]u8{0} ** (config.max_length + 1);
        for (self.branches[0..self.branches_n]) |br| {
            pb[br[0] + 1] = 1;
        }

        for (self.branches[branch][1] + 1..self.size + 1) |i| {
            if (pb[i] == 0 and i != self.branches[branch][0] and i != self.branches[branch][0] + 2) {
                self.branches[branch][1] = @intCast(i);
                return true;
            }
        }

        return false;
    }

    fn incrementPosition(self: *BranchTemplate, branch: u8) bool {
        const rbranches = self.branches_n - branch;
        if (self.size < self.branches[branch][0] + 1 + rbranches * 2) return false;
        if (config.branch_forward_only and self.branches[branch][0] == self.size - 3) return false;

        const npos = self.branches[branch][0] + 1;
        for (branch..self.branches_n, 0..) |bi, i| {
            self.branches[bi][0] = @intCast(npos + i * 2);
        }

        return true;
    }

    pub fn info(self: BranchTemplate) [config.max_length]Info {
        var infos = [_]Info{.{}} ** config.max_length;

        for (self.branches[0..self.branches_n]) |br| {
            infos[br[0]].is_branch = true;
            infos[br[0] + 1].is_argument = true;
            infos[br[0]].target = @as(u8, @intCast(br[1]));
            if (br[1] < self.size) {
                infos[br[1]].is_target = true;
            }
        }
        return infos;
    }

    pub fn debugPrint(self: BranchTemplate) void {
        var buf: [256]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        var w = &writer;

        w.writeAll("┌ ") catch unreachable;
        for (0..self.size) |i| {
            w.print("{:<3}", .{i}) catch unreachable;
        }
        w.writeAll("\n") catch unreachable;

        var pbuf = [_]u8{0} ** config.max_length;
        for (self.branches[0..self.branches_n], 0..) |br, bri| {
            pbuf[br[0] + 0] = @intCast(bri + 1);
            pbuf[br[0] + 1] = @intCast(0x80 + br[1]);
        }

        w.writeAll("└ ") catch unreachable;
        for (0..self.size) |i| {
            if (pbuf[i] == 0) {
                w.writeAll("   ") catch unreachable;
            } else if (pbuf[i] < 0x80) {
                w.print("b{:<2}", .{pbuf[i] - 1}) catch unreachable;
            } else {
                w.print("{:<3}", .{pbuf[i] - 0x80}) catch unreachable;
            }
        }
        w.writeAll("\n") catch unreachable;
        w.flush() catch unreachable;

        std.debug.print("{s}", .{buf[0..writer.end]});
    }
};
