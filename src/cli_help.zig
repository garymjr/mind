const std = @import("std");

const HELP_TEXT: []const u8 =
    \\
    \\mind - Your second brain for project todos
    \\
    \\USAGE:
    \\    mind [COMMAND] [FLAGS] [ARGS]
    \\
    \\COMMANDS:
    \\    quickstart               Get started with mind
    \\    add <title>              Add a new todo
    \\    list                     List all todos
    \\    show <id>                Show todo details
    \\    done <id>                Mark todo as done
    \\    next                     Show next unblocked todo
    \\    tag <id> <tag>           Add tag to todo
    \\    untag <id> <tag>         Remove tag from todo
    \\    link <child> <parent>    Link todos (parent blocks child)
    \\    unlink <id> --from <id>  Remove dependency link
    \\    delete <id>              Delete a todo
    \\    help [command]           Show help for command
    \\
    \\FLAGS:
    \\    --body <text>            Set body text (for 'add')
    \\    --tags <t1,t2>           Set tags comma-separated (for 'add')
    \\    --status <s>             Filter by status: pending, in-progress, done
    \\    --tag <tag>              Filter by tag
    \\    --blocked                Show only blocked todos
    \\    --unblocked              Show only unblocked todos
    \\    --all                    Show all unblocked todos (for 'next')
    \\    --reason <text>          Set resolution reason (for 'done')
    \\    --json                   Output as JSON
    \\    --help, -h               Show this help
    \\
    \\EXAMPLES:
    \\    mind add "Implement auth" --body "Add JWT authentication" --tags "feature,security"
    \\    mind list --status pending
    \\    mind list --tag feature
    \\    mind show 1234567890-001
    \\    mind done 1234567890-001 --reason "Completed API integration"
    \\    mind next
    \\    mind next --all
    \\    mind link 1234567890-002 1234567890-001
    \\    mind list --json
    \\
    \\STORAGE:
    \\    Todos stored in .mind/mind.json (version control friendly)
    \\
    \\
;

pub fn printFullHelp(writer: *std.fs.File.Writer) !void {
    try writer.interface.writeAll(HELP_TEXT);
}

pub fn printCommandHelp(writer: *std.fs.File.Writer, command: @import("cli.zig").Command) !void {
    const cmd_str = @tagName(command);
    try writer.interface.print("mind {s} - ", .{cmd_str});

    switch (command) {
        .add => {
            try writer.interface.writeAll(
                \\Add a new todo
                \\
                \\USAGE:
                \\    mind add <title> [FLAGS]
                \\
                \\FLAGS:
                \\    --body <text>      Optional body text (adds context)
                \\    --tags <t1,t2>     Comma-separated tags
                \\
                \\EXAMPLES:
                \\    mind add "Fix login bug"
                \\    mind add "Write docs" --body "Document the API endpoints" --tags "docs,urgent"
                \\
                \\
            );
        },
        .list => {
            try writer.interface.writeAll(
                \\List todos
                \\
                \\USAGE:
                \\    mind list [FLAGS]
                \\
                \\FLAGS:
                \\    --status <s>       Filter: pending, in-progress, done
                \\    --tag <tag>        Filter by tag
                \\    --blocked          Show only blocked todos
                \\    --unblocked        Show only unblocked todos
                \\    --json             Output as JSON
                \\
                \\EXAMPLES:
                \\    mind list
                \\    mind list --status pending
                \\    mind list --tag feature --json
                \\
                \\
            );
        },
        .show => {
            try writer.interface.writeAll(
                \\Show todo details
                \\
                \\USAGE:
                \\    mind show <id> [--json]
                \\
                \\FLAGS:
                \\    --json             Output as JSON
                \\
                \\EXAMPLES:
                \\    mind show 1736205028-001
                \\
                \\
            );
        },
        .done => {
            try writer.interface.writeAll(
                \\Mark todo as done
                \\
                \\USAGE:
                \\    mind done <id> [--reason <text>]
                \\
                \\FLAGS:
                \\    --reason <text>    Optional reason for completion
                \\
                \\NOTE: Cannot mark blocked todos as done
                \\
                \\EXAMPLES:
                \\    mind done 1736205028-001
                \\    mind done 1736205028-001 --reason "Fixed the memory leak"
                \\
                \\
            );
        },
        .next => {
            try writer.interface.writeAll(
                \\Show next unblocked todo
                \\
                \\USAGE:
                \\    mind next [--all]
                \\
                \\FLAGS:
                \\    --all              Show all unblocked todos
                \\
                \\EXAMPLES:
                \\    mind next
                \\    mind next --all
                \\
                \\
            );
        },
        .delete => {
            try writer.interface.writeAll(
                \\Delete a todo
                \\
                \\USAGE:
                \\    mind delete <id> [--force]
                \\    mind remove <id> [--force]
                \\
                \\FLAGS:
                \\    --force            Delete todo and all linked todos
                \\
                \\NOTE: Cannot delete a todo with linked dependencies without --force
                \\
                \\EXAMPLES:
                \\    mind delete 1736205028-001
                \\    mind remove 1736205028-001 --force
                \\
                \\
            );
        },
        .link => {
            try writer.interface.writeAll(
                \\Link todos (create dependency)
                \\
                \\USAGE:
                \\    mind link <child-id> <parent-id>
                \\
                \\The child todo will depend on the parent. The child cannot be marked done
                \\until the parent is done.
                \\
                \\A todo can depend on multiple parents.
                \\
                \\EXAMPLES:
                \\    mind link 1736205028-002 1736205028-001
                \\    # Todo 002 now depends on 001
                \\
                \\
            );
        },
        .unlink => {
            try writer.interface.writeAll(
                \\Remove dependency link between todos
                \\
                \\USAGE:
                \\    mind unlink <child-id> --from <parent-id>
                \\
                \\FLAGS:
                \\    --from <parent-id>  Parent todo to unlink from
                \\
                \\EXAMPLES:
                \\    mind unlink 1736205028-002 --from 1736205028-001
                \\    # Todo 002 no longer depends on 001
                \\
                \\
            );
        },
        else => {
            try writer.interface.writeAll("Command help not yet implemented. Use 'mind --help' for overview.\n");
        },
    }
}

pub fn printError(_: anytype, comptime fmt: []const u8, args_: anytype) !void {
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    try (&stderr_writer.interface).print("error: " ++ fmt ++ "\n", args_);
    try stderr_writer.end();
}
