#!/usr/bin/env bash
# SST outputs script
# Shows SST stack outputs

# Get the config path from first arg or default
CONFIG_PATH="${SST_CONFIG_PATH:-infra/sst/sst.config.ts}"

cd "$(dirname "$CONFIG_PATH")"
exec bunx sst outputs "$@"
