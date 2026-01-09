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

    // Parse global args to get command
    const global = cli.parseGlobal(args) catch |err| {
        switch (err) {
            error.UnknownCommand => {
                const stderr = std.fs.File.stderr();
                const stdout = std.fs.File.stdout();
                try stderr.writeAll("error: unknown command: ");
                try stderr.writeAll(args[1]);
                try stderr.writeAll("\n");
                try stdout.writeAll(HELP_TEXT);
            },
            else => unreachable,
        }
        std.process.exit(1);
    };

    // Handle help command
    if (global.command == .help) {
        const cmd_args = if (global.cmd_args_start < args.len) args[global.cmd_args_start..] else &[_][]const u8{};
        if (cmd_args.len > 0) {
            if (cli.parseCommand(cmd_args[0])) |cmd| {
                var buf: [65536]u8 = undefined;
                var stderr_writer = std.fs.File.stderr().writer(&buf);
                defer stderr_writer.end() catch {};
                try help.printCommandHelp(&stderr_writer, cmd);
            } else {
                const stderr = std.fs.File.stderr();
                try stderr.writeAll("error: unknown command: ");
                try stderr.writeAll(cmd_args[0]);
                try stderr.writeAll("\n");
                std.process.exit(1);
            }
        } else {
            const stderr = std.fs.File.stderr();
            try stderr.writeAll(HELP_TEXT);
        }
        return;
    }

    // Handle quickstart
    if (global.command == .quickstart) {
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(QUICKSTART_TEXT);
        return;
    }

    // Parse command-specific arguments
    const cmd_args = cli.parseCommandArgs(global.command, args) catch |err| {
        if (err == error.ShowHelp) {
            // Show help and exit normally (like `git command --help`)
            const stderr = std.fs.File.stderr();
            var buf: [65536]u8 = undefined;
            var stderr_writer = stderr.writer(&buf);
            defer stderr_writer.end() catch {};
            try help.printCommandHelp(&stderr_writer, global.command);
            return;
        }

        const stderr = std.fs.File.stderr();
        const msg = cli.formatParseError(err, global.command);
        try stderr.writeAll("error: ");
        try stderr.writeAll(msg);
        try stderr.writeAll("\n");
        // Show command help on parse error
        var buf: [65536]u8 = undefined;
        var stderr_writer = stderr.writer(&buf);
        defer stderr_writer.end() catch {};
        try help.printCommandHelp(&stderr_writer, global.command);
        std.process.exit(1);
    };

    // Execute command
    switch (global.command) {
        .add => try commands.executeAdd(allocator, cmd_args.add, MIND_FILE),
        .edit => try commands.executeEdit(allocator, cmd_args.edit, MIND_FILE),
        .list => try commands.executeList(allocator, cmd_args.list, MIND_FILE),
        .show => try commands.executeShow(allocator, cmd_args.show, MIND_FILE),
        .status => try commands.executeStatus(allocator, cmd_args.status, MIND_FILE),
        .done => try commands.executeDone(allocator, cmd_args.done, MIND_FILE),
        .next => try commands.executeNext(allocator, cmd_args.next, MIND_FILE),
        .search => try commands.executeSearch(allocator, cmd_args.search, MIND_FILE),
        .delete => try commands.executeDelete(allocator, cmd_args.delete, MIND_FILE),
        .tag => try commands.executeTag(allocator, cmd_args.tag, MIND_FILE),
        .untag => try commands.executeUntag(allocator, cmd_args.untag, MIND_FILE),
        .link => try commands.executeLink(allocator, cmd_args.link, MIND_FILE),
        .unlink => try commands.executeUnlink(allocator, cmd_args.unlink, MIND_FILE),
        .archive => try commands.executeArchive(allocator, cmd_args.archive, MIND_FILE),
        .help, .quickstart, .none => unreachable,
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
    \\    search <query>           Search todos by query
    \\    tag <id> <tag>           Add tag to todo
    \\    untag <id> <tag>         Remove tag from todo
    \\    link <child> <parent>    Link todos (parent blocks child)
    \\    unlink <child> <parent>  Remove dependency link
    \\    delete <id>              Delete a todo
    \\    remove <id>              Alias for delete
    \\    archive                  Archive old done tasks
    \\    help [command]           Show help for command
    \\
    \\FLAGS:
    \\    --help, -h               Show help
    \\
    \\EXAMPLES:
    \\    mind add "Implement auth" --body "Add JWT authentication" --tags "feature,security"
    \\    mind edit mind-a --title "Fix auth implementation"
    \\    mind edit mind-a --status in-progress
    \\    mind list --status pending
    \\    mind list --tag feature
    \\    mind search "auth"
    \\    mind search --tag frontend "auth"
    \\    mind show mind-a
    \\    mind status
    \\    mind done mind-a --reason "Completed API integration"
    \\    mind done mind-a mind-b mind-c
    \\    mind next
    \\    mind next --all
    \\    mind link mind-b mind-a
    \\    mind unlink mind-b mind-a
    \\    mind archive
    \\    mind archive --days 60
    \\    mind list --json
    \\
    \\STORAGE:
    \\    Todos stored in .mind/mind.json (version control friendly)
    \\    Archived todos stored in .mind/archive.json
    \\
    \\Use 'mind help <command>' for command-specific flags and options.
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
