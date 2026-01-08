const std = @import("std");
const todo = @import("todo.zig");

const MAX_TITLE_LENGTH = 100;

/// Escapes a string for JSON output (handles backslash, quotes, control chars)
pub fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '"' => try result.appendSlice(allocator, "\\\""),
            '/' => try result.appendSlice(allocator, "\\/"),
            0x08 => try result.appendSlice(allocator, "\\b"), // backspace
            0x0C => try result.appendSlice(allocator, "\\f"), // form feed
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => {
                // Escape control characters U+0000 to U+001F as \uXXXX
                if (c < 0x20) {
                    try result.appendSlice(allocator, "\\u00");
                    try std.fmt.format(result.writer(allocator), "{x:0>2}", .{c});
                } else {
                    try result.append(allocator, c);
                }
            },
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Writes a single todo as JSON to a writer (no newline after closing brace)
pub fn writeTodoJson(writer: anytype, allocator: std.mem.Allocator, item: todo.Todo) !void {
    const escaped_id = try escapeJsonString(allocator, item.id);
    defer allocator.free(escaped_id);

    const escaped_title = try escapeJsonString(allocator, item.title);
    defer allocator.free(escaped_title);

    const escaped_body = try escapeJsonString(allocator, item.body);
    defer allocator.free(escaped_body);

    const escaped_resolution = try escapeJsonString(allocator, item.resolution_reason);
    defer allocator.free(escaped_resolution);

    const status_str = item.status.toString();

    try writer.writeAll("    {\n");
    try writer.print("      \"id\": \"{s}\",\n", .{escaped_id});
    try writer.print("      \"title\": \"{s}\",\n", .{escaped_title});
    try writer.print("      \"body\": \"{s}\",\n", .{escaped_body});
    try writer.print("      \"status\": \"{s}\",\n", .{status_str});

    try writer.writeAll("      \"tags\": [");
    for (item.tags, 0..) |tag, j| {
        const escaped_tag = try escapeJsonString(allocator, tag);
        defer allocator.free(escaped_tag);
        try writer.print("\"{s}\"", .{escaped_tag});
        if (j < item.tags.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll("],\n");

    try writer.writeAll("      \"depends_on\": [");
    for (item.depends_on, 0..) |dep, j| {
        const escaped_dep = try escapeJsonString(allocator, dep);
        defer allocator.free(escaped_dep);
        try writer.print("\"{s}\"", .{escaped_dep});
        if (j < item.depends_on.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll("],\n");

    try writer.writeAll("      \"blocked_by\": [");
    for (item.blocked_by, 0..) |blocked, j| {
        const escaped_blocked = try escapeJsonString(allocator, blocked);
        defer allocator.free(escaped_blocked);
        try writer.print("\"{s}\"", .{escaped_blocked});
        if (j < item.blocked_by.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll("],\n");

    const escaped_created = try escapeJsonString(allocator, item.created_at);
    defer allocator.free(escaped_created);
    const escaped_updated = try escapeJsonString(allocator, item.updated_at);
    defer allocator.free(escaped_updated);

    try writer.print("      \"created_at\": \"{s}\",\n", .{escaped_created});
    try writer.print("      \"updated_at\": \"{s}\",\n", .{escaped_updated});
    try writer.print("      \"resolution_reason\": \"{s}\"\n", .{escaped_resolution});
    try writer.writeAll("    }");
}

/// Writes an array of todos as JSON with wrapper object
pub fn writeTodosJson(writer: anytype, allocator: std.mem.Allocator, todos: []const todo.Todo) !void {
    try writer.writeAll("{\n  \"todos\": [\n");

    for (todos, 0..) |item, i| {
        try writeTodoJson(writer, allocator, item);
        if (i < todos.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ]\n}\n");
}

// Sequence state for collision prevention
const IDState = struct {
    last_timestamp: i64 = 0,
    last_ms: u32 = 0,
    sequence: u32 = 0,
};

var id_state = IDState{};
var id_state_mutex = std.Thread.Mutex{};

pub fn generateId(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();

    // Get milliseconds from nanosecond timestamp
    // Use @mod instead of @rem to handle negative values correctly
    const ns = std.time.nanoTimestamp();
    const ms = @as(u32, @intCast(@divTrunc(@mod(ns, 1_000_000_000), 1_000_000)));

    // Atomically get sequence number to prevent collisions
    const sequence = blk: {
        id_state_mutex.lock();
        defer id_state_mutex.unlock();

        if (timestamp != id_state.last_timestamp or ms != id_state.last_ms) {
            id_state.last_timestamp = timestamp;
            id_state.last_ms = ms;
            id_state.sequence = 0;
        }

        const seq = id_state.sequence;
        id_state.sequence += 1;
        break :blk seq;
    };

    // Format: {timestamp}-{ms:0>3}-{seq:0>3}
    return std.fmt.allocPrint(allocator, "{d}-{d:0>3}-{d:0>3}", .{ timestamp, ms, sequence });
}

pub fn getCurrentTimestamp(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    return std.fmt.allocPrint(allocator, "{d}", .{timestamp});
}

pub fn validateTitle(title: []const u8) error{TitleEmpty, TitleTooLong}!void {
    if (title.len == 0) return error.TitleEmpty;
    if (title.len > MAX_TITLE_LENGTH) return error.TitleTooLong;
}

/// Validates ID format: {timestamp}-{ms:0>3}-{seq:0>3}
/// Example: "1736205028-001-001"
pub fn validateId(id: []const u8) error{IdInvalidFormat}!void {
    // Split into 3 parts by '-'
    var parts = std.mem.splitScalar(u8, id, '-');
    const timestamp_part = parts.next() orelse return error.IdInvalidFormat;
    const ms_part = parts.next() orelse return error.IdInvalidFormat;
    const seq_part = parts.next() orelse return error.IdInvalidFormat;

    // Should have exactly 3 parts
    if (parts.next() != null) return error.IdInvalidFormat;

    // Timestamp must be non-empty and all digits
    if (timestamp_part.len == 0) return error.IdInvalidFormat;
    for (timestamp_part) |c| {
        if (c < '0' or c > '9') return error.IdInvalidFormat;
    }

    // ms and seq must be exactly 3 digits
    if (ms_part.len != 3) return error.IdInvalidFormat;
    if (seq_part.len != 3) return error.IdInvalidFormat;

    for (ms_part) |c| {
        if (c < '0' or c > '9') return error.IdInvalidFormat;
    }
    for (seq_part) |c| {
        if (c < '0' or c > '9') return error.IdInvalidFormat;
    }
}

test "validateTitle rejects empty title" {
    try std.testing.expectError(error.TitleEmpty, validateTitle(""));
}

test "validateTitle accepts valid title" {
    try validateTitle("Valid title");
}

test "validateTitle rejects too long title" {
    const long_title = "a" ** (MAX_TITLE_LENGTH + 1);
    try std.testing.expectError(error.TitleTooLong, validateTitle(long_title));
}

test "validateId accepts valid ID" {
    try validateId("1736205028-001-001");
}

test "validateId accepts valid ID with leading zeros" {
    try validateId("1736205028-000-000");
}

test "validateId rejects empty string" {
    try std.testing.expectError(error.IdInvalidFormat, validateId(""));
}

test "validateId rejects ID without dashes" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028001001"));
}

test "validateId rejects ID with only one dash" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-001"));
}

test "validateId rejects ID with too many dashes" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-001-001-001"));
}

test "validateId rejects ID with non-digit timestamp" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("abc-001-001"));
}

test "validateId rejects ID with non-digit ms" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-abc-001"));
}

test "validateId rejects ID with non-digit seq" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-001-abc"));
}

test "validateId rejects ID with wrong ms length" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-1-001"));
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-00123-001"));
}

test "validateId rejects ID with wrong seq length" {
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-001-1"));
    try std.testing.expectError(error.IdInvalidFormat, validateId("1736205028-001-00123"));
}

test "generateId produces unique IDs" {
    const allocator = std.testing.allocator;
    var ids = std.StringArrayHashMap(void).init(allocator);
    defer ids.deinit();

    // Generate 100 IDs rapidly - should all be unique
    for (0..100) |_| {
        const id = try generateId(allocator);
        defer allocator.free(id);

        try std.testing.expect(!ids.contains(id));
        try ids.put(id, {});
    }
}

test "generateId format" {
    const allocator = std.testing.allocator;
    const id = try generateId(allocator);
    defer allocator.free(id);

    // Should match format: {timestamp}-{ms:0>3}-{seq:0>3}
    var parts = std.mem.splitScalar(u8, id, '-');
    const timestamp_part = parts.next().?;
    const ms_part = parts.next().?;
    const seq_part = parts.next().?;
    try std.testing.expect(parts.next() == null); // No more parts

    // Verify parts are non-empty
    try std.testing.expect(timestamp_part.len > 0);
    try std.testing.expectEqual(@as(usize, 3), ms_part.len);
    try std.testing.expectEqual(@as(usize, 3), seq_part.len);
}

// JSON escaping tests
test "escapeJsonString escapes backslash" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "test\\value");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("test\\\\value", result);
}

test "escapeJsonString escapes quotes" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "test\"value");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("test\\\"value", result);
}

test "escapeJsonString escapes newline" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "line1\nline2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("line1\\nline2", result);
}

test "escapeJsonString escapes carriage return" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "text\rmore");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("text\\rmore", result);
}

test "escapeJsonString escapes tab" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "col1\tcol2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("col1\\tcol2", result);
}

test "escapeJsonString handles multiple special characters" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "line1\n\"quoted\"\\slash\r\n");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("line1\\n\\\"quoted\\\"\\\\slash\\r\\n", result);
}

test "escapeJsonString handles plain text" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "plain text");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("plain text", result);
}

test "escapeJsonString handles empty string" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "escapeJsonString escapes forward slash" {
    const allocator = std.testing.allocator;
    const result = try escapeJsonString(allocator, "path/to/file");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("path\\/to\\/file", result);
}

test "escapeJsonString escapes backspace" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 't', 'e', 'x', 't', 0x08, 'm', 'o', 'r', 'e' };
    const result = try escapeJsonString(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("text\\bmore", result);
}

test "escapeJsonString escapes form feed" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'p', 'a', 'g', 'e', '1', 0x0C, 'p', 'a', 'g', 'e', '2' };
    const result = try escapeJsonString(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("page1\\fpage2", result);
}

test "escapeJsonString escapes null character" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 't', 'e', 'x', 't', 0x00, 'm', 'o', 'r', 'e' };
    const result = try escapeJsonString(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("text\\u0000more", result);
}

test "escapeJsonString escapes control characters with hex" {
    const allocator = std.testing.allocator;
    // Test various control characters: \x01, \x1F, \x0B (vertical tab)
    const input = [_]u8{ 0x01, 'a', 0x1F, 'b', 0x0B, 'c' };
    const result = try escapeJsonString(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\\u0001a\\u001fb\\u000bc", result);
}

test "escapeJsonString escapes all control chars from 0x00 to 0x1F" {
    const allocator = std.testing.allocator;
    var input: [32]u8 = undefined;
    for (&input, 0..) |*c, i| c.* = @intCast(i);

    const result = try escapeJsonString(allocator, &input);
    defer allocator.free(result);

    const expected = "\\u0000\\u0001\\u0002\\u0003\\u0004\\u0005\\u0006\\u0007\\b\\t\\n\\u000b\\f\\r\\u000e\\u000f\\u0010\\u0011\\u0012\\u0013\\u0014\\u0015\\u0016\\u0017\\u0018\\u0019\\u001a\\u001b\\u001c\\u001d\\u001e\\u001f";
    try std.testing.expectEqualStrings(expected, result);
}
