const std = @import("std");
const todo = @import("todo.zig");

const MAX_TITLE_LENGTH = 100;

fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '"' => try result.appendSlice(allocator, "\\\""),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSlice(allocator);
}

pub const Storage = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) Storage {
        return .{
            .allocator = allocator,
            .path = path,
        };
    }

    pub fn load(self: Storage) !todo.TodoList {
        const file = std.fs.cwd().openFile(self.path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return todo.TodoList.init(self.allocator);
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        // Handle empty file
        if (content.len == 0) return todo.TodoList.init(self.allocator);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root_obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidFormat,
        };
        const todos_value = root_obj.get("todos") orelse return error.InvalidFormat;
        const todos_array = switch (todos_value) {
            .array => |a| a,
            else => return error.InvalidFormat,
        };

        var todo_list = todo.TodoList.init(self.allocator);
        errdefer todo_list.deinit();

        for (todos_array.items) |item| {
            const item_obj = switch (item) {
                .object => |o| o,
                else => return error.InvalidFormat,
            };

            const id_value = item_obj.get("id") orelse return error.InvalidFormat;
            const id = try self.allocator.dupe(u8, switch (id_value) {
                .string => |s| s,
                else => return error.InvalidFormat,
            });
            errdefer self.allocator.free(id);

            const title_value = item_obj.get("title") orelse return error.InvalidFormat;
            const title = try self.allocator.dupe(u8, switch (title_value) {
                .string => |s| s,
                else => return error.InvalidFormat,
            });
            errdefer self.allocator.free(title);

            const body_value = item_obj.get("body") orelse std.json.Value{ .string = "" };
            const body = try self.allocator.dupe(u8, switch (body_value) {
                .string => |s| s,
                else => "",
            });
            errdefer self.allocator.free(body);

            const status_value = item_obj.get("status") orelse std.json.Value{ .string = "pending" };
            const status_str = switch (status_value) {
                .string => |s| s,
                else => "pending",
            };
            const status = todo.Status.fromString(status_str) orelse .pending;

            const tags_value = item_obj.get("tags") orelse return error.InvalidFormat;
            const tags_arr = switch (tags_value) {
                .array => |a| a,
                else => return error.InvalidFormat,
            };
            var tags = std.ArrayListUnmanaged([]const u8){};
            for (tags_arr.items) |tag_item| {
                const tag = try self.allocator.dupe(u8, switch (tag_item) {
                    .string => |s| s,
                    else => return error.InvalidFormat,
                });
                errdefer self.allocator.free(tag);
                try tags.append(self.allocator, tag);
            }

            const depends_value = item_obj.get("depends_on") orelse return error.InvalidFormat;
            const depends_arr = switch (depends_value) {
                .array => |a| a,
                else => return error.InvalidFormat,
            };
            var depends_on = std.ArrayListUnmanaged([]const u8){};
            for (depends_arr.items) |dep_item| {
                const dep = try self.allocator.dupe(u8, switch (dep_item) {
                    .string => |s| s,
                    else => return error.InvalidFormat,
                });
                errdefer self.allocator.free(dep);
                try depends_on.append(self.allocator, dep);
            }

            const blocked_value = item_obj.get("blocked_by") orelse return error.InvalidFormat;
            const blocked_arr = switch (blocked_value) {
                .array => |a| a,
                else => return error.InvalidFormat,
            };
            var blocked_by = std.ArrayListUnmanaged([]const u8){};
            for (blocked_arr.items) |blocked_item| {
                const blocked = try self.allocator.dupe(u8, switch (blocked_item) {
                    .string => |s| s,
                    else => return error.InvalidFormat,
                });
                errdefer self.allocator.free(blocked);
                try blocked_by.append(self.allocator, blocked);
            }

            const created_value = item_obj.get("created_at") orelse return error.InvalidFormat;
            const created_at = try self.allocator.dupe(u8, switch (created_value) {
                .string => |s| s,
                else => return error.InvalidFormat,
            });
            errdefer self.allocator.free(created_at);

            const updated_value = item_obj.get("updated_at") orelse return error.InvalidFormat;
            const updated_at = try self.allocator.dupe(u8, switch (updated_value) {
                .string => |s| s,
                else => return error.InvalidFormat,
            });
            errdefer self.allocator.free(updated_at);

            const resolution_value = item_obj.get("resolution_reason") orelse std.json.Value{ .string = "" };
            const resolution_reason = try self.allocator.dupe(u8, switch (resolution_value) {
                .string => |s| s,
                else => "",
            });
            errdefer self.allocator.free(resolution_reason);

            const tags_slice = try tags.toOwnedSlice(self.allocator);
            const depends_slice = try depends_on.toOwnedSlice(self.allocator);
            const blocked_slice = try blocked_by.toOwnedSlice(self.allocator);

            try todo_list.add(todo.Todo{
                .id = id,
                .title = title,
                .body = body,
                .status = status,
                .tags = tags_slice,
                .depends_on = depends_slice,
                .blocked_by = blocked_slice,
                .created_at = created_at,
                .updated_at = updated_at,
                .resolution_reason = resolution_reason,
            });
        }

        return todo_list;
    }

    pub fn save(self: Storage, todo_list: *todo.TodoList) !void {
        // Ensure directory exists
        const dir = std.fs.path.dirname(self.path) orelse ".";
        try std.fs.cwd().makePath(dir);

        // Compute blocked_by
        try todo_list.computeBlockedBy();

        // Format JSON manually
        const file = try std.fs.cwd().createFile(self.path, .{});

        var write_buf: [4096]u8 = undefined;
        var writer = file.writer(&write_buf);

        try writer.interface.writeAll("{\n  \"todos\": [\n");

        for (todo_list.todos, 0..) |item, i| {
            const escaped_id = try escapeJsonString(self.allocator, item.id);
            defer self.allocator.free(escaped_id);

            const escaped_title = try escapeJsonString(self.allocator, item.title);
            defer self.allocator.free(escaped_title);

            const escaped_body = try escapeJsonString(self.allocator, item.body);
            defer self.allocator.free(escaped_body);

            const status_str = item.status.toString();

            try writer.interface.writeAll("    {\n");
            try writer.interface.print("      \"id\": \"{s}\",\n", .{escaped_id});
            try writer.interface.print("      \"title\": \"{s}\",\n", .{escaped_title});
            try writer.interface.print("      \"body\": \"{s}\",\n", .{escaped_body});
            try writer.interface.print("      \"status\": \"{s}\",\n", .{status_str});

            try writer.interface.writeAll("      \"tags\": [");
            for (item.tags, 0..) |tag, j| {
                const escaped_tag = try escapeJsonString(self.allocator, tag);
                defer self.allocator.free(escaped_tag);
                try writer.interface.print("\"{s}\"", .{escaped_tag});
                if (j < item.tags.len - 1) try writer.interface.writeAll(", ");
            }
            try writer.interface.writeAll("],\n");

            try writer.interface.writeAll("      \"depends_on\": [");
            for (item.depends_on, 0..) |dep, j| {
                const escaped_dep = try escapeJsonString(self.allocator, dep);
                defer self.allocator.free(escaped_dep);
                try writer.interface.print("\"{s}\"", .{escaped_dep});
                if (j < item.depends_on.len - 1) try writer.interface.writeAll(", ");
            }
            try writer.interface.writeAll("],\n");

            try writer.interface.writeAll("      \"blocked_by\": [");
            for (item.blocked_by, 0..) |blocked, j| {
                const escaped_blocked = try escapeJsonString(self.allocator, blocked);
                defer self.allocator.free(escaped_blocked);
                try writer.interface.print("\"{s}\"", .{escaped_blocked});
                if (j < item.blocked_by.len - 1) try writer.interface.writeAll(", ");
            }
            try writer.interface.writeAll("],\n");

            const escaped_created = try escapeJsonString(self.allocator, item.created_at);
            defer self.allocator.free(escaped_created);
            const escaped_updated = try escapeJsonString(self.allocator, item.updated_at);
            defer self.allocator.free(escaped_updated);
            const escaped_resolution = try escapeJsonString(self.allocator, item.resolution_reason);
            defer self.allocator.free(escaped_resolution);

            try writer.interface.print("      \"created_at\": \"{s}\",\n", .{escaped_created});
            try writer.interface.print("      \"updated_at\": \"{s}\",\n", .{escaped_updated});
            try writer.interface.print("      \"resolution_reason\": \"{s}\"\n", .{escaped_resolution});
            try writer.interface.writeAll("    }");
            if (i < todo_list.todos.len - 1) try writer.interface.writeAll(",");
            try writer.interface.writeAll("\n");
        }

        try writer.interface.writeAll("  ]\n}\n");

        // Flush the writer
        try writer.end();
    }

    pub fn exists(self: Storage) bool {
        std.fs.cwd().access(self.path, .{}) catch |err| {
            if (err == error.FileNotFound) return false;
            return true;
        };
        return true;
    }
};

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
