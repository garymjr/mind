const std = @import("std");

pub const Args = struct {};

const FLAGS = struct {
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    for (args) |arg| {
        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        // status command takes no arguments or flags
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }
        return error.UnexpectedPositional;
    }

    return Args{};
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
