const std = @import("std");
const todo = @import("todo.zig");
const util = @import("util.zig");

const MAX_TITLE_LENGTH = 100;

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

        // Handle empty file - treat as new storage
        if (content.len == 0) return todo.TodoList.init(self.allocator);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch |err| {
            std.debug.print("Error: Failed to parse storage file '{s}': {s}\n", .{ self.path, @errorName(err) });
            return error.InvalidJson;
        };
        defer parsed.deinit();

        const root_obj = switch (parsed.value) {
            .object => |o| o,
            else => {
                std.debug.print("Error: Storage file '{s}' must be a JSON object\n", .{self.path});
                return error.InvalidFormat;
            },
        };
        const todos_value = root_obj.get("todos") orelse {
            std.debug.print("Error: Storage file '{s}' missing required 'todos' field\n", .{self.path});
            return error.InvalidFormat;
        };
        const todos_array = switch (todos_value) {
            .array => |a| a,
            else => {
                std.debug.print("Error: Storage file '{s}' 'todos' field must be an array\n", .{self.path});
                return error.InvalidFormat;
            },
        };

        var todo_list = todo.TodoList.init(self.allocator);
        errdefer todo_list.deinit();

        for (todos_array.items, 0..) |item, idx| {
            const item_obj = switch (item) {
                .object => |o| o,
                else => {
                    std.debug.print("Error: Todo at index {d} must be a JSON object\n", .{idx});
                    return error.InvalidFormat;
                },
            };

            const id_value = item_obj.get("id") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'id' field\n", .{idx});
                return error.InvalidFormat;
            };
            const id = try self.allocator.dupe(u8, switch (id_value) {
                .string => |s| s,
                else => {
                    std.debug.print("Error: Todo at index {d} 'id' field must be a string\n", .{idx});
                    return error.InvalidFormat;
                },
            });
            errdefer self.allocator.free(id);

            const title_value = item_obj.get("title") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'title' field\n", .{idx});
                return error.InvalidFormat;
            };
            const title = try self.allocator.dupe(u8, switch (title_value) {
                .string => |s| s,
                else => {
                    std.debug.print("Error: Todo at index {d} 'title' field must be a string\n", .{idx});
                    return error.InvalidFormat;
                },
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

            const tags_value = item_obj.get("tags") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'tags' field\n", .{idx});
                return error.InvalidFormat;
            };
            const tags_arr = switch (tags_value) {
                .array => |a| a,
                else => {
                    std.debug.print("Error: Todo at index {d} 'tags' field must be an array\n", .{idx});
                    return error.InvalidFormat;
                },
            };
            var tags = std.ArrayListUnmanaged([]const u8){};
            for (tags_arr.items) |tag_item| {
                const tag = try self.allocator.dupe(u8, switch (tag_item) {
                    .string => |s| s,
                    else => {
                        std.debug.print("Error: Todo at index {d} 'tags' array contains non-string value\n", .{idx});
                        return error.InvalidFormat;
                    },
                });
                errdefer self.allocator.free(tag);
                try tags.append(self.allocator, tag);
            }

            const depends_value = item_obj.get("depends_on") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'depends_on' field\n", .{idx});
                return error.InvalidFormat;
            };
            const depends_arr = switch (depends_value) {
                .array => |a| a,
                else => {
                    std.debug.print("Error: Todo at index {d} 'depends_on' field must be an array\n", .{idx});
                    return error.InvalidFormat;
                },
            };
            var depends_on = std.ArrayListUnmanaged([]const u8){};
            for (depends_arr.items) |dep_item| {
                const dep = try self.allocator.dupe(u8, switch (dep_item) {
                    .string => |s| s,
                    else => {
                        std.debug.print("Error: Todo at index {d} 'depends_on' array contains non-string value\n", .{idx});
                        return error.InvalidFormat;
                    },
                });
                errdefer self.allocator.free(dep);
                try depends_on.append(self.allocator, dep);
            }

            const blocked_value = item_obj.get("blocked_by") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'blocked_by' field\n", .{idx});
                return error.InvalidFormat;
            };
            const blocked_arr = switch (blocked_value) {
                .array => |a| a,
                else => {
                    std.debug.print("Error: Todo at index {d} 'blocked_by' field must be an array\n", .{idx});
                    return error.InvalidFormat;
                },
            };
            var blocked_by = std.ArrayListUnmanaged([]const u8){};
            for (blocked_arr.items) |blocked_item| {
                const blocked = try self.allocator.dupe(u8, switch (blocked_item) {
                    .string => |s| s,
                    else => {
                        std.debug.print("Error: Todo at index {d} 'blocked_by' array contains non-string value\n", .{idx});
                        return error.InvalidFormat;
                    },
                });
                errdefer self.allocator.free(blocked);
                try blocked_by.append(self.allocator, blocked);
            }

            const created_value = item_obj.get("created_at") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'created_at' field\n", .{idx});
                return error.InvalidFormat;
            };
            const created_at = try self.allocator.dupe(u8, switch (created_value) {
                .string => |s| s,
                else => {
                    std.debug.print("Error: Todo at index {d} 'created_at' field must be a string\n", .{idx});
                    return error.InvalidFormat;
                },
            });
            errdefer self.allocator.free(created_at);

            const updated_value = item_obj.get("updated_at") orelse {
                std.debug.print("Error: Todo at index {d} missing required 'updated_at' field\n", .{idx});
                return error.InvalidFormat;
            };
            const updated_at = try self.allocator.dupe(u8, switch (updated_value) {
                .string => |s| s,
                else => {
                    std.debug.print("Error: Todo at index {d} 'updated_at' field must be a string\n", .{idx});
                    return error.InvalidFormat;
                },
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

        var write_buf: [65536]u8 = undefined;
        var writer = file.writer(&write_buf);

        try util.writeTodosJson(&writer.interface, self.allocator, todo_list.todos);

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

test "load handles empty file" {
    const allocator = std.testing.allocator;
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmp_dir.dir.join(allocator, &[_][]const u8{ "mind.json" });
    defer allocator.free(file_path);

    // Create empty file
    _ = try tmp_dir.dir.createFile("mind.json", .{});

    const storage = Storage.init(allocator, file_path);
    const todo_list = try storage.load();
    defer todo_list.deinit();

    try std.testing.expectEqual(@as(usize, 0), todo_list.todos.len);
}

test "load handles invalid JSON" {
    const allocator = std.testing.allocator;
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmp_dir.dir.join(allocator, &[_][]const u8{ "mind.json" });
    defer allocator.free(file_path);

    // Create file with invalid JSON
    var file = try tmp_dir.dir.createFile("mind.json", .{});
    defer file.close();
    _ = try file.writeAll("{ invalid json }");

    const storage = Storage.init(allocator, file_path);
    const result = storage.load();

    try std.testing.expectError(error.InvalidJson, result);
}

test "load handles missing todos field" {
    const allocator = std.testing.allocator;
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmp_dir.dir.join(allocator, &[_][]const u8{ "mind.json" });
    defer allocator.free(file_path);

    // Create file with valid JSON but missing todos field
    var file = try tmp_dir.dir.createFile("mind.json", .{});
    defer file.close();
    _ = try file.writeAll("{}");

    const storage = Storage.init(allocator, file_path);
    const result = storage.load();

    try std.testing.expectError(error.InvalidFormat, result);
}
