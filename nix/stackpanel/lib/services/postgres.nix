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
}: let
  defaultPackage = pkgs.postgresql_17;
in {
  # Required packages for PostgreSQL
  packages = [
    defaultPackage
    defaultPackage.lib
  ];

  # Create a service configuration for a project
  mkService = {
    projectName,
    port ? 5432,
    databases ? [],
    package ? defaultPackage,
  }: let
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
  in {
    inherit env;
    inherit dataDir socketDir port databases;
    package = postgresPackage;

    # All packages needed by the CLI to manage PostgreSQL
    allPackages = [
      postgresPackage
      postgresPackage.lib
    ];

    # Shell hook to set environment variables
    shellHook = ''
      # Set environment variables for PostgreSQL
      export STACKPANEL_POSTGRES_ENABLED=1
      export STACKPANEL_POSTGRES_PORT="${toString port}"
      export STACKPANEL_POSTGRES_DATADIR="${dataDir}"
      export STACKPANEL_POSTGRES_SOCKETDIR="${socketDir}"
      ${lib.optionalString (databases != []) ''
        export STACKPANEL_POSTGRES_DATABASES="${lib.concatStringsSep "," databases}"
      ''}
      export PGDATA="${dataDir}"
      export PGHOST="${socketDir}"
      export PGPORT="${toString port}"
      export PGDATABASE="postgres"
      export PGUSER="postgres"
      export DATABASE_URL="postgresql://postgres@localhost:${toString port}/postgres?host=${socketDir}"
      export POSTGRES_URL="postgresql://postgres@localhost:${toString port}/postgres?host=${socketDir}"
    '';
  };
}
