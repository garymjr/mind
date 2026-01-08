const std = @import("std");

pub const Args = struct {
    title: []const u8,
    body: ?[]const u8 = null,
    priority: ?[]const u8 = null,
    tags: ?[]const u8 = null,
    quiet: bool = false,
};

const FLAGS = struct {
    const BODY = "--body";
    const PRIORITY = "--priority";
    const TAGS = "--tags";
    const SHORT_TAGS = "-t";
    const QUIET = "--quiet";
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{
        .title = undefined,
    };
    var title_set = false;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        if (std.mem.eql(u8, arg, FLAGS.QUIET)) {
            result.quiet = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.BODY)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.body = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.PRIORITY)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.priority = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.TAGS) or std.mem.eql(u8, arg, FLAGS.SHORT_TAGS)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.tags = args[i];
            i += 1;
            continue;
        }

        // Not a flag, must be positional (title)
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }

        if (!title_set) {
            result.title = arg;
            title_set = true;
            i += 1;
        } else {
            return error.UnexpectedPositional;
        }
    }

    if (!title_set) return error.MissingTitle;

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
