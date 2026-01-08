const std = @import("std");

pub const Args = struct {
    query: ?[]const u8 = null,
    tag_filter: ?[]const u8 = null,
    json: bool = false,
};

const FLAGS = struct {
    const TAG = "--tag";
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

        if (std.mem.eql(u8, arg, FLAGS.TAG)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.tag_filter = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.JSON)) {
            result.json = true;
            i += 1;
            continue;
        }

        // Unexpected flag
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }

        // First positional arg is the search query
        if (result.query == null) {
            result.query = arg;
            i += 1;
            continue;
        }

        return error.UnexpectedPositional;
    }

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
