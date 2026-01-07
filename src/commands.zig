const std = @import("std");
const cli = @import("cli.zig");
const todo = @import("todo.zig");
const storage = @import("storage.zig");

const BODY_HINT = "Tip: Add a body with --body to provide context for this todo";

pub fn executeAdd(allocator: std.mem.Allocator, args: cli.Args, store_path: []const u8) !void {
    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    if (args.title == null) {
        try stderr.writeAll("error: add requires a title\n");
        return error.MissingTitle;
    }

    var tags_list = std.ArrayListUnmanaged([]const u8){};
    defer tags_list.deinit(allocator);

    if (args.tags) |tags_str| {
        var iter = std.mem.splitScalar(u8, tags_str, ',');
        while (iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                try tags_list.append(allocator, trimmed);
            }
        }
    }

    const body = args.body orelse "";

    const new_todo = try todo.createTodo(
        allocator,
        args.title.?,
        body,
        tags_list.items,
        &.{},
    );

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    try todo_list.add(new_todo);
    st.save(&todo_list) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "Save error: {}\n", .{err});
        try stderr.writeAll(msg);
        return err;
    };

    try stdout.writeAll("Created todo: ");
    try stdout.writeAll(new_todo.id);
    try stdout.writeAll("\n  ");
    try stdout.writeAll(new_todo.title);
    try stdout.writeAll("\n");

    if (body.len == 0) {
        try stdout.writeAll("\n");
        try stdout.writeAll(BODY_HINT);
        try stdout.writeAll("\n");
    }
}

pub fn executeList(allocator: std.mem.Allocator, args: cli.Args, store_path: []const u8) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Apply filters - for now, no filtering
    const todos_to_show = todo_list.todos;

    if (args.json) {
        try outputJson(&stdout, todos_to_show);
    } else {
        try outputList(&stdout, todos_to_show);
    }

    // Flush the buffer
    try stdout.end();
}

pub fn executeShow(allocator: std.mem.Allocator, args: cli.Args, store_path: []const u8) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    defer stdout.end() catch {};
    defer stderr.end() catch {};

    if (args.target == null) {
        try (&stderr.interface).writeAll("error: show requires a todo ID\n");
        return error.MissingId;
    }

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const item = todo_list.findById(args.target.?) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.target.?});
        return error.TodoNotFound;
    };

    if (args.json) {
        try outputJson(&stdout, &[_]todo.Todo{item.*});
    } else {
        try outputTodoDetail(&stdout, item.*, &todo_list);
    }
}

pub fn executeDone(allocator: std.mem.Allocator, args: cli.Args, store_path: []const u8) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    defer stdout.end() catch {};
    defer stderr.end() catch {};

    if (args.target == null) {
        try cli.printError(stderr, "done requires a todo ID", .{});
        try cli.printCommandHelp(&stdout, .done);
        return error.MissingId;
    }

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const idx = todo_list.findIndexById(args.target.?) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.target.?});
        return error.TodoNotFound;
    };

    // Check if blocked
    if (todo_list.isBlocked(todo_list.todos[idx])) {
        try cli.printError(stderr, "cannot mark blocked todo as done. Unblock dependencies first.", .{});
        return error.TodoBlocked;
    }

    // Update status
    todo_list.todos[idx].status = .done;
    
    // Update timestamp
    allocator.free(todo_list.todos[idx].updated_at);
    todo_list.todos[idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

    try st.save(&todo_list);

    try stdout.interface.print("Marked todo as done: {s}\n", .{args.target.?});
}

fn outputList(writer: *std.fs.File.Writer, todos: []const todo.Todo) !void {
    const w = &writer.interface;

    if (todos.len == 0) {
        try w.writeAll("No todos found.\n");
        return;
    }

    for (todos) |item| {
        const status_str = item.status.toString();
        const title_trunc = if (item.title.len > 40) item.title[0..40] ++ "..." else item.title;
        
        try w.print("{s} {s:<12} {s}\n", .{ item.id, status_str, title_trunc });
    }
}

fn outputTodoDetail(writer: *std.fs.File.Writer, item: todo.Todo, todo_list: *const todo.TodoList) !void {
    const w = &writer.interface;

    try w.print("ID: {s}\n", .{item.id});
    try w.print("Status: {s}\n", .{item.status.toString()});
    try w.print("Title: {s}\n", .{item.title});

    if (item.body.len > 0) {
        try w.print("\nBody:\n{s}\n", .{item.body});
    }

    if (item.tags.len > 0) {
        try w.writeAll("\nTags: ");
        for (item.tags, 0..) |tag, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll(tag);
        }
        try w.writeAll("\n");
    }

    if (item.depends_on.len > 0) {
        try w.writeAll("\nDepends on:\n");
        for (item.depends_on) |dep_id| {
            const status = if (todo_list.findById(dep_id)) |parent| parent.status else .pending;
            const status_str = status.toString();
            try w.print("  {s} ({s})\n", .{ dep_id, status_str });
        }
    }

    if (item.blocked_by.len > 0) {
        try w.writeAll("\nBlocked by:\n");
        for (item.blocked_by) |blocker_id| {
            try w.print("  {s}\n", .{blocker_id});
        }
    }

    try w.print("\nCreated: {s}\n", .{item.created_at});
    try w.print("Updated: {s}\n", .{item.updated_at});
}

fn outputJson(writer: *std.fs.File.Writer, todos: []const todo.Todo) !void {
    const w = &writer.interface;

    try w.writeAll("{\n  \"todos\": [\n");

    for (todos, 0..) |item, i| {
        try w.writeAll("    {\n");
        try w.print("      \"id\": \"{s}\",\n", .{item.id});
        try w.print("      \"title\": \"{s}\",\n", .{item.title});
        try w.print("      \"body\": \"{s}\",\n", .{item.body});
        try w.print("      \"status\": \"{s}\",\n", .{item.status.toString()});
        
        try w.writeAll("      \"tags\": [");
        for (item.tags, 0..) |tag, j| {
            try w.print("\"{s}\"", .{tag});
            if (j < item.tags.len - 1) try w.writeAll(", ");
        }
        try w.writeAll("],\n");

        try w.writeAll("      \"depends_on\": [");
        for (item.depends_on, 0..) |dep, j| {
            try w.print("\"{s}\"", .{dep});
            if (j < item.depends_on.len - 1) try w.writeAll(", ");
        }
        try w.writeAll("],\n");

        try w.writeAll("      \"blocked_by\": [");
        for (item.blocked_by, 0..) |blocked, j| {
            try w.print("\"{s}\"", .{blocked});
            if (j < item.blocked_by.len - 1) try w.writeAll(", ");
        }
        try w.writeAll("],\n");

        try w.print("      \"created_at\": \"{s}\",\n", .{item.created_at});
        try w.print("      \"updated_at\": \"{s}\"\n", .{item.updated_at});
        try w.writeAll("    }");
        if (i < todos.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }

    try w.writeAll("  ]\n}\n");
}
