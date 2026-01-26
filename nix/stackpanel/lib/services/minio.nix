# ==============================================================================
# services/minio.nix
#
# MinIO S3-compatible object storage service configuration.
# Pure functions that work with any Nix module system.
#
# This module ONLY provides packages and environment variables.
# All lifecycle management (start/stop/status) is handled by the stackpanel CLI.
#
# Features:
#   - MinIO server package and client (mc) inclusion
#   - S3-compatible environment variable configuration
#   - Console port configuration for web UI access
#   - Shell hooks for automatic environment setup
#
# Note: Does NOT set AWS_* environment variables to avoid breaking AWS IAM auth.
# Apps should use MINIO_ENDPOINT and S3_ENDPOINT for MinIO access.
#
# Usage:
#   let minioLib = import ./minio.nix { inherit pkgs lib; baseDir = ".stackpanel/state"; };
#   in minioLib.mkService { projectName = "myapp"; port = 9000; }
# ==============================================================================
{
  pkgs,
  lib,
  baseDir,
}:
let
  defaultPackage = pkgs.minio;
  minioClient = pkgs.minio-client;
in
{
  # Required packages for Minio
  packages = [
    defaultPackage
    minioClient
  ];

  # Create a service configuration for a project
  mkService =
    {
      projectName,
      port ? 9000,
      consolePort ? 9001,
      accessKey ? "minioadmin",
      secretKey ? "minioadmin",
      package ? defaultPackage,
    }:
    let
      minioPackage = package;
      dataDir = "${baseDir}/minio/data";
      configDir = "${baseDir}/minio/config";
      pidFile = "${baseDir}/minio/minio.pid";
      logFile = "${baseDir}/minio/minio.log";
      env = {
        MINIO_ROOT_USER = accessKey;
        MINIO_ROOT_PASSWORD = secretKey;
        MINIO_ENDPOINT = "http://localhost:${toString port}";
        MINIO_CONSOLE_ADDRESS = ":${toString consolePort}";
        # S3-compatible env vars for Minio access (not AWS_ prefixed to avoid breaking AWS auth)
        MINIO_ACCESS_KEY = accessKey;
        MINIO_SECRET_KEY = secretKey;
        S3_ENDPOINT = "http://localhost:${toString port}";
      };
    in
    {
      inherit env;
      inherit
        dataDir
        configDir
        pidFile
        logFile
        port
        consolePort
        accessKey
        secretKey
        ;
      package = minioPackage;
      client = minioClient;

      # All packages needed by the CLI to manage Minio
      allPackages = [
        minioPackage
        minioClient
      ];

      # Shell hook to set environment variables
      # NOTE: We do NOT set AWS_ENDPOINT_URL, AWS_ENDPOINT_URL_S3, AWS_ACCESS_KEY_ID,
      # or AWS_SECRET_ACCESS_KEY globally because it breaks AWS IAM authentication.
      # Apps that need to use Minio should use MINIO_ENDPOINT and S3_ENDPOINT.
      shellHook = ''
        # Set environment variables for Minio
        export MINIO_ROOT_USER="${accessKey}"
        export MINIO_ROOT_PASSWORD="${secretKey}"
        export MINIO_ENDPOINT="http://localhost:${toString port}"
        export MINIO_ACCESS_KEY="${accessKey}"
        export MINIO_SECRET_KEY="${secretKey}"
        export S3_ENDPOINT="http://localhost:${toString port}"
      '';

      # Foreground start script for process-compose
      # Runs Minio server in the foreground.
      # Process-compose manages the lifecycle.
      startScript = pkgs.writeShellScriptBin "minio-start" ''
        set -euo pipefail

        DATADIR="${dataDir}"
        PORT="${toString port}"
        CONSOLE_PORT="${toString consolePort}"

        mkdir -p "$DATADIR"

        # Set credentials
        export MINIO_ROOT_USER="${accessKey}"
        export MINIO_ROOT_PASSWORD="${secretKey}"

        # Start Minio in foreground
        exec ${minioPackage}/bin/minio server "$DATADIR" \
          --address ":$PORT" \
          --console-address ":$CONSOLE_PORT"
      '';
    };
}
