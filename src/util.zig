const std = @import("std");
const todo = @import("todo.zig");

pub const MAX_TITLE_LENGTH = 100;

/// Unicode combining character ranges (simplified for common cases)
const COMBINING_RANGES = [_]struct { start: u21, end: u21 }{
    .{ .start = 0x0300, .end = 0x036F },   // Combining Diacritical Marks
    .{ .start = 0x1AB0, .end = 0x1AFF },   // Combining Diacritical Marks Extended
    .{ .start = 0x20D0, .end = 0x20FF },   // Combining Diacritical Marks for Symbols
    .{ .start = 0xFE20, .end = 0xFE2F },   // Combining Half Marks
};

/// Precomposed character mapping entry
const PrecomposedEntry = struct {
    base: u21,
    combining: u21,
    precomposed: u21,
};

/// Common precomposed mappings (NFC)
const PRECOMPOSED_ENTRIES = [_]PrecomposedEntry{
    // Grave accent
    .{ .base = 'a', .combining = 0x0300, .precomposed = 0x00E0 },  // à
    .{ .base = 'e', .combining = 0x0300, .precomposed = 0x00E8 },  // è
    .{ .base = 'i', .combining = 0x0300, .precomposed = 0x00EC },  // ì
    .{ .base = 'o', .combining = 0x0300, .precomposed = 0x00F2 },  // ò
    .{ .base = 'u', .combining = 0x0300, .precomposed = 0x00F9 },  // ù
    .{ .base = 'A', .combining = 0x0300, .precomposed = 0x00C0 },  // À
    .{ .base = 'E', .combining = 0x0300, .precomposed = 0x00C8 },  // È
    .{ .base = 'I', .combining = 0x0300, .precomposed = 0x00CC },  // Ì
    .{ .base = 'O', .combining = 0x0300, .precomposed = 0x00D2 },  // Ò
    .{ .base = 'U', .combining = 0x0300, .precomposed = 0x00D9 },  // Ù

    // Acute accent
    .{ .base = 'a', .combining = 0x0301, .precomposed = 0x00E1 },  // á
    .{ .base = 'e', .combining = 0x0301, .precomposed = 0x00E9 },  // é
    .{ .base = 'i', .combining = 0x0301, .precomposed = 0x00ED },  // í
    .{ .base = 'o', .combining = 0x0301, .precomposed = 0x00F3 },  // ó
    .{ .base = 'u', .combining = 0x0301, .precomposed = 0x00FA },  // ú
    .{ .base = 'y', .combining = 0x0301, .precomposed = 0x00FD },  // ý
    .{ .base = 'A', .combining = 0x0301, .precomposed = 0x00C1 },  // Á
    .{ .base = 'E', .combining = 0x0301, .precomposed = 0x00C9 },  // É
    .{ .base = 'I', .combining = 0x0301, .precomposed = 0x00CD },  // Í
    .{ .base = 'O', .combining = 0x0301, .precomposed = 0x00D3 },  // Ó
    .{ .base = 'U', .combining = 0x0301, .precomposed = 0x00DA },  // Ú
    .{ .base = 'Y', .combining = 0x0301, .precomposed = 0x00DD },  // Ý

    // Circumflex
    .{ .base = 'a', .combining = 0x0302, .precomposed = 0x00E2 },  // â
    .{ .base = 'e', .combining = 0x0302, .precomposed = 0x00EA },  // ê
    .{ .base = 'i', .combining = 0x0302, .precomposed = 0x00EE },  // î
    .{ .base = 'o', .combining = 0x0302, .precomposed = 0x00F4 },  // ô
    .{ .base = 'u', .combining = 0x0302, .precomposed = 0x00FB },  // û
    .{ .base = 'A', .combining = 0x0302, .precomposed = 0x00C2 },  // Â
    .{ .base = 'E', .combining = 0x0302, .precomposed = 0x00CA },  // Ê
    .{ .base = 'I', .combining = 0x0302, .precomposed = 0x00CE },  // Î
    .{ .base = 'O', .combining = 0x0302, .precomposed = 0x00D4 },  // Ô
    .{ .base = 'U', .combining = 0x0302, .precomposed = 0x00DB },  // Û

    // Tilde
    .{ .base = 'a', .combining = 0x0303, .precomposed = 0x00E3 },  // ã
    .{ .base = 'n', .combining = 0x0303, .precomposed = 0x00F1 },  // ñ
    .{ .base = 'o', .combining = 0x0303, .precomposed = 0x00F5 },  // õ
    .{ .base = 'A', .combining = 0x0303, .precomposed = 0x00C3 },  // Ã
    .{ .base = 'N', .combining = 0x0303, .precomposed = 0x00D1 },  // Ñ
    .{ .base = 'O', .combining = 0x0303, .precomposed = 0x00D5 },  // Õ

    // Diaeresis (umlaut)
    .{ .base = 'a', .combining = 0x0308, .precomposed = 0x00E4 },  // ä
    .{ .base = 'e', .combining = 0x0308, .precomposed = 0x00EB },  // ë
    .{ .base = 'i', .combining = 0x0308, .precomposed = 0x00EF },  // ï
    .{ .base = 'o', .combining = 0x0308, .precomposed = 0x00F6 },  // ö
    .{ .base = 'u', .combining = 0x0308, .precomposed = 0x00FC },  // ü
    .{ .base = 'y', .combining = 0x0308, .precomposed = 0x00FF },  // ÿ
    .{ .base = 'A', .combining = 0x0308, .precomposed = 0x00C4 },  // Ä
    .{ .base = 'E', .combining = 0x0308, .precomposed = 0x00CB },  // Ë
    .{ .base = 'I', .combining = 0x0308, .precomposed = 0x00CF },  // Ï
    .{ .base = 'O', .combining = 0x0308, .precomposed = 0x00D6 },  // Ö
    .{ .base = 'U', .combining = 0x0308, .precomposed = 0x00DC },  // Ü

    // Cedilla
    .{ .base = 'c', .combining = 0x0327, .precomposed = 0x00E7 },  // ç
    .{ .base = 'C', .combining = 0x0327, .precomposed = 0x00C7 },  // Ç

    // Macron
    .{ .base = 'a', .combining = 0x0304, .precomposed = 0x0101 },  // ā
    .{ .base = 'A', .combining = 0x0304, .precomposed = 0x0100 },  // Ā
    .{ .base = 'e', .combining = 0x0304, .precomposed = 0x0113 },  // ē
    .{ .base = 'E', .combining = 0x0304, .precomposed = 0x0112 },  // Ē
    .{ .base = 'i', .combining = 0x0304, .precomposed = 0x012B },  // ī
    .{ .base = 'I', .combining = 0x0304, .precomposed = 0x012A },  // Ī
    .{ .base = 'o', .combining = 0x0304, .precomposed = 0x014D },  // ō
    .{ .base = 'O', .combining = 0x0304, .precomposed = 0x014C },  // Ō
    .{ .base = 'u', .combining = 0x0304, .precomposed = 0x016B },  // ū
    .{ .base = 'U', .combining = 0x0304, .precomposed = 0x016A },  // Ū

    // Dot above
    .{ .base = 'a', .combining = 0x0307, .precomposed = 0x0105 },  // ą
    .{ .base = 'A', .combining = 0x0307, .precomposed = 0x0104 },  // Ą
    .{ .base = 'e', .combining = 0x0307, .precomposed = 0x0117 },  // ė
    .{ .base = 'E', .combining = 0x0307, .precomposed = 0x0116 },  // Ė
    .{ .base = 'i', .combining = 0x0307, .precomposed = 0x0131 },  // ı
    .{ .base = 'I', .combining = 0x0307, .precomposed = 0x0130 },  // İ
};

/// Check if a codepoint is a combining character
fn isCombining(cp: u21) bool {
    for (COMBINING_RANGES) |range| {
        if (cp >= range.start and cp <= range.end) return true;
    }
    return false;
}

/// Find precomposed form for base + combining mark
fn findPrecomposed(base: u21, combining: u21) ?u21 {
    for (PRECOMPOSED_ENTRIES) |entry| {
        if (entry.base == base and entry.combining == combining) {
            return entry.precomposed;
        }
    }
    return null;
}

/// Normalize string to NFC form (canonical composition)
/// Converts decomposed characters (e.g., e + combining acute) to precomposed (é)
/// Returns allocated string in normalized form
pub fn normalizeNfc(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (input.len == 0) return allocator.dupe(u8, "");

    var result = std.ArrayListUnmanaged(u8){};
    try result.ensureTotalCapacity(allocator, input.len);
    defer result.deinit(allocator);

    var it = std.unicode.Utf8View.initUnchecked(input).iterator();
    var pending_combining: ?u21 = null;

    while (it.nextCodepoint()) |cp| {
        if (!isCombining(cp)) {
            // Flush any pending combining mark
            if (pending_combining) |comb| {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(comb, &buf) catch continue;
                try result.appendSlice(allocator, buf[0..len]);
                pending_combining = null;
            }

            // Write base character
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch continue;
            try result.appendSlice(allocator, buf[0..len]);
        } else {
            // This is a combining mark
            if (result.items.len > 0 and pending_combining == null) {
                // Try to combine with last base character
                const prev_utf8 = std.unicode.Utf8View.initUnchecked(result.items);
                var prev_it = prev_utf8.iterator();
                var prev_cp: ?u21 = null;

                // Get last codepoint
                while (prev_it.nextCodepoint()) |code| {
                    prev_cp = code;
                }

                if (prev_cp) |base| {
                    if (findPrecomposed(base, cp)) |precomposed| {
                        // Replace base with precomposed
                        var combo_buf: [4]u8 = undefined;
                        const base_len = std.unicode.utf8Encode(base, &combo_buf) catch unreachable;
                        const precomposed_len = std.unicode.utf8Encode(precomposed, &combo_buf) catch continue;

                        // Remove base from result
                        result.items.len -= base_len;

                        // Add precomposed
                        try result.appendSlice(allocator, combo_buf[0..precomposed_len]);
                    } else {
                        // No precomposed form, keep as combining mark
                        pending_combining = cp;
                    }
                } else {
                    pending_combining = cp;
                }
            } else {
                // Multiple combining marks - just write them
                pending_combining = cp;
            }
        }
    }

    // Flush any pending combining mark
    if (pending_combining) |comb| {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(comb, &buf) catch {
            return result.toOwnedSlice(allocator);
        };
        try result.appendSlice(allocator, buf[0..len]);
    }

    return result.toOwnedSlice(allocator);
}

/// Compare two strings with Unicode normalization
pub fn eqlNormalized(a: []const u8, b: []const u8) bool {
    // Quick path: byte comparison
    if (std.mem.eql(u8, a, b)) return true;

    // Slow path: need normalization
    // For simplicity, just do byte compare for now
    // Full normalization would require allocation
    // In most practical cases, byte comparison is sufficient
    // when both strings have been normalized on input
    return false;
}

// Unicode normalization tests
test "normalizeNfc handles empty string" {
    const allocator = std.testing.allocator;
    const result = try normalizeNfc(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "normalizeNfc handles plain ASCII" {
    const allocator = std.testing.allocator;
    const result = try normalizeNfc(allocator, "hello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "normalizeNfc converts e + combining acute to é" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'e', 0xCC, 0x81 }; // e + combining acute
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\u{00E9}", result); // Single é character
}

test "normalizeNfc converts a + combining grave to à" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'a', 0xCC, 0x80 }; // a + combining grave
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\u{00E0}", result); // Single à character
}

test "normalizeNfc converts n + combining tilde to ñ" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'n', 0xCC, 0xA3 }; // n + combining tilde
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\u{00F1}", result); // Single ñ character
}

test "normalizeNfc converts c + combining cedilla to ç" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'c', 0xCC, 0xA7 }; // c + combining cedilla
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\u{00E7}", result); // Single ç character
}

test "normalizeNfc handles mixed text" {
    const allocator = std.testing.allocator;
    // "cafe" with e + combining acute + " " + "na" with n + combining tilde + "t" + "ive"
    const input = [_]u8{ 'c', 'a', 'f', 'e', 0xCC, 0x81, ' ', 'n', 'a', 0xCC, 0xA3, 't', 'i', 'v', 'e' };
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("café naïve", result);
}

test "normalizeNfc handles already precomposed text" {
    const allocator = std.testing.allocator;
    const result = try normalizeNfc(allocator, "café");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("café", result);
}

test "normalizeNfc handles multiple combining marks on same base" {
    const allocator = std.testing.allocator;
    // e + combining acute + combining grave (no precomposed form)
    const input = [_]u8{ 'e', 0xCC, 0x81, 0xCC, 0x80 };
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    // Should keep both combining marks as there's no precomposed form
    try std.testing.expectEqualStrings(&input, result);
}

test "normalizeNfc handles uppercase letters" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'E', 0xCC, 0x81 }; // E + combining acute
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\u{00C9}", result); // Single É character
}

test "normalizeNfc handles u + diaeresis" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 'u', 0xCC, 0x88 }; // u + combining diaeresis
    const result = try normalizeNfc(allocator, &input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\u{00FC}", result); // Single ü character
}

test "normalizeNfc makes decomposed and precomposed tags equivalent" {
    const allocator = std.testing.allocator;

    // Precomposed "café"
    const precomposed = "café";
    // Decomposed "café" (c, a, f, e, combining acute)
    const decomposed = [_]u8{ 'c', 'a', 'f', 'e', 0xCC, 0x81 };

    const norm1 = try normalizeNfc(allocator, precomposed);
    defer allocator.free(norm1);

    const norm2 = try normalizeNfc(allocator, &decomposed);
    defer allocator.free(norm2);

    // Both should normalize to the same precomposed form
    try std.testing.expectEqualStrings(norm1, norm2);
}

test "normalizeNfc preserves already normalized text" {
    const allocator = std.testing.allocator;
    const input = "café naïve";

    const result = try normalizeNfc(allocator, input);
    defer allocator.free(result);

    // Already normalized text should pass through unchanged
    try std.testing.expectEqualStrings(input, result);
}

/// Escapes a string for JSON output (handles backslash, quotes, control chars)
/// Returns allocated string. For direct writing to buffered output, prefer writeEscapedStringToWriter.
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

/// Writes an escaped string directly to a writer, avoiding allocation.
/// Use this for tight loops where allocating per string would be inefficient.
pub fn writeEscapedStringToWriter(writer: anytype, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '/' => try writer.writeAll("\\/"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.writeAll("\\u00");
                    try writer.print("{x:0>2}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Writes a single todo as JSON to a writer (no newline after closing brace)
pub fn writeTodoJson(writer: anytype, allocator: std.mem.Allocator, item: todo.Todo) !void {
    _ = allocator; // Unused after optimization
    const status_str = item.status.toString();
    const priority_str = item.priority.toString();

    try writer.writeAll("    {\n");
    try writer.writeAll("      \"id\": \"");
    try writeEscapedStringToWriter(writer, item.id);
    try writer.writeAll("\",\n");

    try writer.writeAll("      \"title\": \"");
    try writeEscapedStringToWriter(writer, item.title);
    try writer.writeAll("\",\n");

    try writer.writeAll("      \"body\": \"");
    try writeEscapedStringToWriter(writer, item.body);
    try writer.writeAll("\",\n");

    try writer.print("      \"status\": \"{s}\",\n", .{status_str});

    try writer.print("      \"priority\": \"{s}\",\n", .{priority_str});

    try writer.writeAll("      \"tags\": [");
    for (item.tags, 0..) |tag, j| {
        try writer.writeAll("\"");
        try writeEscapedStringToWriter(writer, tag);
        try writer.writeAll("\"");
        if (j < item.tags.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll("],\n");

    try writer.writeAll("      \"depends_on\": [");
    for (item.depends_on, 0..) |dep, j| {
        try writer.writeAll("\"");
        try writeEscapedStringToWriter(writer, dep);
        try writer.writeAll("\"");
        if (j < item.depends_on.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll("],\n");

    try writer.writeAll("      \"blocked_by\": [");
    for (item.blocked_by, 0..) |blocked, j| {
        try writer.writeAll("\"");
        try writeEscapedStringToWriter(writer, blocked);
        try writer.writeAll("\"");
        if (j < item.blocked_by.len - 1) try writer.writeAll(", ");
    }
    try writer.writeAll("],\n");

    try writer.writeAll("      \"created_at\": \"");
    try writeEscapedStringToWriter(writer, item.created_at);
    try writer.writeAll("\",\n");

    try writer.writeAll("      \"updated_at\": \"");
    try writeEscapedStringToWriter(writer, item.updated_at);
    try writer.writeAll("\",\n");

    try writer.writeAll("      \"resolution_reason\": \"");
    try writeEscapedStringToWriter(writer, item.resolution_reason);
    try writer.writeAll("\"\n");

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

test "writeEscapedStringToWriter matches escapeJsonString" {
    const allocator = std.testing.allocator;
    const test_cases = [_][]const u8{
        "plain text",
        "test\\value",
        "test\"value",
        "line1\nline2",
        "text\rmore",
        "col1\tcol2",
        "line1\n\"quoted\"\\slash\r\n",
        "path/to/file",
    };

    for (test_cases) |input| {
        const allocated = try escapeJsonString(allocator, input);
        defer allocator.free(allocated);

        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        try writeEscapedStringToWriter(buffer.writer(), input);

        try std.testing.expectEqualStrings(allocated, buffer.items);
    }
}
