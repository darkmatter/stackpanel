# PostgreSQL Service

Project-local PostgreSQL server with automatic database creation.

## Overview

Provides a `mkService` factory that creates a PostgreSQL instance with data stored under `.stack/state/services/postgres/`. Handles initialization, socket-based connections, and foreground execution for process-compose.

## Environment Variables

| Variable | Example |
|----------|---------|
| `DATABASE_URL` | `postgresql://localhost:5432/myapp` |
| `POSTGRES_URL` | `postgresql://localhost:5432/myapp` |
| `PGHOST` | `.stack/state/services/postgres/socket` |
| `PGPORT` | `5432` |
| `PGDATABASE` | `myapp` |
| `PGUSER` | `$USER` |

## Usage

```nix
stack.globalServices.postgres = {
  enable = true;
  databases = [ "myapp" "myapp_test" ];
};
```
