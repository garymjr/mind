const std = @import("std");
const cli = @import("cli.zig");
const cli_args = @import("cli_args.zig");
const todo = @import("todo.zig");
const util = @import("util.zig");
const storage = @import("storage.zig");

const BODY_HINT = "Tip: Add a body with --body to provide context for this todo";

pub fn executeAdd(allocator: std.mem.Allocator, args: cli_args.Add.Args, store_path: []const u8) !void {
    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    if (args.title.len == 0) {
        try stderr.writeAll("error: title cannot be empty\n");
        return error.TitleEmpty;
    }

    var tags_list = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (tags_list.items) |tag| allocator.free(tag);
        tags_list.deinit(allocator);
    }

    if (args.tags) |tags_str| {
        var iter = std.mem.splitScalar(u8, tags_str, ',');
        while (iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                const normalized = try util.normalizeNfc(allocator, trimmed);
                try tags_list.append(allocator, normalized);
            }
        }
    }

    const body = args.body orelse "";

    // Parse priority
    const priority = if (args.priority) |p| todo.Priority.fromString(p) orelse .medium else .medium;

    const new_todo = try todo.createTodo(
        allocator,
        args.title,
        body,
        priority,
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

    if (args.quiet) {
        try stdout.writeAll(new_todo.id);
        try stdout.writeAll("\n");
    } else {
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
}

pub fn executeEdit(allocator: std.mem.Allocator, args: cli_args.Edit.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    // Validate ID format
    util.validateId(args.id) catch |err| {
        try cli.printError(stderr, "invalid ID format: {s}", .{args.id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const idx = todo_list.findIndexById(args.id) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.id});
        return error.TodoNotFound;
    };

    var modified = false;

    // Update title
    if (args.title) |new_title| {
        const normalized = try util.normalizeNfc(allocator, new_title);
        try util.validateTitle(normalized);
        allocator.free(todo_list.todos[idx].title);
        todo_list.todos[idx].title = normalized;
        modified = true;
    }

    // Update body
    if (args.body) |new_body| {
        allocator.free(todo_list.todos[idx].body);
        todo_list.todos[idx].body = try allocator.dupe(u8, new_body);
        modified = true;
    }

    // Update status
    if (args.status) |status_str| {
        const new_status = todo.Status.fromString(status_str) orelse {
            try cli.printError(stderr, "invalid status: {s} (must be: pending, in-progress, done)", .{status_str});
            return error.InvalidStatus;
        };
        todo_list.todos[idx].status = new_status;
        modified = true;
    }

    // Update priority
    if (args.priority) |priority_str| {
        const new_priority = todo.Priority.fromString(priority_str) orelse {
            try cli.printError(stderr, "invalid priority: {s} (must be: low, medium, high, critical)", .{priority_str});
            return error.InvalidPriority;
        };
        todo_list.todos[idx].priority = new_priority;
        modified = true;
    }

    // Update tags (replace all)
    if (args.tags) |tags_str| {
        // Free old tags
        for (todo_list.todos[idx].tags) |tag| allocator.free(tag);
        allocator.free(todo_list.todos[idx].tags);

        // Parse new tags
        var tags_list = std.ArrayListUnmanaged([]const u8){};
        defer tags_list.deinit(allocator);
        var iter = std.mem.splitScalar(u8, tags_str, ',');
        while (iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                // Normalize each tag
                const normalized = try util.normalizeNfc(allocator, trimmed);
                try tags_list.append(allocator, normalized);
            }
        }

        // Allocate new tags array
        var new_tags = try allocator.alloc([]const u8, tags_list.items.len);
        for (tags_list.items, 0..) |tag, i| {
            new_tags[i] = tag;
        }
        tags_list.items.len = 0; // Don't free - transferred to new_tags
        todo_list.todos[idx].tags = new_tags;
        modified = true;
    }

    if (modified) {
        // Update timestamp
        allocator.free(todo_list.todos[idx].updated_at);
        todo_list.todos[idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

        try st.save(&todo_list);
        try stdout.interface.print("Updated todo: {s}\n", .{args.id});
        try stdout.end();
    }
}

pub fn executeStatus(allocator: std.mem.Allocator, args: cli_args.Status.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    errdefer stdout.end() catch {};

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Count todos by status
    var pending_count: usize = 0;
    var in_progress_count: usize = 0;
    var done_count: usize = 0;
    var blocked_count: usize = 0;
    var unblocked_pending: usize = 0;

    for (todo_list.todos) |*item| {
        switch (item.status) {
            .pending => {
                pending_count += 1;
                if (todo_list.isBlocked(item.*)) {
                    blocked_count += 1;
                } else {
                    unblocked_pending += 1;
                }
            },
            .@"in-progress" => in_progress_count += 1,
            .done => done_count += 1,
        }
    }

    const total = todo_list.todos.len;
    const w = &stdout.interface;

    if (args.json) {
        const progress_pct = if (total > 0)
            @as(f64, @floatFromInt(done_count)) / @as(f64, @floatFromInt(total)) * 100.0
        else
            0.0;
        try w.print(
            \\{{
            \\  "total": {d},
            \\  "by_status": {{
            \\    "pending": {d},
            \\    "in_progress": {d},
            \\    "done": {d}
            \\  }},
            \\  "blocking_state": {{
            \\    "blocked": {d},
            \\    "ready": {d}
            \\  }},
            \\  "progress_percent": {d:.1}
            \\}}
        , .{ total, pending_count, in_progress_count, done_count, blocked_count, unblocked_pending, progress_pct });
    } else {
        try w.writeAll("Project Status\n");
        try w.writeAll("══════════════\n\n");

        try w.print("Total todos: {d}\n\n", .{total});

        try w.writeAll("By Status:\n");
        try w.print("  Pending:      {d}\n", .{pending_count});
        try w.print("  In Progress:  {d}\n", .{in_progress_count});
        try w.print("  Done:         {d}\n", .{done_count});

        try w.writeAll("\nBlocking State:\n");
        try w.print("  Blocked:      {d}\n", .{blocked_count});
        try w.print("  Ready to do:  {d}\n", .{unblocked_pending});

        if (pending_count > 0) {
            const progress_pct = @as(f64, @floatFromInt(done_count)) / @as(f64, @floatFromInt(total)) * 100.0;
            try w.print("\nProgress: {d:.1}% complete\n", .{progress_pct});
        }
    }

    try stdout.end();
}

pub fn executeList(allocator: std.mem.Allocator, args: cli_args.List.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    errdefer stdout.end() catch {};

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Normalize tag filter if present
    const normalized_tag_filter = if (args.tag_filter) |filter_tag|
        try util.normalizeNfc(allocator, filter_tag)
    else
        null;
    defer if (normalized_tag_filter) |tag| allocator.free(tag);

    // Build filtered list
    var filtered = std.ArrayListUnmanaged(*const todo.Todo){};
    defer filtered.deinit(allocator);

    for (todo_list.todos) |*item| {
        // Apply status filter
        if (args.status) |status_str| {
            const filter_status = todo.Status.fromString(status_str);
            if (filter_status) |s| {
                if (item.status != s) continue;
            }
        }

        // Apply priority filter
        if (args.priority) |priority_str| {
            const filter_priority = todo.Priority.fromString(priority_str);
            if (filter_priority) |p| {
                if (item.priority != p) continue;
            }
        }

        // Apply tag filter (tags are already normalized in storage)
        if (normalized_tag_filter) |filter_tag| {
            var has_tag = false;
            for (item.tags) |tag| {
                if (std.mem.eql(u8, tag, filter_tag)) {
                    has_tag = true;
                    break;
                }
            }
            if (!has_tag) continue;
        }

        try filtered.append(allocator, item);
    }

    // Sort by priority if requested
    if (args.sort) |sort_by| {
        if (std.mem.eql(u8, sort_by, "priority")) {
            // Sort by priority (critical first, then high, medium, low)
            std.sort.insertion(*const todo.Todo, filtered.items, {}, struct {
                fn lessThan(_: void, a: *const todo.Todo, b: *const todo.Todo) bool {
                    return @intFromEnum(a.priority) > @intFromEnum(b.priority);
                }
            }.lessThan);
        } else if (std.mem.eql(u8, sort_by, "priority-asc")) {
            // Sort by priority ascending (low first)
            std.sort.insertion(*const todo.Todo, filtered.items, {}, struct {
                fn lessThan(_: void, a: *const todo.Todo, b: *const todo.Todo) bool {
                    return @intFromEnum(a.priority) < @intFromEnum(b.priority);
                }
            }.lessThan);
        }
    }

    // Convert to slice for output functions
    var todos_slice = try allocator.alloc(*const todo.Todo, filtered.items.len);
    defer allocator.free(todos_slice);
    for (filtered.items, 0..) |item, i| {
        todos_slice[i] = item;
    }

    if (args.json) {
        // Convert back to Todo[] for JSON output
        var todos_for_json = try allocator.alloc(todo.Todo, filtered.items.len);
        defer {
            for (todos_for_json) |_| {
                // Don't free - these are borrowed from todo_list
            }
            allocator.free(todos_for_json);
        }
        for (filtered.items, 0..) |item, i| {
            todos_for_json[i] = item.*;
        }
        try outputJson(&stdout, allocator, todos_for_json);
    } else {
        // Dereference pointers for outputList
        var todos_output = try allocator.alloc(todo.Todo, filtered.items.len);
        defer allocator.free(todos_output);
        for (filtered.items, 0..) |item, i| {
            todos_output[i] = item.*;
        }
        try outputList(&stdout, todos_output);
    }

    // Flush the buffer
    try stdout.end();
}

pub fn executeSearch(allocator: std.mem.Allocator, args: cli_args.Search.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    errdefer stdout.end() catch {};

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Normalize query for case-insensitive search
    const query_lower = if (args.query) |q| blk: {
        const lower = try allocator.alloc(u8, q.len);
        for (q, 0..) |c, i| {
            lower[i] = std.ascii.toLower(c);
        }
        break :blk lower;
    } else null;
    defer if (query_lower) |q| allocator.free(q);

    // Normalize tag filter if present
    const normalized_tag_filter = if (args.tag_filter) |filter_tag|
        try util.normalizeNfc(allocator, filter_tag)
    else
        null;
    defer if (normalized_tag_filter) |tag| allocator.free(tag);

    // Build filtered list
    var filtered = std.ArrayListUnmanaged(*const todo.Todo){};
    defer filtered.deinit(allocator);

    for (todo_list.todos) |*item| {
        // Apply query filter (case-insensitive substring search)
        if (query_lower) |q| {
            var query_found = false;

            // Search in title
            var title_lower = std.ArrayListUnmanaged(u8){};
            defer title_lower.deinit(allocator);
            try title_lower.ensureTotalCapacity(allocator, item.title.len);
            for (item.title) |c| {
                try title_lower.append(allocator, std.ascii.toLower(c));
            }

            if (std.mem.indexOf(u8, title_lower.items, q) != null) {
                query_found = true;
            }

            // Search in body if not found in title
            if (!query_found and item.body.len > 0) {
                var body_lower = std.ArrayListUnmanaged(u8){};
                defer body_lower.deinit(allocator);
                try body_lower.ensureTotalCapacity(allocator, item.body.len);
                for (item.body) |c| {
                    try body_lower.append(allocator, std.ascii.toLower(c));
                }

                if (std.mem.indexOf(u8, body_lower.items, q) != null) {
                    query_found = true;
                }
            }

            if (!query_found) continue;
        }

        // Apply tag filter (tags are already normalized in storage)
        if (normalized_tag_filter) |filter_tag| {
            var has_tag = false;
            for (item.tags) |tag| {
                if (std.mem.eql(u8, tag, filter_tag)) {
                    has_tag = true;
                    break;
                }
            }
            if (!has_tag) continue;
        }

        try filtered.append(allocator, item);
    }

    if (args.json) {
        // Convert back to Todo[] for JSON output
        var todos_for_json = try allocator.alloc(todo.Todo, filtered.items.len);
        defer {
            for (todos_for_json) |_| {
                // Don't free - these are borrowed from todo_list
            }
            allocator.free(todos_for_json);
        }
        for (filtered.items, 0..) |item, i| {
            todos_for_json[i] = item.*;
        }
        try outputJson(&stdout, allocator, todos_for_json);
    } else {
        // Dereference pointers for outputList
        var todos_output = try allocator.alloc(todo.Todo, filtered.items.len);
        defer allocator.free(todos_output);
        for (filtered.items, 0..) |item, i| {
            todos_output[i] = item.*;
        }
        try outputList(&stdout, todos_output);
    }

    // Flush the buffer
    try stdout.end();
}

pub fn executeShow(allocator: std.mem.Allocator, args: cli_args.Show.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    // Validate ID format
    util.validateId(args.id) catch |err| {
        try cli.printError(stderr, "invalid ID format: {s}", .{args.id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const item = todo_list.findById(args.id) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.id});
        return error.TodoNotFound;
    };

    if (args.json) {
        try outputJson(&stdout, allocator, &[_]todo.Todo{item.*});
    } else {
        try outputTodoDetail(&stdout, item.*, &todo_list);
    }

    try stdout.end();
}

pub fn executeDelete(allocator: std.mem.Allocator, args: cli_args.Delete.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    // Validate ID format
    util.validateId(args.id) catch |err| {
        try cli.printError(stderr, "invalid ID format: {s}", .{args.id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const todo_to_delete = todo_list.findById(args.id) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.id});
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

        // Recursively collect ALL linked todos transitively
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
                    if (!already_in_list and !std.mem.eql(u8, dep_id, args.id)) {
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
                    if (!already_in_list and !std.mem.eql(u8, blocked_id, args.id)) {
                        try linked_ids.append(allocator, try allocator.dupe(u8, blocked_id));
                    }
                }
            }
            i += 1;
        }

        // Show what will be deleted
        const total_to_delete = linked_ids.items.len + 1;
        try stderr.interface.writeAll("WARNING: This will delete ");
        try stderr.interface.print("{d} todos:\n", .{total_to_delete});
        try stderr.interface.print("  Target: {s} {s}\n", .{ args.id, todo_to_delete.title });
        for (linked_ids.items) |id| {
            if (todo_list.findById(id)) |t| {
                try stderr.interface.print("    {s} {s}\n", .{ id, t.title });
            }
        }
        try stderr.interface.writeAll("\n");

        // Require explicit confirmation (unless --yes flag is set)
        if (!args.yes) {
            try stderr.interface.print("Delete {d} todos? [y/N]: ", .{total_to_delete});
            try stderr.end();
            const stdin = std.fs.File.stdin();
            var input_buf: [10]u8 = undefined;
            const input = stdin.read(&input_buf) catch 0;
            const response = if (input > 0) input_buf[0] else 'N';

            if (response != 'y' and response != 'Y') {
                const stderr_file = std.fs.File.stderr();
                try stderr_file.writeAll("Aborted.\n");
                std.process.exit(0);
            }
        }

        // Now perform the deletions
        for (linked_ids.items) |id| {
            try todo_list.remove(id);
            deleted_count += 1;
        }

        // Delete the main todo
        try todo_list.remove(args.id);

        try stdout.interface.print("Deleted {d} todos\n", .{deleted_count});
    } else {
        // Just delete the single todo
        try todo_list.remove(args.id);
        try stdout.interface.print("Deleted todo: {s}\n", .{args.id});
    }

    try st.save(&todo_list);

    try stdout.end();
}

pub fn executeDone(allocator: std.mem.Allocator, args: cli_args.Done.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    if (args.ids.len == 0) return error.MissingId;

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    var marked_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (marked_ids.items) |id| allocator.free(id);
        marked_ids.deinit(allocator);
    }

    var marked_count: usize = 0;
    var error_count: usize = 0;

    // Process each ID
    for (args.ids) |id| {
        // Validate ID format
        util.validateId(id) catch {
            try cli.printError(stderr, "invalid ID format: {s}", .{id});
            try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
            error_count += 1;
            continue;
        };

        const idx = todo_list.findIndexById(id) orelse {
            try cli.printError(stderr, "todo not found: {s}", .{id});
            error_count += 1;
            continue;
        };

        // Check if blocked
        if (todo_list.isBlocked(todo_list.todos[idx])) {
            try cli.printError(stderr, "cannot mark blocked todo as done: {s}", .{id});
            error_count += 1;
            continue;
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

        try marked_ids.append(allocator, try allocator.dupe(u8, id));
        marked_count += 1;
    }

    // Save only if at least one todo was marked
    if (marked_count > 0) {
        try st.save(&todo_list);
    }

    if (args.json) {
        try stdout.interface.writeAll("{\n  \"marked\": [");
        for (marked_ids.items, 0..) |id, i| {
            if (i > 0) try stdout.interface.writeAll(", ");
            try stdout.interface.print("\"{s}\"", .{id});
        }
        try stdout.interface.print("],\n  \"count\": {d},\n  \"errors\": {d}\n}}\n", .{ marked_count, error_count });
    } else {
        if (marked_count > 0) {
            if (marked_count == 1) {
                try stdout.interface.print("Marked {d} todo as done: {s}\n", .{ marked_count, args.ids[0] });
            } else {
                try stdout.interface.print("Marked {d} todos as done\n", .{marked_count});
            }
        }

        if (error_count > 0) {
            try stdout.interface.print("{d} error(s) occurred\n", .{error_count});
        }
    }

    try stdout.end();
}

pub fn executeNext(allocator: std.mem.Allocator, args: cli_args.Next.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

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
        if (args.json) {
            try stdout.interface.writeAll("{\n  \"todos\": [],\n  \"count\": 0\n}\n");
        } else {
            try stdout.interface.writeAll("No unblocked todos found.\n");
        }
        try stdout.end();
        return;
    }

    if (args.json) {
        try stdout.interface.writeAll("{\n  \"todos\": [\n");
        for (unblocked.items, 0..) |item, i| {
            if (i > 0) try stdout.interface.writeAll(",\n");
            try stdout.interface.writeAll("    {\n");
            try stdout.interface.writeAll("      \"id\": \"");
            try util.writeEscapedStringToWriter(&stdout.interface, item.id);
            try stdout.interface.writeAll("\",\n");
            try stdout.interface.writeAll("      \"title\": \"");
            try util.writeEscapedStringToWriter(&stdout.interface, item.title);
            try stdout.interface.writeAll("\",\n");
            try stdout.interface.print("      \"status\": \"{s}\",\n", .{item.status.toString()});
            try stdout.interface.print("      \"priority\": \"{s}\"\n", .{item.priority.toString()});
            try stdout.interface.writeAll("    }");
        }
        try stdout.interface.writeAll("\n  ],\n  \"count\": ");
        try stdout.interface.print("{d}\n", .{unblocked.items.len});
        try stdout.interface.writeAll("}\n");
    } else if (args.all) {
        try stdout.interface.writeAll("Unblocked todos:\n");
        for (unblocked.items) |item| {
            const priority_symbol = item.priority.toSymbol();
            try stdout.interface.print("  {s} {s} {s:<12} {s}\n", .{ priority_symbol, item.id, item.status.toString(), item.title });
        }
    } else {
        const next_todo = unblocked.items[0];
        try stdout.interface.writeAll("Next todo:\n");
        try outputTodoDetail(&stdout, next_todo.*, &todo_list);
    }

    try stdout.end();
}

pub fn executeLink(allocator: std.mem.Allocator, args: cli_args.Link.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    const child_id = args.child_id;
    const parent_id = args.parent_id;

    // Validate ID formats
    util.validateId(child_id) catch |err| {
        try cli.printError(stderr, "invalid ID format for child: {s}", .{child_id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };
    util.validateId(parent_id) catch |err| {
        try cli.printError(stderr, "invalid ID format for parent: {s}", .{parent_id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Verify both todos exist
    const child_idx = todo_list.findIndexById(child_id) orelse {
        try cli.printError(stderr, "child todo not found: {s}", .{child_id});
        return error.TodoNotFound;
    };

    if (todo_list.findById(parent_id) == null) {
        try cli.printError(stderr, "parent todo not found: {s}", .{parent_id});
        return error.TodoNotFound;
    }

    // Check for circular dependency
    if (wouldCreateCycle(&todo_list, child_id, parent_id)) {
        try cli.printError(stderr, "linking would create a circular dependency", .{});
        return error.CircularDependency;
    }

    // Check if already linked
    for (todo_list.todos[child_idx].depends_on) |dep| {
        if (std.mem.eql(u8, dep, parent_id)) {
            try cli.printError(stderr, "todo already depends on parent: {s}", .{parent_id});
            return error.AlreadyLinked;
        }
    }

    // Add parent to child's depends_on
    const old_deps = todo_list.todos[child_idx].depends_on;
    const new_deps = try allocator.alloc([]const u8, old_deps.len + 1);
    for (old_deps, 0..) |dep, i| {
        new_deps[i] = try allocator.dupe(u8, dep);
    }
    new_deps[old_deps.len] = try allocator.dupe(u8, parent_id);

    // Free old depends_on strings
    for (old_deps) |dep| allocator.free(dep);
    allocator.free(old_deps);

    todo_list.todos[child_idx].depends_on = new_deps;

    // Update timestamp
    allocator.free(todo_list.todos[child_idx].updated_at);
    todo_list.todos[child_idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

    // Recompute blocked_by for all todos
    try todo_list.computeBlockedBy();

    try st.save(&todo_list);

    try stdout.interface.print("Linked: {s} now depends on {s}\n", .{ child_id, parent_id });
    try stdout.end();
}

pub fn executeUnlink(allocator: std.mem.Allocator, args: cli_args.Unlink.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    const child_id = args.child_id;
    const parent_id = args.parent_id;

    // Validate ID formats
    util.validateId(child_id) catch |err| {
        try cli.printError(stderr, "invalid ID format for child: {s}", .{child_id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };
    util.validateId(parent_id) catch |err| {
        try cli.printError(stderr, "invalid ID format for parent: {s}", .{parent_id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const child_idx = todo_list.findIndexById(child_id) orelse {
        try cli.printError(stderr, "child todo not found: {s}", .{child_id});
        return error.TodoNotFound;
    };

    // Find and remove parent from depends_on
    var found = false;
    var new_idx: usize = 0;
    const old_deps = todo_list.todos[child_idx].depends_on;
    var new_deps = try allocator.alloc([]const u8, old_deps.len);

    for (old_deps) |dep| {
        if (!std.mem.eql(u8, dep, parent_id)) {
            new_deps[new_idx] = try allocator.dupe(u8, dep);
            new_idx += 1;
        } else {
            found = true;
            // Don't free dep here - it's still owned by old_deps
            // It will be freed when old_deps is freed
        }
    }

    if (!found) {
        try cli.printError(stderr, "todo does not depend on parent: {s}", .{parent_id});
        // Free the new deps we allocated
        for (new_deps[0..new_idx]) |dep| allocator.free(dep);
        allocator.free(new_deps);
        return error.NotLinked;
    }

    // Shrink to fit (preserves new_deps pointer if possible)
    const final_deps = try allocator.realloc(new_deps, new_idx);

    // Free old depends_on strings and array
    for (old_deps) |dep| allocator.free(dep);
    allocator.free(old_deps);

    todo_list.todos[child_idx].depends_on = final_deps;

    // Update timestamp
    allocator.free(todo_list.todos[child_idx].updated_at);
    todo_list.todos[child_idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

    // Recompute blocked_by for all todos
    try todo_list.computeBlockedBy();

    try st.save(&todo_list);

    try stdout.interface.print("Unlinked: {s} no longer depends on {s}\n", .{ child_id, parent_id });
    try stdout.end();
}

pub fn executeTag(allocator: std.mem.Allocator, args: cli_args.Tag.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    // Validate ID format
    util.validateId(args.id) catch |err| {
        try cli.printError(stderr, "invalid ID format: {s}", .{args.id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const idx = todo_list.findIndexById(args.id) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.id});
        return error.TodoNotFound;
    };

    // Normalize the tag
    const normalized_tag = try util.normalizeNfc(allocator, args.tag);
    defer allocator.free(normalized_tag);

    // Check if tag already exists
    for (todo_list.todos[idx].tags) |tag| {
        if (std.mem.eql(u8, tag, normalized_tag)) {
            try cli.printError(stderr, "todo already has tag: {s}", .{args.tag});
            return error.TagAlreadyExists;
        }
    }

    // Add the tag
    const old_tags = todo_list.todos[idx].tags;
    const new_tags = try allocator.alloc([]const u8, old_tags.len + 1);
    for (old_tags, 0..) |tag, i| {
        new_tags[i] = tag;
    }
    new_tags[old_tags.len] = try allocator.dupe(u8, normalized_tag);
    todo_list.todos[idx].tags = new_tags;
    allocator.free(old_tags);

    // Update timestamp
    allocator.free(todo_list.todos[idx].updated_at);
    todo_list.todos[idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

    try st.save(&todo_list);

    try stdout.interface.print("Added tag '{s}' to todo: {s}\n", .{ args.tag, args.id });
    try stdout.end();
}

pub fn executeUntag(allocator: std.mem.Allocator, args: cli_args.Untag.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    // Validate ID format
    util.validateId(args.id) catch |err| {
        try cli.printError(stderr, "invalid ID format: {s}", .{args.id});
        try cli.printError(stderr, "Expected format: {{timestamp}}-{{ms:0>3}}-{{seq:0>3}}", .{});
        return err;
    };

    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    const idx = todo_list.findIndexById(args.id) orelse {
        try cli.printError(stderr, "todo not found: {s}", .{args.id});
        return error.TodoNotFound;
    };

    // Normalize the tag for comparison
    const normalized_tag = try util.normalizeNfc(allocator, args.tag);
    defer allocator.free(normalized_tag);

    // Build new tags array excluding the one to remove
    var tags_list = std.ArrayListUnmanaged([]const u8){};
    defer {
        // Only free the array, not the strings (they're borrowed from old_tags)
        tags_list.deinit(allocator);
    }
    try tags_list.ensureTotalCapacity(allocator, todo_list.todos[idx].tags.len);

    var found = false;
    var removed_tag: ?[]const u8 = null;
    for (todo_list.todos[idx].tags) |tag| {
        if (std.mem.eql(u8, tag, normalized_tag)) {
            found = true;
            removed_tag = tag; // Save reference to free later
        } else {
            try tags_list.append(allocator, tag);
        }
    }

    if (!found) {
        try cli.printError(stderr, "todo does not have tag: {s}", .{args.tag});
        return error.TagNotFound;
    }

    // Replace old tags with new array
    const old_tags = todo_list.todos[idx].tags;
    var final_tags = try allocator.alloc([]const u8, tags_list.items.len);
    for (tags_list.items, 0..) |tag, i| {
        final_tags[i] = tag;
    }

    // Free the removed tag string and the old tags array (but not the strings we kept)
    if (removed_tag) |tag| allocator.free(tag);
    allocator.free(old_tags);

    todo_list.todos[idx].tags = final_tags;

    // Update timestamp
    allocator.free(todo_list.todos[idx].updated_at);
    todo_list.todos[idx].updated_at = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});

    try st.save(&todo_list);

    try stdout.interface.print("Removed tag '{s}' from todo: {s}\n", .{ args.tag, args.id });
    try stdout.end();
}

pub fn executeArchive(allocator: std.mem.Allocator, args: cli_args.Archive.Args, store_path: []const u8) !void {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [65536]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    errdefer stdout.end() catch {};
    errdefer stderr.end() catch {};

    const archive_path = ".mind/archive.json";
    const current_time = std.time.timestamp();
    const cutoff_time = current_time - (@as(i64, @intCast(args.days)) * 86400); // days * seconds_per_day

    // Load current todos
    var st = storage.Storage.init(allocator, store_path);
    var todo_list = try st.load();
    defer todo_list.deinit();

    // Load existing archive (if any)
    var archive_todo_list = todo.TodoList.init(allocator);
    defer archive_todo_list.deinit();

    // Try to load existing archive
    if (std.fs.cwd().openFile(archive_path, .{})) |archive_file| {
        archive_file.close();
        var archive_st = storage.Storage.init(allocator, archive_path);
        archive_todo_list = try archive_st.load();
    } else |err| {
        if (err != error.FileNotFound) {
            try cli.printError(stderr, "error loading archive: {}", .{err});
            return err;
        }
    }

    // Collect todos to archive (done and older than cutoff)
    var to_archive = std.ArrayListUnmanaged(usize){};
    defer to_archive.deinit(allocator);

    for (todo_list.todos, 0..) |item, idx| {
        if (item.status != .done) continue;

        const updated_at = std.fmt.parseInt(i64, item.updated_at, 10) catch 0;
        if (updated_at < cutoff_time) {
            try to_archive.append(allocator, idx);
        }
    }

    if (to_archive.items.len == 0) {
        try stdout.interface.print("No todos to archive (done older than {d} days)\n", .{args.days});
        try stdout.end();
        return;
    }

    if (args.dry_run) {
        try stdout.interface.print("Would archive {d} todos (older than {d} days):\n", .{ to_archive.items.len, args.days });
        for (to_archive.items) |idx| {
            try stdout.interface.print("  {s} {s}\n", .{ todo_list.todos[idx].id, todo_list.todos[idx].title });
        }
        try stdout.end();
        return;
    }

    // Show what will be archived
    try stdout.interface.print("Archiving {d} todos (older than {d} days):\n", .{ to_archive.items.len, args.days });
    for (to_archive.items) |idx| {
        try stdout.interface.print("  {s} {s}\n", .{ todo_list.todos[idx].id, todo_list.todos[idx].title });
    }
    try stdout.interface.writeAll("\n");

    // Archive the todos by moving them to the archive list
    // We need to process in reverse order to maintain correct indices
    std.sort.insertion(usize, to_archive.items, {}, struct {
        fn lessThan(_: void, a: usize, b: usize) bool {
            return a > b; // descending order
        }
    }.lessThan);

    for (to_archive.items) |idx| {
        try archive_todo_list.add(todo_list.todos[idx]);
        // Mark as removed from todo_list (we'll rebuild the list)
    }

    // Rebuild active todo list without archived items
    var new_todos = try allocator.alloc(todo.Todo, todo_list.todos.len - to_archive.items.len);
    var new_idx: usize = 0;
    var archived_count: usize = 0;

    for (todo_list.todos) |item| {
        var is_archived = false;
        for (to_archive.items) |archive_idx| {
            if (item.id.ptr == todo_list.todos[archive_idx].id.ptr) {
                is_archived = true;
                break;
            }
        }
        if (!is_archived) {
            new_todos[new_idx] = item;
            new_idx += 1;
        } else {
            archived_count += 1;
        }
    }

    allocator.free(todo_list.todos);
    todo_list.todos = new_todos;

    // Save both files
    var archive_st = storage.Storage.init(allocator, archive_path);
    try archive_st.save(&archive_todo_list);
    try st.save(&todo_list);

    try stdout.interface.print("Archived {d} todos to {s}\n", .{ archived_count, archive_path });
    try stdout.end();
}

fn wouldCreateCycle(todo_list: *const todo.TodoList, child_id: []const u8, parent_id: []const u8) bool {
    // Check if adding parent_id to child_id would create a cycle
    // This happens if parent_id transitively depends on child_id
    // Uses iterative DFS with ArrayList tracking (no hash overhead)
    const MAX_DEPTH = 100; // Prevent infinite loops on malformed data

    var path = std.ArrayListUnmanaged([]const u8){};
    defer path.deinit(todo_list.allocator);

    path.append(todo_list.allocator, parent_id) catch return false;

    while (path.items.len > 0) {
        const current = path.items[path.items.len - 1];
        path.items.len -= 1;

        // Depth limit check (treat very deep graphs as cycle to be safe)
        if (path.items.len >= MAX_DEPTH) return true;

        // Check if current path contains child_id (cycle found)
        for (path.items) |visited| {
            if (std.mem.eql(u8, visited, child_id)) return true;
        }

        // Check if current todo matches child_id
        if (std.mem.eql(u8, current, child_id)) return true;

        // Check if already in current path (cycle in graph itself)
        var in_path = false;
        for (path.items) |visited| {
            if (std.mem.eql(u8, visited, current)) {
                in_path = true;
                break;
            }
        }
        if (in_path) continue;

        // Add dependencies to stack
        const current_todo = todo_list.findById(current) orelse continue;
        for (current_todo.depends_on) |dep_id| {
            path.append(todo_list.allocator, dep_id) catch return false;
        }
    }

    return false;
}

fn outputList(writer: *std.fs.File.Writer, todos: []const todo.Todo) !void {
    const w = &writer.interface;

    if (todos.len == 0) {
        try w.writeAll("No todos found.\n");
        return;
    }

    for (todos) |item| {
        const status_str = item.status.toString();
        const priority_symbol = item.priority.toSymbol();
        const title_trunc = if (item.title.len > 40) item.title[0..40] ++ "..." else item.title;

        try w.print("{s} {s} {s:<12} {s}\n", .{ priority_symbol, item.id, status_str, title_trunc });
    }
}

fn outputTodoDetail(writer: *std.fs.File.Writer, item: todo.Todo, todo_list: *const todo.TodoList) !void {
    const w = &writer.interface;

    try w.print("ID: {s}\n", .{item.id});
    try w.print("Status: {s}\n", .{item.status.toString()});
    try w.print("Priority: {s}\n", .{item.priority.toString()});
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

fn outputJson(writer: *std.fs.File.Writer, allocator: std.mem.Allocator, todos: []const todo.Todo) !void {
    try util.writeTodosJson(&writer.interface, allocator, todos);
}
