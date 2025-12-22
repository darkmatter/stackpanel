# Modular Services Library
#
# This directory contains individual service definitions that can be
# composed together. Each service file exports a `mkService` function.
#
# Services are PROJECT-LOCAL by default, storing data in:
#   <projectRoot>/.stackpanel/state/services/
#
# This allows different projects to use different versions and configurations.
# Caddy remains GLOBAL to avoid port 443 conflicts.
#
# To add a new service:
# 1. Create a new file: nix/lib/services/<service-name>.nix
# 2. Export a mkService function following the pattern in existing services
# 3. Add the service to the registry in default.nix
#
# Example service structure:
#   { pkgs, lib, baseDir }:
#   {
#     mkService = { projectName, port ? 1234, ... }: {
#       name = "myservice";
#       displayName = "My Service";
#       port = port;
#       env = { ... };
#       allPackages = [ ... ];
#       registerResources = pkgs.writeShellScriptBin "myservice-register" ''...'';
#     };
#   }
#
{
  pkgs,
  lib,
  # Project root directory - services will be stored in <projectRoot>/.stackpanel/state/services/
  # If not provided, falls back to legacy global directory
  projectRoot ? null,
}: let
  # Base directory for service data
  # Project-local by default, with fallback to global for backwards compatibility
  baseDir =
    if projectRoot != null
    then "${projectRoot}/.stackpanel/state/services"
    else "$HOME/.local/share/devservices";

  # Global directory for services that must be shared (like Caddy)
  globalBaseDir = "$HOME/.local/share/devservices";

  # Import individual service modules with the appropriate baseDir
  postgresModule = import ./postgres.nix {inherit pkgs lib baseDir;};
  redisModule = import ./redis.nix {inherit pkgs lib baseDir;};
  minioModule = import ./minio.nix {inherit pkgs lib baseDir;};

  # Service registry - add new services here
  serviceModules = {
    postgres = postgresModule;
    redis = redisModule;
    minio = minioModule;
  };

  # Default ports for well-known services
  defaultPorts = {
    postgres = 5432;
    redis = 6379;
    minio = 9000;
    minio-console = 9001;
  };
in {
  inherit baseDir globalBaseDir defaultPorts serviceModules;

  # Get list of available service names
  availableServices = lib.attrNames serviceModules;

  # Create a service instance by name
  mkService = name: args:
    if lib.hasAttr name serviceModules
    then serviceModules.${name}.mkService args
    else throw "Unknown service: ${name}. Available: ${lib.concatStringsSep ", " (lib.attrNames serviceModules)}";

  # Convenience functions for specific services
  mkGlobalPostgres = postgresModule.mkService;
  mkGlobalRedis = redisModule.mkService;
  mkGlobalMinio = minioModule.mkService;
}
