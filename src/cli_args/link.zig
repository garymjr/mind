const std = @import("std");

pub const Args = struct {
    child_id: []const u8,
    parent_id: []const u8,
};

const FLAGS = struct {
    const HELP = "--help";
    const SHORT_HELP = "-h";
};

pub fn parse(args: []const []const u8) !Args {
    var result = Args{
        .child_id = undefined,
        .parent_id = undefined,
    };
    var child_set = false;
    var parent_set = false;

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

        if (!child_set) {
            result.child_id = arg;
            child_set = true;
        } else if (!parent_set) {
            result.parent_id = arg;
            parent_set = true;
        } else {
            return error.UnexpectedPositional;
        }
        i += 1;
    }

    if (!child_set) return error.MissingChildId;
    if (!parent_set) return error.MissingParentId;

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
