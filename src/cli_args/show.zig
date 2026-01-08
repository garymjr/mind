const std = @import("std");

pub const Args = struct {
    id: []const u8,
    json: bool = false,
};

const FLAGS = struct {
    const JSON = "--json";
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{
        .id = undefined,
    };
    var id_set = false;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        if (std.mem.eql(u8, arg, FLAGS.JSON)) {
            result.json = true;
            i += 1;
            continue;
        }

        // Not a flag, must be positional (id)
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }

        if (!id_set) {
            result.id = arg;
            id_set = true;
            i += 1;
        } else {
            return error.UnexpectedPositional;
        }
    }

    if (!id_set) return error.MissingId;

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
