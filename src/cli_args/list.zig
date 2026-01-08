const std = @import("std");

pub const Args = struct {
    status: ?[]const u8 = null,
    tag_filter: ?[]const u8 = null,
    blocked_only: bool = false,
    unblocked_only: bool = false,
    json: bool = false,
};

const FLAGS = struct {
    const STATUS = "--status";
    const SHORT_STATUS = "-s";
    const TAG = "--tag";
    const BLOCKED = "--blocked";
    const UNBLOCKED = "--unblocked";
    const JSON = "--json";
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{};

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        if (std.mem.eql(u8, arg, FLAGS.STATUS) or std.mem.eql(u8, arg, FLAGS.SHORT_STATUS)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.status = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.TAG)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.tag_filter = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.BLOCKED)) {
            result.blocked_only = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.UNBLOCKED)) {
            result.unblocked_only = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.JSON)) {
            result.json = true;
            i += 1;
            continue;
        }

        // Unexpected flag or positional
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }
        return error.UnexpectedPositional;
    }

    // Validate flag combinations
    if (result.blocked_only and result.unblocked_only) {
        return error.ConflictingFlags;
    }

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
