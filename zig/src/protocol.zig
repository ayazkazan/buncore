const std = @import("std");

pub const Request = struct {
    authToken: ?[]const u8 = null,
    action: []const u8,
    requestId: ?[]const u8 = null,
    payload: std.json.Value = .null,
};

pub const ResponseEnvelope = struct {
    success: bool,
    requestId: ?[]const u8 = null,
    data_json: []const u8 = "null",
    @"error": ?[]const u8 = null,
};

pub fn parseRequest(allocator: std.mem.Allocator, input: []const u8) !std.json.Parsed(Request) {
    return std.json.parseFromSlice(Request, allocator, input, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

pub fn stringifyResponseAlloc(allocator: std.mem.Allocator, response: ResponseEnvelope) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    const w = list.writer();
    try w.writeByte('{');
    try w.print("\"success\":{s}", .{if (response.success) "true" else "false"});
    if (response.requestId) |request_id| {
        try w.print(",\"requestId\":", .{});
        try std.json.stringify(request_id, .{}, w);
    }
    try w.writeAll(",\"data\":");
    try w.writeAll(response.data_json);
    if (response.@"error") |err_msg| {
        try w.writeAll(",\"error\":");
        try std.json.stringify(err_msg, .{}, w);
    }
    try w.writeByte('}');
    return list.toOwnedSlice();
}

pub fn payloadString(payload: std.json.Value, key: []const u8) ?[]const u8 {
    if (payload != .object) return null;
    const value = payload.object.get(key) orelse return null;
    return switch (value) {
        .string => value.string,
        else => null,
    };
}

pub fn payloadBool(payload: std.json.Value, key: []const u8, default_value: bool) bool {
    if (payload != .object) return default_value;
    const value = payload.object.get(key) orelse return default_value;
    return switch (value) {
        .bool => value.bool,
        else => default_value,
    };
}

pub fn payloadInt(payload: std.json.Value, key: []const u8, comptime T: type, default_value: T) T {
    if (payload != .object) return default_value;
    const value = payload.object.get(key) orelse return default_value;
    return switch (value) {
        .integer => |v| std.math.cast(T, v) orelse default_value,
        .float => |v| std.math.cast(T, @as(i64, @intFromFloat(v))) orelse default_value,
        else => default_value,
    };
}

pub fn payloadStringArrayAlloc(allocator: std.mem.Allocator, payload: std.json.Value, key: []const u8) ![][]u8 {
    if (payload != .object) return allocator.alloc([]u8, 0);
    const value = payload.object.get(key) orelse return allocator.alloc([]u8, 0);
    if (value != .array) return allocator.alloc([]u8, 0);
    const items = try allocator.alloc([]u8, value.array.items.len);
    for (value.array.items, 0..) |item, idx| {
        items[idx] = try allocator.dupe(u8, switch (item) {
            .string => item.string,
            else => "",
        });
    }
    return items;
}

pub fn payloadIntArrayAlloc(allocator: std.mem.Allocator, payload: std.json.Value, key: []const u8) ![]i32 {
    if (payload != .object) return allocator.alloc(i32, 0);
    const value = payload.object.get(key) orelse return allocator.alloc(i32, 0);
    if (value != .array) return allocator.alloc(i32, 0);
    const items = try allocator.alloc(i32, value.array.items.len);
    for (value.array.items, 0..) |item, idx| {
        items[idx] = switch (item) {
            .integer => |v| std.math.cast(i32, v) orelse 0,
            else => 0,
        };
    }
    return items;
}
