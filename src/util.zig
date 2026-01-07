const std = @import("std");

const MAX_TITLE_LENGTH = 100;

pub fn generateId(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();

    // Get milliseconds for uniqueness
    const ms = @as(u32, @intCast(@rem(timestamp, 1000)));

    return std.fmt.allocPrint(allocator, "{d}-{d:0>3}", .{ timestamp, ms });
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
