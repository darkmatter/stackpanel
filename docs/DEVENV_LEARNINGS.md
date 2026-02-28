# Learnings from devenv's `.devenv/` Directory

This document analyzes devenv's approach to managing development environment state and identifies improvements we can make to Stackpanel.

## Overview

Devenv creates a `.devenv/` directory with the following structure:

```
.devenv/
├── bash                    # Symlink to bash store path
├── devenv.json            # Input configuration (JSON)
├── flake.json             # Flake inputs (JSON)
├── gc/                    # GC root symlinks (prevents garbage collection)
│   ├── procfilescript -> /nix/store/...-devenv-up
│   ├── shell -> shell-1-link
│   └── shell-1-link -> /nix/store/...-devenv-shell-env
├── imports.txt            # Empty (reserved for future use)
├── input-paths.txt        # List of files that affect the shell
├── load-exports           # (Placeholder, 1 byte)
├── nix-eval-cache.db      # SQLite cache for Nix evaluations
├── nix-eval-cache.db-shm  # SQLite shared memory
├── nix-eval-cache.db-wal  # SQLite write-ahead log
├── processes              # Script to start processes
├── profile/               # Symlink to unified profile derivation
├── run/                   # Ephemeral runtime data (tmpfs)
├── state/                 # Persistent state data
│   ├── git-hooks/
│   ├── process-compose/
│   └── starship.toml
└── tasks.db               # SQLite database for task tracking
```

## Key Learnings

### 1. Smart Caching with File & Command Tracking (`nix-eval-cache.db`)

**What devenv does:**
- Uses SQLite database to cache Nix evaluation results
- Tracks file content hashes, not just modification times
- Links commands to their file dependencies
- Stores command hash, input hash, and output

**Schema:**
```sql
CREATE TABLE cached_cmd (
  id             INTEGER NOT NULL PRIMARY KEY,
  raw            TEXT NOT NULL,
  cmd_hash       CHAR(64) NOT NULL UNIQUE,
  input_hash     CHAR(64) NOT NULL,
  output         TEXT NOT NULL,
  updated_at     INTEGER NOT NULL
);

CREATE TABLE file_input (
  id           INTEGER NOT NULL PRIMARY KEY,
  path         BLOB NOT NULL UNIQUE,
  is_directory BOOLEAN NOT NULL,
  content_hash CHAR(64) NOT NULL,
  modified_at  INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE cmd_input_path (
  id                INTEGER NOT NULL PRIMARY KEY,
  cached_cmd_id     INTEGER,
  file_input_id     INTEGER,
  UNIQUE(cached_cmd_id, file_input_id),
  FOREIGN KEY(cached_cmd_id) REFERENCES cached_cmd(id),
  FOREIGN KEY(file_input_id) REFERENCES file_input(id)
);

CREATE TABLE env_input (
  id            INTEGER NOT NULL PRIMARY KEY,
  cached_cmd_id INTEGER NOT NULL,
  name          TEXT NOT NULL,
  content_hash  CHAR(64) NOT NULL,
  updated_at    INTEGER NOT NULL,
  FOREIGN KEY(cached_cmd_id) REFERENCES cached_cmd(id),
  UNIQUE(cached_cmd_id, name)
);
```

**Benefits:**
- Extremely fast shell reloads (checks file hashes instead of re-evaluating)
- Tracks dependencies precisely (knows which files affect which commands)
- Invalidates cache only when actual content changes, not mtime
- Supports environment variable tracking

**Current Stackpanel approach:**
- Single `.files-manifest` hash file
- No file-level dependency tracking
- No command result caching

### 2. Task System (`tasks.db`)

**What devenv does:**
- Tracks task runs with timestamps and output
- Records watched files per task with content hashes
- Can skip tasks if watched files haven't changed

**Schema:**
```sql
CREATE TABLE task_run (
  id        INTEGER PRIMARY KEY,
  task_name TEXT NOT NULL UNIQUE,
  last_run  INTEGER NOT NULL,
  output    JSON
);

CREATE TABLE watched_file (
  id            INTEGER PRIMARY KEY,
  task_name     TEXT NOT NULL,
  path          TEXT NOT NULL,
  modified_time INTEGER NOT NULL,
  content_hash  TEXT,
  is_directory  BOOLEAN NOT NULL DEFAULT 0,
  UNIQUE(task_name, path)
);
```

**Benefits:**
- Persistent task history across shell sessions
- Smart task skipping based on file changes
- Debugging: can see when tasks last ran and their output

**Current Stackpanel approach:**
- Turbo tasks in `tasks/` directory
- No persistent state tracking
- No file dependency tracking per task

### 3. Input Tracking (`input-paths.txt`)

**What devenv does:**
- Explicitly lists all files that affect the shell environment
- Generated during shell build

**Example:**
```
/Users/cm/git/darkmatter/nixmac/.devenv/flake.json
/Users/cm/git/darkmatter/nixmac/.devenv.flake.nix
/Users/cm/git/darkmatter/nixmac/.env
/Users/cm/git/darkmatter/nixmac/devenv.local.nix
/Users/cm/git/darkmatter/nixmac/devenv.lock
/Users/cm/git/darkmatter/nixmac/devenv.nix
/Users/cm/git/darkmatter/nixmac/devenv.yaml
```

**Benefits:**
- Clear documentation of what affects the shell
- Useful for cache invalidation
- Helps debug "why did my shell change?"
- Can be used by direnv for watch_file

**Current Stackpanel approach:**
- Manual `watch_file` calls scattered in `.envrc`
- No generated list of dependencies

### 4. GC Roots (`gc/` directory)

**What devenv does:**
- Creates numbered generation symlinks: `shell-1-link`, `shell-2-link`, etc.
- Prevents garbage collection of current and recent shells
- Allows rollback to previous generations

**Structure:**
```
gc/
├── procfilescript -> /nix/store/...-devenv-up
├── shell -> shell-1-link                        # Current
└── shell-1-link -> /nix/store/...-devenv-shell-env
```

**Benefits:**
- Keeps current and previous generations around
- Prevents "shell disappeared" errors during `nix-collect-garbage`
- Numbered generations allow rollback
- Can see shell history

**Current Stackpanel approach:**
- Single `shellhook.sh` symlink
- No generation tracking
- No rollback capability

### 5. Separate State & Runtime (`state/` and `run/`)

**What devenv does:**
- **`state/`**: Persistent data (git-hooks, process-compose state, configs)
- **`run/`**: Ephemeral runtime data (symlinks to `/tmp`)

**Benefits:**
- Clear separation of persistent vs temporary data
- Can safely clean `run/` without losing state
- Runtime data in tmpfs is faster
- Better semantics

**Current Stackpanel approach:**
- Everything in `.stackpanel/state/`
- No distinction between persistent and ephemeral
- Accumulates temporary files over time

### 6. JSON Configuration Files (`devenv.json`, `flake.json`)

**What devenv does:**
- Stores input configurations as JSON
- Flake inputs stored separately

**Benefits:**
- Easy to query with `jq`
- Machine-readable for tooling
- Stable format for caching
- Can diff between generations

**Current Stackpanel approach:**
- `stackpanel.json` is similar
- Could add more structured data

### 7. Profile Linking (`profile/`)

**What devenv does:**
- Creates a unified profile derivation with all packages
- Single symlink to profile in store

**Benefits:**
- Single PATH entry instead of many
- Consistent environment structure
- Can inspect what's in the environment easily
- Faster PATH lookups

**Current Stackpanel approach:**
- Add individual store paths to PATH
- Longer PATH variable
- More lookups during command resolution

## Recommendations for Stackpanel

### High Priority

#### 1. Add SQLite Caching System

**Task:** Implement `nix-eval-cache.db` equivalent for Stackpanel

**Goals:**
- Cache file content hashes (not just mtimes)
- Track which files affect which generated outputs
- Cache command results with dependency tracking
- Support environment variable change detection

**Implementation:**
- Create `.stackpanel/state/eval-cache.db`
- Schema similar to devenv's (see above)
- Use for `write-files` and other codegen
- Invalidate only when actual content changes

**Benefits:**
- Much faster shell reloads
- More reliable cache invalidation
- Better debugging (can see why cache was invalidated)
- Reduces unnecessary rebuilds

**Estimated effort:** Large (2-3 days)

#### 2. Better GC Root Management

**Task:** Implement numbered generations and prevent GC issues

**Goals:**
- Use numbered generations like `shell-1-link`, `shell-2-link`
- Keep last N generations (default: 3)
- Prevent accidental GC of current shell
- Support rollback to previous generation

**Implementation:**
- Create `.stackpanel/state/gc/` directory
- Create `shell` symlink pointing to `shell-N-link`
- Increment N on each shell rebuild
- Add `stackpanel rollback` command
- Clean up old generations (keep last N)

**Benefits:**
- No more "shell disappeared" errors
- Can rollback if new shell is broken
- Clear history of shell changes
- Better GC safety

**Estimated effort:** Medium (1 day)

#### 3. Generate Input Paths List

**Task:** Create `.stackpanel/state/input-paths.txt`

**Goals:**
- List all files that affect the shell environment
- Generated during shell build
- Used by direnv for watch_file
- Help users debug configuration changes

**Implementation:**
- During shell build, track all imported files
- Write to `input-paths.txt`
- Update `.envrc` to read from this file
- Show in `stackpanel status` when inputs changed

**Benefits:**
- Clear documentation of dependencies
- Better cache invalidation
- Easier debugging
- Automated direnv watches

**Estimated effort:** Small (4 hours)

### Medium Priority

#### 4. Separate State and Runtime Directories

**Task:** Split `.stackpanel/state/` into `state/` and `run/`

**Goals:**
- Move ephemeral data to `.stackpanel/run/`
- Keep persistent data in `.stackpanel/state/`
- Optionally symlink `run/` to tmpfs

**Implementation:**
- Create `.stackpanel/run/` directory
- Move temporary files: PID files, sockets, temp logs
- Keep persistent: databases, configs, generated files
- Add cleanup on shell exit

**What goes where:**
- **`state/`**: databases, configs, generated files, caches, logs
- **`run/`**: PID files, sockets, lock files, temp status

**Benefits:**
- Clearer semantics
- Can safely clean run/ without losing state
- Faster if run/ is on tmpfs
- Less disk I/O

**Estimated effort:** Medium (1 day)

#### 5. Task State Tracking

**Task:** Implement `tasks.db` for persistent task tracking

**Goals:**
- Track task runs with timestamps
- Record file dependencies per task
- Skip unchanged tasks automatically
- Store task output for debugging

**Implementation:**
- Create `.stackpanel/state/tasks.db`
- Schema similar to devenv's (see above)
- Integrate with turbo tasks
- Add `stackpanel tasks history` command
- Show stale tasks in status

**Benefits:**
- Faster builds (skip unchanged tasks)
- Task run history
- Better debugging
- Visible task dependencies

**Estimated effort:** Large (2-3 days)

### Low Priority

#### 6. Unified Profile

**Task:** Build single profile derivation instead of many PATH entries

**Goals:**
- Create unified profile with all packages
- Single PATH entry
- Faster command lookups

**Implementation:**
- Build profile derivation in Nix
- Symlink to `.stackpanel/state/profile/`
- Update PATH to single entry
- Maintain compatibility with devenv

**Benefits:**
- Cleaner PATH variable
- Faster command resolution
- Easier to inspect environment

**Considerations:**
- Might conflict with devenv integration
- Need to ensure packages don't conflict
- Profile building has overhead

**Estimated effort:** Medium (1-2 days)

## Action Items

### Phase 1: Foundation (Week 1)
- [ ] **Task #1**: Generate input-paths.txt
  - Track imports during shell build
  - Write to state directory
  - Update .envrc to use it
  - Show in status command

- [ ] **Task #2**: Implement GC roots with generations
  - Create gc/ directory structure
  - Numbered generation links
  - Keep last N generations
  - Add rollback command

### Phase 2: Caching (Week 2-3)
- [ ] **Task #3**: Design SQLite caching schema
  - Based on devenv's approach
  - Adapt for Stackpanel's needs
  - Document schema and usage

- [ ] **Task #4**: Implement eval cache database
  - Create tables and indexes
  - File content hash tracking
  - Command result caching
  - Cache invalidation logic

- [ ] **Task #5**: Integrate cache with write-files
  - Check cache before generating
  - Update cache on generation
  - Use file content hashes

### Phase 3: State Management (Week 4)
- [ ] **Task #6**: Separate state and runtime directories
  - Create run/ directory
  - Move ephemeral data
  - Update all references
  - Add cleanup hooks

- [ ] **Task #7**: Task state tracking database
  - Create tasks.db
  - Track task runs
  - File dependency tracking
  - Skip logic

### Phase 4: Polish (Week 5)
- [ ] **Task #8**: Unified profile (optional)
  - Evaluate feasibility
  - Build profile derivation
  - Test with devenv integration
  - Measure performance impact

## Metrics

Track improvements after implementation:

- **Shell reload time**: Measure time from direnv trigger to prompt
- **Cache hit rate**: Percentage of files/commands served from cache
- **GC incidents**: Number of "shell disappeared" errors (should be zero)
- **Unnecessary rebuilds**: Track when files change but output stays same

## Related Issues

- [Previous issue]: `.gitignore` deletion due to stale cache
- Could have been prevented with: GC roots, better cache invalidation, input tracking

## References

- [devenv source code](https://github.com/cachix/devenv)
- [nix-eval-cache implementation](https://github.com/cachix/devenv/tree/main/devenv-eval-cache)
- [devenv tasks system](https://github.com/cachix/devenv/tree/main/devenv-tasks)