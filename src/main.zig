const std = @import("std");
const cli = @import("cli.zig");
const commands = @import("commands.zig");

const MIND_DIR = ".mind";
const MIND_FILE = ".mind/mind.json";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
            std.process.exit(1);
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        const stderr = std.fs.File.stderr();
        try stderr.writeAll(HELP_TEXT);
        return;
    }

    const parsed = cli.parseArgs(allocator, args) catch |err| {
        switch (err) {
            error.UnknownCommand => {
                const stderr = std.fs.File.stderr();
                const stdout = std.fs.File.stdout();
                try stderr.writeAll("error: unknown command: ");
                try stderr.writeAll(args[1]);
                try stderr.writeAll("\n");
                try stdout.writeAll(HELP_TEXT);
            },
            error.MissingValueForFlag => {
                const stderr = std.fs.File.stderr();
                try stderr.writeAll("error: flag requires a value\n");
            },
            else => unreachable,
        }
        std.process.exit(1);
    };

    // Handle --help flag
    if (parsed.command == .help) {
        if (parsed.target) |cmd_str| {
            if (cli.parseCommand(cmd_str)) |cmd| {
                const stderr = std.fs.File.stderr();
                try stderr.writeAll("mind ");
                try stderr.writeAll(@tagName(cmd));
                try stderr.writeAll(" - ");
                switch (cmd) {
                    .add => try stderr.writeAll("Add a new todo\n    Usage: mind add <title> [--body <text>] [--tags <t1,t2>]\n"),
                    .list => try stderr.writeAll("List todos\n    Usage: mind list [--status <s>] [--tag <tag>] [--blocked] [--unblocked] [--json]\n"),
                    .show => try stderr.writeAll("Show todo details\n    Usage: mind show <id> [--json]\n"),
                    .done => try stderr.writeAll("Mark todo as done\n    Usage: mind done <id>\n"),
                    .delete => try stderr.writeAll("Delete a todo\n    Usage: mind delete <id> [--force]\n"),
                    else => try stderr.writeAll("Command help not yet implemented\n"),
                }
            } else {
                const stderr = std.fs.File.stderr();
                try stderr.writeAll("error: unknown command: ");
                try stderr.writeAll(cmd_str);
                try stderr.writeAll("\n");
                std.process.exit(1);
            }
        } else {
            const stderr = std.fs.File.stderr();
            try stderr.writeAll(HELP_TEXT);
        }
        return;
    }

    // Execute command
    switch (parsed.command) {
        .quickstart => {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(QUICKSTART_TEXT);
        },
        .add => try commands.executeAdd(allocator, parsed, MIND_FILE),
        .list => try commands.executeList(allocator, parsed, MIND_FILE),
        .show => try commands.executeShow(allocator, parsed, MIND_FILE),
        .done => try commands.executeDone(allocator, parsed, MIND_FILE),
        .delete => try commands.executeDelete(allocator, parsed, MIND_FILE),
        .tag, .untag, .link, .unlink => {
            const stderr = std.fs.File.stderr();
            try stderr.writeAll("error: command '");
            try stderr.writeAll(@tagName(parsed.command));
            try stderr.writeAll("' not yet implemented\n");
            std.process.exit(1);
        },
        .none, .help => unreachable,
    }
}

const HELP_TEXT =
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
    \\    tag <id> <tag>           Add tag to todo
    \\    untag <id> <tag>         Remove tag from todo
    \\    link <child> <parent>    Link todos (parent blocks child)
    \\    unlink <id> --from <id>  Remove dependency link
    \\    delete <id> [--force]    Delete a todo
    \\    remove <id> [--force]    Alias for delete
    \\    help [command]           Show help for command
    \\
    \\FLAGS:
    \\    --body <text>            Set body text (for 'add')
    \\    --tags <t1,t2>           Set tags comma-separated (for 'add')
    \\    --status <s>             Filter by status: pending, in-progress, done
    \\    --tag <tag>              Filter by tag
    \\    --blocked                Show only blocked todos
    \\    --unblocked              Show only unblocked todos
    \\    --json                   Output as JSON
    \\    --help, -h               Show this help
    \\
    \\EXAMPLES:
    \\    mind add "Implement auth" --body "Add JWT authentication" --tags "feature,security"
    \\    mind list --status pending
    \\    mind list --tag feature
    \\    mind show 1234567890-001
    \\    mind done 1234567890-001
    \\    mind link 1234567890-002 1234567890-001
    \\    mind list --json
    \\
    \\STORAGE:
    \\    Todos stored in .mind/mind.json (version control friendly)
    \\
    \\
;

const QUICKSTART_TEXT =
    \\╔════════════════════════════════════════════════════════════════╗
    \\║                   mind - Quick Start Guide                     ║
    \\╚════════════════════════════════════════════════════════════════╝
    \\
    \\Welcome to mind! Your second brain for managing project todos.
    \\
    \\══════════════════════════════════════════════════════════════════
    \\GETTING STARTED
    \\══════════════════════════════════════════════════════════════════
    \\
    \\1. Add your first todo:
    \\       $ mind add "Learn how to use mind"
    \\
    \\2. Add with more details:
    \\       $ mind add "Read the docs" --body "Check out the full help" --tags "learning"
    \\
    \\3. See what you've added:
    \\       $ mind list
    \\
    \\4. Get details on a todo:
    \\       $ mind show <id>  (use the ID from 'mind list')
    \\
    \\5. Mark a todo as done:
    \\       $ mind done <id>
    \\       (Use 'done' when you finish a todo)
    \\
    \\══════════════════════════════════════════════════════════════════
    \\POWER FEATURES
    \\══════════════════════════════════════════════════════════════════
    \\
    \\• Dependencies: Link todos so tasks block each other
    \\       $ mind link <child-id> <parent-id>
    \\       Child won't be doable until parent is done
    \\
    \\• Tags: Organize todos with categories
    \\       $ mind add "Fix bug" --tags "bug,urgent"
    \\       $ mind list --tag bug
    \\
    \\• Filters: See only what matters
    \\       $ mind list --status pending
    \\       $ mind list --blocked      (tasks waiting on others)
    \\
    \\══════════════════════════════════════════════════════════════════
    \\COMMON WORKFLOWS
    \\══════════════════════════════════════════════════════════════════
    \\
    \\Plan a feature:
    \\   1. mind add "Design the feature" --tags "planning"
    \\   2. mind add "Implement core logic" --tags "dev"
    \\   3. mind link <implement-id> <design-id>
    \\   4. mind done <design-id>
    \\   5. mind done <implement-id>
    \\
    \\Track bugs:
    \\   1. mind add "Fix login crash" --tags "bug,critical"
    \\   2. mind list --tag bug
    \\   3. mind done <bug-id>
    \\
    \\══════════════════════════════════════════════════════════════════
    \\FOR MORE HELP
    \\══════════════════════════════════════════════════════════════════
    \\
    \\   $ mind help              Show all commands
    \\   $ mind help <command>    Help for specific command
    \\
    \\Happy organizing! 🧠
    \\
;
