#!/usr/bin/env bash
# SST dev mode script
# Starts SST in development mode

# Get the config path from first arg or default
CONFIG_PATH="${SST_CONFIG_PATH:-infra/sst/sst.config.ts}"

cd "$(dirname "$CONFIG_PATH")"
exec bunx sst dev "$@"
