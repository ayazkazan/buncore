const std = @import("std");
const builtin = @import("builtin");
const storage_mod = @import("storage");
const protocol = @import("protocol");
const watch_mod = @import("watch.zig");

const Allocator = std.mem.Allocator;

const Status = enum {
    launching,
    online,
    stopping,
    stopped,
    errored,

    fn label(self: Status) []const u8 {
        return switch (self) {
            .launching => "launching",
            .online => "online",
            .stopping => "stopping",
            .stopped => "stopped",
            .errored => "errored",
        };
    }
};

const SummaryMetrics = struct {
    rss: ?u64 = null,
    heapUsed: ?u64 = null,
    heapTotal: ?u64 = null,
    external: ?u64 = null,
    arrayBuffers: ?u64 = null,
    cpuPercent: ?f64 = null,
    cpuUser: ?f64 = null,
    cpuSystem: ?f64 = null,
    gcFreed: ?u64 = null,
    runtimeLagMs: ?f64 = null,
    timestamp: ?i64 = null,
};

const JscHeapStats = struct {
    heapSize: ?u64 = null,
    heapCapacity: ?u64 = null,
    extraMemorySize: ?u64 = null,
    objectCount: ?u64 = null,
    protectedObjectCount: ?u64 = null,
    globalObjectCount: ?u64 = null,
    protectedGlobalObjectCount: ?u64 = null,
};

const JscMemoryUsage = struct {
    current: ?u64 = null,
    peak: ?u64 = null,
    currentCommit: ?u64 = null,
    peakCommit: ?u64 = null,
    pageFaults: ?u64 = null,
};

const ResourceUsage = struct {
    userCPUTime: ?u64 = null,
    systemCPUTime: ?u64 = null,
    maxRSS: ?u64 = null,
    minorPageFault: ?u64 = null,
    majorPageFault: ?u64 = null,
    fsRead: ?u64 = null,
    fsWrite: ?u64 = null,
    voluntaryContextSwitches: ?u64 = null,
    involuntaryContextSwitches: ?u64 = null,
};

const DetailMetrics = struct {
    jscHeapStats: ?JscHeapStats = null,
    jscMemoryUsage: ?JscMemoryUsage = null,
    resourceUsage: ?ResourceUsage = null,
};

const HistoryPoint = struct {
    timestamp: i64,
    rss: ?u64,
    heapUsed: ?u64,
    heapTotal: ?u64,
};

const OwnedWatchSpec = struct {
    process_id: u32,
    cwd: []u8,
    script: []u8,
    watch_path: ?[]u8,
    ignore_watch: [][]u8,

    fn deinit(self: *OwnedWatchSpec, allocator: Allocator) void {
        allocator.free(self.cwd);
        allocator.free(self.script);
        if (self.watch_path) |watch_path| allocator.free(watch_path);
        for (self.ignore_watch) |item| allocator.free(item);
        allocator.free(self.ignore_watch);
    }

    fn spec(self: OwnedWatchSpec) watch_mod.Spec {
        return .{
            .process_id = self.process_id,
            .cwd = self.cwd,
            .script = self.script,
            .watch_path = self.watch_path,
            .ignore_watch = self.ignore_watch,
        };
    }
};

const ProcessConfig = struct {
    name: []u8,
    script: []u8,
    args: [][]u8,
    cwd: []u8,
    interpreter: ?[]u8,
    env_pairs: [][]u8,
    instances: u32,
    watch: bool,
    watch_path: ?[]u8,
    ignore_watch: [][]u8,
    max_memory_restart: u64,
    autorestart: bool,
    max_restarts: u32,
    min_uptime: i64,
    restart_delay: u64,
    out_file: ?[]u8,
    error_file: ?[]u8,
    exec_mode: ?[]u8,
    exp_backoff_restart_delay: u64,
    stop_exit_codes: []i32,
    cron_restart: ?[]u8,
    max_log_size: u64,
    kill_timeout: u64,
};

fn deinitProcessConfig(allocator: Allocator, config: *ProcessConfig) void {
    allocator.free(config.name);
    allocator.free(config.script);
    allocator.free(config.cwd);
    if (config.interpreter) |interpreter| allocator.free(interpreter);
    for (config.args) |arg| allocator.free(arg);
    allocator.free(config.args);
    for (config.env_pairs) |pair| allocator.free(pair);
    allocator.free(config.env_pairs);
    if (config.watch_path) |watch_path| allocator.free(watch_path);
    for (config.ignore_watch) |item| allocator.free(item);
    allocator.free(config.ignore_watch);
    if (config.out_file) |out_file| allocator.free(out_file);
    if (config.error_file) |error_file| allocator.free(error_file);
    if (config.exec_mode) |exec_mode| allocator.free(exec_mode);
    allocator.free(config.stop_exit_codes);
    if (config.cron_restart) |cron| allocator.free(cron);
}

const ManagedProcess = struct {
    allocator: Allocator,
    id: u32,
    config: ProcessConfig,
    status: Status = .stopped,
    pid: ?i32 = null,
    created_at: i64,
    started_at: ?i64 = null,
    stopped_at: ?i64 = null,
    restarts: u32 = 0,
    unstable_restarts: u32 = 0,
    last_exit_code: ?i32 = null,
    runtime_kind: []const u8 = "generic",
    child: ?*std.process.Child = null,
    stop_requested: bool = false,
    log_path: []u8,
    out_log_path: ?[]u8 = null,
    err_log_path: ?[]u8 = null,
    summary: SummaryMetrics = .{},
    details: DetailMetrics = .{},
    history: std.ArrayListUnmanaged(HistoryPoint) = .{},
    agent: ?*AgentConnection = null,
    watch_ready: bool = false,
    watch_signature: u64 = 0,
    last_cpu_total_ticks: ?u64 = null,
    last_cpu_sample_ms: ?i64 = null,
    current_backoff_delay: u64 = 0,
    last_cron_minute: ?i64 = null,

    fn deinit(self: *ManagedProcess) void {
        deinitProcessConfig(self.allocator, &self.config);
        self.allocator.free(self.log_path);
        if (self.out_log_path) |p| self.allocator.free(p);
        if (self.err_log_path) |p| self.allocator.free(p);
        self.history.deinit(self.allocator);
        if (self.child) |child| self.allocator.destroy(child);
        self.allocator.destroy(self);
    }
};

const AgentHello = struct {
    authToken: ?[]const u8 = null,
    action: []const u8,
    payload: struct {
        processId: u32,
        processName: []const u8,
        pid: i32,
        runtime: []const u8,
    },
};

const TelemetryEnvelope = struct {
    authToken: ?[]const u8 = null,
    action: []const u8,
    payload: struct {
        processId: u32,
        pid: i32,
        runtime: []const u8,
        summary: SummaryMetrics,
        details: ?DetailMetrics = null,
    },
};

const AgentResultEnvelope = struct {
    authToken: ?[]const u8 = null,
    action: []const u8,
    requestId: []const u8,
    payload: std.json.Value = .null,
    @"error": ?[]const u8 = null,
};

const AgentConnection = struct {
    allocator: Allocator,
    process_id: u32,
    stream: std.net.Stream,
    write_mutex: std.Thread.Mutex = .{},
    wait_mutex: std.Thread.Mutex = .{},
    wait_cond: std.Thread.Condition = .{},
    waiting: bool = false,
    waiting_request_id: ?[]u8 = null,
    last_response_json: ?[]u8 = null,
    last_error: ?[]u8 = null,
    closed: bool = false,

    fn sendCommandAndWait(self: *AgentConnection, command_json: []const u8, request_id: []const u8) ![]u8 {
        self.wait_mutex.lock();
        defer self.wait_mutex.unlock();

        self.waiting = true;
        if (self.waiting_request_id) |prev| self.allocator.free(prev);
        self.waiting_request_id = try self.allocator.dupe(u8, request_id);
        if (self.last_response_json) |prev| self.allocator.free(prev);
        self.last_response_json = null;
        if (self.last_error) |prev| self.allocator.free(prev);
        self.last_error = null;

        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        try self.stream.writer().print("{{\"action\":\"command\",\"payload\":{{\"command\":{s}}}}}\n", .{command_json});

        while (self.waiting and !self.closed) {
            self.wait_cond.timedWait(&self.wait_mutex, 30 * std.time.ns_per_s) catch return error.Timeout;
        }

        if (self.closed) return error.ConnectionResetByPeer;
        if (self.last_error) |_| return error.CommandFailed;
        if (self.last_response_json) |payload| return try self.allocator.dupe(u8, payload);
        return error.Unexpected;
    }

    fn sendCommand(self: *AgentConnection, command_json: []const u8) !void {
        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        try self.stream.writer().print("{{\"action\":\"command\",\"payload\":{{\"command\":{s}}}}}\n", .{command_json});
    }

    fn acceptResult(self: *AgentConnection, request_id: []const u8, payload_json: []const u8, error_message: ?[]const u8) void {
        self.wait_mutex.lock();
        defer self.wait_mutex.unlock();
        if (!self.waiting) return;
        if (self.waiting_request_id) |expected| {
            if (!std.mem.eql(u8, expected, request_id)) return;
        }
        if (self.last_response_json) |prev| self.allocator.free(prev);
        self.last_response_json = self.allocator.dupe(u8, payload_json) catch null;
        if (self.last_error) |prev| self.allocator.free(prev);
        self.last_error = if (error_message) |msg| self.allocator.dupe(u8, msg) catch null else null;
        self.waiting = false;
        self.wait_cond.signal();
    }
};

const DaemonState = struct {
    allocator: Allocator,
    storage: storage_mod.Storage,
    token: []u8,
    host: []const u8,
    port: u16,
    dashboard_port: u16,
    processes: std.ArrayList(*ManagedProcess),
    next_process_id: u32 = 0,
    mutex: std.Thread.Mutex = .{},
    running: bool = true,

    fn deinit(self: *DaemonState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.processes.items) |process| process.deinit();
        self.processes.deinit();
        self.allocator.free(self.token);
        self.storage.deinit();
    }

    fn findProcess(self: *DaemonState, target: []const u8) ?*ManagedProcess {
        for (self.processes.items) |process| {
            if (std.mem.eql(u8, process.config.name, target)) return process;
            if (std.fmt.parseInt(u32, target, 10)) |id| {
                if (process.id == id) return process;
            } else |_| {}
        }
        return null;
    }

    fn findProcessById(self: *DaemonState, process_id: u32) ?*ManagedProcess {
        for (self.processes.items) |process| {
            if (process.id == process_id) return process;
        }
        return null;
    }

    fn findProcessByNameExact(self: *DaemonState, name: []const u8) ?*ManagedProcess {
        for (self.processes.items) |process| {
            if (std.mem.eql(u8, process.config.name, name)) return process;
        }
        return null;
    }
};

fn collectTargetProcessIds(allocator: Allocator, state: *DaemonState, target: []const u8) ![]u32 {
    var ids = std.ArrayList(u32).init(allocator);
    errdefer ids.deinit();

    if (std.mem.eql(u8, target, "all")) {
        for (state.processes.items) |process| try ids.append(process.id);
        return ids.toOwnedSlice();
    }

    if (std.fmt.parseInt(u32, target, 10)) |id| {
        if (state.findProcessById(id) != null) try ids.append(id);
        return ids.toOwnedSlice();
    } else |_| {}

    for (state.processes.items) |process| {
        if (std.mem.eql(u8, process.config.name, target) or std.mem.startsWith(u8, process.config.name, target)) {
            if (std.mem.eql(u8, process.config.name, target) or
                (process.config.name.len > target.len and process.config.name[target.len] == '-'))
            {
                try ids.append(process.id);
            }
        }
    }
    return ids.toOwnedSlice();
}

fn duplicateStrings(allocator: Allocator, items: [][]u8) ![][]u8 {
    const out = try allocator.alloc([]u8, items.len);
    for (items, 0..) |item, idx| out[idx] = try allocator.dupe(u8, item);
    return out;
}

fn cloneConfig(allocator: Allocator, config: ProcessConfig) !ProcessConfig {
    return .{
        .name = try allocator.dupe(u8, config.name),
        .script = try allocator.dupe(u8, config.script),
        .args = try duplicateStrings(allocator, config.args),
        .cwd = try allocator.dupe(u8, config.cwd),
        .interpreter = if (config.interpreter) |value| try allocator.dupe(u8, value) else null,
        .env_pairs = try duplicateStrings(allocator, config.env_pairs),
        .instances = config.instances,
        .watch = config.watch,
        .watch_path = if (config.watch_path) |value| try allocator.dupe(u8, value) else null,
        .ignore_watch = try duplicateStrings(allocator, config.ignore_watch),
        .max_memory_restart = config.max_memory_restart,
        .autorestart = config.autorestart,
        .max_restarts = config.max_restarts,
        .min_uptime = config.min_uptime,
        .restart_delay = config.restart_delay,
        .out_file = if (config.out_file) |value| try allocator.dupe(u8, value) else null,
        .error_file = if (config.error_file) |value| try allocator.dupe(u8, value) else null,
        .exec_mode = if (config.exec_mode) |value| try allocator.dupe(u8, value) else null,
        .exp_backoff_restart_delay = config.exp_backoff_restart_delay,
        .stop_exit_codes = blk: {
            const out = try allocator.alloc(i32, config.stop_exit_codes.len);
            @memcpy(out, config.stop_exit_codes);
            break :blk out;
        },
        .cron_restart = if (config.cron_restart) |value| try allocator.dupe(u8, value) else null,
        .max_log_size = config.max_log_size,
        .kill_timeout = config.kill_timeout,
    };
}

fn cloneConfigWithName(allocator: Allocator, config: ProcessConfig, name: []const u8) !ProcessConfig {
    var out = try cloneConfig(allocator, config);
    allocator.free(out.name);
    out.name = try allocator.dupe(u8, name);
    return out;
}

fn openListen(port: u16) !std.net.Server {
    const address = try std.net.Address.parseIp("127.0.0.1", port);
    return std.net.Address.listen(address, .{ .reuse_address = true });
}

fn choosePort(base: u16) !u16 {
    var port = base;
    while (port < base + 32) : (port += 1) {
        var server = openListen(port) catch continue;
        server.deinit();
        return port;
    }
    return error.AddressInUse;
}

fn appendLogLine(path: []const u8, process_name: []const u8, stream_name: []const u8, line: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = false, .read = true });
    defer file.close();
    try file.seekFromEnd(0);
    try file.writer().print("[{d}] {s} {s}: {s}\n", .{ storage_mod.timestampMs(), process_name, stream_name, line });
}

fn streamPumpThread(state: *DaemonState, process_id: u32, process_name: []const u8, stream_name: []const u8, file: std.fs.File, log_path: []const u8, separate_log_path: ?[]const u8) void {
    _ = state;
    var local_file = file;

    var buffer: [4096]u8 = undefined;
    var pending = std.ArrayList(u8).init(std.heap.page_allocator);
    defer pending.deinit();

    while (true) {
        const read_len = local_file.read(&buffer) catch break;
        if (read_len == 0) break;
        pending.appendSlice(buffer[0..read_len]) catch break;
        while (std.mem.indexOfScalar(u8, pending.items, '\n')) |idx| {
            const line = pending.items[0..idx];
            appendLogLine(log_path, process_name, stream_name, line) catch {};
            if (separate_log_path) |sep_path| {
                appendLogLine(sep_path, process_name, stream_name, line) catch {};
            }
            _ = process_id;
            const rest = pending.items[idx + 1 ..];
            std.mem.copyForwards(u8, pending.items[0..rest.len], rest);
            pending.shrinkRetainingCapacity(rest.len);
        }
    }
    if (pending.items.len > 0) {
        appendLogLine(log_path, process_name, stream_name, pending.items) catch {};
        if (separate_log_path) |sep_path| {
            appendLogLine(sep_path, process_name, stream_name, pending.items) catch {};
        }
    }
}

fn termToExitCode(term: std.process.Child.Term) i32 {
    return switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => |sig| -@as(i32, @intCast(sig)),
        else => -1,
    };
}

fn processWaitThread(state: *DaemonState, process_id: u32, child: *std.process.Child) void {
    const term = child.wait() catch {
        state.mutex.lock();
        defer state.mutex.unlock();
        if (state.findProcessById(process_id)) |process| {
            process.status = .errored;
            process.child = null;
            process.pid = null;
        }
        return;
    };

    var should_restart = false;
    var restart_delay_ms: u64 = 0;
    state.mutex.lock();
    if (state.findProcessById(process_id)) |process| {
        const exit_code = termToExitCode(term);
        process.last_exit_code = exit_code;
        process.stopped_at = storage_mod.timestampMs();
        const uptime = if (process.started_at) |started_at| process.stopped_at.? - started_at else 0;
        process.pid = null;
        process.child = null;
        process.agent = null;

        // Check if exit code is in stop_exit_codes list (skip restart for these)
        var skip_for_exit_code = false;
        for (process.config.stop_exit_codes) |code| {
            if (code == exit_code) {
                skip_for_exit_code = true;
                break;
            }
        }

        if (!process.stop_requested and !skip_for_exit_code and process.config.autorestart and process.restarts < process.config.max_restarts) {
            if (uptime < process.config.min_uptime) process.unstable_restarts += 1;
            process.restarts += 1;
            process.status = .launching;
            should_restart = true;

            // Exponential backoff restart delay
            if (process.config.exp_backoff_restart_delay > 0) {
                if (process.current_backoff_delay == 0) {
                    process.current_backoff_delay = process.config.exp_backoff_restart_delay;
                } else {
                    process.current_backoff_delay = @min(process.current_backoff_delay * 2, 15000);
                }
                restart_delay_ms = process.current_backoff_delay;
            } else {
                restart_delay_ms = process.config.restart_delay;
            }

            // Reset backoff if process ran long enough
            if (uptime >= process.config.min_uptime) {
                process.current_backoff_delay = 0;
            }
        } else if (process.stop_requested) {
            process.status = .stopped;
            process.stop_requested = false;
        } else {
            process.status = .errored;
        }
    }
    state.mutex.unlock();

    if (should_restart) {
        std.time.sleep(restart_delay_ms * std.time.ns_per_ms);
        state.mutex.lock();
        if (state.findProcessById(process_id)) |process| {
            if (process.status == .launching) {
                relaunchExistingProcess(state, process) catch {
                    process.status = .errored;
                };
            }
        }
        state.mutex.unlock();
    }
    state.allocator.destroy(child);
}

fn terminateProcess(process: *ManagedProcess, force: bool) void {
    if (builtin.os.tag == .windows) {
        if (process.child) |child| {
            _ = child.kill() catch {};
        }
        process.pid = null;
        return;
    }

    if (process.pid) |pid| {
        std.posix.kill(pid, if (force) std.posix.SIG.KILL else std.posix.SIG.TERM) catch {};
    }
}

fn rotateLogIfNeeded(path: []const u8, max_size: u64) void {
    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();
    const stat = file.stat() catch return;
    if (stat.size < max_size) return;

    // Rotate: .2 -> .3, .1 -> .2, current -> .1
    var buf3: [4096]u8 = undefined;
    var buf2: [4096]u8 = undefined;
    var buf1: [4096]u8 = undefined;
    const path3 = std.fmt.bufPrint(&buf3, "{s}.3", .{path}) catch return;
    const path2 = std.fmt.bufPrint(&buf2, "{s}.2", .{path}) catch return;
    const path1 = std.fmt.bufPrint(&buf1, "{s}.1", .{path}) catch return;
    std.fs.cwd().deleteFile(path3) catch {};
    std.fs.cwd().rename(path2, path3) catch {};
    std.fs.cwd().rename(path1, path2) catch {};
    std.fs.cwd().rename(path, path1) catch {};
    // Create fresh empty log
    const new_file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return;
    new_file.close();
}

fn matchesCronMinute(cron_expr: []const u8, now_ms: i64) bool {
    // Minimal cron parser: "minute hour dom month dow" (5 fields)
    // Supports: * (any), specific numbers, no ranges/lists for simplicity
    const epoch_sec = @divTrunc(now_ms, 1000);
    const day_sec = @mod(epoch_sec, 86400);
    const current_hour: u8 = @intCast(@divTrunc(day_sec, 3600));
    const current_minute: u8 = @intCast(@divTrunc(@mod(day_sec, 3600), 60));

    var it = std.mem.tokenizeAny(u8, cron_expr, " \t");
    const minute_field = it.next() orelse return false;
    const hour_field = it.next() orelse return false;
    // We only check minute and hour for simplicity (dom/month/dow = *)

    if (!cronFieldMatches(minute_field, current_minute)) return false;
    if (!cronFieldMatches(hour_field, current_hour)) return false;
    return true;
}

fn cronFieldMatches(field: []const u8, value: u8) bool {
    if (std.mem.eql(u8, field, "*")) return true;
    // Support */N step syntax
    if (field.len > 2 and field[0] == '*' and field[1] == '/') {
        const step = std.fmt.parseInt(u8, field[2..], 10) catch return false;
        if (step == 0) return false;
        return @mod(value, step) == 0;
    }
    const parsed = std.fmt.parseInt(u8, field, 10) catch return false;
    return parsed == value;
}

fn genericMetricsThread(state: *DaemonState) void {
    var cron_pending_restarts = std.ArrayList(u32).init(std.heap.page_allocator);
    defer cron_pending_restarts.deinit();

    while (true) {
        std.time.sleep(std.time.ns_per_s);
        state.mutex.lock();
        if (!state.running) {
            state.mutex.unlock();
            break;
        }
        cron_pending_restarts.clearRetainingCapacity();

        for (state.processes.items) |process| {
            if (process.pid == null or process.status != .online) continue;
            if (std.mem.eql(u8, process.runtime_kind, "bun") and process.agent != null) {
                if (process.summary.timestamp) |timestamp| {
                    if (storage_mod.timestampMs() - timestamp <= 3000) continue;
                }
            }
            updateGenericMetrics(process) catch {};
            if (process.summary.timestamp) |timestamp| {
                process.history.append(state.allocator, .{
                    .timestamp = timestamp,
                    .rss = process.summary.rss,
                    .heapUsed = process.summary.heapUsed,
                    .heapTotal = process.summary.heapTotal,
                }) catch {};
                if (process.history.items.len > 600) _ = process.history.orderedRemove(0);
            }
            if (process.config.max_memory_restart > 0 and process.summary.rss != null and process.summary.rss.? > process.config.max_memory_restart and !process.stop_requested) {
                terminateProcess(process, false);
                process.stop_requested = false;
            }

            // Log rotation: rotate if max_log_size exceeded
            if (process.config.max_log_size > 0) {
                rotateLogIfNeeded(process.log_path, process.config.max_log_size);
                if (process.out_log_path) |p| rotateLogIfNeeded(p, process.config.max_log_size);
                if (process.err_log_path) |p| rotateLogIfNeeded(p, process.config.max_log_size);
            }

            // Cron restart: check if cron expression matches current minute
            if (process.config.cron_restart) |cron_expr| {
                const now_ms = storage_mod.timestampMs();
                const current_minute = @divTrunc(now_ms, 60000);
                if (process.last_cron_minute == null or process.last_cron_minute.? != current_minute) {
                    if (matchesCronMinute(cron_expr, now_ms)) {
                        process.last_cron_minute = current_minute;
                        cron_pending_restarts.append(process.id) catch {};
                    } else {
                        process.last_cron_minute = current_minute;
                    }
                }
            }
        }
        state.mutex.unlock();

        // Perform cron restarts outside the lock
        for (cron_pending_restarts.items) |process_id| {
            restartProcessById(state, process_id);
        }
    }
}

fn readLinuxStatm(pid: i32) !struct { rss: u64, total: u64 } {
    var buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "/proc/{d}/statm", .{pid});
    const content = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 4096);
    defer std.heap.page_allocator.free(content);
    var it = std.mem.tokenizeAny(u8, content, " \n\t");
    const total_pages = try std.fmt.parseInt(u64, it.next() orelse "0", 10);
    const rss_pages = try std.fmt.parseInt(u64, it.next() orelse "0", 10);
    return .{
        .rss = rss_pages * 4096,
        .total = total_pages * 4096,
    };
}

fn readLinuxProcCpuTicks(pid: i32) !u64 {
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid});
    const content = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 4096);
    defer std.heap.page_allocator.free(content);
    const close_paren = std.mem.lastIndexOfScalar(u8, content, ')') orelse return error.InvalidArgument;
    if (close_paren + 2 >= content.len) return error.InvalidArgument;
    const rest = content[close_paren + 2 ..];
    var it = std.mem.tokenizeAny(u8, rest, " \n\t");
    var field_index: usize = 0;
    var utime: u64 = 0;
    var stime: u64 = 0;
    while (it.next()) |part| : (field_index += 1) {
        if (field_index == 11) utime = try std.fmt.parseInt(u64, part, 10);
        if (field_index == 12) {
            stime = try std.fmt.parseInt(u64, part, 10);
            break;
        }
    }
    return utime + stime;
}

fn updateGenericMetrics(process: *ManagedProcess) !void {
    const pid = process.pid orelse return;
    const statm = try readLinuxStatm(pid);
    const now_ms = storage_mod.timestampMs();
    process.summary.rss = statm.rss;
    process.summary.heapUsed = statm.rss;
    process.summary.heapTotal = statm.total;
    process.summary.timestamp = now_ms;

    const cpu_ticks = readLinuxProcCpuTicks(pid) catch {
        process.summary.cpuPercent = process.summary.cpuPercent orelse 0;
        return;
    };
    if (process.last_cpu_total_ticks) |prev_ticks| {
        if (process.last_cpu_sample_ms) |prev_ms| {
            const delta_ticks = cpu_ticks - prev_ticks;
            const delta_ms = @max(now_ms - prev_ms, 1);
            const cpu_ms = (@as(f64, @floatFromInt(delta_ticks)) / 100.0) * 1000.0;
            process.summary.cpuPercent = @max(0, (cpu_ms / @as(f64, @floatFromInt(delta_ms))) * 100.0);
        }
    } else {
        process.summary.cpuPercent = 0;
    }
    process.last_cpu_total_ticks = cpu_ticks;
    process.last_cpu_sample_ms = now_ms;
}

fn resolveScriptPath(allocator: Allocator, process: *ManagedProcess) ![]u8 {
    const joined = if (std.fs.path.isAbsolute(process.config.script))
        try allocator.dupe(u8, process.config.script)
    else
        try std.fs.path.join(allocator, &.{ process.config.cwd, process.config.script });
    errdefer allocator.free(joined);

    const resolved = std.fs.realpathAlloc(allocator, joined) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => return joined,
    };
    allocator.free(joined);
    return resolved;
}

fn launchManagedProcess(state: *DaemonState, process: *ManagedProcess) !void {
    var argv = std.ArrayList([]const u8).init(state.allocator);
    defer argv.deinit();

    const agent_preload = try storage_mod.agentPreloadPath(state.allocator);
    defer state.allocator.free(agent_preload);
    const script_path = try resolveScriptPath(state.allocator, process);
    defer state.allocator.free(script_path);

    const use_bun = process.config.interpreter == null or std.mem.eql(u8, process.config.interpreter.?, "bun");
    if (use_bun) {
        try argv.append("bun");
        try argv.append("--preload");
        try argv.append(agent_preload);
        process.runtime_kind = "bun";
    } else {
        try argv.append(process.config.interpreter.?);
        process.runtime_kind = "generic";
    }
    try argv.append(script_path);
    for (process.config.args) |arg| try argv.append(arg);

    if (process.child) |existing_child| state.allocator.destroy(existing_child);
    const child_ptr = try state.allocator.create(std.process.Child);
    child_ptr.* = std.process.Child.init(argv.items, state.allocator);
    child_ptr.stdin_behavior = .Ignore;
    child_ptr.stdout_behavior = .Pipe;
    child_ptr.stderr_behavior = .Pipe;
    child_ptr.cwd = if (std.fs.path.isAbsolute(process.config.cwd)) process.config.cwd else blk: {
        // Resolve relative CWD
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const resolved = std.fs.cwd().realpath(process.config.cwd, &buf) catch process.config.cwd;
        const duped = state.allocator.dupe(u8, resolved) catch process.config.cwd;
        break :blk duped;
    };

    var env_map = try std.process.getEnvMap(state.allocator);
    defer env_map.deinit();
    for (process.config.env_pairs) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |idx| {
            try env_map.put(pair[0..idx], pair[idx + 1 ..]);
        }
    }
    if (use_bun) {
        try env_map.put("BUNCORE_HOST", state.host);
        try env_map.put("BUNCORE_TOKEN", state.token);
        const port_text = try std.fmt.allocPrint(state.allocator, "{d}", .{state.port});
        defer state.allocator.free(port_text);
        try env_map.put("BUNCORE_PORT", port_text);
        const process_id_text = try std.fmt.allocPrint(state.allocator, "{d}", .{process.id});
        defer state.allocator.free(process_id_text);
        try env_map.put("BUNCORE_PROCESS_ID", process_id_text);
        try env_map.put("BUNCORE_PROCESS_NAME", process.config.name);
    }

    // Cluster mode: set BUNCORE_REUSEPORT and BUNCORE_INSTANCE_ID for SO_REUSEPORT load balancing
    const is_cluster = if (process.config.exec_mode) |mode| std.mem.eql(u8, mode, "cluster") else false;
    if (is_cluster) {
        try env_map.put("BUNCORE_REUSEPORT", "true");
        // Extract instance index from name suffix (e.g. "api-0" -> "0")
        const instance_id = blk: {
            if (std.mem.lastIndexOfScalar(u8, process.config.name, '-')) |dash_idx| {
                const suffix = process.config.name[dash_idx + 1 ..];
                _ = std.fmt.parseInt(u32, suffix, 10) catch break :blk "0";
                break :blk suffix;
            }
            break :blk "0";
        };
        try env_map.put("BUNCORE_INSTANCE_ID", instance_id);
    }
    child_ptr.env_map = &env_map;
    try child_ptr.spawn();

    process.child = child_ptr;
    process.pid = if (builtin.os.tag == .windows) null else @intCast(child_ptr.id);
    process.started_at = storage_mod.timestampMs();
    process.stopped_at = null;
    process.status = .online;
    process.stop_requested = false;
    process.agent = null;
    process.watch_ready = false;
    process.watch_signature = 0;
    process.last_cpu_total_ticks = null;
    process.last_cpu_sample_ms = null;

    updateGenericMetrics(process) catch {};

    if (child_ptr.stdout) |stdout_file| {
        _ = try std.Thread.spawn(.{}, streamPumpThread, .{ state, process.id, process.config.name, "stdout", stdout_file, process.log_path, process.out_log_path });
    }
    if (child_ptr.stderr) |stderr_file| {
        _ = try std.Thread.spawn(.{}, streamPumpThread, .{ state, process.id, process.config.name, "stderr", stderr_file, process.log_path, process.err_log_path });
    }
    _ = try std.Thread.spawn(.{}, processWaitThread, .{ state, process.id, child_ptr });

}

fn startManagedProcess(state: *DaemonState, config: ProcessConfig) !*ManagedProcess {
    const persistent_config = try cloneConfig(state.allocator, config);
    const process = try state.allocator.create(ManagedProcess);
    const log_path = try state.storage.processLogPath(state.allocator, persistent_config.name, state.next_process_id, "combined");
    const out_log = if (persistent_config.out_file) |of| try state.allocator.dupe(u8, of) else null;
    const err_log = if (persistent_config.error_file) |ef| try state.allocator.dupe(u8, ef) else null;
    process.* = .{
        .allocator = state.allocator,
        .id = state.next_process_id,
        .config = persistent_config,
        .created_at = storage_mod.timestampMs(),
        .log_path = log_path,
        .out_log_path = out_log,
        .err_log_path = err_log,
    };
    state.next_process_id += 1;
    errdefer process.deinit();
    try state.processes.append(process);
    errdefer _ = state.processes.pop();
    try launchManagedProcess(state, process);
    return process;
}

fn relaunchExistingProcess(state: *DaemonState, process: *ManagedProcess) !void {
    try launchManagedProcess(state, process);
}

fn removeProcessById(state: *DaemonState, process_id: u32) void {
    for (state.processes.items, 0..) |item, idx| {
        if (item.id == process_id) {
            const removed = state.processes.orderedRemove(idx);
            removed.deinit();
            return;
        }
    }
}

fn stopManagedProcess(process: *ManagedProcess) void {
    process.stop_requested = true;
    process.status = .stopping;
    terminateProcess(process, false);
}

fn waitStopped(state: *DaemonState, process_id: u32, timeout_ms: u64) bool {
    const deadline = storage_mod.timestampMs() + @as(i64, @intCast(timeout_ms));
    while (storage_mod.timestampMs() < deadline) {
        state.mutex.lock();
        if (state.findProcessById(process_id)) |process| {
            if (process.status == .stopped or process.status == .errored) {
                state.mutex.unlock();
                return true;
            }
        } else {
            state.mutex.unlock();
            return true;
        }
        state.mutex.unlock();
        std.time.sleep(100 * std.time.ns_per_ms);
    }
    return false;
}

fn ensureProcessStopped(state: *DaemonState, process_id: u32, timeout_ms: u64) void {
    if (waitStopped(state, process_id, timeout_ms)) {
        state.mutex.lock();
        if (state.findProcessById(process_id)) |process| {
            if (process.status == .stopping and process.pid == null) {
                process.status = .stopped;
                process.stop_requested = false;
            }
        }
        state.mutex.unlock();
        return;
    }
    state.mutex.lock();
    if (state.findProcessById(process_id)) |process| {
        terminateProcess(process, true);
    }
    state.mutex.unlock();
    _ = waitStopped(state, process_id, 2000);
    state.mutex.lock();
    if (state.findProcessById(process_id)) |process| {
        if (process.pid == null) {
            process.status = .stopped;
            process.stop_requested = false;
        }
    }
    state.mutex.unlock();
}

fn restartProcessById(state: *DaemonState, process_id: u32) void {
    state.mutex.lock();
    const process = state.findProcessById(process_id) orelse {
        state.mutex.unlock();
        return;
    };
    if (process.status == .launching or process.status == .stopping) {
        state.mutex.unlock();
        return;
    }
    stopManagedProcess(process);
    state.mutex.unlock();
    ensureProcessStopped(state, process_id, 6000);
    state.mutex.lock();
    if (state.findProcessById(process_id)) |stopped_process| {
        relaunchExistingProcess(state, stopped_process) catch {
            stopped_process.status = .errored;
        };
    }
    state.mutex.unlock();
}

fn reloadProcessById(state: *DaemonState, process_id: u32) void {
    // Graceful reload: launch new instance first, wait for it to come online, then stop old one.
    // For single-instance processes, falls back to restart behavior.
    state.mutex.lock();
    const process = state.findProcessById(process_id) orelse {
        state.mutex.unlock();
        return;
    };
    if (process.status == .launching or process.status == .stopping) {
        state.mutex.unlock();
        return;
    }

    // Clone config for the new replacement instance
    const new_config = cloneConfig(state.allocator, process.config) catch {
        state.mutex.unlock();
        restartProcessById(state, process_id);
        return;
    };
    defer deinitProcessConfig(state.allocator, @constCast(&new_config));

    // Start a temporary new instance with the same config
    const new_process = startManagedProcess(state, new_config) catch {
        state.mutex.unlock();
        restartProcessById(state, process_id);
        return;
    };
    const new_id = new_process.id;
    state.mutex.unlock();

    // Wait for new instance to come online (up to 10 seconds)
    var online = false;
    var wait_attempts: usize = 0;
    while (wait_attempts < 100) : (wait_attempts += 1) {
        std.time.sleep(100 * std.time.ns_per_ms);
        state.mutex.lock();
        if (state.findProcessById(new_id)) |new_proc| {
            if (new_proc.status == .online and (new_proc.agent != null or new_proc.pid != null)) {
                online = true;
                state.mutex.unlock();
                break;
            }
            if (new_proc.status == .errored or new_proc.status == .stopped) {
                state.mutex.unlock();
                break;
            }
        } else {
            state.mutex.unlock();
            break;
        }
        state.mutex.unlock();
    }

    if (!online) {
        // New instance failed to come online - remove it and keep old one running
        state.mutex.lock();
        if (state.findProcessById(new_id)) |failed| {
            stopManagedProcess(failed);
        }
        state.mutex.unlock();
        ensureProcessStopped(state, new_id, 4000);
        state.mutex.lock();
        removeProcessById(state, new_id);
        state.mutex.unlock();
        return;
    }

    // New instance is online - gracefully stop old one
    state.mutex.lock();
    if (state.findProcessById(process_id)) |old_process| {
        stopManagedProcess(old_process);
    }
    state.mutex.unlock();
    ensureProcessStopped(state, process_id, 6000);

    // Remove old process entry
    state.mutex.lock();
    removeProcessById(state, process_id);
    state.mutex.unlock();
}

fn shouldIgnoreWatchPath(process: *ManagedProcess, rel_path: []const u8) bool {
    for (process.config.ignore_watch) |ignore_item| {
        if (ignore_item.len == 0) continue;
        if (std.mem.indexOf(u8, rel_path, ignore_item) != null) return true;
    }
    return false;
}

fn resolveWatchRoot(allocator: Allocator, process: *ManagedProcess) ![]u8 {
    if (process.config.watch_path) |watch_path| {
        if (std.fs.path.isAbsolute(watch_path)) return allocator.dupe(u8, watch_path);
        return std.fs.path.join(allocator, &.{ process.config.cwd, watch_path });
    }
    if (std.fs.path.dirname(process.config.script)) |dir_path| {
        if (std.fs.path.isAbsolute(process.config.script)) return allocator.dupe(u8, dir_path);
        return std.fs.path.join(allocator, &.{ process.config.cwd, dir_path });
    }
    return allocator.dupe(u8, process.config.cwd);
}

fn computeWatchSignature(allocator: Allocator, process: *ManagedProcess) !u64 {
    return watch_mod.computeSignature(allocator, .{
        .process_id = process.id,
        .cwd = process.config.cwd,
        .script = process.config.script,
        .watch_path = process.config.watch_path,
        .ignore_watch = process.config.ignore_watch,
    });
}

fn collectOwnedWatchSpecs(allocator: Allocator, state: *DaemonState) ![]OwnedWatchSpec {
    var list = std.ArrayList(OwnedWatchSpec).init(allocator);
    errdefer {
        for (list.items) |*item| item.deinit(allocator);
        list.deinit();
    }

    state.mutex.lock();
    defer state.mutex.unlock();
    for (state.processes.items) |process| {
        if (!process.config.watch) continue;
        if (process.status != .online or process.stop_requested) continue;

        const ignore_copy = try allocator.alloc([]u8, process.config.ignore_watch.len);
        for (process.config.ignore_watch, 0..) |item, idx| {
            ignore_copy[idx] = try allocator.dupe(u8, item);
        }

        try list.append(.{
            .process_id = process.id,
            .cwd = try allocator.dupe(u8, process.config.cwd),
            .script = try allocator.dupe(u8, process.config.script),
            .watch_path = if (process.config.watch_path) |watch_path| try allocator.dupe(u8, watch_path) else null,
            .ignore_watch = ignore_copy,
        });
    }

    return list.toOwnedSlice();
}

fn watchThread(state: *DaemonState) void {
    while (true) {
        if (watch_mod.strategy() == .linux_inotify or watch_mod.strategy() == .darwin_kqueue or watch_mod.strategy() == .windows_read_directory_changes) {
            state.mutex.lock();
            const running = state.running;
            state.mutex.unlock();
            if (!running) break;

            const owned_specs = collectOwnedWatchSpecs(std.heap.page_allocator, state) catch {
                std.time.sleep(std.time.ns_per_s);
                continue;
            };
            defer {
                for (owned_specs) |*spec| spec.deinit(std.heap.page_allocator);
                std.heap.page_allocator.free(owned_specs);
            }

            if (owned_specs.len == 0) {
                std.time.sleep(std.time.ns_per_s);
                continue;
            }

            const specs = std.heap.page_allocator.alloc(watch_mod.Spec, owned_specs.len) catch {
                std.time.sleep(std.time.ns_per_s);
                continue;
            };
            defer std.heap.page_allocator.free(specs);
            for (owned_specs, 0..) |owned, idx| specs[idx] = owned.spec();

            const changed = switch (watch_mod.strategy()) {
                .linux_inotify => watch_mod.waitForLinuxChanges(std.heap.page_allocator, specs, 1000),
                .darwin_kqueue => watch_mod.waitForKqueueChanges(std.heap.page_allocator, specs, 1000),
                .windows_read_directory_changes => watch_mod.waitForWindowsChanges(std.heap.page_allocator, specs, 1000),
                else => unreachable,
            } catch {
                std.time.sleep(std.time.ns_per_s);
                continue;
            };
            defer std.heap.page_allocator.free(changed);
            for (changed) |process_id| restartProcessById(state, process_id);
            continue;
        }

        std.time.sleep(std.time.ns_per_s);
        state.mutex.lock();
        if (!state.running) {
            state.mutex.unlock();
            break;
        }

        var pending_restarts = std.ArrayList(u32).init(std.heap.page_allocator);
        defer pending_restarts.deinit();

        for (state.processes.items) |process| {
            if (!process.config.watch) continue;
            if (process.status != .online or process.stop_requested) continue;
            const signature = computeWatchSignature(std.heap.page_allocator, process) catch continue;
            if (!process.watch_ready) {
                process.watch_ready = true;
                process.watch_signature = signature;
                continue;
            }
            if (process.watch_signature != signature) {
                process.watch_signature = signature;
                pending_restarts.append(process.id) catch {};
            }
        }
        state.mutex.unlock();

        for (pending_restarts.items) |process_id| restartProcessById(state, process_id);
    }
}

fn writeHistorySliceJson(writer: anytype, process: *ManagedProcess, limit: ?usize) !void {
    try writer.writeByte('[');
    const total = process.history.items.len;
    const start_index = if (limit) |max_points|
        if (total > max_points) total - max_points else 0
    else
        0;

    for (process.history.items[start_index..], 0..) |point, idx| {
        if (idx > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.print("\"timestamp\":{d},\"rss\":", .{point.timestamp});
        if (point.rss) |rss| try writer.print("{d}", .{rss}) else try writer.writeAll("null");
        try writer.writeAll(",\"heapUsed\":");
        if (point.heapUsed) |heap_used| try writer.print("{d}", .{heap_used}) else try writer.writeAll("null");
        try writer.writeAll(",\"heapTotal\":");
        if (point.heapTotal) |heap_total| try writer.print("{d}", .{heap_total}) else try writer.writeAll("null");
        try writer.writeByte('}');
    }

    try writer.writeByte(']');
}

fn buildProcessJson(allocator: Allocator, process: *ManagedProcess) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeByte('{');
    try writer.print("\"id\":{d}", .{process.id});
    try writer.writeAll(",\"name\":");
    try std.json.stringify(process.config.name, .{}, writer);
    try writer.writeAll(",\"script\":");
    try std.json.stringify(process.config.script, .{}, writer);
    try writer.writeAll(",\"cwd\":");
    try std.json.stringify(process.config.cwd, .{}, writer);
    try writer.writeAll(",\"status\":");
    try std.json.stringify(process.status.label(), .{}, writer);
    try writer.writeAll(",\"pid\":");
    if (process.pid) |pid| try writer.print("{d}", .{pid}) else try writer.writeAll("null");
    try writer.print(",\"createdAt\":{d}", .{process.created_at});
    try writer.writeAll(",\"startedAt\":");
    if (process.started_at) |started_at| try writer.print("{d}", .{started_at}) else try writer.writeAll("null");
    try writer.writeAll(",\"stoppedAt\":");
    if (process.stopped_at) |stopped_at| try writer.print("{d}", .{stopped_at}) else try writer.writeAll("null");
    try writer.print(",\"restarts\":{d},\"unstableRestarts\":{d}", .{ process.restarts, process.unstable_restarts });
    try writer.writeAll(",\"lastExitCode\":");
    if (process.last_exit_code) |last_exit_code| try writer.print("{d}", .{last_exit_code}) else try writer.writeAll("null");
    try writer.writeAll(",\"runtime\":");
    try std.json.stringify(process.runtime_kind, .{}, writer);
    try writer.writeAll(",\"platform\":");
    try std.json.stringify(watch_mod.platformLabel(), .{}, writer);
    try writer.writeAll(",\"watchEnabled\":");
    try writer.writeAll(if (process.config.watch) "true" else "false");
    try writer.writeAll(",\"watchStrategy\":");
    try std.json.stringify(watch_mod.strategyLabel(watch_mod.strategy()), .{}, writer);
    try writer.writeAll(",\"watchPreferredStrategy\":");
    try std.json.stringify(watch_mod.strategyLabel(watch_mod.preferredStrategy()), .{}, writer);
    try writer.writeAll(",\"watchNative\":");
    try writer.writeAll(if (watch_mod.strategyIsNative(watch_mod.strategy())) "true" else "false");
    try writer.writeAll(",\"summary\":");
    try std.json.stringify(process.summary, .{}, writer);
    try writer.writeAll(",\"details\":");
    try std.json.stringify(process.details, .{}, writer);
    try writer.writeAll(",\"recentMetrics\":");
    try writeHistorySliceJson(writer, process, 30);

    try writer.writeAll(",\"config\":{");
    try writer.writeAll("\"args\":");
    try std.json.stringify(process.config.args, .{}, writer);
    try writer.writeAll(",\"envPairs\":");
    try std.json.stringify(process.config.env_pairs, .{}, writer);
    try writer.print(",\"instances\":{d},\"watch\":{s},\"maxMemoryRestart\":{d},\"autorestart\":{s},\"maxRestarts\":{d},\"minUptime\":{d},\"restartDelay\":{d},\"expBackoffRestartDelay\":{d},\"maxLogSize\":{d},\"killTimeout\":{d}", .{
        process.config.instances,
        if (process.config.watch) "true" else "false",
        process.config.max_memory_restart,
        if (process.config.autorestart) "true" else "false",
        process.config.max_restarts,
        process.config.min_uptime,
        process.config.restart_delay,
        process.config.exp_backoff_restart_delay,
        process.config.max_log_size,
        process.config.kill_timeout,
    });
    try writer.writeAll(",\"interpreter\":");
    if (process.config.interpreter) |interpreter| try std.json.stringify(interpreter, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"watchPath\":");
    if (process.config.watch_path) |watch_path| try std.json.stringify(watch_path, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"ignoreWatch\":");
    try std.json.stringify(process.config.ignore_watch, .{}, writer);
    try writer.writeAll(",\"outFile\":");
    if (process.config.out_file) |out_file| try std.json.stringify(out_file, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"errorFile\":");
    if (process.config.error_file) |error_file| try std.json.stringify(error_file, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"execMode\":");
    if (process.config.exec_mode) |exec_mode| try std.json.stringify(exec_mode, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"stopExitCodes\":");
    try std.json.stringify(process.config.stop_exit_codes, .{}, writer);
    try writer.writeAll(",\"cronRestart\":");
    if (process.config.cron_restart) |cron_restart| try std.json.stringify(cron_restart, .{}, writer) else try writer.writeAll("null");
    try writer.writeByte('}');

    try writer.writeAll(",\"logPaths\":{\"combined\":");
    try std.json.stringify(process.log_path, .{}, writer);
    try writer.writeAll(",\"stdout\":");
    if (process.out_log_path) |stdout_path| try std.json.stringify(stdout_path, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"stderr\":");
    if (process.err_log_path) |stderr_path| try std.json.stringify(stderr_path, .{}, writer) else try writer.writeAll("null");
    try writer.writeAll("}}");
    return out.toOwnedSlice();
}

fn buildProcessesListJson(allocator: Allocator, state: *DaemonState) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.writeAll("{\"processes\":[");
    for (state.processes.items, 0..) |process, idx| {
        if (idx > 0) try writer.writeByte(',');
        const process_json = try buildProcessJson(allocator, process);
        defer allocator.free(process_json);
        try writer.writeAll(process_json);
    }
    try writer.writeAll("]}");
    return out.toOwnedSlice();
}

fn buildDashboardSnapshotJson(allocator: Allocator, state: *DaemonState) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.print("{{\"type\":\"snapshot\",\"timestamp\":{d},\"processes\":[", .{storage_mod.timestampMs()});
    for (state.processes.items, 0..) |process, idx| {
        if (idx > 0) try writer.writeByte(',');
        const process_json = try buildProcessJson(allocator, process);
        defer allocator.free(process_json);
        try writer.writeAll(process_json);
    }
    try writer.writeAll("]}");
    return out.toOwnedSlice();
}

fn buildHistoryJson(allocator: Allocator, process: *ManagedProcess) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.writeAll("{\"metrics\":");
    try writeHistorySliceJson(writer, process, null);
    try writer.writeByte('}');
    return out.toOwnedSlice();
}

fn readLogSlice(allocator: Allocator, path: []const u8, tail_lines: usize, offset: usize) ![]u8 {
    const content = std.fs.cwd().readFileAlloc(allocator, path, 2 * 1024 * 1024) catch return allocator.dupe(u8, "");
    errdefer allocator.free(content);
    if (offset > 0) {
        if (offset >= content.len) return allocator.dupe(u8, "");
        return allocator.dupe(u8, content[offset..]);
    }
    var count: usize = 0;
    var index: usize = content.len;
    while (index > 0) : (index -= 1) {
        if (content[index - 1] == '\n') {
            count += 1;
            if (count > tail_lines) break;
        }
    }
    return allocator.dupe(u8, content[index..]);
}

fn waitForFileJson(allocator: Allocator, path: []const u8, timeout_ms: u64) ![]u8 {
    const deadline = storage_mod.timestampMs() + @as(i64, @intCast(timeout_ms));
    while (storage_mod.timestampMs() < deadline) {
        const content = std.fs.cwd().readFileAlloc(allocator, path, 4 * 1024 * 1024) catch {
            std.time.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        return content;
    }
    return error.Timeout;
}

fn wakePort(host: []const u8, port: u16) void {
    const stream = std.net.tcpConnectToHost(std.heap.page_allocator, host, port) catch return;
    stream.close();
}

fn shutdownThread(state: *DaemonState) void {
    for (state.processes.items) |process| stopManagedProcess(process);
    for (state.processes.items) |process| ensureProcessStopped(state, process.id, 4000);
    std.fs.deleteFileAbsolute(state.storage.daemon_file) catch {};
    std.time.sleep(100 * std.time.ns_per_ms);
    std.posix.exit(0);
}

fn handleControlRequest(state: *DaemonState, allocator: Allocator, request: protocol.Request) ![]u8 {
    if (!std.mem.eql(u8, request.authToken orelse "", state.token)) {
        return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "unauthorized" });
    }

    if (std.mem.eql(u8, request.action, "ping")) {
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"pong\":true}" });
    }

    if (std.mem.eql(u8, request.action, "list")) {
        state.mutex.lock();
        const data = try buildProcessesListJson(allocator, state);
        state.mutex.unlock();
        defer allocator.free(data);
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = data });
    }

    if (std.mem.eql(u8, request.action, "start")) {
        const name = protocol.payloadString(request.payload, "name") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing name" });
        const script = protocol.payloadString(request.payload, "script") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing script" });
        const cwd = protocol.payloadString(request.payload, "cwd") orelse ".";
        const args = try protocol.payloadStringArrayAlloc(allocator, request.payload, "args");
        defer {
            for (args) |arg| allocator.free(arg);
            allocator.free(args);
        }
        const env_pairs = try protocol.payloadStringArrayAlloc(allocator, request.payload, "envPairs");
        defer {
            for (env_pairs) |pair| allocator.free(pair);
            allocator.free(env_pairs);
        }
        const ignore_watch = try protocol.payloadStringArrayAlloc(allocator, request.payload, "ignoreWatch");
        defer {
            for (ignore_watch) |item| allocator.free(item);
            allocator.free(ignore_watch);
        }

        var config = ProcessConfig{
            .name = try allocator.dupe(u8, name),
            .script = try allocator.dupe(u8, script),
            .args = try duplicateStrings(allocator, args),
            .cwd = try allocator.dupe(u8, cwd),
            .interpreter = if (protocol.payloadString(request.payload, "interpreter")) |value| try allocator.dupe(u8, value) else null,
            .env_pairs = try duplicateStrings(allocator, env_pairs),
            .instances = @intCast(protocol.payloadInt(request.payload, "instances", i64, 1)),
            .watch = protocol.payloadBool(request.payload, "watch", false),
            .watch_path = if (protocol.payloadString(request.payload, "watchPath")) |value| try allocator.dupe(u8, value) else null,
            .ignore_watch = try duplicateStrings(allocator, ignore_watch),
            .max_memory_restart = @intCast(protocol.payloadInt(request.payload, "maxMemoryRestart", i64, 0)),
            .autorestart = protocol.payloadBool(request.payload, "autorestart", true),
            .max_restarts = @intCast(protocol.payloadInt(request.payload, "maxRestarts", i64, 15)),
            .min_uptime = protocol.payloadInt(request.payload, "minUptime", i64, 1000),
            .restart_delay = @intCast(protocol.payloadInt(request.payload, "restartDelay", i64, 100)),
            .out_file = if (protocol.payloadString(request.payload, "outFile")) |value| try allocator.dupe(u8, value) else null,
            .error_file = if (protocol.payloadString(request.payload, "errorFile")) |value| try allocator.dupe(u8, value) else null,
            .exec_mode = if (protocol.payloadString(request.payload, "execMode")) |value| try allocator.dupe(u8, value) else null,
            .exp_backoff_restart_delay = @intCast(protocol.payloadInt(request.payload, "expBackoffRestartDelay", i64, 0)),
            .stop_exit_codes = try protocol.payloadIntArrayAlloc(allocator, request.payload, "stopExitCodes"),
            .cron_restart = if (protocol.payloadString(request.payload, "cronRestart")) |value| try allocator.dupe(u8, value) else null,
            .max_log_size = @intCast(protocol.payloadInt(request.payload, "maxLogSize", i64, 0)),
            .kill_timeout = @intCast(protocol.payloadInt(request.payload, "killTimeout", i64, 6000)),
        };
        defer deinitProcessConfig(allocator, &config);

        const instance_count: u32 = if (config.instances == 0) 1 else config.instances;
        state.mutex.lock();
        for (0..instance_count) |index| {
            const instance_name = if (instance_count == 1)
                try allocator.dupe(u8, config.name)
            else
                try std.fmt.allocPrint(allocator, "{s}-{d}", .{ config.name, index });
            defer allocator.free(instance_name);
            if (state.findProcessByNameExact(instance_name) != null) {
                state.mutex.unlock();
                return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "process name already exists" });
            }
        }

        for (0..instance_count) |index| {
            const instance_name = if (instance_count == 1)
                try allocator.dupe(u8, config.name)
            else
                try std.fmt.allocPrint(allocator, "{s}-{d}", .{ config.name, index });
            var instance_config = try cloneConfigWithName(allocator, config, instance_name);
            allocator.free(instance_name);
            instance_config.instances = 1;
            defer deinitProcessConfig(allocator, &instance_config);
            _ = startManagedProcess(state, instance_config) catch |err| {
                state.mutex.unlock();
                const error_text = switch (err) {
                    error.FileNotFound => try std.fmt.allocPrint(allocator, "script not found: {s}", .{instance_config.script}),
                    else => try allocator.dupe(u8, @errorName(err)),
                };
                defer allocator.free(error_text);
                return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = error_text });
            };
        }
        state.mutex.unlock();
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    if (std.mem.eql(u8, request.action, "stop") or std.mem.eql(u8, request.action, "restart") or std.mem.eql(u8, request.action, "reload") or std.mem.eql(u8, request.action, "delete") or std.mem.eql(u8, request.action, "info") or std.mem.eql(u8, request.action, "logs") or std.mem.eql(u8, request.action, "flush") or std.mem.eql(u8, request.action, "metrics") or std.mem.eql(u8, request.action, "heap") or std.mem.eql(u8, request.action, "heap-analyze") or std.mem.eql(u8, request.action, "profile")) {
        const target = protocol.payloadString(request.payload, "target") orelse protocol.payloadString(request.payload, "id") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing target" });

        const is_multi_target_action =
            std.mem.eql(u8, request.action, "stop") or
            std.mem.eql(u8, request.action, "restart") or
            std.mem.eql(u8, request.action, "reload") or
            std.mem.eql(u8, request.action, "delete") or
            std.mem.eql(u8, request.action, "flush");

        state.mutex.lock();
        if (is_multi_target_action) {
            const ids = try collectTargetProcessIds(allocator, state, target);
            state.mutex.unlock();
            defer allocator.free(ids);
            if (ids.len == 0) {
                return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "process not found" });
            }

            if (std.mem.eql(u8, request.action, "stop")) {
                for (ids) |process_id| {
                    state.mutex.lock();
                    if (state.findProcessById(process_id)) |target_process| stopManagedProcess(target_process);
                    state.mutex.unlock();
                    ensureProcessStopped(state, process_id, 6000);
                }
            } else if (std.mem.eql(u8, request.action, "restart")) {
                for (ids) |process_id| restartProcessById(state, process_id);
            } else if (std.mem.eql(u8, request.action, "reload")) {
                for (ids) |process_id| reloadProcessById(state, process_id);
            } else if (std.mem.eql(u8, request.action, "delete")) {
                for (ids) |process_id| {
                    state.mutex.lock();
                    if (state.findProcessById(process_id)) |target_process| stopManagedProcess(target_process);
                    state.mutex.unlock();
                    ensureProcessStopped(state, process_id, 6000);
                    state.mutex.lock();
                    removeProcessById(state, process_id);
                    state.mutex.unlock();
                }
            } else if (std.mem.eql(u8, request.action, "flush")) {
                state.mutex.lock();
                for (ids) |process_id| {
                    if (state.findProcessById(process_id)) |target_process| {
                        std.fs.cwd().writeFile(.{ .sub_path = target_process.log_path, .data = "" }) catch {};
                    }
                }
                state.mutex.unlock();
            }

            const data = try std.fmt.allocPrint(allocator, "{{\"ok\":true,\"count\":{d}}}", .{ids.len});
            defer allocator.free(data);
            return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = data });
        }

        const process = state.findProcess(target) orelse {
            state.mutex.unlock();
            return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "process not found" });
        };

        if (std.mem.eql(u8, request.action, "info")) {
            const data = try buildProcessJson(allocator, process);
            state.mutex.unlock();
            defer allocator.free(data);
            return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = data });
        }

        if (std.mem.eql(u8, request.action, "metrics")) {
            const data = try buildHistoryJson(allocator, process);
            state.mutex.unlock();
            defer allocator.free(data);
            return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = data });
        }

        if (std.mem.eql(u8, request.action, "logs")) {
            const tail_lines = @as(usize, @intCast(protocol.payloadInt(request.payload, "lines", i64, 50)));
            const offset = @as(usize, @intCast(protocol.payloadInt(request.payload, "offset", i64, 0)));
            const chunk = try readLogSlice(allocator, process.log_path, tail_lines, offset);
            const data = try std.fmt.allocPrint(allocator, "{{\"log\":{s},\"nextOffset\":{d},\"path\":{s}}}", .{
                try std.json.stringifyAlloc(allocator, chunk, .{}),
                chunk.len + offset,
                try std.json.stringifyAlloc(allocator, process.log_path, .{}),
            });
            state.mutex.unlock();
            defer allocator.free(chunk);
            defer allocator.free(data);
            return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = data });
        }

        const agent = process.agent orelse {
            state.mutex.unlock();
            return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "bun agent unavailable" });
        };

        var artifact_path: []u8 = undefined;
        if (std.mem.eql(u8, request.action, "heap") or std.mem.eql(u8, request.action, "heap-analyze")) {
            artifact_path = try state.storage.snapshotPath(allocator, process.config.name, process.id, storage_mod.timestampMs(), "heapsnapshot");
        } else {
            artifact_path = try state.storage.profilePath(allocator, process.config.name, process.id, storage_mod.timestampMs());
        }
        defer allocator.free(artifact_path);
        const result_path = try std.fmt.allocPrint(allocator, "{s}.result.json", .{artifact_path});
        defer allocator.free(result_path);
        std.fs.cwd().deleteFile(result_path) catch {};

        const include_jsc = protocol.payloadBool(request.payload, "includeJsc", false);
        const duration_ms = protocol.payloadInt(request.payload, "durationMs", i64, 10_000);
        const agent_request_id = try std.fmt.allocPrint(allocator, "{d}-{d}", .{ process.id, storage_mod.timestampMs() });
        defer allocator.free(agent_request_id);

        const command_json = if (std.mem.eql(u8, request.action, "heap"))
            try std.fmt.allocPrint(allocator, "{{\"type\":\"heap_snapshot\",\"requestId\":\"{s}\",\"artifactPath\":{s},\"resultPath\":{s},\"includeJsc\":{s}}}", .{
                agent_request_id,
                try std.json.stringifyAlloc(allocator, artifact_path, .{}),
                try std.json.stringifyAlloc(allocator, result_path, .{}),
                if (include_jsc) "true" else "false",
            })
        else if (std.mem.eql(u8, request.action, "heap-analyze"))
            try std.fmt.allocPrint(allocator, "{{\"type\":\"heap_analyze\",\"requestId\":\"{s}\",\"artifactPath\":{s},\"resultPath\":{s},\"includeJsc\":{s}}}", .{
                agent_request_id,
                try std.json.stringifyAlloc(allocator, artifact_path, .{}),
                try std.json.stringifyAlloc(allocator, result_path, .{}),
                if (include_jsc) "true" else "false",
            })
        else
            try std.fmt.allocPrint(allocator, "{{\"type\":\"cpu_profile\",\"requestId\":\"{s}\",\"artifactPath\":{s},\"resultPath\":{s},\"durationMs\":{d}}}", .{
                agent_request_id,
                try std.json.stringifyAlloc(allocator, artifact_path, .{}),
                try std.json.stringifyAlloc(allocator, result_path, .{}),
                duration_ms,
            });
        state.mutex.unlock();
        defer allocator.free(command_json);
        agent.sendCommand(command_json) catch |err| {
            return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = @errorName(err) });
        };
        const result = waitForFileJson(allocator, result_path, 30_000) catch |err| {
            return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = @errorName(err) });
        };
        defer allocator.free(result);
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = result });
    }

    if (std.mem.eql(u8, request.action, "signal")) {
        const target = protocol.payloadString(request.payload, "target") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing target" });
        const sig_name = protocol.payloadString(request.payload, "signal") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing signal" });

        const sig_num: u6 = if (std.mem.eql(u8, sig_name, "SIGUSR1"))
            std.posix.SIG.USR1
        else if (std.mem.eql(u8, sig_name, "SIGUSR2"))
            std.posix.SIG.USR2
        else if (std.mem.eql(u8, sig_name, "SIGINT"))
            std.posix.SIG.INT
        else if (std.mem.eql(u8, sig_name, "SIGTERM"))
            std.posix.SIG.TERM
        else if (std.mem.eql(u8, sig_name, "SIGHUP"))
            std.posix.SIG.HUP
        else
            std.fmt.parseInt(u6, sig_name, 10) catch return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "unknown signal" });

        state.mutex.lock();
        const ids = try collectTargetProcessIds(allocator, state, target);
        state.mutex.unlock();
        defer allocator.free(ids);
        for (ids) |process_id| {
            state.mutex.lock();
            const pid = if (state.findProcessById(process_id)) |p| p.pid else null;
            state.mutex.unlock();
            if (pid) |real_pid| {
                std.posix.kill(real_pid, sig_num) catch {};
            }
        }
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    if (std.mem.eql(u8, request.action, "scale")) {
        const target_name = protocol.payloadString(request.payload, "target") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing target" });
        const desired_count: u32 = @intCast(protocol.payloadInt(request.payload, "count", i64, 1));

        state.mutex.lock();
        // Count current instances with matching base name
        var current_count: u32 = 0;
        var base_config: ?ProcessConfig = null;
        for (state.processes.items) |process| {
            const pname = process.config.name;
            if (std.mem.eql(u8, pname, target_name)) {
                current_count += 1;
                base_config = process.config;
            } else if (std.mem.startsWith(u8, pname, target_name)) {
                const rest = pname[target_name.len..];
                if (rest.len > 0 and rest[0] == '-') {
                    _ = std.fmt.parseInt(u32, rest[1..], 10) catch continue;
                    current_count += 1;
                    base_config = process.config;
                }
            }
        }
        state.mutex.unlock();

        if (base_config == null) {
            return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "process not found" });
        }

        if (desired_count > current_count) {
            // Scale up: add new instances
            const to_add = desired_count - current_count;
            state.mutex.lock();
            for (current_count..current_count + to_add) |index| {
                const instance_name = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ target_name, index });
                var instance_config = try cloneConfigWithName(allocator, base_config.?, instance_name);
                allocator.free(instance_name);
                instance_config.instances = 1;
                defer deinitProcessConfig(allocator, &instance_config);
                _ = startManagedProcess(state, instance_config) catch continue;
            }
            state.mutex.unlock();
        } else if (desired_count < current_count) {
            // Scale down: remove excess instances (from highest index)
            var to_remove = current_count - desired_count;
            state.mutex.lock();
            var i: usize = state.processes.items.len;
            while (i > 0 and to_remove > 0) {
                i -= 1;
                const process = state.processes.items[i];
                const pname = process.config.name;
                var matches = false;
                if (std.mem.eql(u8, pname, target_name)) {
                    matches = true;
                } else if (std.mem.startsWith(u8, pname, target_name) and pname.len > target_name.len and pname[target_name.len] == '-') {
                    _ = std.fmt.parseInt(u32, pname[target_name.len + 1 ..], 10) catch continue;
                    matches = true;
                }
                if (matches) {
                    stopManagedProcess(process);
                    state.mutex.unlock();
                    ensureProcessStopped(state, process.id, 6000);
                    state.mutex.lock();
                    removeProcessById(state, process.id);
                    to_remove -= 1;
                }
            }
            state.mutex.unlock();
        }
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    if (std.mem.eql(u8, request.action, "reset")) {
        const target = protocol.payloadString(request.payload, "target") orelse return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "missing target" });
        state.mutex.lock();
        const ids = try collectTargetProcessIds(allocator, state, target);
        for (ids) |process_id| {
            if (state.findProcessById(process_id)) |process| {
                process.restarts = 0;
                process.unstable_restarts = 0;
                process.current_backoff_delay = 0;
            }
        }
        state.mutex.unlock();
        allocator.free(ids);
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    if (std.mem.eql(u8, request.action, "save")) {
        state.mutex.lock();
        var out = std.ArrayList(u8).init(allocator);
        try out.appendSlice("{\"apps\":[");
        for (state.processes.items, 0..) |process, idx| {
            if (idx > 0) try out.append(',');
            const writer = out.writer();
            try writer.writeByte('{');
            try writer.writeAll("\"name\":");
            try std.json.stringify(process.config.name, .{}, writer);
            try writer.writeAll(",\"script\":");
            try std.json.stringify(process.config.script, .{}, writer);
            try writer.writeAll(",\"cwd\":");
            try std.json.stringify(process.config.cwd, .{}, writer);
            try writer.writeAll(",\"args\":");
            try std.json.stringify(process.config.args, .{}, writer);
            try writer.writeAll(",\"envPairs\":");
            try std.json.stringify(process.config.env_pairs, .{}, writer);
            try writer.print(",\"instances\":{d},\"watch\":{s},\"maxMemoryRestart\":{d},\"autorestart\":{s},\"maxRestarts\":{d},\"minUptime\":{d},\"restartDelay\":{d}", .{
                process.config.instances,
                if (process.config.watch) "true" else "false",
                process.config.max_memory_restart,
                if (process.config.autorestart) "true" else "false",
                process.config.max_restarts,
                process.config.min_uptime,
                process.config.restart_delay,
            });
            try writer.writeAll(",\"interpreter\":");
            if (process.config.interpreter) |interpreter| try std.json.stringify(interpreter, .{}, writer) else try writer.writeAll("null");
            try writer.writeAll(",\"watchPath\":");
            if (process.config.watch_path) |watch_path| try std.json.stringify(watch_path, .{}, writer) else try writer.writeAll("null");
            try writer.writeAll(",\"ignoreWatch\":");
            try std.json.stringify(process.config.ignore_watch, .{}, writer);
            try writer.writeAll(",\"outFile\":");
            if (process.config.out_file) |out_file| try std.json.stringify(out_file, .{}, writer) else try writer.writeAll("null");
            try writer.writeAll(",\"errorFile\":");
            if (process.config.error_file) |error_file| try std.json.stringify(error_file, .{}, writer) else try writer.writeAll("null");
            try writer.writeAll(",\"execMode\":");
            if (process.config.exec_mode) |exec_mode| try std.json.stringify(exec_mode, .{}, writer) else try writer.writeAll("null");
            try writer.writeAll(",\"expBackoffRestartDelay\":");
            try std.json.stringify(process.config.exp_backoff_restart_delay, .{}, writer);
            try writer.writeAll(",\"stopExitCodes\":");
            try std.json.stringify(process.config.stop_exit_codes, .{}, writer);
            try writer.writeAll(",\"cronRestart\":");
            if (process.config.cron_restart) |cron| try std.json.stringify(cron, .{}, writer) else try writer.writeAll("null");
            try writer.writeAll(",\"maxLogSize\":");
            try std.json.stringify(process.config.max_log_size, .{}, writer);
            try writer.writeAll(",\"killTimeout\":");
            try std.json.stringify(process.config.kill_timeout, .{}, writer);
            try writer.writeByte('}');
        }
        try out.appendSlice("]}");
        std.fs.cwd().writeFile(.{ .sub_path = state.storage.state_file, .data = out.items }) catch {};
        state.mutex.unlock();
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    if (std.mem.eql(u8, request.action, "resurrect")) {
        const content = std.fs.cwd().readFileAlloc(allocator, state.storage.state_file, 1024 * 1024) catch {
            return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "state file missing" });
        };
        defer allocator.free(content);
        const parsed = try std.json.parseFromSlice(struct {
            apps: []struct {
                name: []const u8,
                script: []const u8,
                cwd: []const u8,
                args: [][]const u8 = &.{},
                envPairs: [][]const u8 = &.{},
                instances: u32 = 1,
                watch: bool = false,
                watchPath: ?[]const u8 = null,
                ignoreWatch: [][]const u8 = &.{},
                maxMemoryRestart: u64 = 0,
                interpreter: ?[]const u8 = null,
                autorestart: bool = true,
                maxRestarts: u32 = 15,
                minUptime: i64 = 1000,
                restartDelay: u64 = 100,
                outFile: ?[]const u8 = null,
                errorFile: ?[]const u8 = null,
                execMode: ?[]const u8 = null,
                expBackoffRestartDelay: u64 = 0,
                stopExitCodes: []const i64 = &.{},
                cronRestart: ?[]const u8 = null,
                maxLogSize: u64 = 0,
                killTimeout: u64 = 6000,
            },
        }, allocator, content, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        for (parsed.value.apps) |app| {
            var config = ProcessConfig{
                .name = try allocator.dupe(u8, app.name),
                .script = try allocator.dupe(u8, app.script),
                .cwd = try allocator.dupe(u8, app.cwd),
                .args = blk: {
                    const out = try allocator.alloc([]u8, app.args.len);
                    for (app.args, 0..) |item, idx| out[idx] = try allocator.dupe(u8, item);
                    break :blk out;
                },
                .env_pairs = blk: {
                    const out = try allocator.alloc([]u8, app.envPairs.len);
                    for (app.envPairs, 0..) |item, idx| out[idx] = try allocator.dupe(u8, item);
                    break :blk out;
                },
                .instances = app.instances,
                .watch = app.watch,
                .watch_path = if (app.watchPath) |value| try allocator.dupe(u8, value) else null,
                .ignore_watch = blk: {
                    const out = try allocator.alloc([]u8, app.ignoreWatch.len);
                    for (app.ignoreWatch, 0..) |item, idx| out[idx] = try allocator.dupe(u8, item);
                    break :blk out;
                },
                .max_memory_restart = app.maxMemoryRestart,
                .interpreter = if (app.interpreter) |value| try allocator.dupe(u8, value) else null,
                .autorestart = app.autorestart,
                .max_restarts = app.maxRestarts,
                .min_uptime = app.minUptime,
                .restart_delay = app.restartDelay,
                .out_file = if (app.outFile) |value| try allocator.dupe(u8, value) else null,
                .error_file = if (app.errorFile) |value| try allocator.dupe(u8, value) else null,
                .exec_mode = if (app.execMode) |value| try allocator.dupe(u8, value) else null,
                .exp_backoff_restart_delay = app.expBackoffRestartDelay,
                .stop_exit_codes = blk: {
                    const out = try allocator.alloc(i32, app.stopExitCodes.len);
                    for (app.stopExitCodes, 0..) |item, idx| out[idx] = std.math.cast(i32, item) orelse 0;
                    break :blk out;
                },
                .cron_restart = if (app.cronRestart) |value| try allocator.dupe(u8, value) else null,
                .max_log_size = app.maxLogSize,
                .kill_timeout = app.killTimeout,
            };
            defer deinitProcessConfig(allocator, &config);
            const instance_count: u32 = if (config.instances == 0) 1 else config.instances;
            for (0..instance_count) |index| {
                const instance_name = if (instance_count == 1)
                    try allocator.dupe(u8, config.name)
                else
                    try std.fmt.allocPrint(allocator, "{s}-{d}", .{ config.name, index });
                var instance_config = try cloneConfigWithName(allocator, config, instance_name);
                allocator.free(instance_name);
                instance_config.instances = 1;
                defer deinitProcessConfig(allocator, &instance_config);

                state.mutex.lock();
                if (state.findProcessByNameExact(instance_config.name)) |existing| {
                    switch (existing.status) {
                        .online, .launching => {
                            state.mutex.unlock();
                            continue;
                        },
                        .stopping => {
                            if (existing.pid != null) {
                                state.mutex.unlock();
                                continue;
                            }
                            const process_id = existing.id;
                            removeProcessById(state, process_id);
                        },
                        .stopped, .errored => {
                            const process_id = existing.id;
                            removeProcessById(state, process_id);
                        },
                    }
                }
                _ = try startManagedProcess(state, instance_config);
                state.mutex.unlock();
            }
        }
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    if (std.mem.eql(u8, request.action, "kill")) {
        state.mutex.lock();
        state.running = false;
        state.mutex.unlock();
        return protocol.stringifyResponseAlloc(allocator, .{ .success = true, .requestId = request.requestId, .data_json = "{\"ok\":true}" });
    }

    return protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = request.requestId, .@"error" = "unknown action" });
}

fn handleAgentLine(state: *DaemonState, allocator: Allocator, agent: *AgentConnection, line: []const u8) void {
    var req = protocol.parseRequest(allocator, line) catch return;
    defer req.deinit();
    const action = req.value.action;
    if (!std.mem.eql(u8, req.value.authToken orelse "", state.token)) return;

    if (std.mem.eql(u8, action, "agent_hello")) {
        const parsed = std.json.parseFromSlice(AgentHello, allocator, line, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return;
        defer parsed.deinit();
        state.mutex.lock();
        if (state.findProcessById(parsed.value.payload.processId)) |process| {
            process.runtime_kind = if (std.mem.eql(u8, parsed.value.payload.runtime, "bun")) "bun" else "generic";
            process.agent = agent;
            process.pid = parsed.value.payload.pid;
        }
        state.mutex.unlock();
        return;
    }

    if (std.mem.eql(u8, action, "telemetry")) {
        const parsed = std.json.parseFromSlice(TelemetryEnvelope, allocator, line, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return;
        defer parsed.deinit();
        state.mutex.lock();
        if (state.findProcessById(parsed.value.payload.processId)) |process| {
            process.pid = parsed.value.payload.pid;
            process.status = .online;
            process.runtime_kind = if (std.mem.eql(u8, parsed.value.payload.runtime, "bun")) "bun" else "generic";
            process.summary = parsed.value.payload.summary;
            if (parsed.value.payload.details) |details| process.details = details;
            process.history.append(state.allocator, .{
                .timestamp = process.summary.timestamp orelse storage_mod.timestampMs(),
                .rss = process.summary.rss,
                .heapUsed = process.summary.heapUsed,
                .heapTotal = process.summary.heapTotal,
            }) catch {};
            if (process.history.items.len > 600) _ = process.history.orderedRemove(0);
        }
        state.mutex.unlock();
        return;
    }

    if (std.mem.eql(u8, action, "agent_result")) {
        const parsed = std.json.parseFromSlice(AgentResultEnvelope, allocator, line, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return;
        defer parsed.deinit();
        const payload_json = std.json.stringifyAlloc(allocator, parsed.value.payload, .{}) catch return;
        defer allocator.free(payload_json);
        agent.acceptResult(parsed.value.requestId, payload_json, parsed.value.@"error");
    }
}

fn agentClientThread(state: *DaemonState, stream: std.net.Stream) void {
    var local_stream = stream;
    defer local_stream.close();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const connection = allocator.create(AgentConnection) catch return;
    connection.* = .{
        .allocator = allocator,
        .process_id = 0,
        .stream = local_stream,
    };

    var buffered = std.io.bufferedReader(local_stream.reader());
    var reader = buffered.reader();
    while (true) {
        const line = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024 * 1024) catch break;
        if (line == null) break;
        defer allocator.free(line.?);
        handleAgentLine(state, allocator, connection, std.mem.trim(u8, line.?, " \r\n\t"));
    }

    connection.wait_mutex.lock();
    connection.closed = true;
    connection.waiting = false;
    connection.wait_cond.broadcast();
    connection.wait_mutex.unlock();
}

fn controlClientThread(state: *DaemonState, stream: std.net.Stream) void {
    var local_stream = stream;
    defer local_stream.close();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffered = std.io.bufferedReader(local_stream.reader());
    var reader = buffered.reader();
    const line = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024 * 1024) catch return;
    if (line == null) return;
    defer allocator.free(line.?);
    var parsed = protocol.parseRequest(allocator, std.mem.trim(u8, line.?, " \r\n\t")) catch return;
    defer parsed.deinit();
    const response = handleControlRequest(state, allocator, parsed.value) catch |err| protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = parsed.value.requestId, .@"error" = @errorName(err) }) catch return;
    defer allocator.free(response);
    local_stream.writer().print("{s}\n", .{response}) catch {};
}

fn routeClientThread(state: *DaemonState, stream: std.net.Stream) void {
    var local_stream = stream;
    defer local_stream.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffered = std.io.bufferedReader(local_stream.reader());
    var reader = buffered.reader();
    const first_line = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024 * 1024) catch return;
    if (first_line == null) return;
    defer allocator.free(first_line.?);
    const trimmed = std.mem.trim(u8, first_line.?, " \r\n\t");

    var parsed = protocol.parseRequest(allocator, trimmed) catch return;
    defer parsed.deinit();
    const is_agent = std.mem.eql(u8, parsed.value.action, "telemetry") or std.mem.eql(u8, parsed.value.action, "agent_hello") or std.mem.eql(u8, parsed.value.action, "agent_result");
    if (!is_agent) {
        const response = handleControlRequest(state, allocator, parsed.value) catch |err| protocol.stringifyResponseAlloc(allocator, .{ .success = false, .requestId = parsed.value.requestId, .@"error" = @errorName(err) }) catch return;
        defer allocator.free(response);
        local_stream.writer().print("{s}\n", .{response}) catch {};
        if (std.mem.eql(u8, parsed.value.action, "kill")) {
            shutdownThread(state);
        }
        return;
    }

    const connection = allocator.create(AgentConnection) catch return;
    connection.* = .{
        .allocator = allocator,
        .process_id = 0,
        .stream = local_stream,
    };
    handleAgentLine(state, allocator, connection, trimmed);
    while (true) {
        const line = reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024 * 1024) catch break;
        if (line == null) break;
        defer allocator.free(line.?);
        handleAgentLine(state, allocator, connection, std.mem.trim(u8, line.?, " \r\n\t"));
    }

    connection.wait_mutex.lock();
    connection.closed = true;
    connection.waiting = false;
    connection.wait_cond.broadcast();
    connection.wait_mutex.unlock();
}

fn httpTypedResponse(stream: anytype, status: []const u8, content_type: []const u8, data: []const u8) void {
    stream.writer().print("HTTP/1.1 {s}\r\nContent-Type: {s}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ status, content_type, data.len, data }) catch {};
}

fn httpJsonResponse(stream: anytype, status: []const u8, data: []const u8) void {
    httpTypedResponse(stream, status, "application/json; charset=utf-8", data);
}

fn httpHtmlResponse(stream: anytype, data: []const u8) void {
    httpTypedResponse(stream, "200 OK", "text/html; charset=utf-8", data);
}

fn httpJsResponse(stream: anytype, data: []const u8) void {
    httpTypedResponse(stream, "200 OK", "text/javascript; charset=utf-8", data);
}

fn httpCssResponse(stream: anytype, data: []const u8) void {
    httpTypedResponse(stream, "200 OK", "text/css; charset=utf-8", data);
}

fn extractHttpBody(buf: []const u8) []const u8 {
    if (std.mem.indexOf(u8, buf, "\r\n\r\n")) |idx| return buf[idx + 4 ..];
    if (std.mem.indexOf(u8, buf, "\n\n")) |idx| return buf[idx + 2 ..];
    return "";
}

fn httpRequestPath(first_line: []const u8) []const u8 {
    const first_space = std.mem.indexOfScalar(u8, first_line, ' ') orelse return "/";
    const rest = first_line[first_space + 1 ..];
    const second_space = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    return rest[0..second_space];
}

fn httpHeaderValue(request_buf: []const u8, header_name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, request_buf, '\n');
    _ = lines.next();
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \r\n\t");
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, header_name)) return value;
    }
    return null;
}

fn dashboardDistAssetPath(allocator: Allocator, asset_name: []const u8) ![]u8 {
    const root = try storage_mod.projectRootFromExe(allocator);
    defer allocator.free(root);
    return std.fs.path.join(allocator, &.{ root, "web", "dist", asset_name });
}

fn contentTypeForPath(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".woff2")) return "font/woff2";
    if (std.mem.endsWith(u8, path, ".woff")) return "font/woff";
    if (std.mem.endsWith(u8, path, ".ttf")) return "font/ttf";
    return "application/octet-stream";
}

fn pathLooksLikeAsset(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "/assets/") or std.mem.indexOfScalar(u8, path, '.') != null;
}

fn serveDashboardAsset(allocator: Allocator, stream: anytype, request_path: []const u8) bool {
    const asset_name = if (request_path.len > 0 and request_path[0] == '/') request_path[1..] else request_path;
    if (asset_name.len == 0) return false;
    if (std.mem.indexOf(u8, asset_name, "..") != null) {
        httpJsonResponse(stream, "403 Forbidden", "{\"success\":false,\"error\":\"invalid asset path\"}");
        return true;
    }

    const asset_path = dashboardDistAssetPath(allocator, asset_name) catch return false;
    defer allocator.free(asset_path);

    const data = std.fs.cwd().readFileAlloc(allocator, asset_path, 4 * 1024 * 1024) catch return false;
    defer allocator.free(data);

    httpTypedResponse(stream, "200 OK", contentTypeForPath(asset_name), data);
    return true;
}

fn websocketAcceptKeyAlloc(allocator: Allocator, client_key: []const u8) ![]u8 {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(client_key);
    sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");

    var digest: [20]u8 = undefined;
    sha1.final(&digest);

    var encoded: [28]u8 = undefined;
    const output = std.base64.standard.Encoder.encode(&encoded, &digest);
    return allocator.dupe(u8, output);
}

fn websocketWriteTextFrame(stream: anytype, data: []const u8) !void {
    const writer = stream.writer();
    try writer.writeByte(0x81);
    if (data.len <= 125) {
        try writer.writeByte(@intCast(data.len));
    } else if (data.len <= 65535) {
        try writer.writeByte(126);
        try writer.writeInt(u16, @intCast(data.len), .big);
    } else {
        try writer.writeByte(127);
        try writer.writeInt(u64, @intCast(data.len), .big);
    }
    try writer.writeAll(data);
}

fn websocketSnapshotLoop(state: *DaemonState, stream: *std.net.Stream, allocator: Allocator) void {
    while (state.running) {
        {
            state.mutex.lock();
            const payload_owned = buildDashboardSnapshotJson(allocator, state) catch null;
            state.mutex.unlock();
            defer if (payload_owned) |owned| allocator.free(owned);

            const payload = if (payload_owned) |owned| owned else "{\"type\":\"snapshot\",\"timestamp\":0,\"processes\":[]}";
            websocketWriteTextFrame(stream, payload) catch break;
        }
        std.time.sleep(1100 * std.time.ns_per_ms);
    }
}

fn dashboardClientThread(state: *DaemonState, stream_arg: std.net.Stream) void {
    var stream = stream_arg;
    defer stream.close();

    var request_storage: [16384]u8 = undefined;
    const read_len = stream.read(&request_storage) catch return;
    if (read_len == 0) return;
    const request_buf = request_storage[0..read_len];
    const first_line = std.mem.sliceTo(request_buf, '\n');
    const path = httpRequestPath(first_line);
    const allocator = std.heap.page_allocator;

    if (std.mem.startsWith(u8, first_line, "OPTIONS ")) {
        stream.writer().writeAll("HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\nConnection: close\r\n\r\n") catch {};
        return;
    }

    if (std.mem.eql(u8, path, "/ws")) {
        const client_key = httpHeaderValue(request_buf, "Sec-WebSocket-Key") orelse {
            httpJsonResponse(&stream, "400 Bad Request", "{\"success\":false,\"error\":\"missing websocket key\"}");
            return;
        };
        const accept_key = websocketAcceptKeyAlloc(allocator, client_key) catch {
            httpJsonResponse(&stream, "500 Internal Server Error", "{\"success\":false,\"error\":\"websocket handshake failed\"}");
            return;
        };
        defer allocator.free(accept_key);

        stream.writer().print("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept_key}) catch return;
        websocketSnapshotLoop(state, &stream, allocator);
        return;
    }

    if (std.mem.startsWith(u8, first_line, "GET /api/processes")) {
        state.mutex.lock();
        const data = buildProcessesListJson(allocator, state) catch "{\"processes\":[]}";
        state.mutex.unlock();
        defer if (@TypeOf(data) == []u8) allocator.free(data);
        httpJsonResponse(&stream, "200 OK", data);
        return;
    }
    if (std.mem.startsWith(u8, first_line, "GET /api/metrics?id=")) {
        const query = first_line["GET /api/metrics?id=".len..];
        const end = std.mem.indexOfScalar(u8, query, ' ') orelse query.len;
        state.mutex.lock();
        const process = state.findProcess(query[0..end]);
        const data = if (process) |p| buildHistoryJson(allocator, p) catch "{\"metrics\":[]}" else "{\"metrics\":[]}";
        state.mutex.unlock();
        defer if (@TypeOf(data) == []u8) allocator.free(data);
        httpJsonResponse(&stream, "200 OK", data);
        return;
    }
    if (std.mem.startsWith(u8, first_line, "GET /api/logs?id=")) {
        const query = first_line["GET /api/logs?id=".len..];
        const end = std.mem.indexOfScalar(u8, query, ' ') orelse query.len;
        const query_str = query[0..end];
        var target_id = query_str;
        var tail_lines: usize = 100;
        if (std.mem.indexOf(u8, query_str, "&lines=")) |amp| {
            target_id = query_str[0..amp];
            const lines_str = query_str[amp + 7 ..];
            tail_lines = std.fmt.parseInt(usize, lines_str, 10) catch 100;
        }
        state.mutex.lock();
        const process = state.findProcess(target_id);
        const log_data = if (process) |p| readLogSlice(allocator, p.log_path, tail_lines, 0) catch allocator.dupe(u8, "") catch "" else "";
        state.mutex.unlock();
        const log_json = std.json.stringifyAlloc(allocator, log_data, .{}) catch "\"\"";
        defer allocator.free(log_json);
        defer if (@TypeOf(log_data) == []u8) allocator.free(log_data);
        const resp = std.fmt.allocPrint(allocator, "{{\"log\":{s}}}", .{log_json}) catch "{\"log\":\"\"}";
        defer if (@TypeOf(resp) == []u8) allocator.free(resp);
        httpJsonResponse(&stream, "200 OK", resp);
        return;
    }
    if (std.mem.startsWith(u8, first_line, "POST /api/action")) {
        const body = extractHttpBody(request_buf);
        const trimmed = std.mem.trim(u8, body, " \r\n\t");
        if (trimmed.len == 0) {
            httpJsonResponse(&stream, "400 Bad Request", "{\"success\":false,\"error\":\"empty body\"}");
            return;
        }

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{ .allocate = .alloc_always }) catch {
            httpJsonResponse(&stream, "400 Bad Request", "{\"success\":false,\"error\":\"invalid json\"}");
            return;
        };
        defer parsed.deinit();

        const action = protocol.payloadString(parsed.value, "action") orelse {
            httpJsonResponse(&stream, "400 Bad Request", "{\"success\":false,\"error\":\"missing action\"}");
            return;
        };

        const allowed =
            std.mem.eql(u8, action, "start") or
            std.mem.eql(u8, action, "stop") or
            std.mem.eql(u8, action, "restart") or
            std.mem.eql(u8, action, "reload") or
            std.mem.eql(u8, action, "delete") or
            std.mem.eql(u8, action, "flush") or
            std.mem.eql(u8, action, "reset") or
            std.mem.eql(u8, action, "scale") or
            std.mem.eql(u8, action, "signal") or
            std.mem.eql(u8, action, "save") or
            std.mem.eql(u8, action, "resurrect");
        if (!allowed) {
            httpJsonResponse(&stream, "403 Forbidden", "{\"success\":false,\"error\":\"action not allowed\"}");
            return;
        }

        const fake_request = protocol.Request{
            .authToken = state.token,
            .action = action,
            .requestId = "dashboard",
            .payload = parsed.value,
        };
        const response = handleControlRequest(state, allocator, fake_request) catch {
            httpJsonResponse(&stream, "500 Internal Server Error", "{\"success\":false,\"error\":\"internal error\"}");
            return;
        };
        defer allocator.free(response);
        httpJsonResponse(&stream, "200 OK", response);
        return;
    }

    if (!std.mem.eql(u8, path, "/")) {
        if (serveDashboardAsset(allocator, &stream, path)) return;
        if (pathLooksLikeAsset(path)) {
            httpJsonResponse(&stream, "404 Not Found", "{\"success\":false,\"error\":\"asset not found\"}");
            return;
        }
    }

    const index_path = storage_mod.dashboardIndexPath(allocator) catch {
        httpHtmlResponse(&stream, "<h1>buncore dashboard unavailable</h1>");
        return;
    };
    defer allocator.free(index_path);
    const html = std.fs.cwd().readFileAlloc(allocator, index_path, 1024 * 1024) catch "<h1>buncore dashboard unavailable</h1>";
    defer if (@TypeOf(html) == []u8) allocator.free(html);
    httpHtmlResponse(&stream, html);
}

fn dashboardThread(state: *DaemonState) void {
    var server = openListen(state.dashboard_port) catch return;
    defer server.deinit();

    while (state.running) {
        const conn = server.accept() catch continue;
        _ = std.Thread.spawn(.{}, dashboardClientThread, .{ state, conn.stream }) catch conn.stream.close();
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var storage = try storage_mod.Storage.init(allocator);
    try storage.ensure();
    const token = storage.readToken(allocator) catch blk: {
        const new_token = try storage_mod.randomToken(allocator);
        try storage.writeToken(new_token);
        break :blk new_token;
    };

    const port = try choosePort(9616);
    const dashboard_port = try choosePort(9716);

    var state = DaemonState{
        .allocator = allocator,
        .storage = storage,
        .token = token,
        .host = "127.0.0.1",
        .port = port,
        .dashboard_port = dashboard_port,
        .processes = std.ArrayList(*ManagedProcess).init(allocator),
    };
    defer state.deinit();

    try state.storage.writeDaemonInfo(.{
        .host = state.host,
        .port = state.port,
        .pid = @intCast(std.os.linux.getpid()),
        .dashboard_port = state.dashboard_port,
        .token_preview = if (state.token.len >= 8) state.token[0..8] else state.token,
        .started_at = storage_mod.timestampMs(),
    });

    var control_server = try openListen(port);
    defer control_server.deinit();

    _ = try std.Thread.spawn(.{}, genericMetricsThread, .{&state});
    _ = try std.Thread.spawn(.{}, watchThread, .{&state});
    _ = try std.Thread.spawn(.{}, dashboardThread, .{&state});

    while (state.running) {
        const connection = control_server.accept() catch continue;
        _ = try std.Thread.spawn(.{}, routeClientThread, .{ &state, connection.stream });
    }

    std.fs.deleteFileAbsolute(state.storage.daemon_file) catch {};
}
