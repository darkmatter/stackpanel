# Port computation utilities - pure functions that work with any Nix module system
#
# Usage:
#   let portsLib = import ./lib/core/ports.nix { inherit lib; };
#   in portsLib.computeBasePort { name = "myproject"; }
#
# This module provides deterministic port assignment based on project name.
# Apps and services use the base port and increment from there.
#
# The base port is computed as:
#   minPort + (hash(projectName) % portRange) - ((hash(projectName) % portRange) % modulus)
#
# This ensures the port is:
#   1. Deterministic (same name = same port)
#   2. Round (e.g., 3100 instead of 3174) for easier memorization
#   3. Unlikely to conflict with other projects
#
# Port Layout (from basePort):
#   +0 to +9:   User apps (defined in stackpanel.apps)
#   +10 to +99: Infrastructure services (postgres, redis, minio, etc.)
#
{ lib }: rec {
  # Default port configuration
  defaults = {
    minPort = 3000;
    portRange = 7000;
    modulus = 100;
    servicesBaseOffset = 10;
  };

  # Compute the base port from project name
  # Uses MD5 hash of name, takes first 4 hex chars, converts to number
  # Then rounds to nearest modulus (default 100)
  computeBasePort = {
    name,
    minPort ? defaults.minPort,
    portRange ? defaults.portRange,
    modulus ? defaults.modulus,
  }: let
    hash = builtins.hashString "md5" name;
    rawOffset = lib.trivial.fromHexString (builtins.substring 0 4 hash);
    # Get offset within range, then round down to nearest modulus
    offsetInRange = lib.mod rawOffset portRange;
    roundedOffset = offsetInRange - (lib.mod offsetInRange modulus);
  in
    minPort + roundedOffset;

  # Compute port for a service based on its index
  computeServicePort = {
    basePort,
    index,
    servicesBaseOffset ? defaults.servicesBaseOffset,
  }:
    basePort + servicesBaseOffset + index;

  # Compute ports for a list of services
  # Returns a list of attrsets with key, name, port, displayName
  computeServicesWithPorts = {
    basePort,
    services,
    servicesBaseOffset ? defaults.servicesBaseOffset,
  }:
    lib.imap0 (idx: svc: {
      inherit (svc) key;
      name = svc.name or "";
      port = basePort + servicesBaseOffset + idx;
      displayName =
        if (svc.name or "") != ""
        then svc.name
        else svc.key;
    })
    services;

  # Create attrset for easy lookup: { POSTGRES = { port = ...; ... }; }
  mkServicesByKey = servicesWithPorts:
    lib.listToAttrs (map (svc: {
        name = svc.key;
        value = svc;
      })
      servicesWithPorts);

  # Generate environment variables for all services
  # Returns { STACKPANEL_POSTGRES_PORT = "3110"; ... }
  mkServiceEnvVars = servicesWithPorts:
    lib.listToAttrs (map (svc: {
        name = "STACKPANEL_${svc.key}_PORT";
        value = toString svc.port;
      })
      servicesWithPorts);

  # Convenience function: compute everything from project name and services list
  # Returns { basePort, servicesWithPorts, servicesByKey, serviceEnvVars }
  mkPortsConfig = {
    projectName,
    services ? [],
    minPort ? defaults.minPort,
    portRange ? defaults.portRange,
    modulus ? defaults.modulus,
    servicesBaseOffset ? defaults.servicesBaseOffset,
  }: let
    basePort = computeBasePort {
      name = projectName;
      inherit minPort portRange modulus;
    };
    servicesWithPorts = computeServicesWithPorts {
      inherit basePort services servicesBaseOffset;
    };
    servicesByKey = mkServicesByKey servicesWithPorts;
    serviceEnvVars = mkServiceEnvVars servicesWithPorts;
  in {
    inherit basePort servicesWithPorts servicesByKey serviceEnvVars;
    # Environment variables including base port
    env = { STACKPANEL_BASE_PORT = toString basePort; } // serviceEnvVars;
  };
}
