const std = @import("std");

pub const Args = struct {
    all: bool = false,
};

const FLAGS = struct {
    const ALL = "--all";
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

        if (std.mem.eql(u8, arg, FLAGS.ALL)) {
            result.all = true;
            i += 1;
            continue;
        }

        // Unexpected flag or positional
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }
        return error.UnexpectedPositional;
    }

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
