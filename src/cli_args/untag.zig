const std = @import("std");

pub const Args = struct {
    id: []const u8,
    tag: []const u8,
};

const FLAGS = struct {
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{
        .id = undefined,
        .tag = undefined,
    };
    var id_set = false;
    var tag_set = false;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        // Handle flags
        if (std.mem.eql(u8, arg, FLAGS.HELP) or std.mem.eql(u8, arg, FLAGS.SHORT_HELP)) {
            return error.ShowHelp;
        }

        // Not a flag, must be positional arguments
        if (isFlag(arg)) {
            return error.UnknownFlag;
        }

        if (!id_set) {
            result.id = arg;
            id_set = true;
        } else if (!tag_set) {
            result.tag = arg;
            tag_set = true;
        } else {
            return error.UnexpectedPositional;
        }
        i += 1;
    }

    if (!id_set) return error.MissingId;
    if (!tag_set) return error.MissingTag;

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
