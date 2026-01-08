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
mind add "Fix bug" --tags "bug,urgent" # With tags
mind add "Task with details" --body "Description here" --tags "frontend"
```

### Viewing Tasks

```bash
mind list                              # List all
mind list --status pending             # Filter by status
mind list --tag bug                    # Filter by tag
mind show <id>                         # Show details
mind next                              # Show next ready task
```

### Managing Tasks

```bash
mind edit <id> --title "New title"              # Update title
mind edit <id> --body "More details"             # Update body
mind edit <id> --status in-progress              # Update status
mind edit <id> --tags "priority,urgent"          # Replace tags
mind done <id>                                    # Mark as done
```

## Dependency Management

### Creating Dependencies

```bash
# Parent task first
PARENT=$(mind add "Parent task")
# Note: Use the ID returned from the add command

# Child task that depends on parent
mind add "Child task"
mind link <child-id> <parent-id>
```

### Dependency Relationships

- `depends_on`: Tasks this depends on (parents)
- `blocked_by`: Tasks that depend on this (children, auto-populated)

### Finding Ready Work

```bash
mind next                              # Show next ready task (no dependencies)
mind next --all                        # Show all ready tasks
mind list --unblocked                  # Show only unblocked tasks
# Use show to see dependencies
mind show <id>                         # Shows depends_on and blocked_by
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
EPIC_ID=$(mind add "Feature: User authentication" --tags "feature,auth")
# Extract ID from output

# 2. Add subtasks
DESIGN=$(mind add "Design login form" --tags "design")
API=$(mind add "Implement login API" --tags "backend")
UI=$(mind add "Create login UI" --tags "frontend")
TEST=$(mind add "Write tests" --tags "testing")

# 3. Create dependencies
mind link $DESIGN $EPIC_ID
mind link $API $DESIGN
mind link $UI $API
mind link $TEST $API
```

### Daily Workflow

```bash
# Check what's ready
mind next                              # Show next ready task
mind list --status pending             # See all pending tasks

# Start working
mind edit <id> --status in-progress

# When done
mind done <id>

# Check what unblocked
mind next                              # Find next task
```

### Bug Fix Workflow

```bash
# Add bug
BUG=$(mind add "Fix: Login validation error" --tags "bug,urgent")
# Extract ID from output

# If blocked by investigation, add dependency
INVESTIGATE=$(mind add "Investigate root cause")
mind link $BUG $INVESTIGATE

# Once investigated
mind done $INVESTIGATE
mind edit $BUG --status in-progress
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
mind --help                     # General help
mind help [command]              # Help for specific command
```
