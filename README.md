# tracker

A simple task and time tracker written in Janet lang.

## Features

- Create and manage time-tracked tasks
- Pause/resume/stop tasks with automatic time calculation
- Add tags and notes to tasks
- Store data in human-readable markdown format
- Unique task IDs for easy reference
- Environment variable configuration

## Installation

### Install Janet

```bash
git clone --depth 1 https://github.com/janet-lang/janet && cd janet
make clean && PREFIX=$HOME/.local/janet make && PREFIX=$HOME/.local/janet make install

# JPM
cd ..
git clone --depth 1 https://github.com/janet-lang/jpm && cd jpm
PREFIX=$HOME/.local/janet janet bootstrap.janet

# Spork not needed, but here if required in future
cd ..
git clone --depth 1 https://github.com/janet-lang/spork && cd spork
jpm install
```

### Build from source

Requirements:
- [Janet](https://janet-lang.org/) programming language
- [jpm](https://github.com/janet-lang/jpm) (Janet Package Manager)

```bash
# Clone and build
git clone <repository-url>
cd tracker
jpm build
```

### Build static binary with container (podman)

```bash
# Build static binary using containerization
just build

# Or manually:
podman build -t tracker-image .
podman create --name tracker-container tracker-image
podman cp tracker-container:/output/tracker-static ./tracker-static
podman rm tracker-container
```

## Usage

Run directly with Janet:
```bash
janet tracker.janet <command> [args...]
```

Or use the compiled binary:
```bash
./tracker <command> [args...]
```

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `create <name>` | Create a new task | `tracker create "Fix database bug"` |
| `pause <name-or-id>` | Pause a running task | `tracker pause "Fix database bug"` |
| `resume <name-or-id>` | Resume a paused task | `tracker resume abc1` |
| `stop <name-or-id>` | Stop a task completely | `tracker stop abc1` |
| `list` | List all tasks with status | `tracker list` |
| `tag <name-or-id> <tag>` | Add a tag to task | `tracker tag abc1 urgent` |
| `note <name-or-id> <note>` | Add a note to task | `tracker note abc1 "Found root cause"` |

### Examples

```bash
# Create a new task
tracker create "Implement user authentication"

# Pause the task (stops time tracking)
tracker pause "Implement user authentication"

# Resume work on the task
tracker resume "Implement user authentication"

# Add tags and notes
tracker tag "Implement user authentication" backend
tracker tag "Implement user authentication" security
tracker note "Implement user authentication" "Using JWT tokens"

# List all tasks
tracker list

# Stop task when finished
tracker stop "Implement user authentication"
```

## Configuration

### Environment Variables

- `TRACKER_FILE`: Path to tracker markdown file (default: `~/.tracker.md`)

```bash
# Use custom tracker file
TRACKER_FILE=/path/to/my-project.md tracker list

# Use project-specific tracker
export TRACKER_FILE=$(pwd)/project-tracker.md
tracker create "New feature"
```

## Data Format

Tasks are stored in markdown format with structured metadata:

```markdown
# Time Tracker

# Task: Implement user authentication
- **ID**: abc1
- **Status**: running
- **Created**: 2023-12-01 09:30
- **Task Time**: 2023-12-01 09:30-2023-12-01 12:30; 2023-12-01 14:00-nil
- **Tags**: #backend #security
- **Notes**: Using JWT tokens; Added password hashing
```

## Building with Just

The project includes a `Justfile` for common build tasks:

```bash
# List available commands
just

# Build static binary
just build

# Clean containers
just clean
```

## Development

### Running tests

```bash
janet test-tracker.janet
# or
jpm test
```

### Project structure

- `tracker.janet` - Main application code
- `project.janet` - Janet project configuration
- `test-tracker.janet` - Test suite
- `Justfile` - Build automation
- `Containerfile` - Container build configuration

## Example

```bash
$ tracker list
Tasks from /home/marek/.tracker.md:
 [stopped] [         2h 10m] [ab]: Task 1
    Created:    2025-02-13 00:31
    Session  1: 2025-02-13 00:31 - 2025-02-13 02:41 [         2h 10m]
    Tags: #test
    Notes: A note

 [stopped] [      1d 6h 10m] [a5]: Task 3
    Created:    2025-02-13 12:31
    Session  1: 2025-02-13 12:31 - 2025-02-14 18:41 [      1d 6h 10m]
    Tags: #test #tag2
    Notes: A note; Another note

 [running] [             7m] [tw]: Task 2
    Created:    2025-06-13 08:58
    Session  1: 2025-06-13 08:58 -          running [             7m]

 [ paused] [          1d 3m] [82]: Paused task
    Created:    2025-02-13 09:03
    Session  1: 2025-02-13 09:03 - 2025-02-14 09:03 [             1d]
    Session  2: 2025-06-13 09:03 - 2025-06-13 09:04 [             1m]
    Session  3: 2025-06-13 09:04 - 2025-06-13 09:06 [             2m]
```
