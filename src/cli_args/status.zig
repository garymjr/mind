const std = @import("std");

pub const Args = struct {
    json: bool = false,
};

const FLAGS = struct {
    const JSON = "--json";
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{};

    for (args) |arg| {
        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        if (std.mem.eql(u8, arg, FLAGS.JSON)) {
            result.json = true;
            continue;
        }

        // status command takes no positional arguments
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
