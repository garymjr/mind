// Command-specific argument parsers
// Each command module defines its own Args struct and parse() function

pub const Add = @import("cli_args/add.zig");
pub const Edit = @import("cli_args/edit.zig");
pub const List = @import("cli_args/list.zig");
pub const Show = @import("cli_args/show.zig");
pub const Status = @import("cli_args/status.zig");
pub const Done = @import("cli_args/done.zig");
pub const Next = @import("cli_args/next.zig");
pub const Search = @import("cli_args/search.zig");
pub const Tag = @import("cli_args/tag.zig");
pub const Untag = @import("cli_args/untag.zig");
pub const Link = @import("cli_args/link.zig");
pub const Unlink = @import("cli_args/unlink.zig");
pub const Delete = @import("cli_args/delete.zig");
pub const Archive = @import("cli_args/archive.zig");
