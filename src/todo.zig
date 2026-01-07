const std = @import("std");
const util = @import("util.zig");

pub const Status = enum(u8) {
    pending,
    @"in-progress",
    done,

    pub fn fromString(str: []const u8) ?Status {
        if (std.mem.eql(u8, str, "pending")) return .pending;
        if (std.mem.eql(u8, str, "in-progress")) return .@"in-progress";
        if (std.mem.eql(u8, str, "done")) return .done;
        return null;
    }

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .pending => "pending",
            .@"in-progress" => "in-progress",
            .done => "done",
        };
    }

    pub fn format(self: Status, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(fmt, .{self.toString()});
    }
};

pub const Todo = struct {
    id: []const u8,
    title: []const u8,
    body: []const u8,
    status: Status,
    tags: []const []const u8,
    depends_on: []const []const u8,
    blocked_by: []const []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

pub const TodoList = struct {
    todos: []Todo,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TodoList {
        return .{
            .todos = &.{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TodoList) void {
        for (self.todos) |*todo| {
            self.allocator.free(todo.id);
            self.allocator.free(todo.title);
            self.allocator.free(todo.body);
            for (todo.tags) |tag| self.allocator.free(tag);
            self.allocator.free(todo.tags);
            self.allocator.free(todo.depends_on);
            self.allocator.free(todo.blocked_by);
            self.allocator.free(todo.created_at);
            self.allocator.free(todo.updated_at);
        }
        self.allocator.free(self.todos);
    }

    pub fn add(self: *TodoList, todo: Todo) !void {
        const new_todos = try self.allocator.realloc(self.todos, self.todos.len + 1);
        new_todos[self.todos.len] = todo;
        self.todos = new_todos;
    }

    pub fn findById(self: TodoList, id: []const u8) ?*const Todo {
        for (self.todos, 0..) |_, i| {
            if (std.mem.eql(u8, self.todos[i].id, id)) return &self.todos[i];
        }
        return null;
    }

    pub fn findIndexById(self: TodoList, id: []const u8) ?usize {
        for (self.todos, 0..) |_, i| {
            if (std.mem.eql(u8, self.todos[i].id, id)) return i;
        }
        return null;
    }

    pub fn remove(self: *TodoList, id: []const u8) !void {
        const idx = self.findIndexById(id) orelse return error.TodoNotFound;
        
        // Free removed todo memory
        const todo = self.todos[idx];
        self.allocator.free(todo.id);
        self.allocator.free(todo.title);
        self.allocator.free(todo.body);
        for (todo.tags) |tag| self.allocator.free(tag);
        self.allocator.free(todo.tags);
        self.allocator.free(todo.depends_on);
        self.allocator.free(todo.blocked_by);
        self.allocator.free(todo.created_at);
        self.allocator.free(todo.updated_at);

        // Shift remaining todos
        for (idx + 1..self.todos.len) |i| {
            self.todos[i - 1] = self.todos[i];
        }

        self.todos = self.allocator.realloc(self.todos, self.todos.len - 1) catch |err| {
            // If shrink fails, we still have the original array, just try to shrink from end
            // This is a best-effort, shouldn't happen in practice
            return err;
        };
    }

    pub fn computeBlockedBy(self: *TodoList) !void {
        // Build a list of blocked_by for each todo
        var blocked_lists = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)){};
        defer {
            for (blocked_lists.items) |*list| {
                for (list.items) |id| self.allocator.free(id);
                list.deinit(self.allocator);
            }
            blocked_lists.deinit(self.allocator);
        }

        // Initialize empty lists for all todos
        try blocked_lists.ensureTotalCapacity(self.allocator, self.todos.len);
        for (0..self.todos.len) |_| {
            try blocked_lists.append(self.allocator, .{});
        }

        // Find which todos block each dependency
        for (self.todos) |*todo| {
            for (todo.depends_on) |dep_id| {
                for (self.todos, 0..) |*dep_todo, j| {
                    if (std.mem.eql(u8, dep_todo.id, dep_id)) {
                        // Add current todo id to dependency's blocked list
                        const id_copy = try self.allocator.dupe(u8, todo.id);
                        try blocked_lists.items[j].append(self.allocator, id_copy);
                    }
                }
            }
        }

        // Update todos with their new blocked_by lists
        for (self.todos, 0..) |*todo, i| {
            self.allocator.free(todo.blocked_by);
            todo.blocked_by = try blocked_lists.items[i].toOwnedSlice(self.allocator);
            // Free the old backing array from the ArrayList
            if (blocked_lists.items[i].capacity > 0) {
                self.allocator.free(blocked_lists.items[i].allocatedSlice());
            }
            blocked_lists.items[i] = .{}; // Clear so destructor doesn't double-free
        }
    }

    pub fn isBlocked(_: TodoList, todo: Todo) bool {
        return todo.blocked_by.len > 0;
    }
};

pub fn createTodo(
    allocator: std.mem.Allocator,
    title: []const u8,
    body: []const u8,
    tags: []const []const u8,
    depends_on: []const []const u8,
) !Todo {
    try util.validateTitle(title);

    const id = try util.generateId(allocator);
    errdefer allocator.free(id);

    const title_copy = try allocator.dupe(u8, title);
    errdefer allocator.free(title_copy);

    const body_copy = try allocator.dupe(u8, body);
    errdefer allocator.free(body_copy);

    var tags_copy = try allocator.alloc([]const u8, tags.len);
    errdefer {
        for (tags_copy) |tag| allocator.free(tag);
        allocator.free(tags_copy);
    }
    for (tags, 0..) |tag, i| {
        tags_copy[i] = try allocator.dupe(u8, tag);
    }

    var depends_copy = try allocator.alloc([]const u8, depends_on.len);
    errdefer {
        for (depends_copy) |dep| allocator.free(dep);
        allocator.free(depends_copy);
    }
    for (depends_on, 0..) |dep, i| {
        depends_copy[i] = try allocator.dupe(u8, dep);
    }

    const timestamp = try util.getCurrentTimestamp(allocator);
    errdefer allocator.free(timestamp);

    return Todo{
        .id = id,
        .title = title_copy,
        .body = body_copy,
        .status = .pending,
        .tags = tags_copy,
        .depends_on = depends_copy,
        .blocked_by = try allocator.alloc([]const u8, 0),
        .created_at = timestamp,
        .updated_at = try allocator.dupe(u8, timestamp),
    };
}

test "createTodo validates title length" {
    const allocator = std.testing.allocator;
    const long_title = "a" ** 101;
    const result = createTodo(allocator, &long_title, "", &.{}, &.{});
    try std.testing.expectError(error.TitleTooLong, result);
}

test "createTodo rejects empty title" {
    const allocator = std.testing.allocator;
    const result = createTodo(allocator, "", "", &.{}, &.{});
    try std.testing.expectError(error.TitleEmpty, result);
}
