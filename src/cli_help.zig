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
    \\    unlink <id> --from <id>  Remove dependency link
    \\    delete <id>              Delete a todo
    \\    archive                  Archive old done tasks
    \\    help [command]           Show help for command
    \\
    \\FLAGS:
    \\    --quiet                  Output only the todo ID (for 'add')
    \\    --title <text>           Set title (for 'edit')
    \\    --body <text>            Set body text (for 'add', 'edit')
    \\    --priority <p>           Set/filter priority: low, medium, high, critical
    \\    --tags, -t <t1,t2>       Set tags comma-separated (for 'add', 'edit')
    \\    --status, -s <s>         Set/filter by status: pending, in-progress, done
    \\    --tag <tag>              Filter by tag
    \\    --blocked                Show only blocked todos
    \\    --unblocked              Show only unblocked todos
    \\    --all                    Show all unblocked todos (for 'next')
    \\    --sort <field>           Sort by: priority, priority-asc (for 'list')
    \\    --reason <text>          Set resolution reason (for 'done')
    \\    --force                  Delete with dependencies (for 'delete')
    \\    --yes                    Skip confirmation prompts
    \\    --days <n>               Age threshold for archive (default: 30)
    \\    --dry-run                Preview archive without making changes
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
    \\    mind archive
    \\    mind archive --days 60
    \\    mind list --json
    \\
    \\STORAGE:
    \\    Todos stored in .mind/mind.json (version control friendly)
    \\    Archived todos stored in .mind/archive.json
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
                \\    --quiet                Output only the todo ID
                \\    --body <text>         Optional body text (adds context)
                \\    --priority <p>        Priority: low, medium, high, critical (default: medium)
                \\    --tags, -t <t1,t2>     Comma-separated tags
                \\
                \\EXAMPLES:
                \\    mind add "Fix login bug"
                \\    mind add "Write docs" --body "Document the API endpoints" --tags "docs,urgent"
                \\    mind add "Critical issue" --priority critical
                \\    mind add "Quick task" --quiet  # Output only: 1736205028-001
                \\
                \\
            );
        },
        .edit => {
            try writer.interface.writeAll(
                \\Edit an existing todo (alias: update)
                \\
                \\USAGE:
                \\    mind edit <id> [--title <text>] [--body <text>] [--status, -s <s>] [--priority <p>] [--tags, -t <t1,t2>]
                \\    mind update <id> [...]
                \\
                \\FLAGS:
                \\    --title <text>       New title
                \\    --body <text>        New body text
                \\    --status, -s <s>     New status: pending, in-progress, done
                \\    --priority <p>       New priority: low, medium, high, critical
                \\    --tags, -t <t1,t2>   Comma-separated tags (replaces existing)
                \\
                \\At least one field must be specified.
                \\
                \\EXAMPLES:
                \\    mind edit 1736205028-001 --title "Updated title"
                \\    mind update 1736205028-001 --status in-progress
                \\    mind edit 1736205028-001 --body "More details"
                \\    mind edit 1736205028-001 --priority high
                \\    mind update 1736205028-001 --tags "bug,urgent"
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
                \\    --status, -s <s>       Filter: pending, in-progress, done
                \\    --priority <p>         Filter: low, medium, high, critical
                \\    --tag <tag>            Filter by tag
                \\    --blocked              Show only blocked todos
                \\    --unblocked            Show only unblocked todos
                \\    --sort <field>         Sort by: priority, priority-asc
                \\    --json                 Output as JSON
                \\
                \\EXAMPLES:
                \\    mind list
                \\    mind list --status pending
                \\    mind list --priority critical
                \\    mind list --tag feature --json
                \\    mind list --sort priority
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
        .status => {
            try writer.interface.writeAll(
                \\Show project status summary
                \\
                \\USAGE:
                \\    mind status [--json]
                \\
                \\FLAGS:
                \\    --json             Output as JSON
                \\
                \\Displays a summary of all todos grouped by status and blocking state.
                \\
                \\EXAMPLES:
                \\    mind status
                \\    mind status --json
                \\
                \\
            );
        },
        .done => {
            try writer.interface.writeAll(
                \\Mark todo(s) as done
                \\
                \\USAGE:
                \\    mind done <id> [<id> ...] [--reason <text>] [--json]
                \\
                \\FLAGS:
                \\    --reason <text>    Optional reason for completion
                \\    --json             Output as JSON
                \\
                \\NOTE: Cannot mark blocked todos as done
                \\
                \\EXAMPLES:
                \\    mind done 1736205028-001
                \\    mind done 1736205028-001 --reason "Fixed the memory leak"
                \\    mind done 1736205028-001 1736205028-002 1736205028-003
                \\    mind done 1736205028-001 --json
                \\
                \\
            );
        },
        .next => {
            try writer.interface.writeAll(
                \\Show next unblocked todo
                \\
                \\USAGE:
                \\    mind next [--all] [--json]
                \\
                \\FLAGS:
                \\    --all              Show all unblocked todos
                \\    --json             Output as JSON (includes all unblocked todos)
                \\
                \\EXAMPLES:
                \\    mind next
                \\    mind next --all
                \\    mind next --json
                \\
                \\
            );
        },
        .search => {
            try writer.interface.writeAll(
                \\Search todos
                \\
                \\USAGE:
                \\    mind search <query> [--tag <tag>] [--json]
                \\
                \\FLAGS:
                \\    --tag <tag>        Filter by tag in addition to query
                \\    --json             Output as JSON
                \\
                \\Performs case-insensitive substring search across todo titles and bodies.
                \\Combined with --tag for refined results.
                \\
                \\EXAMPLES:
                \\    mind search "auth"
                \\    mind search "API"
                \\    mind search --tag frontend "auth"
                \\    mind search "bug" --json
                \\
                \\
            );
        },
        .delete => {
            try writer.interface.writeAll(
                \\Delete a todo
                \\
                \\USAGE:
                \\    mind delete <id> [--force] [--yes]
                \\    mind remove <id> [--force] [--yes]
                \\
                \\FLAGS:
                \\    --force            Delete todo and all linked todos transitively
                \\    --yes              Skip confirmation prompt (use with caution)
                \\
                \\NOTE: Cannot delete a todo with linked dependencies without --force.
                \\When using --force, you will be shown a preview of what will be deleted
                \\and asked to confirm (unless --yes is also specified).
                \\
                \\EXAMPLES:
                \\    mind delete 1736205028-001
                \\    mind remove 1736205028-001 --force
                \\    mind delete 1736205028-001 --force --yes  # skip confirmation
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
        .tag => {
            try writer.interface.writeAll(
                \\Add a tag to a todo
                \\
                \\USAGE:
                \\    mind tag <id> <tag>
                \\
                \\Tags are normalized to NFC Unicode form, ensuring consistent
                \\storage and filtering regardless of input representation.
                \\
                \\EXAMPLES:
                \\    mind tag 1736205028-001 urgent
                \\    mind tag 1736205028-001 frontend
                \\
                \\
            );
        },
        .untag => {
            try writer.interface.writeAll(
                \\Remove a tag from a todo
                \\
                \\USAGE:
                \\    mind untag <id> <tag>
                \\
                \\EXAMPLES:
                \\    mind untag 1736205028-001 urgent
                \\
                \\
            );
        },
        .archive => {
            try writer.interface.writeAll(
                \\Archive old done tasks
                \\
                \\USAGE:
                \\    mind archive [--days <n>] [--dry-run]
                \\
                \\FLAGS:
                \\    --days <n>         Age threshold in days (default: 30)
                \\    --dry-run          Preview what would be archived without making changes
                \\
                \\Moves completed todos older than the specified number of days from
                \\mind.json to archive.json. This keeps your active view clean while
                \\preserving history.
                \\
                \\Only done todos are archived. The age is calculated based on when
                \\the todo was last updated (marked done).
                \\
                \\EXAMPLES:
                \\    mind archive                         # Archive done todos older than 30 days
                \\    mind archive --days 60               # Archive done todos older than 60 days
                \\    mind archive --dry-run               # Preview what would be archived
                \\
                \\To view archived todos:
                \\    # You can use jq or other tools to inspect archive.json
                \\    cat .mind/archive.json
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
    var stderr_buf: [65536]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    try (&stderr_writer.interface).print("error: " ++ fmt ++ "\n", args_);
    try stderr_writer.end();
}
