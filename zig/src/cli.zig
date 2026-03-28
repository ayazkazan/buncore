const std = @import("std");
const storage_mod = @import("storage");
const protocol = @import("protocol");
const render = @import("render");

const Allocator = std.mem.Allocator;
const JsonObject = std.json.ObjectMap;
const StdoutWriter = @TypeOf(std.io.getStdOut().writer());
const StderrWriter = @TypeOf(std.io.getStdErr().writer());

const Response = struct {
    success: bool,
    requestId: ?[]const u8 = null,
    data: std.json.Value = .null,
    @"error": ?[]const u8 = null,
};

const TableMode = enum { snapshot, monitor };

fn stdoutWriter() StdoutWriter {
    return std.io.getStdOut().writer();
}

fn stderrWriter() StderrWriter {
    return std.io.getStdErr().writer();
}

fn fail(msg: []const u8) error{InvalidArgument} {
    render.writeError(stderrWriter(), msg) catch {};
    return error.InvalidArgument;
}

fn failFmt(comptime fmt: []const u8, args: anytype) error{InvalidArgument} {
    render.writeErrorFmt(stderrWriter(), fmt, args) catch {};
    return error.InvalidArgument;
}

fn writeHero(writer: anytype, title: []const u8, subtitle: []const u8) !void {
    const width: usize = 66;
    try render.writeDblBoxTop(writer, width);
    try render.writeDblBoxMid(writer, title, width);
    try render.writeDblBoxMid(writer, subtitle, width);
    try render.writeDblBoxBottom(writer, width);
}

fn writeSectionTitle(writer: anytype, title: []const u8) !void {
    try writer.writeByte('\n');
    try writer.writeAll("  ");
    try render.writeColored(writer, render.BOLD_CYAN, title);
    try writer.writeByte('\n');
}

fn writeCommandEntry(writer: anytype, syntax: []const u8, description: []const u8) !void {
    try writer.writeAll("  ");
    try render.writeColoredPadLeft(writer, render.BOLD_WHITE, syntax, 62);
    try writer.writeByte(' ');
    try render.writeMuted(writer, description);
    try writer.writeByte('\n');
}

fn writeHelp(writer: anytype) !void {
    try writeHero(writer, "BPM2 CONTROL SURFACE", "Independent Zig process manager for Bun workloads");
    try writer.writeByte('\n');
    try render.writePill(writer, render.BOLD_GREEN, "Launch");
    try writer.writeByte(' ');
    try render.writePill(writer, render.BOLD_CYAN, "Observe");
    try writer.writeByte(' ');
    try render.writePill(writer, render.BOLD_YELLOW, "Inspect");
    try writer.writeByte(' ');
    try render.writePill(writer, render.BOLD_BLUE, "Persist");
    try writer.writeByte('\n');

    try writeSectionTitle(writer, "Lifecycle");
    try writeCommandEntry(writer, "bpm2 start <script|config> [--name <name>] [--watch]", "Launch a script, JSON/JSONC manifest, or ecosystem config");
    try writeCommandEntry(writer, "bpm2 stop <name|id|all>", "Gracefully stop one process, a group, or the full fleet");
    try writeCommandEntry(writer, "bpm2 restart <name|id|all>", "Restart matching processes without losing daemon state");
    try writeCommandEntry(writer, "bpm2 reload <name|id|all>", "Graceful rolling reload with zero-downtime instance replacement");
    try writeCommandEntry(writer, "bpm2 delete <name|id|all>", "Remove processes from management after stopping them");
    try writeCommandEntry(writer, "bpm2 flush [name|id|all]", "Clear combined log files for the selected process scope");
    try writeCommandEntry(writer, "bpm2 scale <name> <count>", "Dynamically scale instances up or down at runtime");
    try writeCommandEntry(writer, "bpm2 signal <signal> <name|id>", "Send a signal (SIGUSR1, SIGUSR2, etc.) to a process");
    try writeCommandEntry(writer, "bpm2 reset <name|id|all>", "Reset restart counters and backoff state");

    try writeSectionTitle(writer, "Fleet Views");
    try writeCommandEntry(writer, "bpm2 list", "Snapshot table with status, CPU, RAM, heap, and restart pressure");
    try writeCommandEntry(writer, "bpm2 monit", "Live terminal monitor that refreshes every second");
    try writeCommandEntry(writer, "bpm2 info <name|id>", "Detailed runtime, lifecycle, and watcher diagnostics");
    try writeCommandEntry(writer, "bpm2 logs <name|id> [--lines <n>] [--follow]", "Structured stdout/stderr tail with stream labels");
    try writeCommandEntry(writer, "bpm2 dashboard", "Print the web dashboard URL and monitoring API endpoints");

    try writeSectionTitle(writer, "Diagnostics");
    try writeCommandEntry(writer, "bpm2 heap <name|id> [--jsc]", "Capture a heap snapshot through the Bun preload agent");
    try writeCommandEntry(writer, "bpm2 heap-analyze <name|id> [--jsc]", "Run heap analysis and print artifact metadata");
    try writeCommandEntry(writer, "bpm2 profile <name|id> [--duration <seconds>]", "Capture a CPU profile for the selected process");
    try writeCommandEntry(writer, "bpm2 ping", "Verify that the daemon control plane is reachable");

    try writeSectionTitle(writer, "Persistence");
    try writeCommandEntry(writer, "bpm2 save", "Save the current managed fleet to ~/.bpm2/state.json");
    try writeCommandEntry(writer, "bpm2 resurrect", "Restore the last saved fleet from ~/.bpm2/state.json");
    try writeCommandEntry(writer, "bpm2 startup", "Generate a system boot script so saved fleet auto-starts");
    try writeCommandEntry(writer, "bpm2 unstartup", "Remove the system boot script created by startup");
    try writeCommandEntry(writer, "bpm2 kill", "Stop managed processes and shut the daemon down");
    try writeCommandEntry(writer, "bpm2 update", "Seamless daemon update: save, kill, respawn, resurrect");
    try writeCommandEntry(writer, "bpm2 ecosystem", "Generate an ecosystem.config.ts starter template");

    try writeSectionTitle(writer, "Examples");
    try writeCommandEntry(writer, "bpm2 start fixtures/test-app.ts --name api --watch", "Launch the sample app with automatic restart on file changes");
    try writeCommandEntry(writer, "bpm2 logs api --lines 200 --follow", "Tail the last 200 lines and stay attached to the stream");
    try writeCommandEntry(writer, "bpm2 profile api --duration 15", "Capture a 15-second CPU profile for later analysis");
}

fn printHelp() !void {
    try writeHelp(stdoutWriter());
}

fn hasFlag(args: [][]u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn flagValue(args: [][]u8, long: []const u8, short: ?[]const u8) ?[]const u8 {
    for (args, 0..) |arg, idx| {
        if (std.mem.eql(u8, arg, long) or (short != null and std.mem.eql(u8, arg, short.?))) {
            if (idx + 1 < args.len) return args[idx + 1];
        }
    }
    return null;
}

fn readResponse(allocator: Allocator, stream: std.net.Stream) !Response {
    const body = try stream.reader().readAllAlloc(allocator, 4 * 1024 * 1024);
    if (body.len == 0) return error.ConnectionResetByPeer;
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(Response, allocator, std.mem.trim(u8, body, " \r\n\t"), .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    return parsed.value;
}

fn sendRequest(allocator: Allocator, storage: storage_mod.Storage, action: []const u8, payload_json: []const u8) !Response {
    const info = try storage.readDaemonInfo(allocator);
    const token = try storage.readToken(allocator);
    defer allocator.free(token);
    const stream = try std.net.tcpConnectToHost(allocator, info.host, info.port);
    defer stream.close();
    const request_id = try std.fmt.allocPrint(allocator, "{d}", .{storage_mod.timestampMs()});
    defer allocator.free(request_id);
    try stream.writer().print("{{\"authToken\":{s},\"action\":{s},\"requestId\":{s},\"payload\":{s}}}\n", .{
        try std.json.stringifyAlloc(allocator, token, .{}),
        try std.json.stringifyAlloc(allocator, action, .{}),
        try std.json.stringifyAlloc(allocator, request_id, .{}),
        payload_json,
    });
    return readResponse(allocator, stream);
}

fn daemonBinaryPath(allocator: Allocator) ![]u8 {
    const exe = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe);
    const dir = std.fs.path.dirname(exe) orelse return error.FileNotFound;
    return std.fs.path.join(allocator, &.{ dir, "bpm2d" });
}

fn ensureDaemon(allocator: Allocator, storage: storage_mod.Storage) !void {
    const info = storage.readDaemonInfo(allocator) catch {
        try spawnDaemon(allocator);
        try waitForDaemon(allocator, storage);
        return;
    };
    _ = info;
    const response = sendRequest(allocator, storage, "ping", "{}") catch {
        try spawnDaemon(allocator);
        try waitForDaemon(allocator, storage);
        return;
    };
    if (!response.success) {
        try spawnDaemon(allocator);
        try waitForDaemon(allocator, storage);
    }
}

fn spawnDaemon(allocator: Allocator) !void {
    const path = try daemonBinaryPath(allocator);
    defer allocator.free(path);
    const argv = if (@import("builtin").os.tag == .windows)
        &[_][]const u8{path}
    else
        &[_][]const u8{ "setsid", path };
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
}

fn waitForDaemon(allocator: Allocator, storage: storage_mod.Storage) !void {
    var attempts: usize = 0;
    while (attempts < 40) : (attempts += 1) {
        std.time.sleep(150 * std.time.ns_per_ms);
        const response = sendRequest(allocator, storage, "ping", "{}") catch continue;
        if (response.success) return;
    }
    return error.ConnectionRefused;
}

fn jsonStringAlloc(allocator: Allocator, value: []const u8) ![]u8 {
    return std.json.stringifyAlloc(allocator, value, .{});
}

fn startPayloadJson(allocator: Allocator, args: [][]u8) ![]u8 {
    const script = args[1];
    const name = flagValue(args, "--name", "-n") orelse std.fs.path.stem(script);
    const cwd = flagValue(args, "--cwd", null) orelse ".";
    const interpreter = flagValue(args, "--interpreter", null);
    const instances = flagValue(args, "--instances", "-i") orelse "1";
    const max_memory = flagValue(args, "--max-memory", null) orelse "0";
    const env_flag = flagValue(args, "--env", null);
    const watch_path = flagValue(args, "--watch-path", null);
    const ignore_watch_flag = flagValue(args, "--ignore-watch", null);
    const watch = hasFlag(args, "--watch") or hasFlag(args, "-w");
    const out_file = flagValue(args, "--out-file", "-o");
    const error_file = flagValue(args, "--error-file", "-e");
    const exec_mode = flagValue(args, "--exec-mode", null);
    const exp_backoff = flagValue(args, "--exp-backoff-restart-delay", null) orelse "0";
    const cron_restart = flagValue(args, "--cron-restart", null);
    const max_log_size = flagValue(args, "--max-log-size", null) orelse "0";
    const kill_timeout = flagValue(args, "--kill-timeout", null) orelse "6000";

    var extra_args = std.ArrayList([]const u8).init(allocator);
    defer extra_args.deinit();
    var past_double_dash = false;
    for (args[2..]) |arg| {
        if (past_double_dash) {
            try extra_args.append(arg);
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            past_double_dash = true;
        }
    }

    var env_pairs = std.ArrayList([]const u8).init(allocator);
    defer env_pairs.deinit();
    if (env_flag) |value| {
        var split = std.mem.splitScalar(u8, value, ',');
        while (split.next()) |part| {
            if (part.len > 0) try env_pairs.append(part);
        }
    }

    var ignore_watch = std.ArrayList([]const u8).init(allocator);
    defer ignore_watch.deinit();
    if (ignore_watch_flag) |value| {
        var split = std.mem.splitScalar(u8, value, ',');
        while (split.next()) |part| {
            if (part.len > 0) try ignore_watch.append(part);
        }
    }

    const args_json = try std.json.stringifyAlloc(allocator, extra_args.items, .{});
    defer allocator.free(args_json);
    const env_json = try std.json.stringifyAlloc(allocator, env_pairs.items, .{});
    defer allocator.free(env_json);
    const ignore_watch_json = try std.json.stringifyAlloc(allocator, ignore_watch.items, .{});
    defer allocator.free(ignore_watch_json);
    const name_json = try jsonStringAlloc(allocator, name);
    defer allocator.free(name_json);
    const script_json = try jsonStringAlloc(allocator, script);
    defer allocator.free(script_json);
    const cwd_json = try jsonStringAlloc(allocator, cwd);
    defer allocator.free(cwd_json);
    const interpreter_json = if (interpreter) |value| try jsonStringAlloc(allocator, value) else try allocator.dupe(u8, "null");
    defer allocator.free(interpreter_json);
    const watch_path_json = if (watch_path) |value| try jsonStringAlloc(allocator, value) else try allocator.dupe(u8, "null");
    defer allocator.free(watch_path_json);
    const out_file_json = if (out_file) |value| try jsonStringAlloc(allocator, value) else try allocator.dupe(u8, "null");
    defer allocator.free(out_file_json);
    const error_file_json = if (error_file) |value| try jsonStringAlloc(allocator, value) else try allocator.dupe(u8, "null");
    defer allocator.free(error_file_json);
    const exec_mode_json = if (exec_mode) |value| try jsonStringAlloc(allocator, value) else try allocator.dupe(u8, "null");
    defer allocator.free(exec_mode_json);
    const cron_restart_json = if (cron_restart) |value| try jsonStringAlloc(allocator, value) else try allocator.dupe(u8, "null");
    defer allocator.free(cron_restart_json);
    return std.fmt.allocPrint(allocator,
        "{{\"name\":{s},\"script\":{s},\"cwd\":{s},\"interpreter\":{s},\"args\":{s},\"envPairs\":{s},\"instances\":{s},\"watch\":{s},\"watchPath\":{s},\"ignoreWatch\":{s},\"maxMemoryRestart\":{s},\"autorestart\":true,\"maxRestarts\":15,\"minUptime\":1000,\"restartDelay\":100,\"outFile\":{s},\"errorFile\":{s},\"execMode\":{s},\"expBackoffRestartDelay\":{s},\"cronRestart\":{s},\"maxLogSize\":{s},\"killTimeout\":{s}}}",
        .{
            name_json,
            script_json,
            cwd_json,
            interpreter_json,
            args_json,
            env_json,
            instances,
            if (watch) "true" else "false",
            watch_path_json,
            ignore_watch_json,
            max_memory,
            out_file_json,
            error_file_json,
            exec_mode_json,
            exp_backoff,
            cron_restart_json,
            max_log_size,
            kill_timeout,
        },
    );
}

fn objectString(obj: JsonObject, key: []const u8, fallback: []const u8) []const u8 {
    if (obj.get(key)) |value| {
        if (value == .string) return value.string;
    }
    return fallback;
}

fn objectBool(obj: JsonObject, key: []const u8, fallback: bool) bool {
    if (obj.get(key)) |value| {
        if (value == .bool) return value.bool;
    }
    return fallback;
}

fn objectInt(obj: JsonObject, key: []const u8) ?i64 {
    if (obj.get(key)) |value| {
        return switch (value) {
            .integer => value.integer,
            else => null,
        };
    }
    return null;
}

fn objectUInt(obj: JsonObject, key: []const u8) ?u64 {
    if (obj.get(key)) |value| {
        return switch (value) {
            .integer => if (value.integer >= 0) @intCast(value.integer) else null,
            else => null,
        };
    }
    return null;
}

fn valueToF64(value: std.json.Value) ?f64 {
    return switch (value) {
        .float => value.float,
        .integer => @floatFromInt(value.integer),
        else => null,
    };
}

fn objectNumber(obj: JsonObject, key: []const u8) ?f64 {
    if (obj.get(key)) |value| return valueToF64(value);
    return null;
}

fn objectObject(obj: JsonObject, key: []const u8) ?JsonObject {
    if (obj.get(key)) |value| {
        if (value == .object) return value.object;
    }
    return null;
}

fn truncateAlloc(allocator: Allocator, text: []const u8, max_len: usize) ![]u8 {
    if (text.len <= max_len) return allocator.dupe(u8, text);
    if (max_len <= 3) return allocator.dupe(u8, text[0..max_len]);
    return std.fmt.allocPrint(allocator, "{s}...", .{text[0 .. max_len - 3]});
}

fn formatSignedOpt(allocator: Allocator, value: ?i64, fallback: []const u8) ![]u8 {
    if (value) |current| return std.fmt.allocPrint(allocator, "{d}", .{current});
    return allocator.dupe(u8, fallback);
}

fn formatPercentOpt(allocator: Allocator, value: ?f64) ![]u8 {
    if (value) |current| return std.fmt.allocPrint(allocator, "{d:.1}%", .{current});
    return allocator.dupe(u8, "N/A");
}

fn formatMillisecondsOpt(allocator: Allocator, value: ?f64) ![]u8 {
    if (value) |current| return std.fmt.allocPrint(allocator, "{d:.2} ms", .{current});
    return allocator.dupe(u8, "N/A");
}

fn formatHeapPair(allocator: Allocator, used: ?u64, total: ?u64) ![]u8 {
    const used_text = try render.formatBytes(allocator, used);
    defer allocator.free(used_text);
    const total_text = try render.formatBytes(allocator, total);
    defer allocator.free(total_text);
    return std.fmt.allocPrint(allocator, "{s} / {s}", .{ used_text, total_text });
}

fn formatTimestampOpt(allocator: Allocator, value: ?i64) ![]u8 {
    if (value) |current| return render.formatTimestamp(allocator, current);
    return allocator.dupe(u8, "-");
}

fn formatUptimeForProcess(allocator: Allocator, status: []const u8, started_at: ?i64, stopped_at: ?i64) ![]u8 {
    if (started_at == null) return allocator.dupe(u8, "-");
    const now_ms: i64 = @intCast(std.time.milliTimestamp());
    const end_ms = if (std.mem.eql(u8, status, "online"))
        now_ms
    else if (stopped_at) |stopped|
        stopped
    else
        now_ms;
    return render.formatUptime(allocator, end_ms - started_at.?);
}

fn actionTitle(command: []const u8) []const u8 {
    if (std.mem.eql(u8, command, "stop")) return "Stop";
    if (std.mem.eql(u8, command, "restart")) return "Restart";
    if (std.mem.eql(u8, command, "reload")) return "Reload";
    if (std.mem.eql(u8, command, "delete")) return "Delete";
    if (std.mem.eql(u8, command, "flush")) return "Flush";
    if (std.mem.eql(u8, command, "save")) return "Save";
    if (std.mem.eql(u8, command, "resurrect")) return "Resurrect";
    if (std.mem.eql(u8, command, "kill")) return "Shutdown";
    return "Action";
}

fn cpuColor(value: ?f64) []const u8 {
    if (value == null) return render.GRAY;
    if (value.? < 50.0) return render.BOLD_GREEN;
    if (value.? < 80.0) return render.BOLD_YELLOW;
    return render.BOLD_RED;
}

fn latencyColor(value: ?f64) []const u8 {
    if (value == null) return render.GRAY;
    if (value.? < 20.0) return render.BOLD_GREEN;
    if (value.? < 80.0) return render.BOLD_YELLOW;
    return render.BOLD_RED;
}

fn restartColor(value: ?i64) []const u8 {
    if (value == null) return render.GRAY;
    if (value.? == 0) return render.BOLD_GREEN;
    if (value.? <= 2) return render.BOLD_YELLOW;
    return render.BOLD_RED;
}

fn exitCodeColor(value: ?i64) []const u8 {
    if (value == null) return render.GRAY;
    if (value.? == 0) return render.BOLD_GREEN;
    return render.BOLD_RED;
}

fn boolText(value: bool) []const u8 {
    return if (value) "enabled" else "disabled";
}

fn boolColor(value: bool) []const u8 {
    return if (value) render.BOLD_GREEN else render.GRAY;
}

fn writeTableLeftCell(writer: anytype, text: []const u8, color: []const u8, width: usize) !void {
    try render.writeCellSep(writer);
    try writer.writeByte(' ');
    try render.writeColoredPadLeft(writer, color, text, width);
    try writer.writeByte(' ');
}

fn writeTableRightCell(writer: anytype, text: []const u8, color: []const u8, width: usize) !void {
    try render.writeCellSep(writer);
    try writer.writeByte(' ');
    try render.writeColoredPadRight(writer, color, text, width);
    try writer.writeByte(' ');
}

fn writeProcessTableHeader(writer: anytype, widths: []const usize) !void {
    try render.writeTableBorder(writer, widths, .top);
    try writeTableRightCell(writer, "ID", render.GRAY, widths[0]);
    try writeTableLeftCell(writer, "Process", render.GRAY, widths[1]);
    try writeTableLeftCell(writer, "State", render.GRAY, widths[2]);
    try writeTableRightCell(writer, "PID", render.GRAY, widths[3]);
    try writeTableRightCell(writer, "CPU", render.GRAY, widths[4]);
    try writeTableRightCell(writer, "RSS", render.GRAY, widths[5]);
    try writeTableRightCell(writer, "Heap", render.GRAY, widths[6]);
    try writeTableRightCell(writer, "Restart", render.GRAY, widths[7]);
    try render.writeCellSep(writer);
    try writer.writeByte('\n');
    try render.writeTableBorder(writer, widths, .mid);
}

fn writeProcessTableRow(allocator: Allocator, writer: anytype, item: std.json.Value, widths: []const usize) !void {
    if (item != .object) return;
    const obj = item.object;
    const summary = objectObject(obj, "summary");

    const id_text = try formatSignedOpt(allocator, objectInt(obj, "id"), "-");
    defer allocator.free(id_text);
    const name_text = try truncateAlloc(allocator, objectString(obj, "name", "-"), widths[1]);
    defer allocator.free(name_text);
    const status = objectString(obj, "status", "unknown");
    const status_text = try truncateAlloc(allocator, status, widths[2]);
    defer allocator.free(status_text);
    const pid_text = try formatSignedOpt(allocator, objectInt(obj, "pid"), "-");
    defer allocator.free(pid_text);

    const cpu_percent = if (summary) |info| objectNumber(info, "cpuPercent") else null;
    const cpu_text = try formatPercentOpt(allocator, cpu_percent);
    defer allocator.free(cpu_text);

    const rss_text = try render.formatBytes(allocator, if (summary) |info| objectUInt(info, "rss") else null);
    defer allocator.free(rss_text);
    const heap_text = try render.formatBytes(allocator, if (summary) |info| objectUInt(info, "heapUsed") else null);
    defer allocator.free(heap_text);
    const restart_text = try formatSignedOpt(allocator, objectInt(obj, "restarts"), "0");
    defer allocator.free(restart_text);

    try writeTableRightCell(writer, id_text, render.SOFT, widths[0]);
    try writeTableLeftCell(writer, name_text, render.BOLD_WHITE, widths[1]);
    try writeTableLeftCell(writer, status_text, render.statusColor(status), widths[2]);
    try writeTableRightCell(writer, pid_text, render.SOFT, widths[3]);
    try writeTableRightCell(writer, cpu_text, cpuColor(cpu_percent), widths[4]);
    try writeTableRightCell(writer, rss_text, render.SOFT, widths[5]);
    try writeTableRightCell(writer, heap_text, render.SOFT, widths[6]);
    try writeTableRightCell(writer, restart_text, restartColor(objectInt(obj, "restarts")), widths[7]);
    try render.writeCellSep(writer);
    try writer.writeByte('\n');
}

fn printEmptyFleet(mode: TableMode) !void {
    const out = stdoutWriter();
    if (mode == .monitor) {
        try writeHero(out, "BPM2 LIVE MONITOR", "Terminal fleet view with per-second refresh");
    } else {
        try writeHero(out, "BPM2 FLEET SNAPSHOT", "Process inventory and runtime pressure overview");
    }
    try out.writeByte('\n');
    try render.writeWarning(out, "No processes are being managed right now.");
    try render.writeInfoMsg(out, "Launch one with: bpm2 start <script> --name api");
}

fn printFleetSummary(allocator: Allocator, processes: []const std.json.Value, mode: TableMode) !void {
    const out = stdoutWriter();
    if (mode == .monitor) {
        try writeHero(out, "BPM2 LIVE MONITOR", "Terminal fleet view with per-second refresh");
    } else {
        try writeHero(out, "BPM2 FLEET SNAPSHOT", "Process inventory and runtime pressure overview");
    }
    try out.writeByte('\n');

    var online_count: usize = 0;
    var watch_count: usize = 0;
    var alert_count: usize = 0;
    var total_cpu: f64 = 0.0;
    var total_rss: u64 = 0;

    for (processes) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const status = objectString(obj, "status", "unknown");
        if (std.mem.eql(u8, status, "online")) {
            online_count += 1;
        } else if (!std.mem.eql(u8, status, "launching")) {
            alert_count += 1;
        }
        if (objectBool(obj, "watchEnabled", false)) watch_count += 1;
        if (objectObject(obj, "summary")) |summary| {
            total_cpu += objectNumber(summary, "cpuPercent") orelse 0.0;
            total_rss += objectUInt(summary, "rss") orelse 0;
        }
    }

    const fleet_text = try std.fmt.allocPrint(allocator, "Fleet {d}", .{processes.len});
    defer allocator.free(fleet_text);
    const online_text = try std.fmt.allocPrint(allocator, "Online {d}", .{online_count});
    defer allocator.free(online_text);
    const cpu_text = try std.fmt.allocPrint(allocator, "CPU {d:.1}%", .{total_cpu});
    defer allocator.free(cpu_text);
    const total_rss_bytes = try render.formatBytes(allocator, total_rss);
    defer allocator.free(total_rss_bytes);
    const rss_text = try std.fmt.allocPrint(allocator, "RSS {s}", .{total_rss_bytes});
    defer allocator.free(rss_text);
    const watch_text = try std.fmt.allocPrint(allocator, "Watch {d}", .{watch_count});
    defer allocator.free(watch_text);
    const alert_text = try std.fmt.allocPrint(allocator, "Alerts {d}", .{alert_count});
    defer allocator.free(alert_text);
    const updated_at = try render.formatTimestamp(allocator, storage_mod.timestampMs());
    defer allocator.free(updated_at);
    const updated_text = try std.fmt.allocPrint(allocator, "Updated {s}", .{updated_at});
    defer allocator.free(updated_text);

    try render.writePill(out, render.BOLD_CYAN, fleet_text);
    try out.writeByte(' ');
    try render.writePill(out, render.BOLD_GREEN, online_text);
    try out.writeByte(' ');
    try render.writePill(out, cpuColor(total_cpu), cpu_text);
    try out.writeByte(' ');
    try render.writePill(out, render.SOFT, rss_text);
    try out.writeByte(' ');
    try render.writePill(out, render.BOLD_BLUE, watch_text);
    try out.writeByte(' ');
    try render.writePill(out, if (alert_count == 0) render.BOLD_GREEN else render.BOLD_YELLOW, alert_text);
    try out.writeByte('\n');

    try render.writePill(out, if (mode == .monitor) render.BOLD_YELLOW else render.BOLD_BLUE, if (mode == .monitor) "Live refresh 1s" else "One-shot snapshot");
    try out.writeByte(' ');
    try render.writePill(out, render.SOFT, updated_text);
    try out.writeByte('\n');
}

fn printProcessTableView(allocator: Allocator, response: Response, mode: TableMode) !void {
    if (response.data != .object) {
        try printEmptyFleet(mode);
        return;
    }

    const processes = response.data.object.get("processes") orelse {
        try printEmptyFleet(mode);
        return;
    };

    if (processes != .array or processes.array.items.len == 0) {
        try printEmptyFleet(mode);
        return;
    }

    try printFleetSummary(allocator, processes.array.items, mode);
    try stdoutWriter().writeByte('\n');

    const widths = [_]usize{ 3, 18, 11, 7, 7, 10, 10, 8 };
    const out = stdoutWriter();
    try writeProcessTableHeader(out, widths[0..]);
    for (processes.array.items) |item| {
        try writeProcessTableRow(allocator, out, item, widths[0..]);
    }
    try render.writeTableBorder(out, widths[0..], .bottom);
}

fn printRawJson(response: Response) !void {
    const writer = stdoutWriter();
    try std.json.stringify(response.data, .{ .whitespace = .indent_2 }, writer);
    try writer.writeByte('\n');
}

fn printProcessTable(allocator: Allocator, response: Response) !void {
    try printProcessTableView(allocator, response, .snapshot);
}

fn printInfo(allocator: Allocator, response: Response) !void {
    if (response.data != .object) return;

    const out = stdoutWriter();
    const obj = response.data.object;
    const summary = objectObject(obj, "summary");
    const details = objectObject(obj, "details");

    const name = objectString(obj, "name", "process");
    const status = objectString(obj, "status", "unknown");
    const hero_name = try truncateAlloc(allocator, name, 58);
    defer allocator.free(hero_name);

    const pid_text = try formatSignedOpt(allocator, objectInt(obj, "pid"), "-");
    defer allocator.free(pid_text);
    const cpu_text = try formatPercentOpt(allocator, if (summary) |info| objectNumber(info, "cpuPercent") else null);
    defer allocator.free(cpu_text);
    const rss_text = try render.formatBytes(allocator, if (summary) |info| objectUInt(info, "rss") else null);
    defer allocator.free(rss_text);
    const heap_text = try formatHeapPair(allocator, if (summary) |info| objectUInt(info, "heapUsed") else null, if (summary) |info| objectUInt(info, "heapTotal") else null);
    defer allocator.free(heap_text);
    const lag_text = try formatMillisecondsOpt(allocator, if (summary) |info| objectNumber(info, "runtimeLagMs") else null);
    defer allocator.free(lag_text);

    const script_text = try truncateAlloc(allocator, objectString(obj, "script", "-"), 62);
    defer allocator.free(script_text);
    const cwd_text = try truncateAlloc(allocator, objectString(obj, "cwd", "-"), 62);
    defer allocator.free(cwd_text);

    const created_text = try formatTimestampOpt(allocator, objectInt(obj, "createdAt"));
    defer allocator.free(created_text);
    const started_text = try formatTimestampOpt(allocator, objectInt(obj, "startedAt"));
    defer allocator.free(started_text);
    const stopped_text = try formatTimestampOpt(allocator, objectInt(obj, "stoppedAt"));
    defer allocator.free(stopped_text);
    const uptime_text = try formatUptimeForProcess(allocator, status, objectInt(obj, "startedAt"), objectInt(obj, "stoppedAt"));
    defer allocator.free(uptime_text);
    const restarts_text = try formatSignedOpt(allocator, objectInt(obj, "restarts"), "0");
    defer allocator.free(restarts_text);
    const last_exit_text = try formatSignedOpt(allocator, objectInt(obj, "lastExitCode"), "-");
    defer allocator.free(last_exit_text);

    const jsc_heap_size_text = try render.formatBytes(allocator, if (details) |info| blk: {
        if (objectObject(info, "jscHeapStats")) |jsc| break :blk objectUInt(jsc, "heapSize");
        break :blk null;
    } else null);
    defer allocator.free(jsc_heap_size_text);
    const jsc_object_count_text = try formatSignedOpt(allocator, if (details) |info| blk: {
        if (objectObject(info, "jscHeapStats")) |jsc| break :blk objectInt(jsc, "objectCount");
        break :blk null;
    } else null, "N/A");
    defer allocator.free(jsc_object_count_text);

    try writeHero(out, "BPM2 PROCESS PROFILE", hero_name);
    try out.writeByte('\n');

    const status_pill = try std.fmt.allocPrint(allocator, "Status {s}", .{status});
    defer allocator.free(status_pill);
    const pid_pill = try std.fmt.allocPrint(allocator, "PID {s}", .{pid_text});
    defer allocator.free(pid_pill);
    const runtime_pill = try std.fmt.allocPrint(allocator, "Runtime {s}", .{objectString(obj, "runtime", "-")});
    defer allocator.free(runtime_pill);
    const watch_pill = try std.fmt.allocPrint(allocator, "Watch {s}", .{boolText(objectBool(obj, "watchEnabled", false))});
    defer allocator.free(watch_pill);

    try render.writePill(out, render.statusColor(status), status_pill);
    try out.writeByte(' ');
    try render.writePill(out, render.SOFT, pid_pill);
    try out.writeByte(' ');
    try render.writePill(out, render.BOLD_CYAN, runtime_pill);
    try out.writeByte(' ');
    try render.writePill(out, boolColor(objectBool(obj, "watchEnabled", false)), watch_pill);
    try out.writeByte('\n');
    try out.print("PID: {s}\n", .{pid_text});
    try out.writeByte('\n');

    const row_width: usize = 78;
    try render.writeBoxTop(out, "Process Identity", row_width);
    try render.writeBoxKV2(out, "Name:", name, render.BOLD_WHITE, "Status:", status, render.statusColor(status), row_width);
    try render.writeBoxKV2(out, "PID:", pid_text, render.SOFT, "Runtime:", objectString(obj, "runtime", "-"), render.BOLD_CYAN, row_width);
    try render.writeBoxKV(out, "Script:", script_text, render.SOFT, row_width);
    try render.writeBoxKV(out, "CWD:", cwd_text, render.SOFT, row_width);

    try render.writeBoxSep(out, "Runtime Health", row_width);
    try render.writeBoxKV2(out, "CPU:", cpu_text, cpuColor(if (summary) |info| objectNumber(info, "cpuPercent") else null), "RAM (RSS):", rss_text, render.SOFT, row_width);
    try render.writeBoxKV2(out, "JSC Heap:", heap_text, render.SOFT, "Runtime Lag:", lag_text, latencyColor(if (summary) |info| objectNumber(info, "runtimeLagMs") else null), row_width);
    try render.writeBoxKV2(out, "JSC Heap Size:", jsc_heap_size_text, render.SOFT, "JSC Objects:", jsc_object_count_text, render.SOFT, row_width);

    try render.writeBoxSep(out, "Lifecycle", row_width);
    try render.writeBoxKV2(out, "Created:", created_text, render.SOFT, "Started:", started_text, render.SOFT, row_width);
    try render.writeBoxKV2(out, "Uptime:", uptime_text, render.BOLD_CYAN, "Restarts:", restarts_text, restartColor(objectInt(obj, "restarts")), row_width);
    try render.writeBoxKV2(out, "Stopped:", stopped_text, render.SOFT, "Last Exit:", last_exit_text, exitCodeColor(objectInt(obj, "lastExitCode")), row_width);

    try render.writeBoxSep(out, "Watcher", row_width);
    try render.writeBoxKV2(out, "Watch:", boolText(objectBool(obj, "watchEnabled", false)), boolColor(objectBool(obj, "watchEnabled", false)), "Platform:", objectString(obj, "platform", "-"), render.SOFT, row_width);
    try render.writeBoxKV2(out, "Strategy:", objectString(obj, "watchStrategy", "-"), render.SOFT, "Preferred:", objectString(obj, "watchPreferredStrategy", "-"), render.SOFT, row_width);
    try render.writeBoxBottom(out, row_width);
}

fn printJsonValue(value: std.json.Value) !void {
    try std.json.stringify(value, .{ .whitespace = .indent_2 }, stdoutWriter());
    try stdoutWriter().writeByte('\n');
}

fn printJsonPanel(title: []const u8, subtitle: []const u8, value: std.json.Value) !void {
    const out = stdoutWriter();
    try writeHero(out, title, subtitle);
    try out.writeByte('\n');
    try printJsonValue(value);
}

fn printActionResult(command: []const u8, target: []const u8, response: Response) !void {
    const out = stdoutWriter();
    try render.writeSuccessFmt(out, "{s} completed successfully.", .{actionTitle(command)});
    if (response.data == .object) {
        const count = objectInt(response.data.object, "count") orelse 0;
        try render.writeInfoFmt(out, "Target: {s} | affected processes: {d}", .{ target, count });
        return;
    }
    try render.writeInfoFmt(out, "Target: {s}", .{target});
}

fn printLogsHeader(allocator: Allocator, target: []const u8, lines: []const u8, follow: bool, path: []const u8) !void {
    const out = stdoutWriter();
    try writeHero(out, "BPM2 LOG STREAM", "Structured stdout and stderr tail for managed processes");
    try out.writeByte('\n');

    const target_pill = try std.fmt.allocPrint(allocator, "Target {s}", .{target});
    defer allocator.free(target_pill);
    const lines_pill = try std.fmt.allocPrint(allocator, "Tail {s}", .{lines});
    defer allocator.free(lines_pill);

    try render.writePill(out, render.BOLD_CYAN, target_pill);
    try out.writeByte(' ');
    try render.writePill(out, render.SOFT, lines_pill);
    try out.writeByte(' ');
    try render.writePill(out, if (follow) render.BOLD_YELLOW else render.BOLD_BLUE, if (follow) "Mode follow" else "Mode snapshot");
    try out.writeByte('\n');

    if (path.len > 0 and !std.mem.eql(u8, path, "-")) {
        try render.writeInfoFmt(out, "Path: {s}", .{path});
    }
    try out.writeByte('\n');
}

fn printStyledLogLine(writer: anytype, line: []const u8) !void {
    if (line.len == 0) {
        try writer.writeByte('\n');
        return;
    }

    if (line[0] != '[') {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        return;
    }

    const close_idx = std.mem.indexOfScalar(u8, line, ']') orelse {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        return;
    };
    if (close_idx + 2 > line.len) {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        return;
    }

    const rest = line[close_idx + 2 ..];
    const first_space = std.mem.indexOfScalar(u8, rest, ' ') orelse {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        return;
    };
    const colon_idx = std.mem.indexOf(u8, rest, ": ") orelse {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        return;
    };
    if (colon_idx <= first_space) {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        return;
    }

    const timestamp = line[1..close_idx];
    const process_name = rest[0..first_space];
    const stream_name = rest[first_space + 1 .. colon_idx];
    const message = rest[colon_idx + 2 ..];

    const stream_color = if (std.mem.eql(u8, stream_name, "stderr"))
        render.BOLD_RED
    else if (std.mem.eql(u8, stream_name, "stdout"))
        render.BOLD_GREEN
    else
        render.BOLD_BLUE;

    try render.writeColoredFmt(writer, render.GRAY, "[{s}]", .{timestamp});
    try writer.writeByte(' ');
    try render.writeColored(writer, render.BOLD_CYAN, process_name);
    try writer.writeByte(' ');
    try render.writeColored(writer, stream_color, stream_name);
    try writer.writeAll(": ");
    try writer.writeAll(message);
    try writer.writeByte('\n');
}

fn printStyledLogChunk(writer: anytype, chunk: []const u8) !void {
    if (chunk.len == 0) return;

    var start: usize = 0;
    while (start < chunk.len) {
        const end = std.mem.indexOfScalarPos(u8, chunk, start, '\n') orelse chunk.len;
        try printStyledLogLine(writer, chunk[start..end]);
        if (end == chunk.len) break;
        start = end + 1;
    }
}

fn stripJsonCommentsAlloc(allocator: Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    var in_string = false;
    var escape = false;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (in_string) {
            try out.append(c);
            if (escape) {
                escape = false;
            } else if (c == '\\') {
                escape = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }

        if (c == '"') {
            in_string = true;
            try out.append(c);
            continue;
        }

        if (c == '/' and i + 1 < input.len and input[i + 1] == '/') {
            i += 2;
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            if (i < input.len and input[i] == '\n') try out.append('\n');
            continue;
        }

        if (c == '/' and i + 1 < input.len and input[i + 1] == '*') {
            i += 2;
            while (i + 1 < input.len and !(input[i] == '*' and input[i + 1] == '/')) : (i += 1) {
                if (input[i] == '\n') try out.append('\n');
            }
            i += 1;
            continue;
        }

        try out.append(c);
    }

    return out.toOwnedSlice();
}

fn handleConfigStart(allocator: Allocator, storage: storage_mod.Storage, target: []const u8, env_name: ?[]const u8) !void {
    if (std.mem.endsWith(u8, target, ".json") or std.mem.endsWith(u8, target, ".jsonc")) {
        const content = try std.fs.cwd().readFileAlloc(allocator, target, 1024 * 1024);
        defer allocator.free(content);
        const cleaned = try stripJsonCommentsAlloc(allocator, content);
        defer allocator.free(cleaned);
        const parsed = try std.json.parseFromSlice(struct {
            apps: []std.json.Value,
        }, allocator, cleaned, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        for (parsed.value.apps) |app| {
            const json = try std.json.stringifyAlloc(allocator, app, .{});
            const response = try sendRequest(allocator, storage, "start", json);
            allocator.free(json);
            if (!response.success) return fail(response.@"error" orelse "start failed");
        }
        return;
    }

    const loader = try storage_mod.agentConfigLoaderPath(allocator);
    defer allocator.free(loader);
    var child_args = std.ArrayList([]const u8).init(allocator);
    defer child_args.deinit();
    try child_args.appendSlice(&.{ "bun", loader, target });
    if (env_name) |env| try child_args.append(env);
    var child = std.process.Child.init(child_args.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);
    _ = try child.wait();
    const parsed = try std.json.parseFromSlice(struct {
        apps: []std.json.Value,
    }, allocator, stdout, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    for (parsed.value.apps) |app| {
        const json = try std.json.stringifyAlloc(allocator, app, .{});
        const response = try sendRequest(allocator, storage, "start", json);
        allocator.free(json);
        if (!response.success) return fail(response.@"error" orelse "start failed");
    }
}

fn writeEcosystemTemplate() !void {
    try std.fs.cwd().writeFile(.{
        .sub_path = "ecosystem.config.ts",
        .data =
        \\export default {
        \\  apps: [
        \\    {
        \\      name: "api",
        \\      script: "./fixtures/test-app.ts",
        \\      instances: 1,
        \\      watch: false,
        \\      env: {
        \\        PORT: "3388",
        \\      },
        \\    },
        \\  ],
        \\};
        ,
    });
    try render.writeSuccess(stdoutWriter(), "Created ecosystem.config.ts");
    try render.writeInfoMsg(stdoutWriter(), "Edit the template and run: bpm2 start ecosystem.config.ts");
}

fn generateStartupScript(allocator: Allocator, storage: storage_mod.Storage) !void {
    const out = stdoutWriter();
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);
    const builtin_os = @import("builtin").os.tag;

    if (builtin_os == .linux) {
        const user_env = std.process.getEnvVarOwned(allocator, "USER") catch try allocator.dupe(u8, "root");
        defer allocator.free(user_env);
        const home_env = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, "/root");
        defer allocator.free(home_env);

        const unit_content = try std.fmt.allocPrint(allocator,
            \\[Unit]
            \\Description=BPM2 process manager
            \\Documentation=https://github.com/bpm2
            \\After=network.target
            \\
            \\[Service]
            \\Type=forking
            \\User={s}
            \\Environment=HOME={s}
            \\ExecStart={s} resurrect
            \\ExecStop={s} kill
            \\Restart=on-failure
            \\RestartSec=5
            \\
            \\[Install]
            \\WantedBy=multi-user.target
            \\
        , .{ user_env, home_env, exe_path, exe_path });
        defer allocator.free(unit_content);

        const service_path = "/etc/systemd/system/bpm2.service";
        std.fs.cwd().writeFile(.{ .sub_path = service_path, .data = unit_content }) catch |err| {
            try render.writeErrorFmt(stderrWriter(), "Failed to write {s}: {s}. Try running with sudo.", .{ service_path, @errorName(err) });
            return error.InvalidArgument;
        };

        try render.writeSuccess(out, "systemd service created at /etc/systemd/system/bpm2.service");
        try render.writeInfoMsg(out, "Run the following commands to enable:");
        try render.writeInfoFmt(out, "  sudo systemctl daemon-reload", .{});
        try render.writeInfoFmt(out, "  sudo systemctl enable bpm2", .{});
        try render.writeInfoFmt(out, "  sudo systemctl start bpm2", .{});
        try render.writeInfoMsg(out, "Make sure to run 'bpm2 save' before rebooting.");
    } else if (builtin_os == .macos) {
        const home_env = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, "/Users/unknown");
        defer allocator.free(home_env);

        const plist_content = try std.fmt.allocPrint(allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            \\<plist version="1.0">
            \\<dict>
            \\  <key>Label</key>
            \\  <string>com.bpm2.agent</string>
            \\  <key>ProgramArguments</key>
            \\  <array>
            \\    <string>{s}</string>
            \\    <string>resurrect</string>
            \\  </array>
            \\  <key>RunAtLoad</key>
            \\  <true/>
            \\  <key>KeepAlive</key>
            \\  <false/>
            \\  <key>EnvironmentVariables</key>
            \\  <dict>
            \\    <key>HOME</key>
            \\    <string>{s}</string>
            \\  </dict>
            \\  <key>StandardOutPath</key>
            \\  <string>{s}/.bpm2/startup.log</string>
            \\  <key>StandardErrorPath</key>
            \\  <string>{s}/.bpm2/startup.log</string>
            \\</dict>
            \\</plist>
            \\
        , .{ exe_path, home_env, home_env, home_env });
        defer allocator.free(plist_content);

        const plist_path = try std.fmt.allocPrint(allocator, "{s}/Library/LaunchAgents/com.bpm2.agent.plist", .{home_env});
        defer allocator.free(plist_path);

        std.fs.cwd().writeFile(.{ .sub_path = plist_path, .data = plist_content }) catch |err| {
            try render.writeErrorFmt(stderrWriter(), "Failed to write {s}: {s}", .{ plist_path, @errorName(err) });
            return error.InvalidArgument;
        };

        try render.writeSuccess(out, "launchd plist created.");
        try render.writeInfoFmt(out, "Plist: {s}", .{plist_path});
        try render.writeInfoMsg(out, "Run to activate: launchctl load <plist_path>");
        try render.writeInfoMsg(out, "Make sure to run 'bpm2 save' before rebooting.");
    } else {
        try render.writeWarning(out, "Startup script generation is not supported on this platform.");
        try render.writeInfoMsg(out, "Supported platforms: Linux (systemd), macOS (launchd).");
    }
    _ = storage;
}

fn removeStartupScript(allocator: Allocator) !void {
    const out = stdoutWriter();
    const builtin_os = @import("builtin").os.tag;

    if (builtin_os == .linux) {
        std.fs.cwd().deleteFile("/etc/systemd/system/bpm2.service") catch |err| {
            try render.writeErrorFmt(stderrWriter(), "Failed to remove service file: {s}. Try running with sudo.", .{@errorName(err)});
            return error.InvalidArgument;
        };
        try render.writeSuccess(out, "systemd service removed.");
        try render.writeInfoFmt(out, "Run: sudo systemctl daemon-reload", .{});
    } else if (builtin_os == .macos) {
        const home_env = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, "/Users/unknown");
        defer allocator.free(home_env);
        const plist_path = try std.fmt.allocPrint(allocator, "{s}/Library/LaunchAgents/com.bpm2.agent.plist", .{home_env});
        defer allocator.free(plist_path);
        std.fs.cwd().deleteFile(plist_path) catch |err| {
            try render.writeErrorFmt(stderrWriter(), "Failed to remove plist: {s}", .{@errorName(err)});
            return error.InvalidArgument;
        };
        try render.writeSuccess(out, "launchd plist removed.");
    } else {
        try render.writeWarning(out, "Startup script removal is not supported on this platform.");
    }
}

fn printDashboardInfo(allocator: Allocator, host: []const u8, dashboard_port: u16) !void {
    const out = stdoutWriter();
    const url = try std.fmt.allocPrint(allocator, "http://{s}:{d}", .{ host, dashboard_port });
    defer allocator.free(url);
    const api_url = try std.fmt.allocPrint(allocator, "{s}/api/processes", .{url});
    defer allocator.free(api_url);

    try writeHero(out, "BPM2 DASHBOARD READY", "Open the web control room for live fleet visibility");
    try out.writeByte('\n');
    try render.writePill(out, render.BOLD_CYAN, "Dashboard URL");
    try out.writeByte(' ');
    try render.writeMuted(out, url);
    try out.writeByte('\n');
    try render.writePill(out, render.BOLD_BLUE, "Processes API");
    try out.writeByte(' ');
    try render.writeMuted(out, api_url);
    try out.writeByte('\n');
    try render.writeInfoFmt(out, "Dashboard: {s}", .{url});
    try render.writeInfoFmt(out, "Metrics API: {s}/api/metrics?id=<name|id>", .{url});
}

fn printArtifactResult(command: []const u8, value: std.json.Value) !void {
    if (std.mem.eql(u8, command, "heap")) {
        try printJsonPanel("BPM2 HEAP SNAPSHOT", "Raw artifact metadata and snapshot paths", value);
        return;
    }
    if (std.mem.eql(u8, command, "heap-analyze")) {
        try printJsonPanel("BPM2 HEAP ANALYSIS", "Analysis summary and generated output paths", value);
        return;
    }
    try printJsonPanel("BPM2 CPU PROFILE", "Profiler artifact metadata and capture summary", value);
}

fn printMaintenanceResult(storage: storage_mod.Storage, command: []const u8) !void {
    const out = stdoutWriter();
    if (std.mem.eql(u8, command, "save")) {
        try render.writeSuccess(out, "Fleet state saved successfully.");
        try render.writeInfoFmt(out, "State file: {s}", .{storage.state_file});
        return;
    }
    if (std.mem.eql(u8, command, "resurrect")) {
        try render.writeSuccess(out, "Saved fleet state restored successfully.");
        try render.writeInfoFmt(out, "State file: {s}", .{storage.state_file});
        return;
    }
    try render.writeSuccess(out, "Daemon shutdown requested.");
    try render.writeInfoMsg(out, "Managed processes are being stopped and the control plane will exit.");
}

fn run() !void {
    const allocator = std.heap.page_allocator;

    var storage = try storage_mod.Storage.init(allocator);
    defer storage.deinit();
    try storage.ensure();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len <= 1) {
        try printHelp();
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printHelp();
        return;
    }

    if (!std.mem.eql(u8, command, "ecosystem") and !std.mem.eql(u8, command, "startup") and !std.mem.eql(u8, command, "unstartup")) {
        if (hasFlag(args[1..], "--no-daemon")) {
            // Container/foreground mode: run daemon in foreground, start process, wait
            const daemon_path = try daemonBinaryPath(allocator);
            defer allocator.free(daemon_path);
            var daemon_child = std.process.Child.init(&.{daemon_path}, allocator);
            daemon_child.stdin_behavior = .Ignore;
            daemon_child.stdout_behavior = .Inherit;
            daemon_child.stderr_behavior = .Inherit;
            try daemon_child.spawn();
            try waitForDaemon(allocator, storage);

            // Forward the start command (strip --no-daemon from args for payload)
            if (std.mem.eql(u8, command, "start") and args.len >= 3) {
                const target = args[2];
                if (std.mem.endsWith(u8, target, ".ts") and std.mem.indexOf(u8, target, "ecosystem") != null or std.mem.endsWith(u8, target, ".js") or std.mem.endsWith(u8, target, ".json") or std.mem.endsWith(u8, target, ".jsonc")) {
                    const env_name = flagValue(args[2..], "--env", null);
                    handleConfigStart(allocator, storage, target, env_name) catch {};
                } else {
                    const payload = startPayloadJson(allocator, args[1..]) catch {
                        return;
                    };
                    defer allocator.free(payload);
                    _ = sendRequest(allocator, storage, "start", payload) catch {};
                }
                try render.writeSuccess(stdoutWriter(), "Foreground mode: Ctrl+C to stop all processes.");
            }

            // Block until daemon exits
            _ = daemon_child.wait() catch {};
            return;
        }
        try ensureDaemon(allocator, storage);
    }

    if (std.mem.eql(u8, command, "ping")) {
        const response = try sendRequest(allocator, storage, "ping", "{}");
        if (!response.success) return fail(response.@"error" orelse "ping failed");
        try render.writeSuccess(stdoutWriter(), "Daemon reachable.");
        return;
    }

    if (std.mem.eql(u8, command, "start")) {
        if (args.len < 3) return fail("Usage: bpm2 start <script|config> [options]");
        const target = args[2];
        if (std.mem.endsWith(u8, target, ".ts") and std.mem.indexOf(u8, target, "ecosystem") != null or std.mem.endsWith(u8, target, ".js") or std.mem.endsWith(u8, target, ".json") or std.mem.endsWith(u8, target, ".jsonc")) {
            const env_name = flagValue(args[2..], "--env", null);
            try handleConfigStart(allocator, storage, target, env_name);
        } else {
            const payload = try startPayloadJson(allocator, args[1..]);
            defer allocator.free(payload);
            const response = try sendRequest(allocator, storage, "start", payload);
            if (!response.success) return failFmt("start failed: {s}", .{response.@"error" orelse "unknown"});
        }
        try render.writeSuccess(stdoutWriter(), "Launch plan accepted.");
        try stdoutWriter().writeByte('\n');
        const list_response = try sendRequest(allocator, storage, "list", "{}");
        try printProcessTable(allocator, list_response);
        return;
    }

    if (std.mem.eql(u8, command, "list") or std.mem.eql(u8, command, "ls")) {
        const response = try sendRequest(allocator, storage, "list", "{}");
        if (!response.success) return fail(response.@"error" orelse "list failed");
        if (hasFlag(args[1..], "--json")) {
            try printRawJson(response);
            return;
        }
        try printProcessTable(allocator, response);
        return;
    }

    if (std.mem.eql(u8, command, "info")) {
        if (args.len < 3) return fail("Usage: bpm2 info <name|id>");
        const payload = try std.fmt.allocPrint(allocator, "{{\"target\":{s}}}", .{try jsonStringAlloc(allocator, args[2])});
        defer allocator.free(payload);
        const response = try sendRequest(allocator, storage, "info", payload);
        if (!response.success) return fail(response.@"error" orelse "info failed");
        if (hasFlag(args[2..], "--json")) {
            try printRawJson(response);
            return;
        }
        try printInfo(allocator, response);
        return;
    }

    if (std.mem.eql(u8, command, "stop") or std.mem.eql(u8, command, "restart") or std.mem.eql(u8, command, "reload") or std.mem.eql(u8, command, "delete") or std.mem.eql(u8, command, "flush")) {
        const target = if (args.len >= 3) args[2] else "all";
        const payload = try std.fmt.allocPrint(allocator, "{{\"target\":{s}}}", .{try jsonStringAlloc(allocator, target)});
        defer allocator.free(payload);
        const response = try sendRequest(allocator, storage, command, payload);
        if (!response.success) return fail(response.@"error" orelse "request failed");
        try printActionResult(command, target, response);
        return;
    }

    if (std.mem.eql(u8, command, "logs")) {
        if (args.len < 3) return fail("Usage: bpm2 logs <name|id> [--lines <n>] [--follow]");
        var offset: usize = 0;
        const lines = flagValue(args[2..], "--lines", "-l") orelse "50";
        const follow = hasFlag(args[2..], "--follow") or hasFlag(args[2..], "-f");
        var header_written = false;
        while (true) {
            const payload = try std.fmt.allocPrint(allocator, "{{\"target\":{s},\"lines\":{s},\"offset\":{d}}}", .{ try jsonStringAlloc(allocator, args[2]), lines, offset });
            defer allocator.free(payload);
            const response = try sendRequest(allocator, storage, "logs", payload);
            if (!response.success) return fail(response.@"error" orelse "logs failed");
            if (response.data == .object) {
                const path = objectString(response.data.object, "path", "-");
                if (!header_written) {
                    try printLogsHeader(allocator, args[2], lines, follow, path);
                    header_written = true;
                }
                if (response.data.object.get("log")) |log| {
                    if (log == .string and log.string.len > 0) {
                        try printStyledLogChunk(stdoutWriter(), log.string);
                    }
                }
                if (response.data.object.get("nextOffset")) |next| {
                    if (next == .integer) offset = @intCast(next.integer);
                }
            }
            if (!follow) break;
            std.time.sleep(std.time.ns_per_s);
        }
        return;
    }

    if (std.mem.eql(u8, command, "monit")) {
        while (true) {
            try render.clearScreen(stdoutWriter());
            const response = try sendRequest(allocator, storage, "list", "{}");
            if (!response.success) return fail(response.@"error" orelse "monitor failed");
            try printProcessTableView(allocator, response, .monitor);
            std.time.sleep(std.time.ns_per_s);
        }
    }

    if (std.mem.eql(u8, command, "dashboard")) {
        const info = try storage.readDaemonInfo(allocator);
        try printDashboardInfo(allocator, info.host, info.dashboard_port);
        return;
    }

    if (std.mem.eql(u8, command, "heap") or std.mem.eql(u8, command, "heap-analyze") or std.mem.eql(u8, command, "profile")) {
        if (args.len < 3) return fail("Usage: bpm2 heap|heap-analyze|profile <name|id> [options]");
        const include_jsc = hasFlag(args[2..], "--jsc");
        const duration = flagValue(args[2..], "--duration", "-d") orelse "10";
        const duration_seconds = std.fmt.parseInt(i64, duration, 10) catch return fail("Duration must be an integer number of seconds.");
        const duration_ms = duration_seconds * 1000;
        const payload = if (std.mem.eql(u8, command, "profile"))
            try std.fmt.allocPrint(allocator, "{{\"target\":{s},\"durationMs\":{d}}}", .{ try jsonStringAlloc(allocator, args[2]), duration_ms })
        else
            try std.fmt.allocPrint(allocator, "{{\"target\":{s},\"includeJsc\":{s}}}", .{ try jsonStringAlloc(allocator, args[2]), if (include_jsc) "true" else "false" });
        defer allocator.free(payload);
        const response = try sendRequest(allocator, storage, command, payload);
        if (!response.success) return fail(response.@"error" orelse "request failed");
        try printArtifactResult(command, response.data);
        return;
    }

    if (std.mem.eql(u8, command, "signal")) {
        if (args.len < 4) return fail("Usage: bpm2 signal <signal> <name|id>");
        const sig_name = args[2];
        const target = args[3];
        const payload = try std.fmt.allocPrint(allocator, "{{\"signal\":{s},\"target\":{s}}}", .{ try jsonStringAlloc(allocator, sig_name), try jsonStringAlloc(allocator, target) });
        defer allocator.free(payload);
        const response = try sendRequest(allocator, storage, "signal", payload);
        if (!response.success) return failFmt("signal failed: {s}", .{response.@"error" orelse "unknown"});
        try render.writeSuccess(stdoutWriter(), "Signal sent.");
        return;
    }

    if (std.mem.eql(u8, command, "scale")) {
        if (args.len < 4) return fail("Usage: bpm2 scale <name> <count>");
        const target = args[2];
        const count_str = args[3];
        const count = std.fmt.parseInt(i64, count_str, 10) catch return fail("Count must be an integer.");
        const payload = try std.fmt.allocPrint(allocator, "{{\"target\":{s},\"count\":{d}}}", .{ try jsonStringAlloc(allocator, target), count });
        defer allocator.free(payload);
        const response = try sendRequest(allocator, storage, "scale", payload);
        if (!response.success) return failFmt("scale failed: {s}", .{response.@"error" orelse "unknown"});
        try render.writeSuccess(stdoutWriter(), "Scale operation completed.");
        return;
    }

    if (std.mem.eql(u8, command, "reset")) {
        const target = if (args.len >= 3) args[2] else "all";
        const payload = try std.fmt.allocPrint(allocator, "{{\"target\":{s}}}", .{try jsonStringAlloc(allocator, target)});
        defer allocator.free(payload);
        const response = try sendRequest(allocator, storage, "reset", payload);
        if (!response.success) return fail(response.@"error" orelse "reset failed");
        try render.writeSuccess(stdoutWriter(), "Process metadata reset.");
        return;
    }

    if (std.mem.eql(u8, command, "update")) {
        // Seamless daemon update: save → kill → respawn → resurrect
        const out = stdoutWriter();
        try render.writeInfoMsg(out, "Saving fleet state...");
        const save_response = try sendRequest(allocator, storage, "save", "{}");
        if (!save_response.success) return fail(save_response.@"error" orelse "save failed");
        try render.writeInfoMsg(out, "Shutting down old daemon...");
        const kill_response = try sendRequest(allocator, storage, "kill", "{}");
        if (!kill_response.success) return fail(kill_response.@"error" orelse "kill failed");
        std.time.sleep(500 * std.time.ns_per_ms);
        try render.writeInfoMsg(out, "Spawning new daemon...");
        try spawnDaemon(allocator);
        try waitForDaemon(allocator, storage);
        try render.writeInfoMsg(out, "Restoring fleet...");
        const resurrect_response = try sendRequest(allocator, storage, "resurrect", "{}");
        if (!resurrect_response.success) return fail(resurrect_response.@"error" orelse "resurrect failed");
        try render.writeSuccess(out, "Daemon updated and fleet restored.");
        return;
    }

    if (std.mem.eql(u8, command, "save") or std.mem.eql(u8, command, "resurrect") or std.mem.eql(u8, command, "kill")) {
        const response = try sendRequest(allocator, storage, command, "{}");
        if (!response.success) return fail(response.@"error" orelse "request failed");
        try printMaintenanceResult(storage, command);
        return;
    }

    if (std.mem.eql(u8, command, "startup")) {
        try generateStartupScript(allocator, storage);
        return;
    }

    if (std.mem.eql(u8, command, "unstartup")) {
        try removeStartupScript(allocator);
        return;
    }

    if (std.mem.eql(u8, command, "ecosystem")) {
        try writeEcosystemTemplate();
        return;
    }

    try printHelp();
}

pub fn main() !void {
    render.detectColor();
    run() catch |err| switch (err) {
        error.InvalidArgument => std.process.exit(1),
        else => return err,
    };
}

test "help is available" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    try writeHelp(buffer.writer());
    try std.testing.expect(buffer.items.len > 0);
}

test "strip json comments keeps string content" {
    const allocator = std.testing.allocator;
    const input =
        \\{
        \\  // comment
        \\  "url": "https://example.com//keep",
        \\  /* block */
        \\  "name": "demo"
        \\}
    ;
    const output = try stripJsonCommentsAlloc(allocator, input);
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"url\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "https://example.com//keep") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "comment") == null);
}
