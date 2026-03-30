const std = @import("std");

pub const Storage = struct {
    allocator: std.mem.Allocator,
    home_dir: []u8,
    root_dir: []u8,
    logs_dir: []u8,
    profiles_dir: []u8,
    snapshots_dir: []u8,
    daemon_file: []u8,
    state_file: []u8,
    token_file: []u8,

    pub fn init(allocator: std.mem.Allocator) !Storage {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, ".");
        errdefer allocator.free(home);

        const root = try std.fs.path.join(allocator, &.{ home, ".buncore" });
        errdefer allocator.free(root);
        const logs = try std.fs.path.join(allocator, &.{ root, "logs" });
        errdefer allocator.free(logs);
        const profiles = try std.fs.path.join(allocator, &.{ root, "profiles" });
        errdefer allocator.free(profiles);
        const snapshots = try std.fs.path.join(allocator, &.{ root, "snapshots" });
        errdefer allocator.free(snapshots);
        const daemon_file = try std.fs.path.join(allocator, &.{ root, "daemon.json" });
        errdefer allocator.free(daemon_file);
        const state_file = try std.fs.path.join(allocator, &.{ root, "state.json" });
        errdefer allocator.free(state_file);
        const token_file = try std.fs.path.join(allocator, &.{ root, "token" });
        errdefer allocator.free(token_file);

        return .{
            .allocator = allocator,
            .home_dir = home,
            .root_dir = root,
            .logs_dir = logs,
            .profiles_dir = profiles,
            .snapshots_dir = snapshots,
            .daemon_file = daemon_file,
            .state_file = state_file,
            .token_file = token_file,
        };
    }

    pub fn ensure(self: Storage) !void {
        try std.fs.cwd().makePath(self.root_dir);
        try std.fs.cwd().makePath(self.logs_dir);
        try std.fs.cwd().makePath(self.profiles_dir);
        try std.fs.cwd().makePath(self.snapshots_dir);
    }

    pub fn deinit(self: *Storage) void {
        self.allocator.free(self.home_dir);
        self.allocator.free(self.root_dir);
        self.allocator.free(self.logs_dir);
        self.allocator.free(self.profiles_dir);
        self.allocator.free(self.snapshots_dir);
        self.allocator.free(self.daemon_file);
        self.allocator.free(self.state_file);
        self.allocator.free(self.token_file);
    }

    pub fn readDaemonInfo(self: Storage, allocator: std.mem.Allocator) !DaemonInfo {
        const content = try std.fs.cwd().readFileAlloc(allocator, self.daemon_file, 64 * 1024);
        defer allocator.free(content);
        const parsed = try std.json.parseFromSlice(DaemonInfo, allocator, content, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        return parsed.value;
    }

    pub fn writeDaemonInfo(self: Storage, info: DaemonInfo) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        try std.json.stringify(info, .{ .whitespace = .indent_2 }, buffer.writer());
        try std.fs.cwd().writeFile(.{ .sub_path = self.daemon_file, .data = buffer.items });
    }

    pub fn writeToken(self: Storage, token: []const u8) !void {
        try std.fs.cwd().writeFile(.{ .sub_path = self.token_file, .data = token });
    }

    pub fn readToken(self: Storage, allocator: std.mem.Allocator) ![]u8 {
        return std.fs.cwd().readFileAlloc(allocator, self.token_file, 4096);
    }

    pub fn processLogPath(self: Storage, allocator: std.mem.Allocator, name: []const u8, process_id: u32, stream_name: []const u8) ![]u8 {
        const safe_name = try sanitizeName(allocator, name);
        defer allocator.free(safe_name);
        return std.fmt.allocPrint(allocator, "{s}/{s}-{d}.{s}.log", .{ self.logs_dir, safe_name, process_id, stream_name });
    }

    pub fn profilePath(self: Storage, allocator: std.mem.Allocator, name: []const u8, process_id: u32, timestamp_ms: i64) ![]u8 {
        const safe_name = try sanitizeName(allocator, name);
        defer allocator.free(safe_name);
        return std.fmt.allocPrint(allocator, "{s}/{s}-{d}-{d}.cpuprofile.json", .{ self.profiles_dir, safe_name, process_id, timestamp_ms });
    }

    pub fn snapshotPath(self: Storage, allocator: std.mem.Allocator, name: []const u8, process_id: u32, timestamp_ms: i64, suffix: []const u8) ![]u8 {
        const safe_name = try sanitizeName(allocator, name);
        defer allocator.free(safe_name);
        return std.fmt.allocPrint(allocator, "{s}/{s}-{d}-{d}.{s}", .{ self.snapshots_dir, safe_name, process_id, timestamp_ms, suffix });
    }
};

pub const DaemonInfo = struct {
    host: []const u8,
    port: u16,
    pid: i32,
    dashboard_port: u16,
    token_preview: []const u8,
    started_at: i64,
};

pub fn sanitizeName(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') {
            try out.append(c);
        } else {
            try out.append('_');
        }
    }
    if (out.items.len == 0) try out.appendSlice("process");
    return out.toOwnedSlice();
}

pub fn randomToken(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [24]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&bytes)});
}

pub fn timestampMs() i64 {
    return std.time.milliTimestamp();
}

pub fn projectRootFromExe(allocator: std.mem.Allocator) ![]u8 {
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);
    const exe_dir = std.fs.path.dirname(exe_path) orelse return error.FileNotFound;
    const zig_out = std.fs.path.dirname(exe_dir) orelse return error.FileNotFound;
    const root = std.fs.path.dirname(zig_out) orelse return error.FileNotFound;
    return allocator.dupe(u8, root);
}

pub fn agentPreloadPath(allocator: std.mem.Allocator) ![]u8 {
    const root = try projectRootFromExe(allocator);
    defer allocator.free(root);
    return std.fs.path.join(allocator, &.{ root, "agent", "preload.ts" });
}

pub fn agentConfigLoaderPath(allocator: std.mem.Allocator) ![]u8 {
    const root = try projectRootFromExe(allocator);
    defer allocator.free(root);
    return std.fs.path.join(allocator, &.{ root, "agent", "config-loader.ts" });
}

pub fn dashboardIndexPath(allocator: std.mem.Allocator) ![]u8 {
    const root = try projectRootFromExe(allocator);
    defer allocator.free(root);
    return std.fs.path.join(allocator, &.{ root, "web", "dist", "index.html" });
}
