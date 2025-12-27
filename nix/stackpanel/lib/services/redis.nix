# ==============================================================================
# services/redis.nix
#
# Redis in-memory data store service configuration.
# Pure functions that work with any Nix module system.
#
# This module ONLY provides packages and environment variables.
# All lifecycle management (start/stop/status) is handled by the stackpanel CLI.
#
# Features:
#   - Redis package inclusion
#   - Unix socket and TCP connection support
#   - REDIS_URL, REDIS_HOST, REDIS_PORT environment variables
#   - Shell hooks for automatic environment setup
#
# Usage:
#   let redisLib = import ./redis.nix { inherit pkgs lib; baseDir = ".stackpanel/state"; };
#   in redisLib.mkService { projectName = "myapp"; port = 6379; }
# ==============================================================================
{
  pkgs,
  lib,
  baseDir,
}: let
  defaultPackage = pkgs.redis;
in {
  # Required packages for Redis
  packages = [defaultPackage];

  # Create a service configuration for a project
  mkService = {
    projectName,
    port ? 6379,
    package ? defaultPackage,
  }: let
    redisPackage = package;
    dataDir = "${baseDir}/redis";
    socketPath = "${dataDir}/redis.sock";
    pidFile = "${dataDir}/redis.pid";
    configFile = "${dataDir}/redis.conf";
    env = {
      REDIS_URL = "redis://localhost:${toString port}";
      REDIS_HOST = "localhost";
      REDIS_PORT = toString port;
      REDIS_SOCKET = socketPath;
    };
  in {
    inherit env;
    inherit dataDir socketPath pidFile configFile port;
    package = redisPackage;

    # All packages needed by the CLI to manage Redis
    allPackages = [redisPackage];

    # Shell hook to set environment variables
    shellHook = ''
      # Set environment variables for Redis
      export STACKPANEL_REDIS_ENABLED=1
      export STACKPANEL_REDIS_PORT="${toString port}"
      export STACKPANEL_REDIS_DATADIR="${dataDir}"
      export STACKPANEL_REDIS_SOCKET="${socketPath}"
      export REDIS_URL="redis://localhost:${toString port}"
      export REDIS_HOST="localhost"
      export REDIS_PORT="${toString port}"
      export REDIS_SOCKET="${socketPath}"
    '';
  };
}
