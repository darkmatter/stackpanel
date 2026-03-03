# Redis Service

Project-local Redis server for caching and queues.

## Overview

Provides a `mkService` factory that creates a Redis instance with data stored under `.stackpanel/state/services/redis/`. Supports both TCP and Unix socket connections.

## Environment Variables

| Variable | Example |
|----------|---------|
| `REDIS_URL` | `redis://localhost:6379` |
| `REDIS_HOST` | `localhost` |
| `REDIS_PORT` | `6379` |
| `REDIS_SOCKET` | `.stackpanel/state/services/redis/redis.sock` |

## Usage

```nix
stackpanel.globalServices.redis.enable = true;
```
