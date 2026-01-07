# mind - Your Second Brain for Project Todos

A minimalist, AI-friendly CLI tool for managing project todos with dependencies and tags.

## Features

- **Linked todos** with dependency blocking
- **Tags** for organization
- **Version control friendly** storage (JSON)
- **AI discoverable** commands with structured output
- Written in Zig (fast, single binary)

## Installation

```bash
# Clone and build
git clone <repo>
cd mind
just build

# Install to ~/.local/bin
just install
```

## Quick Start

```bash
# Get started with a guided tour
mind quickstart

# Add a todo
mind add "Implement user authentication"

# Add with body and tags
mind add "Write API docs" --body "Document all REST endpoints" --tags "docs,api"

# List all todos
mind list

# Show todo details
mind show 1736205028-001

# Mark as done
mind done 1736205028-001
```

## Commands

### `add <title>` - Add a new todo

```bash
mind add "Fix login bug"
mind add "Write tests" --body "Add unit tests for auth module" --tags "testing,urgent"
```

Flags:
- `--body <text>` - Optional body text (adds context)
- `--tags <t1,t2>` - Comma-separated tags

**Note**: Title is required and max 100 characters. Body is optional but recommended.

### `list` - List todos

```bash
mind list                          # All todos
mind list --status pending         # Filter by status
mind list --tag feature            # Filter by tag
mind list --blocked                # Only blocked todos
mind list --json                   # JSON output
```

Flags:
- `--status <s>` - Filter: pending, in-progress, done
- `--tag <tag>` - Filter by tag
- `--blocked` - Show only blocked todos
- `--unblocked` - Show only unblocked todos
- `--json` - Output as JSON

### `show <id>` - Show todo details

```bash
mind show 1736205028-001
mind show 1736205028-001 --json
```

### `done <id>` - Mark todo as done

```bash
mind done 1736205028-001
```

**Note**: Cannot mark blocked todos as done.

### `tag <id> <tag>` - Add tag to todo

```bash
mind tag 1736205028-001 feature
```

### `untag <id> <tag>` - Remove tag from todo

```bash
mind untag 1736205028-001 old-tag
```

### `link <child> <parent>` - Link todos

```bash
mind link 1736205028-002 1736205028-001
```

The child todo will be blocked until the parent is marked as done.

### `unlink <id> --from <id>` - Remove dependency

```bash
mind unlink 1736205028-002 --from 1736205028-001
```

### `delete <id>` - Delete a todo

```bash
mind delete 1736205028-001
```

### `help [command]` - Show help

```bash
mind help              # Show all commands
mind help add          # Show help for specific command
```

## Storage

Todos are stored in `.mind/mind.json` in your project root. The format is human-readable and diff-friendly, making it perfect for version control.

Example:
```json
{
  "todos": [
    {
      "id": "1736205028-001",
      "title": "Build initial CLI",
      "body": "Implement basic commands: add, list, show",
      "status": "pending",
      "tags": ["feature", "core"],
      "depends_on": [],
      "blocked_by": [],
      "created_at": "1736205028",
      "updated_at": "1736205028"
    }
  ]
}
```

## AI Usage

The `--json` flag outputs structured data for easy parsing by AI agents:

```bash
mind list --json
mind show 1736205028-001 --json
```

All commands are designed to be easily discoverable and parseable by AI systems.

## Development

```bash
# Build
just build

# Run with arguments
just run add "Test todo"
just run list

# Run all tests
just test

# Run tests for specific file
just test-file util

# Run tests with filter
just test-filter "createTodo"

# Build optimized (fast)
just build-fast

# Build optimized (small)
just build-small

# Clean build artifacts
just clean

# Build and test
just check

# Show available recipes
just --list
```

## License

MIT
