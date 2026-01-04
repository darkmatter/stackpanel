# ==============================================================================
# ports.nix
#
# Port computation utilities - pure functions for deterministic port assignment.
#
# This module provides deterministic port assignment based on project name,
# ensuring each project gets a consistent, memorable port range.
#
# Algorithm:
#   basePort = minPort + (hash(projectName) % portRange) -
#              ((hash(projectName) % portRange) % modulus)
#
# This ensures ports are:
#   1. Deterministic - same project name = same port
#   2. Round numbers - e.g., 3100 instead of 3174 for easier memorization
#   3. Collision-resistant - unlikely to conflict with other projects
#
# Port Layout (from basePort):
#   +0 to +9:   User apps (defined in stackpanel.apps)
#   +10 to +99: Infrastructure services (postgres, redis, minio, etc.)
#
# Exports:
#   - stablePort: Compute stable port from project name + service name
#   - computeBasePort: Compute base port from project name
#   - computeServicesFromAttrset: Compute ports from attrset of services (preferred)
#   - computeServicePort: Compute port for a service by index (legacy)
#   - computeServicesWithPorts: Compute ports for a list of services (legacy)
#   - mkServicesByKey: Create lookup attrset by service key
#   - mkServicesConfig: Generate JSON config for services
#   - mkPortsConfig: Convenience function to compute everything at once
#
# Usage:
#   let portsLib = import ./ports.nix { inherit lib; };
#   in portsLib.computeBasePort { name = "myproject"; }
# ==============================================================================
{ lib }:
rec {
  # Default port configuration
  defaults = {
    minPort = 3000;
    portRange = 7000;
    modulus = 100;
    servicesBaseOffset = 10;
  };
  constants = {
    MIN_PORT = 3000;
    MAX_PORT = 10000;
    MODULUS = 100;
  };

  # Compute a value within a specified range based on a key
  # Used internally for port computations
  computeOverRange =
    {
      key,
      min,
      max,
      modulus,
    }:
    let
      range = max - min;
      rawHash = builtins.hashString "md5" key;
      hash = builtins.substring 0 4 rawHash;
      # numeric representation of hash
      n = lib.trivial.fromHexString hash;
      # convert to min < n < max, then round down to nearest modulus
      offset = lib.mod n range;
      # apply offset and round down
      roundedOffset = offset - (lib.mod offset modulus);
    in
    min + roundedOffset;

  stablePort =
    {
      repo,
      service,
    }:
    let
      # compute a range (size 100) over 3000-10000
      projectBase = computeOverRange {
        key = repo;
        min = constants.MIN_PORT;
        max = constants.MAX_PORT;
        modulus = constants.MODULUS;
      };
      # compute service port within that range
      servicePort = computeOverRange {
        key = service;
        min = projectBase;
        max = projectBase + constants.MODULUS;
        modulus = 1;
      };
    in
    servicePort;

  # Compute services from an attrset { KEY = { name = "..."; }; ... }
  # Returns an attrset with port information for each service
  # Uses stablePort for deterministic port assignment without offsets
  computeServicesFromAttrset =
    {
      projectName,
      services,
    }:
    lib.mapAttrs (
      key: svc:
      let
        port = stablePort {
          repo = projectName;
          service = key;
        };
      in
      {
        inherit key port;
        name = svc.name or key;
        displayName = if (svc.name or "") != "" then svc.name else key;
      }
    ) services;

  # Compute the base port from project name
  # Uses computeOverRange for consistent algorithm
  computeBasePort =
    {
      name,
      minPort ? defaults.minPort,
      portRange ? defaults.portRange,
      modulus ? defaults.modulus,
    }:
    computeOverRange {
      key = name;
      min = constants.MIN_PORT;
      max = constants.MAX_PORT;
      modulus = constants.MODULUS;
    };

  # Compute port for a service based on its index
  computeServicePort =
    {
      basePort,
      index,
      servicesBaseOffset ? defaults.servicesBaseOffset,
    }:
    basePort + servicesBaseOffset + index;

  # Compute ports for a list of services
  # Returns a list of attrsets with key, name, port, displayName
  computeServicesWithPorts =
    {
      basePort,
      services,
      servicesBaseOffset ? defaults.servicesBaseOffset,
    }:
    lib.imap0 (idx: svc: {
      inherit (svc) key;
      name = svc.name or "";
      port = basePort + servicesBaseOffset + idx;
      displayName = if (svc.name or "") != "" then svc.name else svc.key;
    }) services;

  # Create attrset for easy lookup: { POSTGRES = { port = ...; ... }; }
  mkServicesByKey =
    servicesWithPorts:
    lib.listToAttrs (
      map (svc: {
        name = svc.key;
        value = svc;
      }) servicesWithPorts
    );

  # Generate JSON config for all services
  mkServicesConfig =
    servicesWithPorts:
    builtins.toJSON (
      map (svc: {
        key = svc.key;
        name = svc.displayName;
        port = svc.port;
      }) servicesWithPorts
    );

  # Convenience function: compute everything from project name and services list
  # Returns { basePort, servicesWithPorts, servicesByKey, servicesConfig }
  mkPortsConfig =
    {
      projectName,
      services ? [ ],
      minPort ? defaults.minPort,
      portRange ? defaults.portRange,
      modulus ? defaults.modulus,
      servicesBaseOffset ? defaults.servicesBaseOffset,
    }:
    let
      basePort = computeBasePort {
        name = projectName;
        inherit minPort portRange modulus;
      };
      servicesWithPorts = computeServicesWithPorts {
        inherit basePort services servicesBaseOffset;
      };
      servicesByKey = mkServicesByKey servicesWithPorts;
      servicesConfig = mkServicesConfig servicesWithPorts;
    in
    {
      inherit
        basePort
        servicesWithPorts
        servicesByKey
        servicesConfig
        ;
      # Environment variables including stable port + services config
      env = {
        STACKPANEL_STABLE_PORT = toString basePort;
        STACKPANEL_SERVICES_CONFIG = servicesConfig;
      };
    };
}
