const std = @import("std");

pub const Args = struct {
    days: u64 = 30, // Default to 30 days
    dry_run: bool = false,
};

const FLAGS = struct {
    const DAYS = "--days";
    const DRY_RUN = "--dry-run";
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

        if (std.mem.eql(u8, arg, FLAGS.DAYS)) {
            if (i + 1 >= args.len) {
                return error.MissingValueForFlag;
            }
            result.days = std.fmt.parseInt(u64, args[i + 1], 10) catch {
                return error.InvalidDaysValue;
            };
            i += 2;
            continue;
        }

        if (std.mem.eql(u8, arg, FLAGS.DRY_RUN)) {
            result.dry_run = true;
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
