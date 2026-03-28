const std = @import("std");

// ── ANSI Color Codes ────────────────────────────────────────────────

pub const RESET = "0";
pub const BOLD = "1";
pub const DIM = "2";
pub const ITALIC = "3";
pub const UNDERLINE = "4";

pub const RED = "38;5;203";
pub const GREEN = "38;5;84";
pub const YELLOW = "38;5;221";
pub const BLUE = "38;5;111";
pub const MAGENTA = "38;5;213";
pub const CYAN = "38;5;117";
pub const WHITE = "38;5;255";

pub const GRAY = "38;5;245";
pub const BRIGHT_RED = "1;38;5;203";
pub const BRIGHT_GREEN = "1;38;5;84";
pub const BRIGHT_YELLOW = "1;38;5;221";
pub const BRIGHT_CYAN = "1;38;5;117";

pub const BOLD_RED = "1;38;5;203";
pub const BOLD_GREEN = "1;38;5;84";
pub const BOLD_YELLOW = "1;38;5;221";
pub const BOLD_BLUE = "1;38;5;111";
pub const BOLD_CYAN = "1;38;5;117";
pub const BOLD_WHITE = "1;38;5;255";
pub const DIM_WHITE = "2;38;5;252";
pub const BORDER = "38;5;239";
pub const SOFT = "38;5;250";
pub const SLATE = "38;5;244";

// ── TTY Detection ───────────────────────────────────────────────────

pub var use_color: bool = true;

pub fn detectColor() void {
    const handle = std.io.getStdOut().handle;
    if (!std.posix.isatty(handle)) {
        use_color = false;
        return;
    }
    // Respect NO_COLOR convention (https://no-color.org)
    const env = std.process.getEnvVarOwned(std.heap.page_allocator, "NO_COLOR") catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => null,
    };
    if (env) |val| {
        std.heap.page_allocator.free(val);
        use_color = false;
        return;
    }
    // Check TERM=dumb
    const term = std.process.getEnvVarOwned(std.heap.page_allocator, "TERM") catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => null,
    };
    if (term) |val| {
        defer std.heap.page_allocator.free(val);
        if (std.mem.eql(u8, val, "dumb")) {
            use_color = false;
        }
    }
}

// ── Colored Writing ─────────────────────────────────────────────────

pub fn writeColored(writer: anytype, code: []const u8, text: []const u8) !void {
    if (use_color) {
        try writer.print("\x1b[{s}m{s}\x1b[0m", .{ code, text });
    } else {
        try writer.writeAll(text);
    }
}

pub fn writeColoredFmt(writer: anytype, code: []const u8, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try writer.print("\x1b[{s}m", .{code});
        try writer.print(fmt, args);
        try writer.writeAll("\x1b[0m");
    } else {
        try writer.print(fmt, args);
    }
}

pub fn writeMuted(writer: anytype, text: []const u8) !void {
    try writeColored(writer, GRAY, text);
}

pub fn writePill(writer: anytype, code: []const u8, text: []const u8) !void {
    if (use_color and code.len > 0) try writer.print("\x1b[{s}m", .{code});
    try writer.writeAll("[ ");
    try writer.writeAll(text);
    try writer.writeAll(" ]");
    if (use_color and code.len > 0) try writer.writeAll("\x1b[0m");
}

pub fn clearScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
}

/// Write text padded to `width` characters (left-aligned), with optional color.
/// ANSI codes are written outside the padding so column alignment is preserved.
pub fn writeColoredPadLeft(writer: anytype, code: []const u8, text: []const u8, width: usize) !void {
    if (use_color and code.len > 0) try writer.print("\x1b[{s}m", .{code});
    try writer.writeAll(text);
    if (use_color and code.len > 0) try writer.writeAll("\x1b[0m");
    if (text.len < width) {
        try writer.writeByteNTimes(' ', width - text.len);
    }
}

/// Write text padded to `width` characters (right-aligned), with optional color.
pub fn writeColoredPadRight(writer: anytype, code: []const u8, text: []const u8, width: usize) !void {
    if (text.len < width) {
        try writer.writeByteNTimes(' ', width - text.len);
    }
    if (use_color and code.len > 0) try writer.print("\x1b[{s}m", .{code});
    try writer.writeAll(text);
    if (use_color and code.len > 0) try writer.writeAll("\x1b[0m");
}

// ── Status Helpers ──────────────────────────────────────────────────

pub fn statusColor(status: []const u8) []const u8 {
    if (std.mem.eql(u8, status, "online")) return BOLD_GREEN;
    if (std.mem.eql(u8, status, "errored")) return BOLD_RED;
    if (std.mem.eql(u8, status, "stopped")) return BRIGHT_RED;
    if (std.mem.eql(u8, status, "launching")) return YELLOW;
    if (std.mem.eql(u8, status, "stopping")) return YELLOW;
    return GRAY;
}

pub fn statusIndicator(status: []const u8) []const u8 {
    if (std.mem.eql(u8, status, "online")) return "\xe2\x97\x8f"; // ●
    if (std.mem.eql(u8, status, "errored")) return "\xe2\x97\x8f"; // ●
    if (std.mem.eql(u8, status, "stopped")) return "\xe2\x97\x8f"; // ●
    if (std.mem.eql(u8, status, "launching")) return "\xe2\x97\x90"; // ◐
    if (std.mem.eql(u8, status, "stopping")) return "\xe2\x97\x91"; // ◑
    return "\xe2\x97\x8b"; // ○
}

// ── Box Drawing Characters ──────────────────────────────────────────

pub const BOX_H = "\xe2\x94\x80"; // ─
pub const BOX_V = "\xe2\x94\x82"; // │
pub const BOX_TL = "\xe2\x94\x8c"; // ┌
pub const BOX_TR = "\xe2\x94\x90"; // ┐
pub const BOX_BL = "\xe2\x94\x94"; // └
pub const BOX_BR = "\xe2\x94\x98"; // ┘
pub const BOX_VR = "\xe2\x94\x9c"; // ├
pub const BOX_VL = "\xe2\x94\xa4"; // ┤
pub const BOX_HD = "\xe2\x94\xac"; // ┬
pub const BOX_HU = "\xe2\x94\xb4"; // ┴
pub const BOX_CROSS = "\xe2\x94\xbc"; // ┼

pub const DBL_H = "\xe2\x95\x90"; // ═
pub const DBL_V = "\xe2\x95\x91"; // ║
pub const DBL_TL = "\xe2\x95\x94"; // ╔
pub const DBL_TR = "\xe2\x95\x97"; // ╗
pub const DBL_BL = "\xe2\x95\x9a"; // ╚
pub const DBL_BR = "\xe2\x95\x9d"; // ╝

// ── Box Drawing Functions ───────────────────────────────────────────

const BorderKind = enum { top, mid, bottom };

pub fn writeTableBorder(writer: anytype, widths: []const usize, kind: BorderKind) !void {
    const left = switch (kind) {
        .top => BOX_TL,
        .mid => BOX_VR,
        .bottom => BOX_BL,
    };
    const joint = switch (kind) {
        .top => BOX_HD,
        .mid => BOX_CROSS,
        .bottom => BOX_HU,
    };
    const right = switch (kind) {
        .top => BOX_TR,
        .mid => BOX_VL,
        .bottom => BOX_BR,
    };

    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(left);
    for (widths, 0..) |w, i| {
        // +2 for padding spaces on each side
        var j: usize = 0;
        while (j < w + 2) : (j += 1) {
            try writer.writeAll(BOX_H);
        }
        if (i < widths.len - 1) {
            try writer.writeAll(joint);
        }
    }
    try writer.writeAll(right);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

pub fn writeHLine(writer: anytype, width: usize) !void {
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    var i: usize = 0;
    while (i < width) : (i += 1) {
        try writer.writeAll(BOX_H);
    }
    if (use_color) try writer.writeAll("\x1b[0m");
}

pub fn writeBoxSep(writer: anytype, title: []const u8, width: usize) !void {
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(BOX_VR);
    try writer.writeAll(BOX_H);
    if (use_color) try writer.writeAll("\x1b[0m");

    try writeColored(writer, BOLD_CYAN, " ");
    try writeColored(writer, BOLD_CYAN, title);
    try writeColored(writer, BOLD_CYAN, " ");

    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    // title visual length + 2 spaces + 2 border chars at start
    const used = title.len + 4;
    if (width > used) {
        var i: usize = 0;
        while (i < width - used) : (i += 1) {
            try writer.writeAll(BOX_H);
        }
    }
    try writer.writeAll(BOX_VL);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

pub fn writeBoxTop(writer: anytype, title: []const u8, width: usize) !void {
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(BOX_TL);
    try writer.writeAll(BOX_H);
    if (use_color) try writer.writeAll("\x1b[0m");

    try writeColored(writer, BOLD_CYAN, " ");
    try writeColored(writer, BOLD_CYAN, title);
    try writeColored(writer, BOLD_CYAN, " ");

    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    const used = title.len + 4;
    if (width > used) {
        var i: usize = 0;
        while (i < width - used) : (i += 1) {
            try writer.writeAll(BOX_H);
        }
    }
    try writer.writeAll(BOX_TR);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

pub fn writeBoxBottom(writer: anytype, width: usize) !void {
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(BOX_BL);
    var i: usize = 0;
    while (i < width) : (i += 1) {
        try writer.writeAll(BOX_H);
    }
    try writer.writeAll(BOX_BR);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

pub fn writeBoxEmptyRow(writer: anytype, width: usize) !void {
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(BOX_V);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByteNTimes(' ', width);
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(BOX_V);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

/// Write a table cell separator (│) with dim styling
pub fn writeCellSep(writer: anytype) !void {
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    try writer.writeAll(BOX_V);
    if (use_color) try writer.writeAll("\x1b[0m");
}

// ── Message Helpers ─────────────────────────────────────────────────

pub fn writeSuccess(writer: anytype, msg: []const u8) !void {
    try writeColored(writer, BOLD_GREEN, "  \xe2\x9c\x93 "); // ✓
    try writer.writeAll(msg);
    try writer.writeByte('\n');
}

pub fn writeError(writer: anytype, msg: []const u8) !void {
    try writeColored(writer, BOLD_RED, "  \xe2\x9c\x97 "); // ✗
    try writer.writeAll(msg);
    try writer.writeByte('\n');
}

pub fn writeInfoMsg(writer: anytype, msg: []const u8) !void {
    try writeColored(writer, BOLD_BLUE, "  \xe2\x84\xb9 "); // ℹ
    try writer.writeAll(msg);
    try writer.writeByte('\n');
}

pub fn writeWarning(writer: anytype, msg: []const u8) !void {
    try writeColored(writer, BOLD_YELLOW, "  \xe2\x9a\xa0 "); // ⚠
    try writer.writeAll(msg);
    try writer.writeByte('\n');
}

pub fn writeSuccessFmt(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writeColored(writer, BOLD_GREEN, "  \xe2\x9c\x93 "); // ✓
    try writer.print(fmt, args);
    try writer.writeByte('\n');
}

pub fn writeErrorFmt(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writeColored(writer, BOLD_RED, "  \xe2\x9c\x97 "); // ✗
    try writer.print(fmt, args);
    try writer.writeByte('\n');
}

pub fn writeInfoFmt(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writeColored(writer, BOLD_BLUE, "  \xe2\x84\xb9 "); // ℹ
    try writer.print(fmt, args);
    try writer.writeByte('\n');
}

// ── Progress Bar ────────────────────────────────────────────────────

/// Write a mini bar chart: filled ▰ and empty ▱ characters.
/// Colors: <50% green, 50-80% yellow, >80% red.
pub fn writeBar(writer: anytype, fraction: f64, width: usize) !void {
    const clamped = @min(@max(fraction, 0.0), 1.0);
    const filled: usize = @intFromFloat(@round(clamped * @as(f64, @floatFromInt(width))));
    const bar_color = if (clamped < 0.5) GREEN else if (clamped < 0.8) YELLOW else RED;

    if (use_color) try writer.print("\x1b[{s}m", .{bar_color});
    var i: usize = 0;
    while (i < filled) : (i += 1) {
        try writer.writeAll("\xe2\x96\xb0"); // ▰
    }
    if (use_color) try writer.writeAll("\x1b[0m");
    if (use_color) try writer.print("\x1b[{s}m", .{BORDER});
    while (i < width) : (i += 1) {
        try writer.writeAll("\xe2\x96\xb1"); // ▱
    }
    if (use_color) try writer.writeAll("\x1b[0m");
}

// ── Formatting Functions ────────────────────────────────────────────

pub fn formatBytes(allocator: std.mem.Allocator, bytes: ?u64) ![]u8 {
    if (bytes == null) return allocator.dupe(u8, "N/A");
    const value = bytes.?;
    if (value == 0) return allocator.dupe(u8, "0 B");
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var scaled = @as(f64, @floatFromInt(value));
    var index: usize = 0;
    while (scaled >= 1024 and index < units.len - 1) : (index += 1) {
        scaled /= 1024;
    }
    return std.fmt.allocPrint(allocator, "{d:.1} {s}", .{ scaled, units[index] });
}

pub fn formatTimestamp(allocator: std.mem.Allocator, timestamp_ms: i64) ![]u8 {
    if (timestamp_ms <= 0) return allocator.dupe(u8, "-");
    const epoch_secs: i64 = @divTrunc(timestamp_ms, 1000);
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch_secs) };
    const day_seconds = es.getDaySeconds();
    const year_day = es.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

pub fn formatUptime(allocator: std.mem.Allocator, uptime_ms: i64) ![]u8 {
    if (uptime_ms <= 0) return allocator.dupe(u8, "0s");
    const total_seconds: i64 = @divTrunc(uptime_ms, 1000);
    const days = @divTrunc(total_seconds, 86400);
    const hours = @divTrunc(@mod(total_seconds, 86400), 3600);
    const minutes = @divTrunc(@mod(total_seconds, 3600), 60);
    const seconds = @mod(total_seconds, 60);
    if (days > 0) return std.fmt.allocPrint(allocator, "{d}d {d}h", .{ days, hours });
    if (hours > 0) return std.fmt.allocPrint(allocator, "{d}h {d}m", .{ hours, minutes });
    if (minutes > 0) return std.fmt.allocPrint(allocator, "{d}m {d}s", .{ minutes, seconds });
    return std.fmt.allocPrint(allocator, "{d}s", .{seconds});
}

pub fn formatRelativeTime(allocator: std.mem.Allocator, timestamp_ms: i64) ![]u8 {
    if (timestamp_ms <= 0) return allocator.dupe(u8, "-");
    const now_ms: i64 = @intCast(std.time.milliTimestamp());
    const diff_ms = now_ms - timestamp_ms;
    if (diff_ms < 0) return allocator.dupe(u8, "just now");
    return formatUptime(allocator, diff_ms);
}

// ── Double-Line Box (for branding) ──────────────────────────────────

pub fn writeDblBoxTop(writer: anytype, width: usize) !void {
    if (use_color) try writer.writeAll("\x1b[" ++ BOLD_CYAN ++ "m");
    try writer.writeAll("  ");
    try writer.writeAll(DBL_TL);
    var i: usize = 0;
    while (i < width) : (i += 1) {
        try writer.writeAll(DBL_H);
    }
    try writer.writeAll(DBL_TR);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

pub fn writeDblBoxMid(writer: anytype, text: []const u8, width: usize) !void {
    if (use_color) try writer.writeAll("\x1b[" ++ BOLD_CYAN ++ "m");
    try writer.writeAll("  ");
    try writer.writeAll(DBL_V);
    // Center the text
    const text_len = text.len;
    const pad_total = if (width > text_len) width - text_len else 0;
    const pad_left = pad_total / 2;
    const pad_right = pad_total - pad_left;
    try writer.writeByteNTimes(' ', pad_left);
    try writer.writeAll(text);
    try writer.writeByteNTimes(' ', pad_right);
    try writer.writeAll(DBL_V);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

pub fn writeDblBoxBottom(writer: anytype, width: usize) !void {
    if (use_color) try writer.writeAll("\x1b[" ++ BOLD_CYAN ++ "m");
    try writer.writeAll("  ");
    try writer.writeAll(DBL_BL);
    var i: usize = 0;
    while (i < width) : (i += 1) {
        try writer.writeAll(DBL_H);
    }
    try writer.writeAll(DBL_BR);
    if (use_color) try writer.writeAll("\x1b[0m");
    try writer.writeByte('\n');
}

// ── Info Panel Key-Value Helpers ────────────────────────────────────

/// Write a key-value pair inside a box row: "│  Label      value                │"
pub fn writeBoxKV(writer: anytype, label: []const u8, value: []const u8, value_color: []const u8, row_width: usize) !void {
    const label_col = 12;
    const content_width = row_width - 2; // minus 2 for "  " prefix inside box

    writeCellSep(writer) catch {};
    try writer.writeAll("  ");
    try writeColored(writer, GRAY, label);
    if (label.len < label_col) {
        try writer.writeByteNTimes(' ', label_col - label.len);
    }
    if (value_color.len > 0) {
        try writeColored(writer, value_color, value);
    } else {
        try writer.writeAll(value);
    }
    const used = 2 + @max(label.len, label_col) + value.len;
    if (used < content_width) {
        try writer.writeByteNTimes(' ', content_width - used);
    }
    writeCellSep(writer) catch {};
    try writer.writeByte('\n');
}

/// Write two key-value pairs side by side in a box row
pub fn writeBoxKV2(writer: anytype, l1: []const u8, v1: []const u8, c1: []const u8, l2: []const u8, v2: []const u8, c2: []const u8, row_width: usize) !void {
    const label_col = 12;
    const half_width = (row_width - 2) / 2;

    writeCellSep(writer) catch {};
    try writer.writeAll("  ");

    // First pair
    try writeColored(writer, GRAY, l1);
    if (l1.len < label_col) {
        try writer.writeByteNTimes(' ', label_col - l1.len);
    }
    if (c1.len > 0) {
        try writeColored(writer, c1, v1);
    } else {
        try writer.writeAll(v1);
    }
    const used1 = 2 + @max(l1.len, label_col) + v1.len;
    if (used1 < half_width) {
        try writer.writeByteNTimes(' ', half_width - used1);
    }

    // Second pair
    try writeColored(writer, GRAY, l2);
    if (l2.len < label_col) {
        try writer.writeByteNTimes(' ', label_col - l2.len);
    }
    if (c2.len > 0) {
        try writeColored(writer, c2, v2);
    } else {
        try writer.writeAll(v2);
    }
    const used2 = @max(l2.len, label_col) + v2.len;
    const total_used = @max(used1, half_width) + used2;
    const content_width = row_width - 2;
    if (total_used < content_width) {
        try writer.writeByteNTimes(' ', content_width - total_used);
    }

    writeCellSep(writer) catch {};
    try writer.writeByte('\n');
}
