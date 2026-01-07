const std = @import("std");
const help = @import("cli_help.zig");

pub const printFullHelp = help.printFullHelp;
pub const printCommandHelp = help.printCommandHelp;
pub const printError = help.printError;

pub const Command = enum {
    none,
    help,
    quickstart,
    add,
    list,
    show,
    done,
    tag,
    untag,
    link,
    unlink,
    delete,
};

pub const Args = struct {
    command: Command = .none,
    target: ?[]const u8 = null, // todo ID or command for help
    title: ?[]const u8 = null,
    body: ?[]const u8 = null,
    tags: ?[]const u8 = null, // comma-separated
    from: ?[]const u8 = null, // for unlink
    status: ?[]const u8 = null,
    tag_filter: ?[]const u8 = null,
    blocked_only: bool = false,
    unblocked_only: bool = false,
    json: bool = false,
    force: bool = false,
};

const FLAG_DEFINITIONS = struct {
    const BODY = "--body";
    const TAGS = "--tags";
    const STATUS = "--status";
    const TAG = "--tag";
    const BLOCKED = "--blocked";
    const UNBLOCKED = "--unblocked";
    const JSON = "--json";
    const FROM = "--from";
    const FORCE = "--force";
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parseArgs(_: std.mem.Allocator, args: []const [:0]const u8) !Args {
    var result = Args{};

    var i: usize = 1; // Skip program name
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.HELP) or std.mem.eql(u8, arg, FLAG_DEFINITIONS.SHORT_HELP)) {
            return Args{ .command = .help };
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.BODY)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.body = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.TAGS)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.tags = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.STATUS)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.status = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.TAG)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.tag_filter = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.FROM)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.from = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.BLOCKED)) {
            result.blocked_only = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.UNBLOCKED)) {
            result.unblocked_only = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.JSON)) {
            result.json = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAG_DEFINITIONS.FORCE)) {
            result.force = true;
            i += 1;
            continue;
        }

        // Not a flag, must be a command or positional argument
        if (result.command == .none) {
            // Parse command
            result.command = parseCommand(arg) orelse return error.UnknownCommand;
        } else {
            // Positional argument
            // For 'add' command, first positional arg is title
            // For other commands, first positional arg is target (id)
            if (result.command == .add) {
                if (result.title == null) {
                    result.title = arg;
                } else if (result.target == null) {
                    result.target = arg;
                }
            } else {
                if (result.target == null) {
                    result.target = arg;
                } else if (result.title == null and result.command == .add) {
                    result.title = arg;
                }
            }
        }
        i += 1;
    }

    return result;
}

pub fn parseCommand(str: []const u8) ?Command {
    if (std.mem.eql(u8, str, "help")) return .help;
    if (std.mem.eql(u8, str, "quickstart")) return .quickstart;
    if (std.mem.eql(u8, str, "add")) return .add;
    if (std.mem.eql(u8, str, "list")) return .list;
    if (std.mem.eql(u8, str, "show")) return .show;
    if (std.mem.eql(u8, str, "done")) return .done;
    if (std.mem.eql(u8, str, "tag")) return .tag;
    if (std.mem.eql(u8, str, "untag")) return .untag;
    if (std.mem.eql(u8, str, "link")) return .link;
    if (std.mem.eql(u8, str, "unlink")) return .unlink;
    if (std.mem.eql(u8, str, "delete")) return .delete;
    if (std.mem.eql(u8, str, "remove")) return .delete;
    return null;
}
