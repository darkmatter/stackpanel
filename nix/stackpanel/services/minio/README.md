# MinIO Service

Project-local S3-compatible object storage.

## Overview

Provides a `mkService` factory that creates a MinIO instance with data stored under `.stackpanel/state/services/minio/`. Includes both the S3 API endpoint and the web console.

## Environment Variables

| Variable | Example |
|----------|---------|
| `MINIO_ENDPOINT` | `http://localhost:9000` |
| `S3_ENDPOINT` | `http://localhost:9000` |
| `MINIO_ROOT_USER` | `minioadmin` |
| `MINIO_ROOT_PASSWORD` | `minioadmin` |

## Usage

```nix
stackpanel.globalServices.minio.enable = true;
```
