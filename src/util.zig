const std = @import("std");

const MAX_TITLE_LENGTH = 100;

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

test "generateId produces unique IDs" {
    const allocator = std.testing.allocator;
    var ids = std.StringArrayHashMap(void).init(allocator);
    defer ids.deinit();

    // Generate 100 IDs rapidly - should all be unique
    for (0..100) |_| {
        const id = try generateId(allocator);
        defer allocator.free(id);

        try std.testing.expect(!ids.contains(id), "ID collision detected: {s}", .{id});
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
