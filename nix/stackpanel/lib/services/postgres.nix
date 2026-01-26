# ==============================================================================
# services/postgres.nix
#
# PostgreSQL database service configuration.
# Pure functions that work with any Nix module system.
#
# This module ONLY provides packages and environment variables.
# All lifecycle management (start/stop/status) is handled by the stackpanel CLI.
#
# Features:
#   - PostgreSQL 17 package inclusion (with lib for extensions)
#   - Unix socket and TCP connection support
#   - Standard PG* environment variable configuration
#   - DATABASE_URL and POSTGRES_URL connection strings
#   - Shell hooks for automatic environment setup
#
# Usage:
#   let pgLib = import ./postgres.nix { inherit pkgs lib; baseDir = ".stackpanel/state"; };
#   in pgLib.mkService { projectName = "myapp"; port = 5432; databases = ["app"]; }
# ==============================================================================
{
  pkgs,
  lib,
  baseDir,
}:
let
  defaultPackage = pkgs.postgresql_17;
in
{
  # Required packages for PostgreSQL
  packages = [
    defaultPackage
    defaultPackage.lib
  ];

  # Create a service configuration for a project
  mkService =
    {
      projectName,
      port ? 5432,
      databases ? [ ],
      package ? defaultPackage,
    }:
    let
      postgresPackage = package;
      dataDir = "${baseDir}/postgres/data";
      socketDir = "${baseDir}/postgres";
      # Common environment variables
      env = {
        PGDATA = dataDir;
        PGHOST = socketDir;
        PGPORT = toString port;
        PGDATABASE = "postgres";
        PGUSER = "postgres";
        # Connection strings for applications
        DATABASE_URL = "postgresql://postgres@localhost:${toString port}/postgres?host=${socketDir}";
        POSTGRES_URL = "postgresql://postgres@localhost:${toString port}/postgres?host=${socketDir}";
      };
    in
    {
      inherit env;
      inherit
        dataDir
        socketDir
        port
        databases
        ;
      package = postgresPackage;

      # All packages needed by the CLI to manage PostgreSQL
      allPackages = [
        postgresPackage
        postgresPackage.lib
      ];

      # Shell hook to set environment variables
      shellHook = ''
        # Set environment variables for PostgreSQL
        export PGDATA="${dataDir}"
        export PGHOST="${socketDir}"
        export PGPORT="${toString port}"
        export PGDATABASE="postgres"
        export PGUSER="postgres"
        export DATABASE_URL="postgresql://postgres@localhost:${toString port}/postgres?host=${socketDir}"
        export POSTGRES_URL="postgresql://postgres@localhost:${toString port}/postgres?host=${socketDir}"
      '';

      # Foreground start script for process-compose
      # Initializes the data directory if needed, creates databases, then runs
      # postgres in the foreground. Process-compose manages the lifecycle.
      startScript = pkgs.writeShellScriptBin "postgres-start" ''
        set -euo pipefail

        DATADIR="${dataDir}"
        SOCKETDIR="${socketDir}"
        PORT="${toString port}"

        # Initialize data directory if needed
        if [ ! -f "$DATADIR/PG_VERSION" ]; then
          echo "Initializing PostgreSQL data directory..."
          mkdir -p "$DATADIR"
          ${postgresPackage}/bin/initdb -D "$DATADIR" --no-locale --encoding=UTF8 -U postgres
        fi

        # Ensure socket directory exists
        mkdir -p "$SOCKETDIR"

        # Create databases after startup (background task)
        (
          # Wait for postgres to be ready
          for i in $(seq 1 30); do
            if ${postgresPackage}/bin/pg_isready -h "$SOCKETDIR" -p "$PORT" -U postgres >/dev/null 2>&1; then
              break
            fi
            sleep 0.5
          done

          # Create configured databases
          ${lib.concatMapStringsSep "\n" (db: ''
            if ! ${postgresPackage}/bin/psql -h "$SOCKETDIR" -p "$PORT" -U postgres -lqt 2>/dev/null | grep -qw "${db}"; then
              echo "Creating database: ${db}"
              ${postgresPackage}/bin/createdb -h "$SOCKETDIR" -p "$PORT" -U postgres "${db}" 2>/dev/null || true
            fi
          '') databases}
        ) &

        # Start PostgreSQL in foreground
        exec ${postgresPackage}/bin/postgres \
          -D "$DATADIR" \
          -p "$PORT" \
          -k "$SOCKETDIR" \
          -h localhost
      '';
    };
}
