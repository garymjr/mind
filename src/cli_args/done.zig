const std = @import("std");

pub const Args = struct {
    ids: []const []const u8,
    reason: ?[]const u8 = null,
};

const FLAGS = struct {
    const REASON = "--reason";
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{
        .ids = &[_][]const u8{},
        .reason = null,
    };

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        if (std.mem.eql(u8, arg, FLAGS.REASON)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.reason = args[i];
            i += 1;
            continue;
        }

        // Not a flag, must be positional (id)
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }

        // Find the end of positional args (first flag or end of args)
        var j: usize = i;
        while (j < args.len and !isFlag(args[j])) : (j += 1) {}

        // Set ids to the slice of positional args
        result.ids = args[i..j];
        i = j;
    }

    if (result.ids.len == 0) return error.MissingId;

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
