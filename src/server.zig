const std = @import("std");
const Program = @import("program.zig").Program;
const BranchTemplate = @import("branch_template.zig").BranchTemplate;
const signals = @import("signals.zig");
const config = @import("config.zig");
const successCallback = @import("root").successCallback;
const errno = std.os.linux.errno;

var efd: std.posix.fd_t = undefined;
var fd: std.posix.fd_t = undefined;

pub const EventId = enum(u32) {
    server,
    client,
};

pub const Task = struct {
    branch_template: BranchTemplate,
    program: Program,
};

pub fn init() !void {
    efd = blk: {
        const rc = std.os.linux.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
        switch (errno(rc)) {
            .SUCCESS => break :blk @intCast(rc),
            else => return error.EpollCreateFailed,
        }
    };
    errdefer _ = std.os.linux.close(efd);

    fd = blk: {
        const rc = std.os.linux.socket(std.posix.AF.INET6, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK, 0);
        switch (errno(rc)) {
            .SUCCESS => break :blk @intCast(rc),
            else => return error.SocketFailed,
        }
    };
    errdefer _ = std.os.linux.close(fd);

    _ = std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&@as(i32, 1))) catch {};

    const addr = std.posix.sockaddr.in6{
        .port = std.mem.nativeToBig(u16, 6502),
        .addr = [_]u8{0} ** 16,
        .flowinfo = 0,
        .scope_id = 0,
    };

    {
        const rc = std.os.linux.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in6));
        switch (errno(rc)) {
            .SUCCESS => {},
            else => return error.BindFailed,
        }
    }

    {
        const rc = std.os.linux.listen(fd, std.math.maxInt(i32));
        switch (errno(rc)) {
            .SUCCESS => {},
            else => return error.ListenFailed,
        }
    }

    var ep = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
        .data = .{ .u64 = 0 },
    };
    _ = std.os.linux.epoll_ctl(efd, std.os.linux.EPOLL.CTL_ADD, fd, &ep);
}

pub fn deinit() void {
    _ = std.os.linux.close(fd);
    _ = std.os.linux.close(efd);
}

pub const Client = struct {
    fd: std.posix.fd_t = -1,

    rbuf: [256]u8 = undefined,
    rbuf_n: usize = 0,

    task: ?Task = null,

    pub fn deinit(self: *Client) void {
        if (self.task) |task| pushTask(task);
        self.task = null;
        _ = std.os.linux.close(self.fd);
        self.fd = -1;
        self.rbuf_n = 0;
    }

    pub fn onEvent(self: *Client) void {
        if (self.fd < 0) return;

        while (true) {
            if (self.rbuf_n == self.rbuf.len) {
                self.deinit();
                return;
            }

            const nbr = std.posix.read(self.fd, self.rbuf[self.rbuf_n..]) catch |err| switch (err) {
                error.WouldBlock => break,
                else => {
                    self.deinit();
                    return;
                },
            };
            if (nbr == 0) {
                self.deinit();
                return;
            }

            self.rbuf_n += nbr;
        }

        while (true) {
            if (self.rbuf_n == 0) return;

            // Hacky as hell, but whatever, it works
            const status = self.rbuf[0];
            switch (status) {
                0 => {
                    self.task = null;
                    self.rbuf_n = 0;
                    if (popTask()) |task| {
                        self.sendTask(task) catch {
                            pushTask(task);
                            self.deinit();
                            return;
                        };
                    }
                },
                1 => {
                    const Msg = extern struct {
                        id: u8,
                        size: u8,
                        bytes: [config.max_length]u8,
                        mask: [config.max_length]u8,
                        worst_cycles: u32,
                        total_cycles: u32,
                    };
                    if (self.rbuf_n < @sizeOf(Msg)) return;

                    var msg: Msg = undefined;
                    @memcpy(std.mem.asBytes(&msg), self.rbuf[0..@sizeOf(Msg)]);

                    var program = Program{ .size = msg.size, .bytes = msg.bytes, .mask = undefined };
                    for (msg.mask, 0..) |m, i| {
                        program.mask[i] = @intCast(m);
                    }

                    successCallback(&program, msg.worst_cycles, msg.total_cycles);

                    std.mem.copyForwards(u8, self.rbuf[0 .. self.rbuf_n - @sizeOf(Msg)], self.rbuf[@sizeOf(Msg)..self.rbuf_n]);
                    self.rbuf_n -= @sizeOf(Msg);
                    continue;
                },
                else => {
                    // borked
                    self.deinit();
                    return;
                },
            }
        }
    }

    pub fn sendTask(self: *Client, task: Task) !void {
        self.task = task;
        const rc = std.os.linux.write(self.fd, std.mem.asBytes(&self.task.?), std.mem.asBytes(&self.task.?).len);
        switch (errno(rc)) {
            .SUCCESS => {},
            else => return error.SendTaskFailed,
        }
    }
};

var branch_template: BranchTemplate = undefined;
var task_programs: []Program = undefined;
var tasks_n: usize = undefined;

fn popTask() ?Task {
    if (tasks_n == 0) return null;
    tasks_n -= 1;

    const task = Task{
        .branch_template = branch_template,
        .program = task_programs[tasks_n],
    };

    // std.debug.print("Pop task:\n", .{});
    // task.program.print() catch {};

    return task;
}

fn pushTask(task: Task) void {
    task_programs[tasks_n] = task.program;
    tasks_n += 1;
}

var clients: []Client = &[_]Client{};

pub fn serveCandidates(btemplate: BranchTemplate, new_candidates: []const Program) !void {
    if (new_candidates.len == 0) return;

    branch_template = btemplate;

    task_programs = try std.heap.page_allocator.alloc(Program, new_candidates.len);
    defer std.heap.page_allocator.free(task_programs);

    for (new_candidates, 0..) |cnd, i| {
        task_programs[new_candidates.len - i - 1] = cnd;
    }
    tasks_n = new_candidates.len;

    for (clients) |*client| {
        if (client.fd == -1) continue;
        if (popTask()) |task| {
            client.sendTask(task) catch {
                client.deinit();
            };
        }
    }

    while (!signals.flag) {
        var eventdata: [8]std.os.linux.epoll_event = undefined;
        const nev = std.os.linux.epoll_pwait(efd, &eventdata, eventdata.len, -1, null);
        if (nev > eventdata.len) return;

        const events = eventdata[0..nev];
        for (events) |event| {
            const evid = event.data.u64;
            switch (evid) {
                0 => onServerEvent(),
                else => {
                    const client = &clients[evid - 1];
                    client.onEvent();
                },
            }
        }

        // All tasks done? Return.
        if (tasks_n == 0) {
            var any_client_has_task: bool = false;
            for (clients) |client| {
                if (client.fd <= 0) continue;
                if (client.task == null) continue;
                any_client_has_task = true;
                break;
            }
            if (any_client_has_task == false) {
                return;
            }
        }
    }
}

fn newClient(cfd: std.posix.fd_t) !*Client {
    for (clients, 0..) |*cli, i| {
        if (cli.fd == -1) {
            cli.* = .{
                .fd = cfd,
                .task = null,
            };

            var ep = std.os.linux.epoll_event{
                .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
                .data = .{ .u64 = 1 + i },
            };
            _ = std.os.linux.epoll_ctl(efd, std.os.linux.EPOLL.CTL_ADD, cli.fd, &ep);
            return cli;
        }
    }

    clients = try std.heap.page_allocator.realloc(clients, clients.len + 1);
    const client = &clients[clients.len - 1];
    client.* = .{
        .fd = cfd,
        .task = null,
    };

    var ep = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
        .data = .{ .u64 = 1 + (clients.len - 1) },
    };
    _ = std.os.linux.epoll_ctl(efd, std.os.linux.EPOLL.CTL_ADD, client.fd, &ep);

    return client;
}

fn onServerEvent() void {
    while (true) {
        const rc = std.os.linux.accept4(fd, null, null, std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC);
        const nfd: i32 = blk: {
            switch (errno(rc)) {
                .SUCCESS => break :blk @intCast(rc),
                .AGAIN => return,
                .CONNABORTED, .PROTO => continue,
                else => unreachable,
            }
        };

        const client = newClient(nfd) catch {
            _ = std.os.linux.close(nfd);
            continue;
        };

        if (popTask()) |task| {
            client.sendTask(task) catch {
                client.deinit();
            };
        }
    }
}
