const std = @import("std");
const cli = @import("cli.zig");
const commands = @import("commands.zig");
const help = @import("cli_help.zig");

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
                var buf: [65536]u8 = undefined;
                var stderr_writer = std.fs.File.stderr().writer(&buf);
                defer stderr_writer.end() catch {};
                try help.printCommandHelp(&stderr_writer, cmd);
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
        .edit => try commands.executeEdit(allocator, parsed, MIND_FILE),
        .list => try commands.executeList(allocator, parsed, MIND_FILE),
        .show => try commands.executeShow(allocator, parsed, MIND_FILE),
        .status => try commands.executeStatus(allocator, parsed, MIND_FILE),
        .done => try commands.executeDone(allocator, parsed, MIND_FILE),
        .next => try commands.executeNext(allocator, parsed, MIND_FILE),
        .delete => try commands.executeDelete(allocator, parsed, MIND_FILE),
        .link => try commands.executeLink(allocator, parsed, MIND_FILE),
        .unlink => try commands.executeUnlink(allocator, parsed, MIND_FILE),
        .tag, .untag => {
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
    \\    edit, update <id>        Edit an existing todo
    \\    list                     List all todos
    \\    show <id>                Show todo details
    \\    status                   Show project status summary
    \\    done <id>                Mark todo as done
    \\    next                     Show next unblocked todo
    \\    tag <id> <tag>           Add tag to todo
    \\    untag <id> <tag>         Remove tag from todo
    \\    link <child> <parent>    Link todos (parent blocks child)
    \\    unlink <id> --from <id>  Remove dependency link
    \\    delete <id> [--force]    Delete a todo
    \\    remove <id> [--force]    Alias for delete
    \\    help [command]           Show help for command
    \\
    \\FLAGS:
    \\    --title <text>           Set title (for 'edit')
    \\    --body <text>            Set body text (for 'add', 'edit')
    \\    --tags, -t <t1,t2>       Set tags comma-separated (for 'add', 'edit')
    \\    --status, -s <s>         Set/filter by status: pending, in-progress, done
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
    \\    mind edit 1234567890-001 --title "Fix auth implementation"
    \\    mind edit 1234567890-001 --status in-progress
    \\    mind list --status pending
    \\    mind list --tag feature
    \\    mind show 1234567890-001
    \\    mind status
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
    \\       $ mind done <id> --reason "Completed successfully"
    \\       (Use 'done' when you finish a todo; optionally add a reason)
    \\
    \\6. Find the next task to work on:
    \\       $ mind next
    \\       (Shows the first unblocked todo)
    \\       $ mind next --all
    \\       (Shows all unblocked todos)
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
    \\       $ mind next                (next unblocked todo)
    \\       $ mind next --all          (all unblocked todos)
    \\
    \\══════════════════════════════════════════════════════════════════
    \\COMMON WORKFLOWS
    \\══════════════════════════════════════════════════════════════════
    \\
    \\Plan a feature:
    \\   1. mind add "Design the feature" --tags "planning"
    \\   2. mind add "Implement core logic" --tags "dev"
    \\   3. mind link <implement-id> <design-id>
    \\   4. mind next              (see what to work on)
    \\   5. mind done <design-id>
    \\   6. mind next              (now implement)
    \\   7. mind done <implement-id>
    \\
    \\Track bugs:
    \\   1. mind add "Fix login crash" --tags "bug,critical"
    \\   2. mind list --tag bug
    \\   3. mind done <bug-id> --reason "Fixed null pointer dereference"
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
