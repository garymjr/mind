---
name: mind
description: Zig-based CLI tool for managing project todos with dependencies and tags. Use when tracking tasks, features, bugs, or any work that requires dependency tracking and organization.
---

# Mind CLI Skill

Mind is a Zig-based CLI tool for managing project todos with dependencies and tags. Store all project work in `.mind/mind.json` (gitignored).

## When to Use

- Managing project todos, features, or bugs
- Tracking work that has dependencies or blockers
- Organizing tasks with tags (epics, areas, priorities)
- Coordinating work across multiple agents
- Any task-based project work

## Core Concepts

- **ID**: `{timestamp}-{ms:0>3}` format, auto-generated
- **Status**: `pending`, `in-progress`, `done`, `blocked`
- **Dependencies**: `depends_on` (parent tasks) and `blocked_by` (child tasks)
- **Tags**: Comma-separated for categorization

## Common Commands

### Adding Tasks

```bash
mind add "Implement feature"          # Simple todo
mind add "Fix bug" -t bug,urgent       # With tags
mind add "Dependent task" -d <parent-id>  # With dependency
```

### Viewing Tasks

```bash
mind list                              # List all
mind list -s pending                   # Filter by status
mind list -t bug                       # Filter by tag
mind show <id>                         # Show details
mind next                              # Show next ready task
```

### Managing Tasks

```bash
mind edit <id>                         # Edit interactively
mind status <id> in-progress           # Update status
mind status <id> done
mind tag <id> +priority                # Add tag
mind tag <id> -old-tag                 # Remove tag
```

## Dependency Management

### Creating Dependencies

```bash
# Parent task first
PARENT=$(mind add "Parent task" --id-only)

# Child task that depends on parent
mind add "Child task" -d $PARENT
```

### Dependency Relationships

- `depends_on`: Tasks this depends on (parents)
- `blocked_by`: Tasks that depend on this (children, auto-populated)

### Finding Ready Work

```bash
mind next                              # Show next ready task (no dependencies)
mind list -s pending | grep -v "depends_on:"  # Tasks without dependencies
# Use blocked_by to see what's blocking
mind show <id> | grep blocked_by
```

**`mind next`** displays the next task that's ready to work on - a pending task with no unmet dependencies. Useful for quickly finding what to start next without scanning the full list.

## Best Practices

1. **Granular tasks**: Break down work into small, completable items
2. **Use tags**: Organize by area, priority, type (e.g., `frontend`, `urgent`, `bug`)
3. **Set dependencies**: Clearly define what blocks what
4. **Update status**: Mark `in-progress` when starting, `done` when complete
5. **Clear titles**: Keep titles under 100 chars, descriptive
6. **Use body**: Add details, acceptance criteria, notes

## Workflows

### Starting New Feature

```bash
# 1. Add epic/task
EPIC=$(mind add "Feature: User authentication" -t feature,auth --id-only)

# 2. Add subtasks
mind add "Design login form" -d $EPIC -t design
mind add "Implement login API" -d $EPIC -t backend
mind add "Create login UI" -d $EPIC -t frontend
mind add "Write tests" -d $EPIC -t testing
```

### Daily Workflow

```bash
# Check what's ready
mind next                              # Quick: show next ready task
mind list -s pending                   # Or: see all pending

# Start working
mind status <id> in-progress

# When done
mind status <id> done

# Check what unblocked
mind next                              # Quick: find next task
mind list -s pending                   # Or: see all pending
```

### Bug Fix Workflow

```bash
# Add bug
BUG=$(mind add "Fix: Login validation error" -t bug,urgent --id-only)

# If blocked by investigation, add dependency
INVESTIGATE=$(mind add "Investigate root cause" -d $BUG --id-only)
mind status $BUG blocked

# Once investigated
mind status $INVESTIGATE done
mind status $BUG in-progress
```

## Testing

```bash
just test              # Test all
just test-file <file>  # Test specific file
just check             # Build + test
```

## Storage

Data stored in `.mind/mind.json`:

```json
{
  "todos": [{
    "id": "1736205028-001",
    "title": "...",
    "body": "...",
    "status": "pending",
    "tags": ["tag"],
    "depends_on": ["parent-id"],
    "blocked_by": ["child-id"],
    "created_at": "1736205028",
    "updated_at": "1736205028"
  }]
}
```

File is gitignored. Don't commit it.

## Getting Help

```bash
mind help              # General help
mind <command> --help  # Command-specific help
```
