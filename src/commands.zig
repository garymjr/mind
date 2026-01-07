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

pub fn executeDelete(allocator: std.mem.Allocator, args: cli.Args, store_path: []const u8) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    defer stdout.end() catch {};
    defer stderr.end() catch {};

    if (args.target == null) {
        try cli.printError(stderr, "delete requires a todo ID", .{});
        try cli.printCommandHelp(&stdout, .delete);
        return error.MissingId;
    }

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const todo_to_delete = todo_list.findById(args.target.?) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.target.?});
        return error.TodoNotFound;
    };

    // Collect all linked todos
    var linked_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (linked_ids.items) |id| allocator.free(id);
        linked_ids.deinit(allocator);
    }

    // Add dependencies (depends_on)
    for (todo_to_delete.depends_on) |dep_id| {
        try linked_ids.append(allocator, try allocator.dupe(u8, dep_id));
    }

    // Add todos blocked by this one
    for (todo_to_delete.blocked_by) |blocked_id| {
        try linked_ids.append(allocator, try allocator.dupe(u8, blocked_id));
    }

    // If there are linked todos and not forcing, error
    if (linked_ids.items.len > 0 and !args.force) {
        try stderr.interface.writeAll("error: cannot delete todo with linked dependencies\n");
        try stderr.interface.writeAll("  depends on: ");
        for (todo_to_delete.depends_on, 0..) |dep, i| {
            if (i > 0) try stderr.interface.writeAll(", ");
            try stderr.interface.print("{s}", .{dep});
        }
        try stderr.interface.writeAll("\n  blocked by: ");
        for (todo_to_delete.blocked_by, 0..) |blocked, i| {
            if (i > 0) try stderr.interface.writeAll(", ");
            try stderr.interface.print("{s}", .{blocked});
        }
        try stderr.interface.writeAll("\n\n");
        try stderr.interface.writeAll("Use --force to delete this todo and all linked todos.\n");
        return error.TodoHasLinks;
    }

    // Delete all linked todos if forcing
    if (args.force) {
        var deleted_count: usize = 1; // Start with the main todo

        // Recursively delete all linked todos
        var i: usize = 0;
        while (i < linked_ids.items.len) {
            const id = linked_ids.items[i];
            if (todo_list.findById(id)) |linked_todo| {
                // Add this todo's dependencies to the list
                for (linked_todo.depends_on) |dep_id| {
                    var already_in_list = false;
                    for (linked_ids.items) |existing_id| {
                        if (std.mem.eql(u8, existing_id, dep_id)) {
                            already_in_list = true;
                            break;
                        }
                    }
                    if (!already_in_list and !std.mem.eql(u8, dep_id, args.target.?)) {
                        try linked_ids.append(allocator, try allocator.dupe(u8, dep_id));
                    }
                }
                // Add this todo's blockers to the list
                for (linked_todo.blocked_by) |blocked_id| {
                    var already_in_list = false;
                    for (linked_ids.items) |existing_id| {
                        if (std.mem.eql(u8, existing_id, blocked_id)) {
                            already_in_list = true;
                            break;
                        }
                    }
                    if (!already_in_list and !std.mem.eql(u8, blocked_id, args.target.?)) {
                        try linked_ids.append(allocator, try allocator.dupe(u8, blocked_id));
                    }
                }
                try todo_list.remove(id);
                deleted_count += 1;
            }
            i += 1;
        }

        // Delete the main todo
        try todo_list.remove(args.target.?);

        try stdout.interface.print("Deleted {d} todos (including dependencies)\n", .{deleted_count});
    } else {
        // Just delete the single todo
        try todo_list.remove(args.target.?);
        try stdout.interface.print("Deleted todo: {s}\n", .{args.target.?});
    }

    try st.save(&todo_list);
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

    // Update resolution reason if provided
    if (args.reason) |reason| {
        allocator.free(todo_list.todos[idx].resolution_reason);
        todo_list.todos[idx].resolution_reason = try allocator.dupe(u8, reason);
    }

    // Update timestamp
    allocator.free(todo_list.todos[idx].updated_at);
    todo_list.todos[idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

    try st.save(&todo_list);

    try stdout.interface.print("Marked todo as done: {s}\n", .{args.target.?});
}

pub fn executeNext(allocator: std.mem.Allocator, args: cli.Args, store_path: []const u8) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    defer stdout.end() catch {};
    defer stderr.end() catch {};

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Build list of unblocked todos
    var unblocked = std.ArrayListUnmanaged(*const todo.Todo){};
    defer unblocked.deinit(allocator);

    for (todo_list.todos) |*item| {
        // Skip completed todos
        if (item.status == .done) continue;

        // Check if all dependencies are done
        var all_deps_done = true;
        for (item.depends_on) |dep_id| {
            if (todo_list.findById(dep_id)) |dep| {
                if (dep.status != .done) {
                    all_deps_done = false;
                    break;
                }
            }
        }

        if (all_deps_done) {
            try unblocked.append(allocator, item);
        }
    }

    if (unblocked.items.len == 0) {
        try stdout.interface.writeAll("No unblocked todos found.\n");
        return;
    }

    if (args.all) {
        try stdout.interface.writeAll("Unblocked todos:\n");
        for (unblocked.items) |item| {
            try stdout.interface.print("  {s} {s:<12} {s}\n", .{ item.id, item.status.toString(), item.title });
        }
    } else {
        const next_todo = unblocked.items[0];
        try stdout.interface.writeAll("Next todo:\n");
        try outputTodoDetail(&stdout, next_todo.*, &todo_list);
    }
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

    if (item.status == .done and item.resolution_reason.len > 0) {
        try w.print("\nResolution: {s}\n", .{item.resolution_reason});
    }
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
        try w.print("      \"updated_at\": \"{s}\",\n", .{item.updated_at});
        try w.print("      \"resolution_reason\": \"{s}\"\n", .{item.resolution_reason});
        try w.writeAll("    }");
        if (i < todos.len - 1) try w.writeAll(",");
        try w.writeAll("\n");
    }

    try w.writeAll("  ]\n}\n");
}
