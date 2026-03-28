const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const kernel32 = std.os.windows.kernel32;
const kqueue_platform = switch (builtin.os.tag) {
    .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
    else => false,
};
const windows_platform = builtin.os.tag == .windows;

pub const Strategy = enum {
    linux_inotify,
    darwin_kqueue,
    windows_read_directory_changes,
    polling_fallback,
};

pub const Spec = struct {
    process_id: u32,
    cwd: []const u8,
    script: []const u8,
    watch_path: ?[]const u8,
    ignore_watch: []const []const u8,
};

const LinuxWatch = struct {
    wd: i32,
    process_id: u32,
    dir_rel_path: []u8,
};

const KqueueEvent = if (kqueue_platform) std.c.Kevent else struct {
    ident: usize = 0,
    filter: i16 = 0,
    flags: u16 = 0,
    fflags: u32 = 0,
    data: i64 = 0,
    udata: usize = 0,
};

const KqueueWatch = struct {
    dir: std.fs.Dir,
    process_id: u32,
    dir_rel_path: []u8,
};

const WindowsWatch = if (windows_platform) struct {
    handle: windows.HANDLE,
    event: windows.HANDLE,
    overlapped: windows.OVERLAPPED,
    buffer: [16 * 1024]u8 align(@alignOf(windows.FILE_NOTIFY_INFORMATION)),
    process_id: u32,
} else struct {
    handle: usize = 0,
    event: usize = 0,
    overlapped: usize = 0,
    buffer: [1]u8 = .{0},
    process_id: u32 = 0,
};

const IN_MODIFY: u32 = 0x00000002;
const IN_ATTRIB: u32 = 0x00000004;
const IN_CLOSE_WRITE: u32 = 0x00000008;
const IN_MOVED_FROM: u32 = 0x00000040;
const IN_MOVED_TO: u32 = 0x00000080;
const IN_CREATE: u32 = 0x00000100;
const IN_DELETE: u32 = 0x00000200;
const IN_DELETE_SELF: u32 = 0x00000400;
const IN_MOVE_SELF: u32 = 0x00000800;
const IN_IGNORED: u32 = 0x00008000;

pub fn strategy() Strategy {
    return switch (builtin.os.tag) {
        .linux => .linux_inotify,
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => .darwin_kqueue,
        .windows => .windows_read_directory_changes,
        else => .polling_fallback,
    };
}

pub fn preferredStrategy() Strategy {
    return switch (builtin.os.tag) {
        .linux => .linux_inotify,
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => .darwin_kqueue,
        .windows => .windows_read_directory_changes,
        else => .polling_fallback,
    };
}

pub fn strategyLabel(value: Strategy) []const u8 {
    return switch (value) {
        .linux_inotify => "linux_inotify",
        .darwin_kqueue => "darwin_kqueue",
        .windows_read_directory_changes => "windows_read_directory_changes",
        .polling_fallback => "polling_fallback",
    };
}

pub fn strategyIsNative(value: Strategy) bool {
    return switch (value) {
        .linux_inotify => true,
        .darwin_kqueue => true,
        .windows_read_directory_changes => true,
        .polling_fallback => false,
    };
}

pub fn platformLabel() []const u8 {
    return @tagName(builtin.os.tag);
}

pub fn shouldIgnoreWatchPath(spec: Spec, rel_path: []const u8) bool {
    for (spec.ignore_watch) |ignore_item| {
        if (ignore_item.len == 0) continue;
        if (std.mem.indexOf(u8, rel_path, ignore_item) != null) return true;
    }
    return false;
}

pub fn resolveWatchRoot(allocator: std.mem.Allocator, spec: Spec) ![]u8 {
    if (spec.watch_path) |watch_path| {
        if (std.fs.path.isAbsolute(watch_path)) return allocator.dupe(u8, watch_path);
        return std.fs.path.join(allocator, &.{ spec.cwd, watch_path });
    }
    if (std.fs.path.dirname(spec.script)) |dir_path| {
        if (std.fs.path.isAbsolute(spec.script)) return allocator.dupe(u8, dir_path);
        return std.fs.path.join(allocator, &.{ spec.cwd, dir_path });
    }
    return allocator.dupe(u8, spec.cwd);
}

pub fn computeSignature(allocator: std.mem.Allocator, spec: Spec) !u64 {
    const root = try resolveWatchRoot(allocator, spec);
    defer allocator.free(root);

    var dir = if (std.fs.path.isAbsolute(root))
        try std.fs.openDirAbsolute(root, .{ .iterate = true })
    else
        try std.fs.cwd().openDir(root, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var signature: u64 = std.hash.Wyhash.hash(0, root);
    while (try walker.next()) |entry| {
        if (shouldIgnoreWatchPath(spec, entry.path)) continue;
        const stat = entry.dir.statFile(entry.basename) catch continue;
        const mtime_bits: u64 = @truncate(@as(u128, @intCast(@max(stat.mtime, 0))));
        signature ^= std.hash.Wyhash.hash(signature ^ mtime_bits, entry.path);
        signature +%= @as(u64, @intCast(entry.path.len));
    }
    return signature;
}

fn isKqueuePlatform() bool {
    return kqueue_platform;
}

fn keventFlags() u16 {
    return switch (builtin.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => std.c.EV_ADD | std.c.EV_ENABLE | std.c.EV_CLEAR,
        else => 0,
    };
}

fn keventFilter() i16 {
    return switch (builtin.os.tag) {
        .macos, .freebsd, .openbsd, .dragonfly => std.c.EVFILT_VNODE,
        .netbsd => std.c.EVFILT_VNODE,
        else => 0,
    };
}

fn keventNoteMask() u32 {
    return switch (builtin.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => std.c.NOTE_WRITE | std.c.NOTE_DELETE | std.c.NOTE_EXTEND | std.c.NOTE_ATTRIB | std.c.NOTE_LINK | std.c.NOTE_RENAME,
        else => 0,
    };
}

fn makeKevent(ident: usize, udata: usize) KqueueEvent {
    return .{
        .ident = ident,
        .filter = keventFilter(),
        .flags = keventFlags(),
        .fflags = keventNoteMask(),
        .data = 0,
        .udata = udata,
    };
}

fn addRecursiveWatches(
    allocator: std.mem.Allocator,
    inotify_fd: i32,
    spec: Spec,
    root: []const u8,
    watch_entries: *std.ArrayList(LinuxWatch),
) !void {
    const mask = IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF;
    const root_wd = try std.posix.inotify_add_watch(inotify_fd, root, mask);
    try watch_entries.append(.{
        .wd = root_wd,
        .process_id = spec.process_id,
        .dir_rel_path = try allocator.dupe(u8, ""),
    });

    var dir = if (std.fs.path.isAbsolute(root))
        try std.fs.openDirAbsolute(root, .{ .iterate = true })
    else
        try std.fs.cwd().openDir(root, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (shouldIgnoreWatchPath(spec, entry.path)) continue;
        const full_path = try std.fs.path.join(allocator, &.{ root, entry.path });
        defer allocator.free(full_path);
        const wd = std.posix.inotify_add_watch(inotify_fd, full_path, mask) catch continue;
        try watch_entries.append(.{
            .wd = wd,
            .process_id = spec.process_id,
            .dir_rel_path = try allocator.dupe(u8, entry.path),
        });
    }
}

fn addRecursiveKqueueWatches(
    allocator: std.mem.Allocator,
    kq: i32,
    spec: Spec,
    root: []const u8,
    watch_entries: *std.ArrayList(KqueueWatch),
) !void {
    const open_dir = if (std.fs.path.isAbsolute(root))
        try std.fs.openDirAbsolute(root, .{ .iterate = true })
    else
        try std.fs.cwd().openDir(root, .{ .iterate = true });
    try watch_entries.append(.{
        .dir = open_dir,
        .process_id = spec.process_id,
        .dir_rel_path = try allocator.dupe(u8, ""),
    });

    {
        const index = watch_entries.items.len - 1;
        var change = [_]KqueueEvent{makeKevent(@intCast(open_dir.fd), index)};
        _ = try std.posix.kevent(kq, &change, &.{}, null);
    }

    var root_dir = if (std.fs.path.isAbsolute(root))
        try std.fs.openDirAbsolute(root, .{ .iterate = true })
    else
        try std.fs.cwd().openDir(root, .{ .iterate = true });
    defer root_dir.close();

    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (shouldIgnoreWatchPath(spec, entry.path)) continue;
        const full_path = try std.fs.path.join(allocator, &.{ root, entry.path });
        defer allocator.free(full_path);
        const dir = if (std.fs.path.isAbsolute(full_path))
            std.fs.openDirAbsolute(full_path, .{ .iterate = true }) catch continue
        else
            std.fs.cwd().openDir(full_path, .{ .iterate = true }) catch continue;
        try watch_entries.append(.{
            .dir = dir,
            .process_id = spec.process_id,
            .dir_rel_path = try allocator.dupe(u8, entry.path),
        });
        const index = watch_entries.items.len - 1;
        var change = [_]KqueueEvent{makeKevent(@intCast(dir.fd), index)};
        _ = std.posix.kevent(kq, &change, &.{}, null) catch {};
    }
}

pub fn waitForLinuxChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
    if (builtin.os.tag != .linux or specs.len == 0) return allocator.alloc(u32, 0);

    const fd = try std.posix.inotify_init1(0);
    defer std.posix.close(fd);

    var watch_entries = std.ArrayList(LinuxWatch).init(allocator);
    defer {
        for (watch_entries.items) |entry| allocator.free(entry.dir_rel_path);
        watch_entries.deinit();
    }

    for (specs) |spec| {
        const root = resolveWatchRoot(allocator, spec) catch continue;
        defer allocator.free(root);
        addRecursiveWatches(allocator, fd, spec, root, &watch_entries) catch {};
    }

    if (watch_entries.items.len == 0) return allocator.alloc(u32, 0);

    var fds = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = try std.posix.poll(&fds, timeout_ms);
    if (ready == 0 or (fds[0].revents & std.posix.POLL.IN) == 0) return allocator.alloc(u32, 0);

    var buffer: [16 * 1024]u8 = undefined;
    const read_len = std.posix.read(fd, &buffer) catch return allocator.alloc(u32, 0);
    if (read_len == 0) return allocator.alloc(u32, 0);

    var changed = std.ArrayList(u32).init(allocator);
    errdefer changed.deinit();

    var index: usize = 0;
    while (index + @sizeOf(std.os.linux.inotify_event) <= read_len) {
        const event = @as(*align(1) const std.os.linux.inotify_event, @ptrCast(buffer[index..].ptr));
        const record_len = @sizeOf(std.os.linux.inotify_event) + event.len;
        if ((event.mask & IN_IGNORED) == 0) {
            for (watch_entries.items) |entry| {
                if (entry.wd != event.wd) continue;
                const name = if (event.len == 0)
                    ""
                else
                    std.mem.sliceTo(
                        @as([*:0]const u8, @ptrCast(buffer[index + @sizeOf(std.os.linux.inotify_event) ..].ptr)),
                        0,
                    );
                const rel_path = if (entry.dir_rel_path.len == 0 or name.len == 0)
                    name
                else
                    try std.fs.path.join(allocator, &.{ entry.dir_rel_path, name });
                defer if (entry.dir_rel_path.len != 0 and name.len != 0) allocator.free(rel_path);
                const spec = blk: {
                    for (specs) |spec| {
                        if (spec.process_id == entry.process_id) break :blk spec;
                    }
                    break :blk specs[0];
                };
                if (shouldIgnoreWatchPath(spec, rel_path)) break;
                var exists = false;
                for (changed.items) |id| {
                    if (id == entry.process_id) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) try changed.append(entry.process_id);
                break;
            }
        }
        if (record_len == 0) break;
        index += record_len;
    }

    return changed.toOwnedSlice();
}

const KqueueWatcher = if (kqueue_platform) struct {
    fn waitForChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
        if (specs.len == 0) return allocator.alloc(u32, 0);

        const kq = try std.posix.kqueue();
        defer std.posix.close(kq);

        var watch_entries = std.ArrayList(KqueueWatch).init(allocator);
        defer {
            for (watch_entries.items) |*entry| {
                entry.dir.close();
                allocator.free(entry.dir_rel_path);
            }
            watch_entries.deinit();
        }

        for (specs) |spec| {
            const root = resolveWatchRoot(allocator, spec) catch continue;
            defer allocator.free(root);
            addRecursiveKqueueWatches(allocator, kq, spec, root, &watch_entries) catch {};
        }

        if (watch_entries.items.len == 0) return allocator.alloc(u32, 0);

        var event_buf: [256]KqueueEvent = undefined;
        var timeout = std.posix.timespec{
            .tv_sec = @divTrunc(timeout_ms, 1000),
            .tv_nsec = @mod(timeout_ms, 1000) * std.time.ns_per_ms,
        };
        const ready = try std.posix.kevent(kq, &.{}, event_buf[0..], &timeout);
        if (ready == 0) return allocator.alloc(u32, 0);

        var changed = std.ArrayList(u32).init(allocator);
        errdefer changed.deinit();

        for (event_buf[0..ready]) |event| {
            if (event.udata >= watch_entries.items.len) continue;
            const entry = watch_entries.items[event.udata];
            var exists = false;
            for (changed.items) |id| {
                if (id == entry.process_id) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try changed.append(entry.process_id);
        }

        return changed.toOwnedSlice();
    }
} else struct {
    fn waitForChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
        _ = specs;
        _ = timeout_ms;
        return allocator.alloc(u32, 0);
    }
};

pub fn waitForKqueueChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
    return KqueueWatcher.waitForChanges(allocator, specs, timeout_ms);
}

const WindowsWatcher = if (windows_platform) struct {
    fn openWatch(allocator: std.mem.Allocator, spec: Spec) !WindowsWatch {
        const root = try resolveWatchRoot(allocator, spec);
        defer allocator.free(root);
        const path_w = try windows.sliceToPrefixedFileW(null, root);
        const handle = kernel32.CreateFileW(
            path_w.span().ptr,
            windows.FILE_LIST_DIRECTORY,
            windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
            null,
            windows.OPEN_EXISTING,
            windows.FILE_FLAG_BACKUP_SEMANTICS | windows.FILE_FLAG_OVERLAPPED,
            null,
        );
        if (handle == windows.INVALID_HANDLE_VALUE) {
            return windows.unexpectedError(kernel32.GetLastError());
        }

        errdefer windows.CloseHandle(handle);
        const event = kernel32.CreateEventExW(null, null, windows.CREATE_EVENT_MANUAL_RESET, windows.EVENT_ALL_ACCESS) orelse
            return windows.unexpectedError(kernel32.GetLastError());
        errdefer windows.CloseHandle(event);

        var watch: WindowsWatch = .{
            .handle = handle,
            .event = event,
            .overlapped = std.mem.zeroes(windows.OVERLAPPED),
            .buffer = undefined,
            .process_id = spec.process_id,
        };
        watch.overlapped.hEvent = event;

        const notify_filter =
            windows.FILE_NOTIFY_CHANGE_FILE_NAME |
            windows.FILE_NOTIFY_CHANGE_DIR_NAME |
            windows.FILE_NOTIFY_CHANGE_LAST_WRITE |
            windows.FILE_NOTIFY_CHANGE_ATTRIBUTES |
            windows.FILE_NOTIFY_CHANGE_SIZE |
            windows.FILE_NOTIFY_CHANGE_CREATION;

        if (kernel32.ReadDirectoryChangesW(
            handle,
            &watch.buffer,
            @intCast(watch.buffer.len),
            1,
            notify_filter,
            null,
            &watch.overlapped,
            null,
        ) == 0) {
            return windows.unexpectedError(kernel32.GetLastError());
        }

        return watch;
    }

    fn closeWatch(watch: *WindowsWatch) void {
        _ = kernel32.CancelIoEx(watch.handle, &watch.overlapped);
        windows.CloseHandle(watch.event);
        windows.CloseHandle(watch.handle);
    }

    fn parseChanges(allocator: std.mem.Allocator, spec: Spec, watch: *WindowsWatch) !bool {
        const bytes = windows.GetOverlappedResult(watch.handle, &watch.overlapped, false) catch |err| switch (err) {
            error.WouldBlock => return false,
            else => return false,
        };
        if (bytes == 0) return false;

        var index: usize = 0;
        while (index + @sizeOf(windows.FILE_NOTIFY_INFORMATION) <= bytes) {
            const info = @as(*align(1) const windows.FILE_NOTIFY_INFORMATION, @ptrCast(watch.buffer[index..].ptr));
            const name_ptr = @as([*]align(1) const u16, @ptrCast(watch.buffer[index + @sizeOf(windows.FILE_NOTIFY_INFORMATION) ..].ptr));
            const name_len: usize = @intCast(info.FileNameLength / 2);
            const aligned_name = try allocator.alloc(u16, name_len);
            defer allocator.free(aligned_name);
            for (0..name_len) |i| aligned_name[i] = name_ptr[i];
            const rel_path = try std.unicode.wtf16LeToWtf8Alloc(allocator, aligned_name);
            defer allocator.free(rel_path);
            if (!shouldIgnoreWatchPath(spec, rel_path)) return true;
            if (info.NextEntryOffset == 0) break;
            index += info.NextEntryOffset;
        }
        return false;
    }

    fn waitForChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
        if (specs.len == 0) return allocator.alloc(u32, 0);

        const limited_len = @min(specs.len, windows.MAXIMUM_WAIT_OBJECTS - 1);
        var watches = std.ArrayList(WindowsWatch).init(allocator);
        defer {
            for (watches.items) |*watch| closeWatch(watch);
            watches.deinit();
        }

        var handles = std.ArrayList(windows.HANDLE).init(allocator);
        defer handles.deinit();

        for (specs[0..limited_len]) |spec| {
            const watch = openWatch(allocator, spec) catch continue;
            try handles.append(watch.event);
            try watches.append(watch);
        }

        if (handles.items.len == 0) return allocator.alloc(u32, 0);

        const signaled_index = windows.WaitForMultipleObjectsEx(handles.items, false, @intCast(timeout_ms), false) catch |err| switch (err) {
            error.WaitTimeOut => return allocator.alloc(u32, 0),
            else => return allocator.alloc(u32, 0),
        };

        var changed = std.ArrayList(u32).init(allocator);
        errdefer changed.deinit();

        if (signaled_index < watches.items.len) {
            const watch = &watches.items[signaled_index];
            var matched_spec: ?Spec = null;
            for (specs) |spec| {
                if (spec.process_id == watch.process_id) {
                    matched_spec = spec;
                    break;
                }
            }
            if (matched_spec != null and try parseChanges(allocator, matched_spec.?, watch)) {
                try changed.append(watch.process_id);
            }
        }

        return changed.toOwnedSlice();
    }
} else struct {
    fn waitForChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
        _ = specs;
        _ = timeout_ms;
        return allocator.alloc(u32, 0);
    }
};

pub fn waitForWindowsChanges(allocator: std.mem.Allocator, specs: []const Spec, timeout_ms: i32) ![]u32 {
    return WindowsWatcher.waitForChanges(allocator, specs, timeout_ms);
}
