const std = @import("std");

pub const Args = struct {
    id: []const u8,
    title: ?[]const u8 = null,
    body: ?[]const u8 = null,
    status: ?[]const u8 = null,
    tags: ?[]const u8 = null,
};

const FLAGS = struct {
    const TITLE = "--title";
    const BODY = "--body";
    const TAGS = "--tags";
    const SHORT_TAGS = "-t";
    const STATUS = "--status";
    const SHORT_STATUS = "-s";
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

        if (std.mem.eql(u8, arg, FLAGS.TITLE)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.title = args[i];
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

        if (std.mem.eql(u8, arg, FLAGS.TAGS) or std.mem.eql(u8, arg, FLAGS.SHORT_TAGS)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.tags = args[i];
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.STATUS) or std.mem.eql(u8, arg, FLAGS.SHORT_STATUS)) {
            i += 1;
            if (i >= args.len) return error.MissingValueForFlag;
            result.status = args[i];
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

    // At least one field must be specified to edit
    if (result.title == null and result.body == null and result.status == null and result.tags == null) {
        return error.MissingEditField;
    }

    return result;
}

fn isFlag(arg: []const u8) bool {
    return arg.len > 0 and arg[0] == '-';
}
