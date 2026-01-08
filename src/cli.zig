const std = @import("std");
const help = @import("cli_help.zig");
const cli_args = @import("cli_args.zig");

pub const printFullHelp = help.printFullHelp;
pub const printCommandHelp = help.printCommandHelp;
pub const printError = help.printError;

pub const Command = enum {
    none,
    help,
    quickstart,
    add,
    edit,
    list,
    show,
    status,
    done,
    next,
    search,
    tag,
    untag,
    link,
    unlink,
    delete,
};

// Tagged union for command-specific arguments
pub const CommandArgs = union(Command) {
    none: void,
    help: ?[]const u8, // optional command name for detailed help
    quickstart: void,
    add: cli_args.Add.Args,
    edit: cli_args.Edit.Args,
    list: cli_args.List.Args,
    show: cli_args.Show.Args,
    status: cli_args.Status.Args,
    done: cli_args.Done.Args,
    next: cli_args.Next.Args,
    search: cli_args.Search.Args,
    tag: cli_args.Tag.Args,
    untag: cli_args.Untag.Args,
    link: cli_args.Link.Args,
    unlink: cli_args.Unlink.Args,
    delete: cli_args.Delete.Args,
};

// Global-only flags (help)
const GLOBAL_FLAGS = struct {
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parseCommand(str: []const u8) ?Command {
    if (std.mem.eql(u8, str, "help")) return .help;
    if (std.mem.eql(u8, str, "quickstart")) return .quickstart;
    if (std.mem.eql(u8, str, "add")) return .add;
    if (std.mem.eql(u8, str, "edit")) return .edit;
    if (std.mem.eql(u8, str, "update")) return .edit;
    if (std.mem.eql(u8, str, "list")) return .list;
    if (std.mem.eql(u8, str, "show")) return .show;
    if (std.mem.eql(u8, str, "status")) return .status;
    if (std.mem.eql(u8, str, "done")) return .done;
    if (std.mem.eql(u8, str, "next")) return .next;
    if (std.mem.eql(u8, str, "search")) return .search;
    if (std.mem.eql(u8, str, "tag")) return .tag;
    if (std.mem.eql(u8, str, "untag")) return .untag;
    if (std.mem.eql(u8, str, "link")) return .link;
    if (std.mem.eql(u8, str, "unlink")) return .unlink;
    if (std.mem.eql(u8, str, "delete")) return .delete;
    if (std.mem.eql(u8, str, "remove")) return .delete;
    return null;
}

/// Parse global arguments and return the command
/// Returns the command and the slice of args starting at index 1 (after command)
pub fn parseGlobal(args: []const []const u8) !struct { command: Command, cmd_args_start: usize } {
    if (args.len < 2) {
        return error.NoCommand;
    }

    const arg = args[1];

    // Check for global --help or -h
    if (std.mem.eql(u8, arg, GLOBAL_FLAGS.HELP) or std.mem.eql(u8, arg, GLOBAL_FLAGS.SHORT_HELP)) {
        return .{ .command = .help, .cmd_args_start = 2 };
    }

    // Parse command
    const command = parseCommand(arg) orelse return error.UnknownCommand;

    return .{ .command = command, .cmd_args_start = 2 };
}

/// Parse command-specific arguments
pub fn parseCommandArgs(command: Command, args: []const []const u8) !CommandArgs {
    const cmd_args = if (args.len >= 2) args[2..] else &[_][]const u8{};

    return switch (command) {
        .add => CommandArgs{ .add = try cli_args.Add.parse(cmd_args) },
        .edit => CommandArgs{ .edit = try cli_args.Edit.parse(cmd_args) },
        .list => CommandArgs{ .list = try cli_args.List.parse(cmd_args) },
        .show => CommandArgs{ .show = try cli_args.Show.parse(cmd_args) },
        .status => CommandArgs{ .status = try cli_args.Status.parse(cmd_args) },
        .done => CommandArgs{ .done = try cli_args.Done.parse(cmd_args) },
        .next => CommandArgs{ .next = try cli_args.Next.parse(cmd_args) },
        .search => CommandArgs{ .search = try cli_args.Search.parse(cmd_args) },
        .tag => CommandArgs{ .tag = try cli_args.Tag.parse(cmd_args) },
        .untag => CommandArgs{ .untag = try cli_args.Untag.parse(cmd_args) },
        .link => CommandArgs{ .link = try cli_args.Link.parse(cmd_args) },
        .unlink => CommandArgs{ .unlink = try cli_args.Unlink.parse(cmd_args) },
        .delete => CommandArgs{ .delete = try cli_args.Delete.parse(cmd_args) },
        .help => {
            // help command takes optional command name as positional arg
            if (cmd_args.len > 0) {
                return CommandArgs{ .help = cmd_args[0] };
            }
            return CommandArgs{ .help = null };
        },
        .quickstart => CommandArgs{ .quickstart = {} },
        .none => CommandArgs{ .none = {} },
    };
}

/// Helper function to format parse errors for user display
pub fn formatParseError(err: anyerror, _: Command) []const u8 {
    return switch (err) {
        error.MissingTitle => "add requires a title",
        error.MissingId => "command requires a todo ID",
        error.MissingTag => "command requires a tag",
        error.MissingChildId => "link requires a child todo ID",
        error.MissingParentId => "link requires a parent todo ID",
        error.MissingValueForFlag => "flag requires a value",
        error.UnknownFlag => "unknown flag",
        error.UnexpectedPositional => "unexpected positional argument",
        error.ConflictingFlags => "conflicting flags specified",
        error.MissingEditField => "edit requires at least one field: --title, --body, --status, or --tags",
        error.ShowHelp => "", // Will be handled separately
        else => "unknown error",
    };
}
