# AGENTS.MD - mind CLI Project

Gary owns this. Zig-based CLI tool for managing project todos with dependencies and tags.

## Build & Test

```bash
just build              # Build
just build-fast         # Build optimized
just install            # Install to ~/.local/bin
just run <cmd>          # Run with args
just test               # Test all
just test-file <file>   # Test specific file
just test-filter <name> # Test by filter
just check              # Build + test
just clean              # Clean artifacts
```

Binary: `zig-out/bin/mind`

## Code Style

- Imports: `const name = @import("file.zig");` (no .zig extension)
- Indent: 4 spaces
- No semicolons
- Types: PascalCase, functions: camelCase, constants: UPPER_SNAKE_CASE
- Error unions: `!T`, propagate with `try`
- Memory: pass `std.mem.Allocator` explicitly, always free allocations
- Use `defer` for cleanup, `errdefer` for error path only

## Testing

```zig
test "descriptive name" {
    const allocator = std.testing.allocator;
    // Arrange, Act, Assert
    try std.testing.expectEqual(expected, result);
    try std.testing.expectError(error.SpecificError, riskyCall());
}
```

## Architecture

```
src/
├── main.zig       # Entry point, command dispatch
├── cli.zig        # Command enum, arg parsing
├── cli_help.zig   # Help text
├── todo.zig       # Todo data structures
├── storage.zig    # JSON persistence
├── util.zig       # ID generation, validation
└── commands.zig   # Command execution
```

**Key patterns:**
- Manual JSON formatting (diff-friendly)
- Error messages to stderr, `std.process.exit(1)`
- ID format: `{basename}-{hex_seq}` (new) or `{timestamp}-{seq:0>3}` (old, for backward compatibility)
- Buffered writers for stdout/stderr

## Storage

`.mind/mind.json` (gitignored):
```json
{
  "todos": [{
    "id": "mind-0000000a",
    "title": "...",
    "body": "...",
    "status": "pending",
    "priority": "medium",
    "tags": ["tag"],
    "depends_on": ["parent-id"],
    "blocked_by": ["child-id"],
    "created_at": "1736205028",
    "updated_at": "1736205028"
  }]
}
```

## ID Format

New format: `{basename}-{hex_seq}`
- `basename`: Git repository basename (e.g., "mind")
- `hex_seq`: 1-8 character lowercase hexadecimal sequence (e.g., "a", "ff", "123")
- Example: `mind-a`, `mind-ff`, `mind-123`
- Sequence stored in `.mind/.seq` (decimal format)
- Leading zeros trimmed for brevity (e.g., 12 → "c", not "0000000c")

Old format: `{timestamp}-{seq:0>3}` (still accepted for backward compatibility)
- Example: `1736205028-001`
- New todos use new format; old todos can still be edited/managed

## Constants

- `MAX_TITLE_LENGTH`: 100
- Storage path: `.mind/mind.json`
- IDs: strings, not numbers
- Tags: comma-separated

## Adding Commands

1. Add enum variant to `cli.Command`
2. Add flags to `cli.FLAG_DEFINITIONS`
3. Handle flags in `cli.parseArgs()`
4. Implement `execute<CommandName>()` in commands.zig
5. Add case to main.zig switch
6. Add help text to cli_help.zig
7. **Update `skill/mind/SKILL.md`** with new command/workflow documentation

## Documentation Updates

When adding new commands, workflows, or common command patterns, **always update `skill/mind/SKILL.md`**:
- Add command to appropriate section (Common Commands, Viewing Tasks, etc.)
- Document usage examples with realistic scenarios
- Add workflow patterns to Workflows section if applicable
- Keep examples copy-pasteable and accurate

## Unimplemented Commands

- `tag`, `untag`

## Justfile

Project uses `just` for common tasks. Run `just --list` to see all recipes.
