# Build recipes for mind CLI

# Build the project
build:
    zig build

# Run the application
run *args:
    zig build run -- {{args}}

# Install to ~/.local/bin
install:
    zig build install --prefix ~/.local

# Run all tests
test:
    zig build test

# Run tests for a specific file
test-file file:
    zig test src/{{file}}.zig

# Run tests with filter
test-filter filter:
    zig build test --test-filter {{filter}}

# Clean build artifacts
clean:
    rm -rf zig-out zig-cache .mind

# Build with optimizations (fast)
build-fast:
    zig build -Doptimize=ReleaseFast

# Build with optimizations (small)
build-small:
    zig build -Doptimize=ReleaseSmall

# Show project status (build + test)
check:
    just build
    just test

# Quick test for development
dev-test:
    just test-file util
    just test-file todo

# List all recipes (default)
default:
    @just --list
